//! Wire ABI and naming constants shared with `stage2/cgtest/j_s2_cgtest.bpf.c`.
//!
//! Keep in sync with `stage2/cgtest/j_s2_cgtest.bpf.c` (do not modify that
//! SHA-pinned C BPF file).

/// Byte size of `struct j_s2_cgtest_cfg` (`<QQII`, 24 bytes little-endian).
pub const CFG_SIZE: usize = 24;

/// Kernel LSM hook suffix passed to `aya::programs::Lsm::load` and
/// `aya::programs::LsmCgroup::load` (aya prepends `bpf_lsm_`).
pub const LSM_HOOK_NAME: &str = "bprm_check_security";

/// Full kernel BTF function name resolved by `aya` for `bprm_check_security`.
pub const LSM_BTF_FUNC_NAME: &str = "bpf_lsm_bprm_check_security";

/// Ordered stat slot names matching `enum { ST_* }` in `j_s2_cgtest.bpf.c`.
pub const STAT_NAMES: [&str; 8] = [
    "observed_outside",
    "denied_inside",
    "denied_outside",
    "cg_helper_err",
    "last_cgid_out",
    "last_cgid_in",
    "m2_seen",
    "obs_seen",
];

/// Expected BPF program symbols in `j_s2_cgtest.bpf.o`.
pub const EXPECTED_PROGS: [&str; 3] = ["j_s2_cgtest_m1", "j_s2_cgtest_m2", "j_s2_cgtest_obs"];

/// Expected BPF map symbols in `j_s2_cgtest.bpf.o`.
pub const EXPECTED_MAPS: [&str; 3] = ["j_s2_cgtest_cfg", "j_s2_cgtest_st", "j_s2_cgtest_cg"];

/// PR #50 N12 naming contract prefix and kernel `BPF_OBJ_NAME_LEN - 1` limit.
pub const NAME_PREFIX: &str = "j_s2_cgtest_";
pub const MAX_BPF_NAME_LEN: usize = 15;

/// Tail line count for printed verifier rejection logs (matches `loader.py`).
pub const VERIFIER_LOG_TAIL_LINES: usize = 25;

/// Runtime configuration stored at key 0 of `j_s2_cgtest_cfg`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CgTestCfg {
    pub sentinel_ino: u64,
    pub target_cgid: u64,
    pub sentinel_sdev: u32,
    pub enabled: u32,
}

impl CgTestCfg {
    /// Encode as 24-byte little-endian layout matching `struct j_s2_cgtest_cfg`.
    pub fn encode(&self) -> [u8; CFG_SIZE] {
        let mut out = [0u8; CFG_SIZE];
        out[0..8].copy_from_slice(&self.sentinel_ino.to_le_bytes());
        out[8..16].copy_from_slice(&self.target_cgid.to_le_bytes());
        out[16..20].copy_from_slice(&self.sentinel_sdev.to_le_bytes());
        out[20..24].copy_from_slice(&self.enabled.to_le_bytes());
        out
    }

    /// Decode from 24-byte little-endian layout.
    pub fn decode(raw: &[u8; CFG_SIZE]) -> Self {
        let sentinel_ino = u64::from_le_bytes([
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
        ]);
        let target_cgid = u64::from_le_bytes([
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15],
        ]);
        let sentinel_sdev = u32::from_le_bytes([raw[16], raw[17], raw[18], raw[19]]);
        let enabled = u32::from_le_bytes([raw[20], raw[21], raw[22], raw[23]]);
        Self {
            sentinel_ino,
            target_cgid,
            sentinel_sdev,
            enabled,
        }
    }
}

/// Pack userspace `stat(2)` `st_dev` into Linux kernel `dev_t` (`i_sb->s_dev`):
/// `MKDEV(major, minor) = (major << 20) | minor`.
pub fn pack_kernel_sdev(st_dev: libc::dev_t) -> Result<u32, String> {
    let maj = libc::major(st_dev);
    let min = libc::minor(st_dev);
    pack_kernel_sdev_parts(maj, min)
}

/// Pack `(major, minor)` into kernel `dev_t` (`12` bits major, `20` bits minor).
pub fn pack_kernel_sdev_parts(major: u32, minor: u32) -> Result<u32, String> {
    if major >= (1 << 12) || minor >= (1 << 20) {
        return Err(format!(
            "device numbers out of kernel dev_t range: major={major} minor={minor}"
        ));
    }
    Ok((major << 20) | minor)
}

/// Check the N12 naming contract (`j_s2_cgtest_` prefix and `<= 15` chars).
pub fn check_n12_names() -> Result<(), String> {
    for name in EXPECTED_MAPS.iter().chain(EXPECTED_PROGS.iter()) {
        if !name.starts_with(NAME_PREFIX) {
            return Err(format!("name missing prefix {NAME_PREFIX}: {name}"));
        }
        if name.len() > MAX_BPF_NAME_LEN {
            return Err(format!(
                "name exceeds {MAX_BPF_NAME_LEN} chars: {name} ({})",
                name.len()
            ));
        }
    }
    Ok(())
}

/// Format the tail of a verifier log with a consistent prefix per line.
pub fn format_log_tail(tag: &str, text: &str) -> Vec<String> {
    let lines: Vec<&str> = text
        .lines()
        .map(str::trim_end)
        .filter(|ln| !ln.trim().is_empty())
        .collect();
    if lines.is_empty() {
        return vec![format!("{tag}: <empty>")];
    }
    let start = lines.len().saturating_sub(VERIFIER_LOG_TAIL_LINES);
    lines[start..]
        .iter()
        .map(|ln| format!("{tag}: {ln}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cfg_round_trip_matches_bpf_c_layout() {
        let cfg = CgTestCfg {
            sentinel_ino: 123_456,
            target_cgid: 789_012,
            sentinel_sdev: (259 << 20) | 2,
            enabled: 1,
        };
        let raw = cfg.encode();
        assert_eq!(raw.len(), 24);
        assert_eq!(CgTestCfg::decode(&raw), cfg);
        assert_eq!(
            u32::from_le_bytes([raw[16], raw[17], raw[18], raw[19]]),
            0x1030_0002
        );
        assert_eq!(u32::from_le_bytes([raw[20], raw[21], raw[22], raw[23]]), 1);
    }

    #[test]
    fn pack_kernel_sdev_matches_tmpfs_and_nvme() {
        let tmpfs = libc::makedev(0, 42);
        assert_eq!(pack_kernel_sdev(tmpfs).unwrap(), 42);

        let nvme = libc::makedev(259, 2);
        let packed = pack_kernel_sdev(nvme).unwrap();
        assert_eq!(packed, (259 << 20) | 2);
        assert_ne!(u64::from(packed), nvme);
    }

    #[test]
    fn pack_kernel_sdev_rejects_overflow() {
        assert!(pack_kernel_sdev_parts(4096, 0).is_err());
        assert!(pack_kernel_sdev_parts(0, 1 << 20).is_err());
    }

    #[test]
    fn n12_names_within_kernel_limit() {
        assert!(check_n12_names().is_ok());
    }

    #[test]
    fn log_tail_truncates_to_last_25_non_empty_lines() {
        assert_eq!(format_log_tail("TAG", "  \n\n "), vec!["TAG: <empty>"]);
        let body: String = (1..=30).map(|i| format!("line-{i}\n\n")).collect();
        let out = format_log_tail("VERIFIER-M1-LOG", &body);
        assert_eq!(out.len(), VERIFIER_LOG_TAIL_LINES);
        assert_eq!(out.first().unwrap(), "VERIFIER-M1-LOG: line-6");
        assert_eq!(out.last().unwrap(), "VERIFIER-M1-LOG: line-30");
    }
}
