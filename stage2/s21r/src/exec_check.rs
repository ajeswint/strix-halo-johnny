//! `/proc/self/cgroup` assertion and direct `execv(2)` check for Cases A–C.

use std::ffi::CString;
use std::fs;
use std::io::{self, Write as _};
use std::os::unix::ffi::OsStrExt as _;
use std::path::Path;
use std::ptr;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExecMode {
    Outside { forbidden_cgroup: String },
    Exact { expected_cgroup: String },
}

/// Parse `/proc/self/cgroup` expecting a single unified cgroup v2 line.
pub fn parse_self_cgroup(contents: &str) -> Result<String, String> {
    let lines: Vec<&str> = contents
        .lines()
        .map(str::trim)
        .filter(|ln| !ln.is_empty())
        .collect();
    if lines.len() != 1 {
        return Err(format!("unexpected /proc/self/cgroup lines={lines:?}"));
    }
    Ok(lines[0].to_owned())
}

/// Check that the current process cgroup satisfies the Case A/B/C assertion.
pub fn check_cgroup_match(cg: &str, mode: &ExecMode) -> Result<(), (i32, String)> {
    match mode {
        ExecMode::Outside { forbidden_cgroup } => {
            let under_forbidden = cg == forbidden_cgroup
                || cg
                    .strip_prefix(forbidden_cgroup.as_str())
                    .is_some_and(|rest| rest.starts_with('/'));
            if under_forbidden {
                return Err((124, format!("STOP-case-a-in-test-cgroup cgroup={cg}")));
            }
            Ok(())
        }
        ExecMode::Exact { expected_cgroup } => {
            if cg != expected_cgroup {
                return Err((
                    124,
                    format!("CGROUP_MISMATCH got={cg} expected={expected_cgroup}"),
                ));
            }
            Ok(())
        }
    }
}

/// Map common Linux errno numbers to symbolic names for `EXEC_RESULT` output.
pub fn errno_name(code: i32) -> String {
    match code {
        libc::EPERM => "EPERM".to_owned(),
        libc::ENOENT => "ENOENT".to_owned(),
        libc::EACCES => "EACCES".to_owned(),
        libc::EINVAL => "EINVAL".to_owned(),
        libc::ENOEXEC => "ENOEXEC".to_owned(),
        libc::EFAULT => "EFAULT".to_owned(),
        libc::ENOTDIR => "ENOTDIR".to_owned(),
        libc::EBUSY => "EBUSY".to_owned(),
        libc::EEXIST => "EEXIST".to_owned(),
        libc::ENOSPC => "ENOSPC".to_owned(),
        libc::ENOMEM => "ENOMEM".to_owned(),
        libc::EOPNOTSUPP => "EOPNOTSUPP".to_owned(),
        libc::EBADF => "EBADF".to_owned(),
        libc::E2BIG => "E2BIG".to_owned(),
        libc::EAGAIN => "EAGAIN".to_owned(),
        other => other.to_string(),
    }
}

/// Read `/proc/self/cgroup`, assert expected membership, then `execv(sentinel)`.
pub fn cmd_exec_check(mode: &ExecMode, sentinel: &Path) -> i32 {
    let raw = match fs::read_to_string("/proc/self/cgroup") {
        Ok(s) => s,
        Err(err) => {
            println!("STOP-exec-check-read-cgroup err={err}");
            let _ = io::stdout().flush();
            return 125;
        }
    };
    let cg = match parse_self_cgroup(&raw) {
        Ok(c) => c,
        Err(err) => {
            println!("STOP-exec-check-parse-cgroup detail={err}");
            let _ = io::stdout().flush();
            return 125;
        }
    };

    println!("SELF_CGROUP {cg}");
    let _ = io::stdout().flush();

    if let Err((rc, msg)) = check_cgroup_match(&cg, mode) {
        println!("{msg}");
        let _ = io::stdout().flush();
        return rc;
    }

    let c_sentinel = match CString::new(sentinel.as_os_str().as_bytes()) {
        Ok(s) => s,
        Err(err) => {
            println!("STOP-exec-check-bad-sentinel err={err}");
            let _ = io::stdout().flush();
            return 125;
        }
    };

    // Match loader.py `os.execv(args.sentinel, [args.sentinel])`:
    // argv[0] keeps basename `true` so rust-coreutils multi-call `/bin/true`
    // dispatches correctly.
    let argv: [*const libc::c_char; 2] = [c_sentinel.as_ptr(), ptr::null()];
    // SAFETY: c_sentinel is NUL-terminated and argv is NULL-terminated.
    unsafe {
        libc::execv(c_sentinel.as_ptr(), argv.as_ptr());
    }

    // execv only returns on error.
    let err = io::Error::last_os_error();
    let code = err.raw_os_error().unwrap_or(0);
    let ename = errno_name(code);
    println!("EXEC_RESULT denied errno={code} name={ename} msg={err}");
    let _ = io::stdout().flush();
    if code == libc::EPERM {
        126
    } else {
        125
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_self_cgroup_accepts_single_unified_line() {
        let got = parse_self_cgroup("0::/johnny-stage2-test\n").unwrap();
        assert_eq!(got, "0::/johnny-stage2-test");
        assert!(parse_self_cgroup("").is_err());
        assert!(parse_self_cgroup("0::/a\n1::/b\n").is_err());
    }

    #[test]
    fn outside_mode_rejects_test_cgroup_and_children_only() {
        let mode = ExecMode::Outside {
            forbidden_cgroup: "0::/johnny-stage2-test".to_owned(),
        };
        assert!(check_cgroup_match("0::/user.slice/user-1000.slice", &mode).is_ok());
        assert!(check_cgroup_match("0::/johnny-stage2-test-other", &mode).is_ok());
        assert_eq!(
            check_cgroup_match("0::/johnny-stage2-test", &mode)
                .unwrap_err()
                .0,
            124
        );
        assert_eq!(
            check_cgroup_match("0::/johnny-stage2-test/nested-child", &mode)
                .unwrap_err()
                .0,
            124
        );
    }

    #[test]
    fn exact_mode_requires_exact_string_match() {
        let mode = ExecMode::Exact {
            expected_cgroup: "0::/johnny-stage2-test/nested-child".to_owned(),
        };
        assert!(check_cgroup_match("0::/johnny-stage2-test/nested-child", &mode).is_ok());
        assert_eq!(
            check_cgroup_match("0::/johnny-stage2-test", &mode)
                .unwrap_err()
                .0,
            124
        );
    }
}
