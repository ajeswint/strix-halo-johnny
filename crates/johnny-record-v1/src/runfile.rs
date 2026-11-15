//! The run file: a 96-byte header, then 80-byte records.
//!
//! Header layout is the Python reader's `HDR = "<8sHHBxxxqQIIII6Q"`
//! (`docs/tool-install/johnny-m1s2b-reader.py:58-63`):
//!
//! | bytes  | field                                   |
//! |--------|-----------------------------------------|
//! | 0..8   | magic `JM1S2RB\0`                       |
//! | 8..10  | header version (1)                      |
//! | 10..12 | record size (80)                        |
//! | 12     | record version (1)                      |
//! | 13..16 | pad, zero                               |
//! | 16..24 | CLOCK_MONOTONIC -> CLOCK_REALTIME offset, ns (i64) |
//! | 24..32 | file start, CLOCK_MONOTONIC ns          |
//! | 32..48 | `m2_cfg` snapshot: ver, sample_every, rate, burst |
//! | 48..96 | `m2_ctl` sums at file start, 6 x u64    |

use std::fmt;
use std::io::{self, Read};

use crate::record::{REC_SIZE, REC_VERSION};

pub const MAGIC: [u8; 8] = *b"JM1S2RB\0";
pub const HDR_SIZE: usize = 96;
pub const HDR_VERSION: u16 = 1;
pub const CFG_SIZE: usize = 16;

/// `m2_ctl` slots, in key order.
pub const CTL_NAMES: [&str; 6] = [
    "seen",
    "sampled_out",
    "rate_limited",
    "rb_full",
    "emitted",
    "discarded",
];

/// `struct m2_cfg` (`docs/tool-install/module1_xdp_records.c:167-174`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct M2Cfg {
    pub ver: u32,
    pub sample_every: u32,
    pub rate: u32,
    pub burst: u32,
}

impl M2Cfg {
    pub fn decode(raw: &[u8; CFG_SIZE]) -> Self {
        let w = |i: usize| u32::from_le_bytes([raw[i], raw[i + 1], raw[i + 2], raw[i + 3]]);
        M2Cfg {
            ver: w(0),
            sample_every: w(4),
            rate: w(8),
            burst: w(12),
        }
    }

    pub fn encode(&self) -> [u8; CFG_SIZE] {
        let mut raw = [0u8; CFG_SIZE];
        raw[0..4].copy_from_slice(&self.ver.to_le_bytes());
        raw[4..8].copy_from_slice(&self.sample_every.to_le_bytes());
        raw[8..12].copy_from_slice(&self.rate.to_le_bytes());
        raw[12..16].copy_from_slice(&self.burst.to_le_bytes());
        raw
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RunHeader {
    pub hdr_version: u16,
    pub rec_size: u16,
    pub rec_version: u8,
    pub mono_to_real_ns: i64,
    pub start_mono_ns: u64,
    pub cfg: M2Cfg,
    pub ctl_start: [u64; 6],
}

/// Why a header is not a v1 header this reader can use. A reader that meets
/// one of these leaves the file alone; it does not guess at the layout.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeaderError {
    BadMagic,
    UnknownHeaderVersion(u16),
    UnknownRecord { rec_size: u16, rec_version: u8 },
}

impl fmt::Display for HeaderError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            HeaderError::BadMagic => write!(f, "bad magic"),
            HeaderError::UnknownHeaderVersion(v) => write!(f, "unknown header version {v}"),
            HeaderError::UnknownRecord {
                rec_size,
                rec_version,
            } => write!(f, "unknown record size {rec_size} version {rec_version}"),
        }
    }
}

impl RunHeader {
    /// A v1 header for a file that starts now.
    pub fn v1(mono_to_real_ns: i64, start_mono_ns: u64, cfg: M2Cfg, ctl_start: [u64; 6]) -> Self {
        RunHeader {
            hdr_version: HDR_VERSION,
            rec_size: REC_SIZE as u16,
            rec_version: REC_VERSION,
            mono_to_real_ns,
            start_mono_ns,
            cfg,
            ctl_start,
        }
    }

    pub fn encode(&self) -> [u8; HDR_SIZE] {
        let mut raw = [0u8; HDR_SIZE];
        raw[0..8].copy_from_slice(&MAGIC);
        raw[8..10].copy_from_slice(&self.hdr_version.to_le_bytes());
        raw[10..12].copy_from_slice(&self.rec_size.to_le_bytes());
        raw[12] = self.rec_version;
        raw[16..24].copy_from_slice(&self.mono_to_real_ns.to_le_bytes());
        raw[24..32].copy_from_slice(&self.start_mono_ns.to_le_bytes());
        raw[32..48].copy_from_slice(&self.cfg.encode());
        for (i, v) in self.ctl_start.iter().enumerate() {
            raw[48 + 8 * i..56 + 8 * i].copy_from_slice(&v.to_le_bytes());
        }
        raw
    }

    pub fn decode(raw: &[u8; HDR_SIZE]) -> Result<Self, HeaderError> {
        if raw[0..8] != MAGIC {
            return Err(HeaderError::BadMagic);
        }
        let hdr_version = u16::from_le_bytes([raw[8], raw[9]]);
        if hdr_version != HDR_VERSION {
            return Err(HeaderError::UnknownHeaderVersion(hdr_version));
        }
        let rec_size = u16::from_le_bytes([raw[10], raw[11]]);
        let rec_version = raw[12];
        if usize::from(rec_size) != REC_SIZE || rec_version != REC_VERSION {
            return Err(HeaderError::UnknownRecord {
                rec_size,
                rec_version,
            });
        }
        let q = |i: usize| {
            let mut b = [0u8; 8];
            b.copy_from_slice(&raw[i..i + 8]);
            u64::from_le_bytes(b)
        };
        let mut cfg = [0u8; CFG_SIZE];
        cfg.copy_from_slice(&raw[32..48]);
        let mut ctl_start = [0u64; 6];
        for (i, v) in ctl_start.iter_mut().enumerate() {
            *v = q(48 + 8 * i);
        }
        Ok(RunHeader {
            hdr_version,
            rec_size,
            rec_version,
            mono_to_real_ns: q(16) as i64,
            start_mono_ns: q(24),
            cfg: M2Cfg::decode(&cfg),
            ctl_start,
        })
    }

    /// File start as whole seconds since the Unix epoch. Same arithmetic as
    /// the Python reader's summary: a float division, then floor.
    pub fn start_unix_secs(&self) -> i64 {
        let ns = i128::from(self.start_mono_ns) + i128::from(self.mono_to_real_ns);
        (ns as f64 / 1e9).floor() as i64
    }
}

#[derive(Debug)]
pub enum RunFileError {
    Io(io::Error),
    /// Fewer than 96 header bytes.
    Short { len: usize },
    Header(HeaderError),
}

impl fmt::Display for RunFileError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RunFileError::Io(e) => write!(f, "{e}"),
            RunFileError::Short { len } => write!(f, "header short len={len}"),
            RunFileError::Header(e) => write!(f, "{e}"),
        }
    }
}

fn read_full<R: Read>(r: &mut R, buf: &mut [u8]) -> io::Result<usize> {
    let mut got = 0;
    while got < buf.len() {
        match r.read(&mut buf[got..]) {
            Ok(0) => break,
            Ok(n) => got += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(e),
        }
    }
    Ok(got)
}

/// Streams the records of one run file. A trailing partial record (a file
/// still being written, or cut short) is ignored and counted.
pub struct RunFileReader<R> {
    inner: R,
    header: RunHeader,
    trailing_bytes: usize,
    done: bool,
}

impl<R: Read> RunFileReader<R> {
    pub fn new(mut inner: R) -> Result<Self, RunFileError> {
        let mut raw = [0u8; HDR_SIZE];
        let len = read_full(&mut inner, &mut raw).map_err(RunFileError::Io)?;
        if len != HDR_SIZE {
            return Err(RunFileError::Short { len });
        }
        let header = RunHeader::decode(&raw).map_err(RunFileError::Header)?;
        Ok(RunFileReader {
            inner,
            header,
            trailing_bytes: 0,
            done: false,
        })
    }

    pub fn header(&self) -> &RunHeader {
        &self.header
    }

    pub fn next_raw(&mut self) -> io::Result<Option<[u8; REC_SIZE]>> {
        if self.done {
            return Ok(None);
        }
        let mut raw = [0u8; REC_SIZE];
        let len = read_full(&mut self.inner, &mut raw)?;
        if len == REC_SIZE {
            return Ok(Some(raw));
        }
        self.trailing_bytes = len;
        self.done = true;
        Ok(None)
    }

    pub fn trailing_bytes(&self) -> usize {
        self.trailing_bytes
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn header() -> RunHeader {
        RunHeader::v1(
            1_794_000_000_123_456_789,
            5_000_000_000,
            M2Cfg {
                ver: 1,
                sample_every: 1,
                rate: 1_000_000,
                burst: 100_000,
            },
            [10, 0, 0, 0, 10, 0],
        )
    }

    #[test]
    fn header_bytes() {
        let raw = header().encode();
        assert_eq!(&raw[0..8], b"JM1S2RB\0");
        assert_eq!(&raw[8..16], &[1, 0, 80, 0, 1, 0, 0, 0]);
        assert_eq!(&raw[16..24], &1_794_000_000_123_456_789i64.to_le_bytes());
        assert_eq!(&raw[24..32], &5_000_000_000u64.to_le_bytes());
        // The cfg hex the boot helper writes (rate cap removal, rev 114).
        assert_eq!(
            &raw[32..48],
            &[0x01, 0, 0, 0, 0x01, 0, 0, 0, 0x40, 0x42, 0x0f, 0, 0xa0, 0x86, 0x01, 0]
        );
        assert_eq!(&raw[48..56], &10u64.to_le_bytes());
        assert_eq!(&raw[80..88], &10u64.to_le_bytes());
        assert_eq!(RunHeader::decode(&raw), Ok(header()));
    }

    #[test]
    fn unknown_headers_are_errors_not_panics() {
        let good = header().encode();
        let mut raw = good;
        raw[0] = b'X';
        assert_eq!(RunHeader::decode(&raw), Err(HeaderError::BadMagic));
        let mut raw = good;
        raw[8] = 2;
        assert_eq!(
            RunHeader::decode(&raw),
            Err(HeaderError::UnknownHeaderVersion(2))
        );
        let mut raw = good;
        raw[12] = 2;
        assert_eq!(
            RunHeader::decode(&raw),
            Err(HeaderError::UnknownRecord {
                rec_size: 80,
                rec_version: 2
            })
        );
        let mut raw = good;
        raw[10] = 96;
        assert!(matches!(
            RunHeader::decode(&raw),
            Err(HeaderError::UnknownRecord { rec_size: 96, .. })
        ));
    }

    #[test]
    fn reader_ignores_a_trailing_partial_record() {
        let mut file = header().encode().to_vec();
        let mut rec = [0u8; REC_SIZE];
        rec[0] = 1;
        file.extend_from_slice(&rec);
        file.extend_from_slice(&rec);
        file.extend_from_slice(&[1, 2, 3]);
        let mut r = RunFileReader::new(&file[..]).unwrap();
        assert_eq!(r.next_raw().unwrap(), Some(rec));
        assert_eq!(r.next_raw().unwrap(), Some(rec));
        assert_eq!(r.next_raw().unwrap(), None);
        assert_eq!(r.next_raw().unwrap(), None);
        assert_eq!(r.trailing_bytes(), 3);
    }

    #[test]
    fn short_header() {
        assert!(matches!(
            RunFileReader::new(&[0u8; 40][..]),
            Err(RunFileError::Short { len: 40 })
        ));
    }

    #[test]
    fn start_secs() {
        assert_eq!(header().start_unix_secs(), 1_794_000_005);
    }
}
