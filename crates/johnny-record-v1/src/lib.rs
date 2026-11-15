//! Johnny record v1.
//!
//! The 80-byte `struct m2_rec` that `j_xdp_records` puts on ring `m2_rb`
//! (`docs/tool-install/module1_xdp_records.c`) is frozen as implicit v1
//! (AJ, 2026-11-14). This crate is the one place that knows its layout, the
//! 96-byte run-file header written by `docs/tool-install/johnny-m1s2b-reader.py`,
//! and the `"version": 1` stamp on userspace outputs.
//!
//! Readers here ignore what they do not know: an unknown record version is
//! handed back as `Decoded::Unknown` and never parsed as v1, and an unknown
//! header version is an error value, never a panic. New fields come only in
//! v2, which is deferred.

#![forbid(unsafe_code)]

pub mod record;
pub mod runfile;
pub mod summary;
pub mod utc;

pub use record::{Decoded, RecordV1, SeqGaps, REC_SIZE, REC_VERSION};
pub use runfile::{HeaderError, M2Cfg, RunFileError, RunFileReader, RunHeader, HDR_SIZE};

/// The version stamped as `"version"` in every userspace output line.
pub const OUTPUT_VERSION: u32 = 1;

/// Append `s` to `out` as a JSON string (quotes included).
pub fn json_str(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_str_escapes() {
        let mut s = String::new();
        json_str(&mut s, "a\"b\\c\n\u{1}");
        assert_eq!(s, "\"a\\\"b\\\\c\\n\\u0001\"");
    }
}
