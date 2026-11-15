//! Command line and limits. Same options, defaults, ceilings, and STOP
//! text as `docs/tool-install/johnny-m1s2b-reader.py:65-71`, `:477-491`,
//! `:654-667`.

use std::path::PathBuf;

use johnny_record_v1::{HDR_SIZE, REC_SIZE};

use crate::stop;
use crate::stop::Stop;

pub const PIN_DIR: &str = "/sys/fs/bpf/johnny_m1s2b";
pub const OUT_DIR: &str = "/var/lib/johnny/m1s2b";

pub const DEF_FILE_BYTES: i128 = 64 << 20;
pub const MAX_FILE_BYTES: i128 = 2 << 30;
pub const DEF_FILE_SECONDS: i128 = 3600;
pub const MAX_FILE_SECONDS: i128 = 86400;
pub const DEF_KEEP: i128 = 6;
pub const MAX_KEEP: i128 = 1000;
pub const DEF_DIR_CAP_BYTES: i128 = 384 << 20;
pub const MAX_DIR_CAP_BYTES: i128 = 16 << 40;
pub const DEF_RESERVE_BYTES: i128 = 256 << 20;
pub const MAX_RESERVE_BYTES: i128 = 16 << 40;
pub const DEF_TOP: usize = 10;

/// Validated rotation and retention limits.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    pub file_max_bytes: u64,
    pub file_max_seconds: u64,
    pub keep: u64,
    pub dir_cap_bytes: u64,
    pub reserve_bytes: u64,
}

/// What the drain does with a ring record whose version byte is not 1.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnknownVersion {
    /// Do not write it, count it, keep draining (AJ, 2026-11-14: readers
    /// ignore unknown versions safely).
    Skip,
    /// Stop with `ring-corrupt ver=N`, as the Python reader does.
    Stop,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogFormat {
    /// One JSON object per line, stamped `"version":1`.
    Json,
    /// The Python reader's lines, character for character.
    Text,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunConfig {
    pub file_max_bytes: i128,
    pub file_max_seconds: i128,
    pub keep: i128,
    pub dir_cap_bytes: i128,
    pub reserve_bytes: i128,
    pub pin_dir: PathBuf,
    pub out_dir: PathBuf,
    /// 0 means no limit.
    pub max_total_records: u64,
    /// 0 means no limit.
    pub max_total_seconds: u64,
    pub on_unknown_version: UnknownVersion,
    pub log_format: LogFormat,
}

impl Default for RunConfig {
    fn default() -> Self {
        RunConfig {
            file_max_bytes: DEF_FILE_BYTES,
            file_max_seconds: DEF_FILE_SECONDS,
            keep: DEF_KEEP,
            dir_cap_bytes: DEF_DIR_CAP_BYTES,
            reserve_bytes: DEF_RESERVE_BYTES,
            pin_dir: PathBuf::from(PIN_DIR),
            out_dir: PathBuf::from(OUT_DIR),
            max_total_records: 0,
            max_total_seconds: 0,
            on_unknown_version: UnknownVersion::Skip,
            log_format: LogFormat::Json,
        }
    }
}

fn bounded(name: &str, val: i128, ceiling: i128, floor: i128) -> Result<u64, Stop> {
    if !(floor <= val && val <= ceiling) {
        return Err(stop!("arg-{name} {val} not in {floor}..{ceiling}"));
    }
    Ok(val as u64)
}

impl RunConfig {
    /// Check every limit against its floor and ceiling, in the Python
    /// reader's order.
    pub fn limits(&self) -> Result<Limits, Stop> {
        let file_max_bytes = bounded(
            "file-max-bytes",
            self.file_max_bytes,
            MAX_FILE_BYTES,
            (HDR_SIZE + REC_SIZE) as i128,
        )?;
        let file_max_seconds =
            bounded("file-max-seconds", self.file_max_seconds, MAX_FILE_SECONDS, 1)?;
        let keep = bounded("keep", self.keep, MAX_KEEP, 1)?;
        let dir_cap_bytes = bounded(
            "dir-cap-bytes",
            self.dir_cap_bytes,
            MAX_DIR_CAP_BYTES,
            i128::from(file_max_bytes),
        )?;
        let reserve_bytes = bounded("reserve-bytes", self.reserve_bytes, MAX_RESERVE_BYTES, 1)?;
        Ok(Limits {
            file_max_bytes,
            file_max_seconds,
            keep,
            dir_cap_bytes,
            reserve_bytes,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Mode {
    Run(RunConfig),
    Summary { file: String, top: usize },
    DumpJson { file: String },
    Probe { pin_dir: PathBuf },
    Version,
    Help,
}

/// A command line the daemon cannot read. Exit status 2.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsageError(pub String);

pub const USAGE: &str = "\
usage: johnny-daemon [options]
  (no mode option)            drain <pin-dir>/m2_rb into rotating run files
  --summary FILE [--top N]    print counts for one run file (no BPF)
  --dump-json FILE            print one run file as JSON lines (no BPF)
  --probe                     read-only look at the pinned maps; consumes nothing
  --version
limits (same names and defaults as johnny-m1s2b-reader.py):
  --file-max-bytes N  --file-max-seconds N  --keep N
  --dir-cap-bytes N   --reserve-bytes N
  --pin-dir DIR       --out-dir DIR
  --max-total-records N  --max-total-seconds N
daemon only:
  --log-format json|text          default json (every line has \"version\":1)
  --on-unknown-version skip|stop  default skip
";

fn int(name: &str, v: &str) -> Result<i128, UsageError> {
    v.parse::<i128>()
        .map_err(|_| UsageError(format!("argument {name}: invalid int value: '{v}'")))
}

fn count(name: &str, v: &str) -> Result<u64, UsageError> {
    v.parse::<u64>()
        .map_err(|_| UsageError(format!("argument {name}: invalid count: '{v}'")))
}

pub fn parse<I: IntoIterator<Item = String>>(args: I) -> Result<Mode, UsageError> {
    let mut cfg = RunConfig::default();
    let mut summary: Option<String> = None;
    let mut dump: Option<String> = None;
    let mut top = DEF_TOP;
    let mut probe = false;
    let mut it = args.into_iter();
    while let Some(arg) = it.next() {
        let (name, inline) = match arg.split_once('=') {
            Some((n, v)) if n.starts_with("--") => (n.to_string(), Some(v.to_string())),
            _ => (arg.clone(), None),
        };
        match name.as_str() {
            "--version" => return Ok(Mode::Version),
            "--help" | "-h" => return Ok(Mode::Help),
            "--probe" => {
                probe = true;
                continue;
            }
            _ => {}
        }
        let mut value = || -> Result<String, UsageError> {
            inline
                .clone()
                .or_else(|| it.next())
                .ok_or_else(|| UsageError(format!("argument {name}: expected one argument")))
        };
        match name.as_str() {
            "--file-max-bytes" => cfg.file_max_bytes = int(&name, &value()?)?,
            "--file-max-seconds" => cfg.file_max_seconds = int(&name, &value()?)?,
            "--keep" => cfg.keep = int(&name, &value()?)?,
            "--dir-cap-bytes" => cfg.dir_cap_bytes = int(&name, &value()?)?,
            "--reserve-bytes" => cfg.reserve_bytes = int(&name, &value()?)?,
            "--pin-dir" => cfg.pin_dir = PathBuf::from(value()?),
            "--out-dir" => cfg.out_dir = PathBuf::from(value()?),
            "--max-total-records" => cfg.max_total_records = count(&name, &value()?)?,
            "--max-total-seconds" => cfg.max_total_seconds = count(&name, &value()?)?,
            "--summary" => summary = Some(value()?),
            "--dump-json" => dump = Some(value()?),
            "--top" => {
                let v = value()?;
                top = v
                    .parse::<usize>()
                    .map_err(|_| UsageError(format!("argument --top: invalid count: '{v}'")))?;
            }
            "--log-format" => {
                cfg.log_format = match value()?.as_str() {
                    "json" => LogFormat::Json,
                    "text" => LogFormat::Text,
                    v => return Err(UsageError(format!("argument --log-format: '{v}' is not json or text"))),
                }
            }
            "--on-unknown-version" => {
                cfg.on_unknown_version = match value()?.as_str() {
                    "skip" => UnknownVersion::Skip,
                    "stop" => UnknownVersion::Stop,
                    v => {
                        return Err(UsageError(format!(
                            "argument --on-unknown-version: '{v}' is not skip or stop"
                        )))
                    }
                }
            }
            _ => return Err(UsageError(format!("unrecognized arguments: {arg}"))),
        }
    }
    if let Some(file) = summary {
        return Ok(Mode::Summary { file, top });
    }
    if let Some(file) = dump {
        return Ok(Mode::DumpJson { file });
    }
    if probe {
        return Ok(Mode::Probe {
            pin_dir: cfg.pin_dir,
        });
    }
    Ok(Mode::Run(cfg))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(args: &[&str]) -> Result<Mode, UsageError> {
        parse(args.iter().map(|s| s.to_string()))
    }

    #[test]
    fn defaults_are_the_python_readers() {
        let Mode::Run(cfg) = p(&[]).unwrap() else {
            panic!()
        };
        assert_eq!(
            cfg.limits().unwrap(),
            Limits {
                file_max_bytes: 67_108_864,
                file_max_seconds: 3600,
                keep: 6,
                dir_cap_bytes: 402_653_184,
                reserve_bytes: 268_435_456,
            }
        );
        assert_eq!(cfg.pin_dir, PathBuf::from("/sys/fs/bpf/johnny_m1s2b"));
        assert_eq!(cfg.out_dir, PathBuf::from("/var/lib/johnny/m1s2b"));
    }

    #[test]
    fn live_unit_limits_validate() {
        // ExecStart of etc/systemd/system/johnny-m1s2b-reader.service.
        let Mode::Run(cfg) = p(&[
            "--file-max-bytes",
            "1073741824",
            "--file-max-seconds",
            "3600",
            "--keep",
            "200",
            "--dir-cap-bytes",
            "214748364800",
            "--reserve-bytes=107374182400",
        ])
        .unwrap() else {
            panic!()
        };
        assert_eq!(
            cfg.limits().unwrap(),
            Limits {
                file_max_bytes: 1 << 30,
                file_max_seconds: 3600,
                keep: 200,
                dir_cap_bytes: 200 << 30,
                reserve_bytes: 100 << 30,
            }
        );
    }

    fn stop_of(args: &[&str]) -> String {
        let Mode::Run(cfg) = p(args).unwrap() else {
            panic!()
        };
        cfg.limits().unwrap_err().to_string()
    }

    #[test]
    fn bounds_stop_text() {
        assert_eq!(
            stop_of(&["--file-max-bytes", "2147483649"]),
            "STOP-arg-file-max-bytes 2147483649 not in 176..2147483648"
        );
        assert_eq!(
            stop_of(&["--file-max-bytes", "175"]),
            "STOP-arg-file-max-bytes 175 not in 176..2147483648"
        );
        assert_eq!(
            stop_of(&["--file-max-seconds", "0"]),
            "STOP-arg-file-max-seconds 0 not in 1..86400"
        );
        assert_eq!(stop_of(&["--keep", "1001"]), "STOP-arg-keep 1001 not in 1..1000");
        assert_eq!(
            stop_of(&["--file-max-bytes", "1000", "--dir-cap-bytes", "500"]),
            "STOP-arg-dir-cap-bytes 500 not in 1000..17592186044416"
        );
        assert_eq!(
            stop_of(&["--reserve-bytes", "-1"]),
            "STOP-arg-reserve-bytes -1 not in 1..17592186044416"
        );
    }

    #[test]
    fn modes() {
        assert_eq!(
            p(&["--summary", "f.bin", "--top", "3"]).unwrap(),
            Mode::Summary {
                file: "f.bin".into(),
                top: 3
            }
        );
        assert_eq!(
            p(&["--dump-json=f.bin"]).unwrap(),
            Mode::DumpJson {
                file: "f.bin".into()
            }
        );
        assert_eq!(p(&["--version"]).unwrap(), Mode::Version);
        assert!(matches!(p(&["--probe"]).unwrap(), Mode::Probe { .. }));
        assert!(p(&["--bogus"]).is_err());
        assert!(p(&["--keep"]).is_err());
        assert!(p(&["--keep", "x"]).is_err());
        assert!(p(&["--log-format", "xml"]).is_err());
    }
}
