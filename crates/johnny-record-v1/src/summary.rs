//! Counts over one run file, printed in the Python reader's `--summary`
//! text (`docs/tool-install/johnny-m1s2b-reader.py:591-651`).

use std::collections::{BTreeMap, HashMap};
use std::fmt::Write as _;
use std::hash::Hash;

use crate::record::{fmt_ip, Decoded, RecordV1, SeqGaps, REC_SIZE};
use crate::runfile::{RunHeader, CTL_NAMES};
use crate::utc;

/// Counts in first-seen order, so a stable sort by count breaks ties the
/// way the Python reader's dict does.
struct Counter<K> {
    order: Vec<(K, u64)>,
    index: HashMap<K, usize>,
}

impl<K: Hash + Eq + Copy> Counter<K> {
    fn new() -> Self {
        Counter {
            order: Vec::new(),
            index: HashMap::new(),
        }
    }

    fn bump(&mut self, k: K) {
        match self.index.get(&k) {
            Some(&i) => self.order[i].1 += 1,
            None => {
                self.index.insert(k, self.order.len());
                self.order.push((k, 1));
            }
        }
    }

    fn by_count(&self) -> Vec<(K, u64)> {
        let mut v = self.order.clone();
        v.sort_by_key(|e| std::cmp::Reverse(e.1));
        v
    }
}

/// The Python reader keys addresses by their printed text. For IPv4 that is
/// the first four bytes only.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
enum IpKey {
    V4([u8; 4]),
    Other([u8; 16]),
}

impl IpKey {
    fn of(b: &[u8; 16], is4: bool) -> Self {
        if is4 {
            IpKey::V4([b[0], b[1], b[2], b[3]])
        } else {
            IpKey::Other(*b)
        }
    }

    fn text(&self) -> String {
        match self {
            IpKey::V4(a) => format!("{}.{}.{}.{}", a[0], a[1], a[2], a[3]),
            IpKey::Other(b) => fmt_ip(b, false),
        }
    }
}

pub struct Summary {
    records: u64,
    total_wire: u64,
    gaps: SeqGaps,
    rxq: BTreeMap<u16, u64>,
    proto: Counter<u8>,
    src: Counter<IpKey>,
    dst: Counter<IpKey>,
    unknown_version: u64,
}

impl Default for Summary {
    fn default() -> Self {
        Summary {
            records: 0,
            total_wire: 0,
            gaps: SeqGaps::default(),
            rxq: BTreeMap::new(),
            proto: Counter::new(),
            src: Counter::new(),
            dst: Counter::new(),
            unknown_version: 0,
        }
    }
}

impl Summary {
    pub fn add(&mut self, raw: &[u8; REC_SIZE]) {
        let r: RecordV1 = match RecordV1::decode(raw) {
            Decoded::V1(r) => r,
            Decoded::Unknown { .. } => {
                self.unknown_version += 1;
                return;
            }
        };
        self.records += 1;
        self.total_wire += u64::from(r.wire_len);
        *self.rxq.entry(r.rxq).or_insert(0) += 1;
        self.proto.bump(r.l4_proto);
        self.src.bump(IpKey::of(&r.src_ip, r.is_ipv4()));
        self.dst.bump(IpKey::of(&r.dst_ip, r.is_ipv4()));
        self.gaps.observe(r.rxq, r.seq_lo);
    }

    pub fn records(&self) -> u64 {
        self.records
    }

    /// Records skipped because their version byte is not 1.
    pub fn unknown_version(&self) -> u64 {
        self.unknown_version
    }

    /// The summary text, one line per `\n`. On a file of v1 records this is
    /// the Python reader's output byte for byte. The `UNKNOWN-VERSION` line
    /// appears only when records were skipped.
    pub fn render(&self, path: &str, header: &RunHeader, top: usize) -> String {
        let mut s = String::new();
        let _ = writeln!(s, "FILE {path}");
        let _ = writeln!(
            s,
            "HEADER magic=JM1S2RB ver={} start_utc={} cfg=ver:{},every:{},rate:{},burst:{}",
            header.hdr_version,
            utc::spaced(header.start_unix_secs()),
            header.cfg.ver,
            header.cfg.sample_every,
            header.cfg.rate,
            header.cfg.burst
        );
        let ctl: Vec<String> = CTL_NAMES
            .iter()
            .zip(header.ctl_start.iter())
            .map(|(k, v)| format!("{k}={v}"))
            .collect();
        let _ = writeln!(s, "CTL-START {}", ctl.join(" "));
        let _ = writeln!(
            s,
            "SUMMARY records={} total_wire_bytes={} seq_gaps={}",
            self.records,
            self.total_wire,
            self.gaps.gaps()
        );
        let queues: Vec<String> = self.rxq.iter().map(|(k, v)| format!("rxq{k}={v}")).collect();
        let _ = writeln!(s, "QUEUES {}", queues.join(" "));
        let proto: Vec<String> = self
            .proto
            .by_count()
            .iter()
            .map(|(k, v)| match k {
                6 => format!("tcp={v}"),
                17 => format!("udp={v}"),
                1 => format!("icmp={v}"),
                58 => format!("icmp6={v}"),
                k => format!("{k}={v}"),
            })
            .collect();
        let _ = writeln!(s, "PROTO {}", proto.join(" "));
        for (label, counter) in [("TOP-SRC", &self.src), ("TOP-DST", &self.dst)] {
            let rows: Vec<String> = counter
                .by_count()
                .iter()
                .take(top)
                .map(|(k, v)| format!("{}={v}", k.text()))
                .collect();
            let _ = writeln!(s, "{label} {}", rows.join(" "));
        }
        if self.unknown_version > 0 {
            let _ = writeln!(s, "UNKNOWN-VERSION skipped={}", self.unknown_version);
        }
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runfile::M2Cfg;

    fn rec(rxq: u16, proto: u8, src: u8, seq: u32) -> [u8; REC_SIZE] {
        let mut raw = [0u8; REC_SIZE];
        raw[0] = 1;
        raw[2..4].copy_from_slice(&rxq.to_le_bytes());
        raw[4..8].copy_from_slice(&100u32.to_le_bytes());
        raw[28..30].copy_from_slice(&0x0800u16.to_le_bytes());
        raw[32..36].copy_from_slice(&[10, 0, 0, src]);
        raw[48..52].copy_from_slice(&[10, 0, 0, 200]);
        raw[64] = proto;
        raw[76..80].copy_from_slice(&seq.to_le_bytes());
        raw
    }

    #[test]
    fn text() {
        let h = RunHeader::v1(1_794_000_000_000_000_000, 0, M2Cfg::default(), [1, 2, 3, 4, 5, 6]);
        let mut s = Summary::default();
        s.add(&rec(1, 17, 2, 1));
        s.add(&rec(0, 6, 1, 1));
        s.add(&rec(0, 6, 1, 3));
        s.add(&rec(0, 47, 3, 4));
        let mut v2 = rec(0, 6, 9, 5);
        v2[0] = 2;
        s.add(&v2);
        assert_eq!(
            s.render("/x/run.bin", &h, 2),
            "FILE /x/run.bin\n\
             HEADER magic=JM1S2RB ver=1 start_utc=2026-11-06 21:20:00Z cfg=ver:0,every:0,rate:0,burst:0\n\
             CTL-START seen=1 sampled_out=2 rate_limited=3 rb_full=4 emitted=5 discarded=6\n\
             SUMMARY records=4 total_wire_bytes=400 seq_gaps=1\n\
             QUEUES rxq0=3 rxq1=1\n\
             PROTO tcp=2 udp=1 47=1\n\
             TOP-SRC 10.0.0.1=2 10.0.0.2=1\n\
             TOP-DST 10.0.0.200=4\n\
             UNKNOWN-VERSION skipped=1\n"
        );
    }
}
