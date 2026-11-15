//! The frozen 80-byte record (`struct m2_rec`), implicit version 1.
//!
//! Offsets are the C side's `_Static_assert`s
//! (`docs/tool-install/module1_xdp_records.c:133-165`) and the Python
//! reader's `REC_FMT` (`docs/tool-install/johnny-m1s2b-reader.py:44`).
//! All integers are little-endian (x86-64 host order on Johnny).

use std::collections::HashMap;
use std::fmt::Write as _;

use crate::OUTPUT_VERSION;

pub const REC_SIZE: usize = 80;
pub const REC_VERSION: u8 = 1;

/// `m2_rec.flags` bits, in bit order.
pub const FLAG_NAMES: [&str; 8] = [
    "trunc_l3",
    "trunc_l4",
    "frag",
    "ip6_ext",
    "vlan",
    "qinq",
    "rl_recovered",
    "vlan_deep",
];

pub const ETHERTYPE_IPV4: u16 = 0x0800;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecordV1 {
    pub flags: u8,
    pub rxq: u16,
    pub wire_len: u32,
    pub ts_ns: u64,
    pub dst_mac: [u8; 6],
    pub src_mac: [u8; 6],
    pub ethertype: u16,
    pub vlan_tci: u16,
    pub src_ip: [u8; 16],
    pub dst_ip: [u8; 16],
    pub l4_proto: u8,
    pub ttl_hlim: u8,
    pub l3_len: u16,
    pub sport: u16,
    pub dport: u16,
    pub tcp_flags: u8,
    pub rsv0: u8,
    pub rsv1: u16,
    pub seq_lo: u32,
}

/// What a reader gets for one 80-byte slot.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decoded {
    V1(RecordV1),
    /// A version this reader does not know. The bytes are not interpreted.
    Unknown { version: u8 },
}

/// Byte 0: the record version.
pub fn raw_version(raw: &[u8; REC_SIZE]) -> u8 {
    raw[0]
}

/// Bytes 2..4: rx queue index.
pub fn raw_rxq(raw: &[u8; REC_SIZE]) -> u16 {
    u16::from_le_bytes([raw[2], raw[3]])
}

/// Bytes 76..80: per-queue record sequence, low 32 bits.
pub fn raw_seq_lo(raw: &[u8; REC_SIZE]) -> u32 {
    u32::from_le_bytes([raw[76], raw[77], raw[78], raw[79]])
}

fn arr<const N: usize>(raw: &[u8; REC_SIZE], at: usize) -> [u8; N] {
    let mut out = [0u8; N];
    out.copy_from_slice(&raw[at..at + N]);
    out
}

impl RecordV1 {
    pub fn decode(raw: &[u8; REC_SIZE]) -> Decoded {
        if raw[0] != REC_VERSION {
            return Decoded::Unknown { version: raw[0] };
        }
        Decoded::V1(RecordV1 {
            flags: raw[1],
            rxq: u16::from_le_bytes(arr(raw, 2)),
            wire_len: u32::from_le_bytes(arr(raw, 4)),
            ts_ns: u64::from_le_bytes(arr(raw, 8)),
            dst_mac: arr(raw, 16),
            src_mac: arr(raw, 22),
            ethertype: u16::from_le_bytes(arr(raw, 28)),
            vlan_tci: u16::from_le_bytes(arr(raw, 30)),
            src_ip: arr(raw, 32),
            dst_ip: arr(raw, 48),
            l4_proto: raw[64],
            ttl_hlim: raw[65],
            l3_len: u16::from_le_bytes(arr(raw, 66)),
            sport: u16::from_le_bytes(arr(raw, 68)),
            dport: u16::from_le_bytes(arr(raw, 70)),
            tcp_flags: raw[72],
            rsv0: raw[73],
            rsv1: u16::from_le_bytes(arr(raw, 74)),
            seq_lo: u32::from_le_bytes(arr(raw, 76)),
        })
    }

    pub fn encode(&self) -> [u8; REC_SIZE] {
        let mut raw = [0u8; REC_SIZE];
        raw[0] = REC_VERSION;
        raw[1] = self.flags;
        raw[2..4].copy_from_slice(&self.rxq.to_le_bytes());
        raw[4..8].copy_from_slice(&self.wire_len.to_le_bytes());
        raw[8..16].copy_from_slice(&self.ts_ns.to_le_bytes());
        raw[16..22].copy_from_slice(&self.dst_mac);
        raw[22..28].copy_from_slice(&self.src_mac);
        raw[28..30].copy_from_slice(&self.ethertype.to_le_bytes());
        raw[30..32].copy_from_slice(&self.vlan_tci.to_le_bytes());
        raw[32..48].copy_from_slice(&self.src_ip);
        raw[48..64].copy_from_slice(&self.dst_ip);
        raw[64] = self.l4_proto;
        raw[65] = self.ttl_hlim;
        raw[66..68].copy_from_slice(&self.l3_len.to_le_bytes());
        raw[68..70].copy_from_slice(&self.sport.to_le_bytes());
        raw[70..72].copy_from_slice(&self.dport.to_le_bytes());
        raw[72] = self.tcp_flags;
        raw[73] = self.rsv0;
        raw[74..76].copy_from_slice(&self.rsv1.to_le_bytes());
        raw[76..80].copy_from_slice(&self.seq_lo.to_le_bytes());
        raw
    }

    pub fn is_ipv4(&self) -> bool {
        self.ethertype == ETHERTYPE_IPV4
    }

    /// One JSON object, no newline, stamped `"version":1` first.
    pub fn write_json(&self, out: &mut String) {
        let _ = write!(
            out,
            "{{\"version\":{OUTPUT_VERSION},\"flags\":{},\"flag_names\":[",
            self.flags
        );
        let mut first = true;
        for (bit, name) in FLAG_NAMES.iter().enumerate() {
            if self.flags & (1 << bit) != 0 {
                if !first {
                    out.push(',');
                }
                first = false;
                let _ = write!(out, "\"{name}\"");
            }
        }
        let _ = write!(
            out,
            "],\"rxq\":{},\"wire_len\":{},\"ts_ns\":{},\"dst_mac\":\"{}\",\"src_mac\":\"{}\",\
             \"ethertype\":{},\"vlan_tci\":{},\"src_ip\":\"{}\",\"dst_ip\":\"{}\",\
             \"l4_proto\":{},\"ttl_hlim\":{},\"l3_len\":{},\"sport\":{},\"dport\":{},\
             \"tcp_flags\":{},\"rsv0\":{},\"rsv1\":{},\"seq_lo\":{}}}",
            self.rxq,
            self.wire_len,
            self.ts_ns,
            fmt_mac(&self.dst_mac),
            fmt_mac(&self.src_mac),
            self.ethertype,
            self.vlan_tci,
            fmt_ip(&self.src_ip, self.is_ipv4()),
            fmt_ip(&self.dst_ip, self.is_ipv4()),
            self.l4_proto,
            self.ttl_hlim,
            self.l3_len,
            self.sport,
            self.dport,
            self.tcp_flags,
            self.rsv0,
            self.rsv1,
            self.seq_lo,
        );
    }
}

pub fn fmt_mac(m: &[u8; 6]) -> String {
    format!(
        "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
        m[0], m[1], m[2], m[3], m[4], m[5]
    )
}

/// Same text as the Python reader's `fmt_ip`: dotted quad from the first
/// four bytes when `is4`, else eight 16-bit hex groups (not compressed).
pub fn fmt_ip(b: &[u8; 16], is4: bool) -> String {
    if is4 {
        return format!("{}.{}.{}.{}", b[0], b[1], b[2], b[3]);
    }
    let mut s = String::with_capacity(39);
    for i in (0..16).step_by(2) {
        if i > 0 {
            s.push(':');
        }
        let _ = write!(s, "{:02x}{:02x}", b[i], b[i + 1]);
    }
    s
}

/// Per-queue sequence gap counter (`seq_lo` is per rx queue, wraps at 2^32).
#[derive(Debug, Default)]
pub struct SeqGaps {
    last: HashMap<u16, u32>,
    gaps: u64,
}

impl SeqGaps {
    pub fn observe(&mut self, rxq: u16, seq: u32) {
        if let Some(prev) = self.last.insert(rxq, seq) {
            self.gaps += u64::from(seq.wrapping_sub(prev).wrapping_sub(1));
        }
    }

    pub fn gaps(&self) -> u64 {
        self.gaps
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> RecordV1 {
        RecordV1 {
            flags: 0x11,
            rxq: 0x0302,
            wire_len: 1514,
            ts_ns: 0x0102_0304_0506_0708,
            dst_mac: [1, 2, 3, 4, 5, 6],
            src_mac: [7, 8, 9, 10, 11, 12],
            ethertype: ETHERTYPE_IPV4,
            vlan_tci: 0x2064,
            src_ip: [192, 168, 50, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            dst_ip: [1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            l4_proto: 6,
            ttl_hlim: 64,
            l3_len: 1500,
            sport: 443,
            dport: 51000,
            tcp_flags: 0x18,
            rsv0: 0,
            rsv1: 0,
            seq_lo: 0xdead_beef,
        }
    }

    #[test]
    fn offsets_match_the_c_asserts() {
        let raw = sample().encode();
        assert_eq!(raw.len(), 80);
        assert_eq!(raw[0], 1);
        assert_eq!(raw[1], 0x11);
        assert_eq!(&raw[2..4], &[0x02, 0x03]);
        assert_eq!(&raw[4..8], &1514u32.to_le_bytes());
        assert_eq!(&raw[8..16], &[8, 7, 6, 5, 4, 3, 2, 1]);
        assert_eq!(&raw[16..22], &[1, 2, 3, 4, 5, 6]);
        assert_eq!(&raw[22..28], &[7, 8, 9, 10, 11, 12]);
        assert_eq!(&raw[28..30], &[0x00, 0x08]);
        assert_eq!(&raw[30..32], &[0x64, 0x20]);
        assert_eq!(&raw[32..36], &[192, 168, 50, 10]);
        assert_eq!(&raw[48..52], &[1, 1, 1, 1]);
        assert_eq!(raw[64], 6);
        assert_eq!(raw[65], 64);
        assert_eq!(&raw[66..68], &1500u16.to_le_bytes());
        assert_eq!(&raw[68..70], &443u16.to_le_bytes());
        assert_eq!(&raw[70..72], &51000u16.to_le_bytes());
        assert_eq!(raw[72], 0x18);
        assert_eq!(&raw[76..80], &0xdead_beefu32.to_le_bytes());
        assert_eq!(raw_rxq(&raw), 0x0302);
        assert_eq!(raw_seq_lo(&raw), 0xdead_beef);
    }

    #[test]
    fn round_trip() {
        let r = sample();
        assert_eq!(RecordV1::decode(&r.encode()), Decoded::V1(r));
    }

    #[test]
    fn unknown_version_is_not_parsed() {
        let mut raw = sample().encode();
        for v in [0u8, 2, 255] {
            raw[0] = v;
            assert_eq!(RecordV1::decode(&raw), Decoded::Unknown { version: v });
        }
    }

    #[test]
    fn json_is_stamped_version_1() {
        let mut s = String::new();
        sample().write_json(&mut s);
        assert!(s.starts_with("{\"version\":1,\"flags\":17,\"flag_names\":[\"trunc_l3\",\"vlan\"],"));
        assert!(s.contains("\"src_ip\":\"192.168.50.10\""));
        assert!(s.contains("\"dst_mac\":\"01:02:03:04:05:06\""));
        assert!(s.ends_with("\"seq_lo\":3735928559}"));
    }

    #[test]
    fn ip_text_matches_python_fmt_ip() {
        let mut b = [0u8; 16];
        b[0] = 0x20;
        b[1] = 0x01;
        b[15] = 1;
        assert_eq!(fmt_ip(&b, false), "2001:0000:0000:0000:0000:0000:0000:0001");
        assert_eq!(fmt_ip(&b, true), "32.1.0.0");
    }

    #[test]
    fn seq_gaps_wrap() {
        let mut g = SeqGaps::default();
        g.observe(0, 0xffff_fffe);
        g.observe(0, 0xffff_ffff);
        g.observe(0, 0);
        assert_eq!(g.gaps(), 0);
        g.observe(0, 3);
        assert_eq!(g.gaps(), 2);
        g.observe(1, 100);
        assert_eq!(g.gaps(), 2);
        g.observe(0, 3);
        assert_eq!(g.gaps(), 2 + 0xffff_ffff);
    }
}
