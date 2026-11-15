//! The event log. Two renderings of the same events:
//!
//! - `json` (default): one object per line, stamped `"version":1`.
//! - `text`: the Python reader's lines, character for character, so a
//!   check written against its journal still reads this one.

use std::fmt::Write as _;
use std::io::{self, Write};

use johnny_record_v1::{json_str, M2Cfg, OUTPUT_VERSION};

use crate::control::config::{Limits, LogFormat, UnknownVersion};
use crate::stop;
use crate::stop::Stop;

#[derive(Debug, Clone, Copy)]
pub enum PruneWhy {
    Keep(u64),
    Cap(u64),
}

#[derive(Debug)]
pub enum Event<'a> {
    ReaderBegin {
        out_dir: &'a str,
        ring_map_id: u32,
        cfg: M2Cfg,
        limits: Limits,
        on_unknown_version: UnknownVersion,
    },
    FileOpen {
        file: &'a str,
        file_num: u64,
        date_utc: &'a str,
    },
    FileClosed {
        file: &'a str,
        records: u64,
        bytes: u64,
    },
    Pruned {
        name: &'a str,
        why: PruneWhy,
    },
    ReaderEnd {
        reason: &'a str,
        total_files: u64,
        total_records: u64,
        total_bytes: u64,
        seq_gaps: u64,
        ring_discarded: u64,
        unknown_version: u64,
        backlog: u64,
    },
}

fn text(ev: &Event<'_>) -> String {
    match *ev {
        Event::ReaderBegin {
            out_dir,
            ring_map_id,
            cfg,
            limits,
            ..
        } => format!(
            "M1S2B-READER-BEGIN out_dir={out_dir} ring_map_id={ring_map_id} \
             cfg=ver:{},every:{},rate:{},burst:{} \
             file_max_bytes={} file_max_seconds={} keep={} dir_cap={} reserve={}",
            cfg.ver,
            cfg.sample_every,
            cfg.rate,
            cfg.burst,
            limits.file_max_bytes,
            limits.file_max_seconds,
            limits.keep,
            limits.dir_cap_bytes,
            limits.reserve_bytes
        ),
        Event::FileOpen {
            file,
            file_num,
            date_utc,
        } => format!("M1S2B-FILE-OPEN file={file} file_num={file_num} DATE-UTC {date_utc}"),
        Event::FileClosed {
            file,
            records,
            bytes,
        } => format!("M1S2B-FILE-CLOSED file={file} records={records} bytes={bytes}"),
        Event::Pruned { name, why } => match why {
            PruneWhy::Keep(keep) => format!("PRUNED {name} (keep={keep})"),
            PruneWhy::Cap(cap) => format!("PRUNED {name} (cap={cap})"),
        },
        Event::ReaderEnd {
            reason,
            total_files,
            total_records,
            total_bytes,
            seq_gaps,
            ring_discarded,
            unknown_version,
            backlog,
        } => {
            let mut s = format!(
                "M1S2B-READER-END reason={reason} total_files={total_files} \
                 total_records={total_records} total_bytes={total_bytes} \
                 seq_gaps={seq_gaps} ring_discarded={ring_discarded} backlog={backlog}"
            );
            // Not a Python reader field. Shown only when records were skipped.
            if unknown_version > 0 {
                let _ = write!(s, " unknown_version={unknown_version}");
            }
            s
        }
    }
}

fn json(ev: &Event<'_>) -> String {
    let mut s = format!("{{\"version\":{OUTPUT_VERSION},\"event\":");
    match *ev {
        Event::ReaderBegin {
            out_dir,
            ring_map_id,
            cfg,
            limits,
            on_unknown_version,
        } => {
            s.push_str("\"reader-begin\",\"out_dir\":");
            json_str(&mut s, out_dir);
            let _ = write!(
                s,
                ",\"ring_map_id\":{ring_map_id},\"cfg\":{{\"ver\":{},\"sample_every\":{},\
                 \"rate\":{},\"burst\":{}}},\"file_max_bytes\":{},\"file_max_seconds\":{},\
                 \"keep\":{},\"dir_cap_bytes\":{},\"reserve_bytes\":{},\
                 \"on_unknown_version\":\"{}\"",
                cfg.ver,
                cfg.sample_every,
                cfg.rate,
                cfg.burst,
                limits.file_max_bytes,
                limits.file_max_seconds,
                limits.keep,
                limits.dir_cap_bytes,
                limits.reserve_bytes,
                match on_unknown_version {
                    UnknownVersion::Skip => "skip",
                    UnknownVersion::Stop => "stop",
                }
            );
        }
        Event::FileOpen {
            file,
            file_num,
            date_utc,
        } => {
            s.push_str("\"file-open\",\"file\":");
            json_str(&mut s, file);
            let _ = write!(s, ",\"file_num\":{file_num},\"date_utc\":\"{date_utc}\"");
        }
        Event::FileClosed {
            file,
            records,
            bytes,
        } => {
            s.push_str("\"file-closed\",\"file\":");
            json_str(&mut s, file);
            let _ = write!(s, ",\"records\":{records},\"bytes\":{bytes}");
        }
        Event::Pruned { name, why } => {
            s.push_str("\"pruned\",\"file\":");
            json_str(&mut s, name);
            let (reason, limit) = match why {
                PruneWhy::Keep(n) => ("keep", n),
                PruneWhy::Cap(n) => ("cap", n),
            };
            let _ = write!(s, ",\"reason\":\"{reason}\",\"limit\":{limit}");
        }
        Event::ReaderEnd {
            reason,
            total_files,
            total_records,
            total_bytes,
            seq_gaps,
            ring_discarded,
            unknown_version,
            backlog,
        } => {
            s.push_str("\"reader-end\",\"reason\":");
            json_str(&mut s, reason);
            let _ = write!(
                s,
                ",\"total_files\":{total_files},\"total_records\":{total_records},\
                 \"total_bytes\":{total_bytes},\"seq_gaps\":{seq_gaps},\
                 \"ring_discarded\":{ring_discarded},\"unknown_version\":{unknown_version},\
                 \"backlog\":{backlog}"
            );
        }
    }
    s.push('}');
    s
}

/// The STOP line for stderr.
pub fn render_stop(format: LogFormat, stop: &Stop) -> String {
    match format {
        LogFormat::Text => stop.to_string(),
        LogFormat::Json => {
            let mut s = format!("{{\"version\":{OUTPUT_VERSION},\"event\":\"stop\",\"stop\":");
            json_str(&mut s, &stop.to_string());
            s.push('}');
            s
        }
    }
}

pub struct Log {
    format: LogFormat,
    out: Box<dyn Write>,
}

impl Log {
    pub fn new(format: LogFormat, out: Box<dyn Write>) -> Self {
        Log { format, out }
    }

    pub fn stdout(format: LogFormat) -> Self {
        Log::new(format, Box::new(io::stdout()))
    }

    pub fn format(&self) -> LogFormat {
        self.format
    }

    /// Write one event line and flush it. A log that cannot be written is a
    /// STOP: the daemon does not run unrecorded.
    pub fn emit(&mut self, ev: &Event<'_>) -> Result<(), Stop> {
        let line = match self.format {
            LogFormat::Text => text(ev),
            LogFormat::Json => json(ev),
        };
        writeln!(self.out, "{line}")
            .and_then(|()| self.out.flush())
            .map_err(|e| stop!("log-write-failed ({e})"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn limits() -> Limits {
        Limits {
            file_max_bytes: 1 << 30,
            file_max_seconds: 3600,
            keep: 200,
            dir_cap_bytes: 200 << 30,
            reserve_bytes: 100 << 30,
        }
    }

    fn begin() -> Event<'static> {
        Event::ReaderBegin {
            out_dir: "/var/lib/johnny/m1s2b",
            ring_map_id: 12,
            cfg: M2Cfg {
                ver: 1,
                sample_every: 1,
                rate: 1_000_000,
                burst: 100_000,
            },
            limits: limits(),
            on_unknown_version: UnknownVersion::Skip,
        }
    }

    #[test]
    fn text_begin_has_the_cfg_token_paste_c_greps() {
        let line = text(&begin());
        assert_eq!(
            line,
            "M1S2B-READER-BEGIN out_dir=/var/lib/johnny/m1s2b ring_map_id=12 \
             cfg=ver:1,every:1,rate:1000000,burst:100000 file_max_bytes=1073741824 \
             file_max_seconds=3600 keep=200 dir_cap=214748364800 reserve=107374182400"
        );
    }

    #[test]
    fn every_json_line_is_stamped_version_1() {
        let events = [
            begin(),
            Event::FileOpen {
                file: "/o/run-a.bin",
                file_num: 1,
                date_utc: "20261114T232111Z",
            },
            Event::FileClosed {
                file: "/o/run-a.bin",
                records: 2,
                bytes: 256,
            },
            Event::Pruned {
                name: "run-a.bin",
                why: PruneWhy::Keep(3),
            },
            Event::ReaderEnd {
                reason: "signal-15",
                total_files: 1,
                total_records: 2,
                total_bytes: 256,
                seq_gaps: 0,
                ring_discarded: 0,
                unknown_version: 0,
                backlog: 0,
            },
        ];
        for ev in &events {
            let line = json(ev);
            assert!(line.starts_with("{\"version\":1,\"event\":\""), "{line}");
            assert!(line.ends_with('}'), "{line}");
        }
        assert_eq!(
            json(&events[3]),
            "{\"version\":1,\"event\":\"pruned\",\"file\":\"run-a.bin\",\"reason\":\"keep\",\"limit\":3}"
        );
        assert_eq!(
            render_stop(LogFormat::Json, &Stop("low-disk free=1 reserve=2".into())),
            "{\"version\":1,\"event\":\"stop\",\"stop\":\"STOP-low-disk free=1 reserve=2\"}"
        );
    }

    #[test]
    fn text_end_shows_unknown_version_only_when_nonzero() {
        let end = |unknown_version| Event::ReaderEnd {
            reason: "signal-15",
            total_files: 1,
            total_records: 2,
            total_bytes: 256,
            seq_gaps: 3,
            ring_discarded: 4,
            unknown_version,
            backlog: 5,
        };
        assert_eq!(
            text(&end(0)),
            "M1S2B-READER-END reason=signal-15 total_files=1 total_records=2 total_bytes=256 \
             seq_gaps=3 ring_discarded=4 backlog=5"
        );
        assert!(text(&end(7)).ends_with(" backlog=5 unknown_version=7"));
    }
}
