//! Policy Engine: every rotation and retention decision, as pure functions
//! of the validated limits. The data plane calls these and does what they
//! say (`docs/tool-install/johnny-m1s2b-reader.py:311-359`, `:447`).

use johnny_record_v1::REC_SIZE;

use crate::control::config::{Limits, UnknownVersion};
use crate::stop;
use crate::stop::Stop;

pub const RUN_PREFIX: &str = "run-";
pub const RUN_SUFFIX: &str = ".bin";

#[derive(Debug, Clone, Copy)]
pub struct Policy {
    pub limits: Limits,
    pub on_unknown_version: UnknownVersion,
}

/// Which of the oldest-first files the byte cap deletes, and whether the
/// directory then has room for one more full file.
#[derive(Debug, PartialEq, Eq)]
pub struct CapPlan {
    pub delete: usize,
    pub verdict: Result<(), Stop>,
}

impl Policy {
    /// Before a record is written: must a new file be opened first?
    pub fn must_rotate(&self, file_open: bool, file_bytes: u64, elapsed_ns: u64) -> bool {
        !file_open
            || file_bytes + REC_SIZE as u64 > self.limits.file_max_bytes
            || self.time_rotation_due(elapsed_ns)
    }

    /// Has the open file reached its age limit?
    pub fn time_rotation_due(&self, elapsed_ns: u64) -> bool {
        elapsed_ns >= self.limits.file_max_seconds * 1_000_000_000
    }

    /// Stop when free space is below the reserve.
    pub fn disk_ok(&self, free: u64) -> Result<(), Stop> {
        if free < self.limits.reserve_bytes {
            return Err(stop!(
                "low-disk free={free} reserve={}",
                self.limits.reserve_bytes
            ));
        }
        Ok(())
    }

    /// How many of the oldest files to delete so that at most `keep - 1`
    /// remain before a new one is opened.
    pub fn keep_prune(&self, existing: usize) -> usize {
        (existing as u64).saturating_sub(self.limits.keep - 1) as usize
    }

    /// `sizes` are the files left after `keep_prune`, oldest first. Delete
    /// oldest first until they plus one full new file fit under the cap.
    pub fn cap_prune(&self, sizes: &[u64]) -> CapPlan {
        let reserved = self.limits.file_max_bytes;
        let cap = self.limits.dir_cap_bytes;
        let mut total: u64 = sizes.iter().sum();
        let mut delete = 0;
        while delete < sizes.len() && total + reserved > cap {
            total -= sizes[delete];
            delete += 1;
        }
        let verdict = if total + reserved > cap {
            Err(stop!(
                "dir-cap-exceeded dir_bytes={} cap={cap}",
                total + reserved
            ))
        } else {
            Ok(())
        };
        CapPlan { delete, verdict }
    }
}

pub fn is_run_file(name: &str) -> bool {
    name.starts_with(RUN_PREFIX) && name.ends_with(RUN_SUFFIX)
}

/// `run-<UTC>.bin`, or `run-<UTC>-NN.bin` when that second already has a file.
pub fn run_file_name(utc: &str, idx: u32) -> String {
    if idx == 0 {
        format!("{RUN_PREFIX}{utc}{RUN_SUFFIX}")
    } else {
        format!("{RUN_PREFIX}{utc}-{idx:02}{RUN_SUFFIX}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy(file_max_bytes: u64, file_max_seconds: u64, keep: u64, cap: u64) -> Policy {
        Policy {
            limits: Limits {
                file_max_bytes,
                file_max_seconds,
                keep,
                dir_cap_bytes: cap,
                reserve_bytes: 1024,
            },
            on_unknown_version: UnknownVersion::Skip,
        }
    }

    #[test]
    fn rotation() {
        let p = policy(96 + 160, 3600, 3, 100_000);
        assert!(p.must_rotate(false, 0, 0));
        assert!(!p.must_rotate(true, 96, 0));
        assert!(!p.must_rotate(true, 96 + 80, 0));
        assert!(p.must_rotate(true, 96 + 160, 0));
        assert!(!p.must_rotate(true, 96, 3_599_999_999_999));
        assert!(p.must_rotate(true, 96, 3_600_000_000_000));
    }

    #[test]
    fn keep_prune_leaves_keep_minus_one() {
        // The self-test's case: 5 files, keep=3 -> 2 remain.
        assert_eq!(policy(100, 1, 3, 10_000).keep_prune(5), 3);
        assert_eq!(policy(100, 1, 3, 10_000).keep_prune(2), 0);
        assert_eq!(policy(100, 1, 1, 10_000).keep_prune(1), 1);
        assert_eq!(policy(100, 1, 200, 10_000).keep_prune(5), 0);
    }

    #[test]
    fn cap_prune_matches_the_self_test_cases() {
        // 2 x 100 bytes, cap 150, new file 100 -> delete both.
        let plan = policy(100, 1, 10, 150).cap_prune(&[100, 100]);
        assert_eq!(plan, CapPlan { delete: 2, verdict: Ok(()) });
        // 5 x 500 bytes, cap 1600, new file 500 -> the 2 newest stay.
        let plan = policy(500, 1, 200, 1600).cap_prune(&[500; 5]);
        assert_eq!(plan, CapPlan { delete: 3, verdict: Ok(()) });
        let plan = policy(500, 1, 200, 1600).cap_prune(&[]);
        assert_eq!(plan, CapPlan { delete: 0, verdict: Ok(()) });
    }

    #[test]
    fn low_disk() {
        let p = policy(100, 1, 3, 1000);
        assert_eq!(p.disk_ok(1024), Ok(()));
        assert_eq!(
            p.disk_ok(1023).unwrap_err().to_string(),
            "STOP-low-disk free=1023 reserve=1024"
        );
    }

    #[test]
    fn names() {
        assert_eq!(run_file_name("20261114T232111Z", 0), "run-20261114T232111Z.bin");
        assert_eq!(run_file_name("20261114T232111Z", 1), "run-20261114T232111Z-01.bin");
        assert_eq!(run_file_name("20261114T232111Z", 123), "run-20261114T232111Z-123.bin");
        assert!(is_run_file("run-x.bin"));
        assert!(!is_run_file("run-x.bin.tmp"));
        assert!(!is_run_file("xrun-.bin"));
    }
}
