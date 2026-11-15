//! Offline modes that read one run file. No BPF, no ring, no root.

use std::fs::File;
use std::io::{BufReader, Write};

use johnny_record_v1::summary::Summary;
use johnny_record_v1::{Decoded, RecordV1, RunFileError, RunFileReader, OUTPUT_VERSION};

use crate::stop;
use crate::stop::Stop;

fn open(path: &str) -> Result<RunFileReader<BufReader<File>>, Stop> {
    let f = File::open(path).map_err(|e| stop!("open {path}: {e}"))?;
    RunFileReader::new(BufReader::with_capacity(1 << 20, f)).map_err(|e| match e {
        RunFileError::Io(e) => stop!("read {path}: {e}"),
        RunFileError::Short { len } => stop!("header-short {path} len={len}"),
        // Bad magic, or a header or record version this reader does not
        // know: say so and leave the file alone.
        RunFileError::Header(_) => stop!("header-corrupt {path}"),
    })
}

/// `--summary FILE`: the Python reader's summary text.
pub fn summary(path: &str, top: usize, out: &mut dyn Write) -> Result<(), Stop> {
    let mut reader = open(path)?;
    let mut sum = Summary::default();
    while let Some(raw) = reader.next_raw().map_err(|e| stop!("read {path}: {e}"))? {
        sum.add(&raw);
    }
    out.write_all(sum.render(path, reader.header(), top).as_bytes())
        .map_err(|e| stop!("write-failed stdout ({e})"))
}

/// `--dump-json FILE`: one JSON object per v1 record, then a closing line
/// with the counts. Records of an unknown version are counted, not printed.
pub fn dump_json(path: &str, out: &mut dyn Write) -> Result<(), Stop> {
    let mut reader = open(path)?;
    let mut records = 0u64;
    let mut unknown = 0u64;
    let mut line = String::new();
    while let Some(raw) = reader.next_raw().map_err(|e| stop!("read {path}: {e}"))? {
        match RecordV1::decode(&raw) {
            Decoded::V1(r) => {
                records += 1;
                line.clear();
                r.write_json(&mut line);
                line.push('\n');
                out.write_all(line.as_bytes())
                    .map_err(|e| stop!("write-failed stdout ({e})"))?;
            }
            Decoded::Unknown { .. } => unknown += 1,
        }
    }
    writeln!(
        out,
        "{{\"version\":{OUTPUT_VERSION},\"event\":\"dump-end\",\"records\":{records},\
         \"unknown_version\":{unknown},\"trailing_bytes\":{}}}",
        reader.trailing_bytes()
    )
    .map_err(|e| stop!("write-failed stdout ({e})"))
}
