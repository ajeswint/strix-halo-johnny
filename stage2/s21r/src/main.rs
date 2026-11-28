//! Johnny Stage 2 S2-1R `aya =0.16.0` parity loader CLI.
//!
//! Mirrors `stage2/cgtest/loader.py`'s subcommand interface (`self-test`,
//! `probe-and-attach`, `read-stats`, `exec-check`) using `aya =0.16.0` in pure
//! Rust instead of Python `ctypes` + `libbpf.so.1`, loading the same
//! clang-built `stage2/cgtest/build/j_s2_cgtest.bpf.o`.

mod abi;
mod bpf_ops;
mod exec_check;

use std::path::PathBuf;
use std::process::ExitCode;

use exec_check::ExecMode;

const USAGE: &str = "\
Usage:
  s21r-loader self-test [--obj <path>]
  s21r-loader probe-and-attach --obj <path> --pin-dir <dir> --cgroup-dir <dir> --sentinel <path>
  s21r-loader read-stats --pin-dir <dir>
  s21r-loader exec-check --mode <outside|exact> [--expected-cgroup <cg>] [--forbidden-cgroup <cg>] --sentinel <path>
";

#[derive(Debug, PartialEq, Eq)]
enum Command {
    SelfTest {
        obj: Option<PathBuf>,
    },
    ProbeAndAttach {
        obj: PathBuf,
        pin_dir: PathBuf,
        cgroup_dir: PathBuf,
        sentinel: PathBuf,
    },
    ReadStats {
        pin_dir: PathBuf,
    },
    ExecCheck {
        mode: ExecMode,
        sentinel: PathBuf,
    },
}

fn next_val<I: Iterator<Item = String>>(iter: &mut I, flag: &str) -> Result<String, String> {
    iter.next()
        .ok_or_else(|| format!("missing value for {flag}"))
}

fn require_arg(opt: Option<PathBuf>, flag: &str) -> Result<PathBuf, String> {
    opt.ok_or_else(|| format!("missing required flag {flag}"))
}

fn parse_args<I: IntoIterator<Item = String>>(args: I) -> Result<Command, String> {
    let mut it = args.into_iter();
    let sub = it
        .next()
        .ok_or_else(|| "missing subcommand".to_owned())?;

    match sub.as_str() {
        "self-test" => {
            let mut obj = None;
            while let Some(flag) = it.next() {
                match flag.as_str() {
                    "--obj" => obj = Some(PathBuf::from(next_val(&mut it, "--obj")?)),
                    other => return Err(format!("unknown flag for self-test: {other}")),
                }
            }
            Ok(Command::SelfTest { obj })
        }
        "probe-and-attach" => {
            let mut obj = None;
            let mut pin_dir = None;
            let mut cgroup_dir = None;
            let mut sentinel = None;
            while let Some(flag) = it.next() {
                match flag.as_str() {
                    "--obj" => obj = Some(PathBuf::from(next_val(&mut it, "--obj")?)),
                    "--pin-dir" => pin_dir = Some(PathBuf::from(next_val(&mut it, "--pin-dir")?)),
                    "--cgroup-dir" => {
                        cgroup_dir = Some(PathBuf::from(next_val(&mut it, "--cgroup-dir")?));
                    }
                    "--sentinel" => {
                        sentinel = Some(PathBuf::from(next_val(&mut it, "--sentinel")?));
                    }
                    other => return Err(format!("unknown flag for probe-and-attach: {other}")),
                }
            }
            Ok(Command::ProbeAndAttach {
                obj: require_arg(obj, "--obj")?,
                pin_dir: require_arg(pin_dir, "--pin-dir")?,
                cgroup_dir: require_arg(cgroup_dir, "--cgroup-dir")?,
                sentinel: require_arg(sentinel, "--sentinel")?,
            })
        }
        "read-stats" => {
            let mut pin_dir = None;
            while let Some(flag) = it.next() {
                match flag.as_str() {
                    "--pin-dir" => pin_dir = Some(PathBuf::from(next_val(&mut it, "--pin-dir")?)),
                    other => return Err(format!("unknown flag for read-stats: {other}")),
                }
            }
            Ok(Command::ReadStats {
                pin_dir: require_arg(pin_dir, "--pin-dir")?,
            })
        }
        "exec-check" => {
            let mut mode_str: Option<String> = None;
            let mut expected_cgroup = String::new();
            let mut forbidden_cgroup = "0::/johnny-stage2-test".to_owned();
            let mut sentinel = None;
            while let Some(flag) = it.next() {
                match flag.as_str() {
                    "--mode" => mode_str = Some(next_val(&mut it, "--mode")?),
                    "--expected-cgroup" => {
                        expected_cgroup = next_val(&mut it, "--expected-cgroup")?;
                    }
                    "--forbidden-cgroup" => {
                        forbidden_cgroup = next_val(&mut it, "--forbidden-cgroup")?;
                    }
                    "--sentinel" => {
                        sentinel = Some(PathBuf::from(next_val(&mut it, "--sentinel")?));
                    }
                    other => return Err(format!("unknown flag for exec-check: {other}")),
                }
            }
            let mode = match mode_str.as_deref() {
                Some("outside") => ExecMode::Outside { forbidden_cgroup },
                Some("exact") => ExecMode::Exact { expected_cgroup },
                Some(bad) => return Err(format!("STOP-exec-check-bad-mode mode={bad}")),
                None => return Err("missing required flag --mode".to_owned()),
            };
            Ok(Command::ExecCheck {
                mode,
                sentinel: require_arg(sentinel, "--sentinel")?,
            })
        }
        other => Err(format!("unknown subcommand: {other}")),
    }
}

fn main() -> ExitCode {
    let cmd = match parse_args(std::env::args().skip(1)) {
        Ok(c) => c,
        Err(msg) => {
            eprintln!("s21r-loader: error: {msg}\n{USAGE}");
            return ExitCode::from(2);
        }
    };

    let rc = match cmd {
        Command::SelfTest { obj } => bpf_ops::cmd_self_test(obj.as_deref()),
        Command::ProbeAndAttach {
            obj,
            pin_dir,
            cgroup_dir,
            sentinel,
        } => bpf_ops::cmd_probe_and_attach(&obj, &pin_dir, &cgroup_dir, &sentinel),
        Command::ReadStats { pin_dir } => bpf_ops::cmd_read_stats(&pin_dir),
        Command::ExecCheck { mode, sentinel } => exec_check::cmd_exec_check(&mode, &sentinel),
    };

    ExitCode::from((rc & 0xff) as u8)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(items: &[&str]) -> Vec<String> {
        items.iter().map(|v| (*v).to_owned()).collect()
    }

    #[test]
    fn parses_all_subcommands() {
        assert_eq!(
            parse_args(s(&["self-test", "--obj", "/tmp/a.o"])).unwrap(),
            Command::SelfTest {
                obj: Some(PathBuf::from("/tmp/a.o"))
            }
        );
        assert_eq!(
            parse_args(s(&[
                "probe-and-attach",
                "--obj",
                "/tmp/a.o",
                "--pin-dir",
                "/sys/fs/bpf/johnny_s2_cgtest",
                "--cgroup-dir",
                "/sys/fs/cgroup/johnny-stage2-test",
                "--sentinel",
                "/run/s/true",
            ]))
            .unwrap(),
            Command::ProbeAndAttach {
                obj: PathBuf::from("/tmp/a.o"),
                pin_dir: PathBuf::from("/sys/fs/bpf/johnny_s2_cgtest"),
                cgroup_dir: PathBuf::from("/sys/fs/cgroup/johnny-stage2-test"),
                sentinel: PathBuf::from("/run/s/true"),
            }
        );
        assert_eq!(
            parse_args(s(&["read-stats", "--pin-dir", "/sys/fs/bpf/johnny_s2_cgtest"])).unwrap(),
            Command::ReadStats {
                pin_dir: PathBuf::from("/sys/fs/bpf/johnny_s2_cgtest"),
            }
        );
        assert_eq!(
            parse_args(s(&[
                "exec-check",
                "--mode",
                "outside",
                "--forbidden-cgroup",
                "0::/johnny-stage2-test",
                "--sentinel",
                "/run/s/true",
            ]))
            .unwrap(),
            Command::ExecCheck {
                mode: ExecMode::Outside {
                    forbidden_cgroup: "0::/johnny-stage2-test".to_owned(),
                },
                sentinel: PathBuf::from("/run/s/true"),
            }
        );
        assert!(parse_args(s(&["exec-check", "--mode", "bogus", "--sentinel", "/x"])).is_err());
    }
}
