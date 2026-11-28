//! `aya =0.16.0` userspace BPF operations for Stage 2 S2-1R parity testing.
//!
//! Source-level capability audit of `aya =0.16.0` (verified in cargo registry
//! `aya-0.16.0` / `aya-obj-0.6.0`; runtime kernel execution is **UNVERIFIED**
//! until AJ runs Paste S2-1R on Rock Box kernel `7.3.0-10-generic`):
//!
//! - Mechanism 1 (`j_s2_cgtest_m1`, `SEC("lsm/bprm_check_security")`):
//!   `aya::programs::Lsm` (`BPF_PROG_TYPE_LSM` + `BPF_LSM_MAC`),
//!   `Lsm::load("bprm_check_security", &btf)` + `Lsm::attach()` + `FdLink::pin`.
//! - Mechanism 2 (`j_s2_cgtest_m2`, `SEC("lsm_cgroup/bprm_check_security")`):
//!   `aya::programs::LsmCgroup` (`BPF_PROG_TYPE_LSM` + `BPF_LSM_CGROUP`),
//!   `LsmCgroup::load("bprm_check_security", &btf)` + `LsmCgroup::attach(&cg_file)`
//!   + `FdLink::pin`.
//! - Global observer (`j_s2_cgtest_obs`, `SEC("lsm/bprm_check_security")`):
//!   same `aya::programs::Lsm` path as M1.
//! - Maps: `aya::maps::Array` (`j_s2_cgtest_cfg`, `j_s2_cgtest_st`) and
//!   `aya::maps::CgroupArray` (`j_s2_cgtest_cg`), pinned via `Map::pin` and
//!   reopened in `read-stats` via `MapData::from_pin`.
//!
//! Known differences from `stage2/cgtest/loader.py` (`libbpf.so.1`) — zero raw
//! `SYS_bpf` workarounds are added here:
//! 1. `aya 0.16.0` only captures verifier logs on `BPF_PROG_LOAD` failure
//!    (`ProgramError::LoadError`); when `load()` succeeds, `aya` discards any
//!    log buffer. On acceptance we print `<aya-0.16.0-omits-log-on-accept>`.
//! 2. `EbpfLoader::load_file` creates all maps declared in the ELF object
//!    before individual program loads (no `bpf_map__set_autocreate(false)`).
//!    When M2 is selected without M1, `j_s2_cgtest_cg` is not pinned and drops
//!    when `Ebpf` drops (runtime teardown **UNVERIFIED** until Paste S2-1R).

use std::fs::{self, DirBuilder, OpenOptions};
use std::io::{self, Write as _};
use std::os::fd::AsRawFd as _;
use std::os::unix::fs::{DirBuilderExt as _, MetadataExt as _, OpenOptionsExt as _};
use std::path::Path;

use aya::maps::{Array, CgroupArray, Map, MapData, MapError};
use aya::programs::links::FdLink;
use aya::programs::{Lsm, LsmCgroup, Program, ProgramError};
use aya::{Btf, EbpfLoader, VerifierLogLevel};
use aya_obj::btf::BtfKind;
use aya_obj::generated::bpf_map_type;
use aya_obj::{Object, ProgramSection};

use crate::abi::{
    check_n12_names, format_log_tail, pack_kernel_sdev, CgTestCfg, CFG_SIZE, LSM_BTF_FUNC_NAME,
    LSM_HOOK_NAME, STAT_NAMES,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ProbeKind {
    Lsm,
    LsmCgroup,
}

fn map_error_errno(err: &MapError) -> i32 {
    match err {
        MapError::SyscallError(s) => s.io_error.raw_os_error().unwrap_or(0),
        _ => 0,
    }
}

/// Unprivileged static verification of ABI packing, N12 naming, `aya-obj 0.6.0`
/// ELF/BTF parsing, and userspace CO-RE relocation against `/sys/kernel/btf/vmlinux`.
///
/// Issues **zero** `bpf()` syscalls; never loads, attaches, or pins anything.
pub fn cmd_self_test(obj_path: Option<&Path>) -> i32 {
    // 1. Verify config struct layout & little-endian round-trip.
    let sample = CgTestCfg {
        sentinel_ino: 123_456,
        target_cgid: 789_012,
        sentinel_sdev: (259 << 20) | 2,
        enabled: 1,
    };
    let encoded = sample.encode();
    if encoded.len() != CFG_SIZE || CgTestCfg::decode(&encoded) != sample {
        println!("STOP-selftest-cfg-abi-mismatch");
        return 1;
    }

    // 2. Verify kernel MKDEV encoding for tmpfs (0:42) and NVMe (259:2).
    let tmpfs_ok = pack_kernel_sdev(libc::makedev(0, 42)).ok() == Some(42);
    let nvme_dev = libc::makedev(259, 2);
    let nvme_packed = pack_kernel_sdev(nvme_dev).ok();
    let nvme_ok = nvme_packed == Some((259 << 20) | 2)
        && nvme_packed.is_some_and(|v| u64::from(v) != nvme_dev);
    if !tmpfs_ok || !nvme_ok {
        println!("STOP-selftest-mkdev-mismatch");
        return 1;
    }

    // 3. Enforce N12 naming contract on expected maps & programs.
    if let Err(detail) = check_n12_names() {
        println!("STOP-selftest-n12 detail={detail}");
        return 1;
    }

    // Report compile-time verified aya 0.16.0 capability surface (runtime kernel
    // attach remains UNVERIFIED until AJ runs Paste S2-1R).
    println!("AYA_CAPABILITIES version=0.16.0 lsm=present lsm_cgroup=present cgroup_array=present");

    // 4. If --obj is supplied, parse ELF + BTF + CO-RE relocations in userspace
    // only (zero bpf() syscalls).
    if let Some(path) = obj_path {
        if !path.is_file() {
            println!("STOP-selftest-missing-obj path={}", path.display());
            return 1;
        }
        let bytes = match fs::read(path) {
            Ok(b) => b,
            Err(err) => {
                println!(
                    "STOP-selftest-read-obj-failed path={} err={err}",
                    path.display()
                );
                return 1;
            }
        };
        let mut obj = match Object::parse(&bytes) {
            Ok(o) => o,
            Err(err) => {
                println!("STOP-selftest-aya-parse-failed err={err}");
                return 1;
            }
        };

        if obj.btf.is_none() || obj.btf_ext.is_none() {
            println!(
                "STOP-selftest-missing-btf btf={} btf_ext={}",
                obj.btf.is_some(),
                obj.btf_ext.is_some()
            );
            return 1;
        }

        let expected_progs = [
            ("j_s2_cgtest_m1", ProbeKind::Lsm),
            ("j_s2_cgtest_m2", ProbeKind::LsmCgroup),
            ("j_s2_cgtest_obs", ProbeKind::Lsm),
        ];
        for (pname, want_kind) in expected_progs {
            match obj.programs.get(pname) {
                None => {
                    println!("STOP-selftest-aya-missing-prog name={pname}");
                    return 1;
                }
                Some(prog) => {
                    let ok = match want_kind {
                        ProbeKind::Lsm => {
                            matches!(prog.section, ProgramSection::Lsm { sleepable: false })
                        }
                        ProbeKind::LsmCgroup => matches!(prog.section, ProgramSection::LsmCgroup),
                    };
                    if !ok {
                        println!(
                            "STOP-selftest-aya-prog-meta name={pname} got={:?} want={want_kind:?}",
                            prog.section
                        );
                        return 1;
                    }
                }
            }
        }

        let expected_maps = [
            (
                "j_s2_cgtest_cfg",
                bpf_map_type::BPF_MAP_TYPE_ARRAY as u32,
                4u32,
                CFG_SIZE as u32,
                1u32,
            ),
            (
                "j_s2_cgtest_st",
                bpf_map_type::BPF_MAP_TYPE_ARRAY as u32,
                4u32,
                8u32,
                STAT_NAMES.len() as u32,
            ),
            (
                "j_s2_cgtest_cg",
                bpf_map_type::BPF_MAP_TYPE_CGROUP_ARRAY as u32,
                4u32,
                4u32,
                1u32,
            ),
        ];
        for (mname, want_ty, want_ks, want_vs, want_max) in expected_maps {
            match obj.maps.get(mname) {
                None => {
                    println!("STOP-selftest-aya-missing-map name={mname}");
                    return 1;
                }
                Some(m) => {
                    let got = (m.map_type(), m.key_size(), m.value_size(), m.max_entries());
                    let want = (want_ty, want_ks, want_vs, want_max);
                    if got != want {
                        println!(
                            "STOP-selftest-aya-map-meta name={mname} got={got:?} want={want:?}"
                        );
                        return 1;
                    }
                }
            }
        }

        // Userspace-only read of /sys/kernel/btf/vmlinux (0444) to verify
        // hook BTF symbol lookup and aya-obj CO-RE relocation without any bpf() syscall.
        let btf = match Btf::from_sys_fs() {
            Ok(b) => b,
            Err(err) => {
                println!("STOP-selftest-btf-read-failed err={err}");
                return 1;
            }
        };
        let hook_btf_id = match btf.id_by_type_name_kind(LSM_BTF_FUNC_NAME, BtfKind::Func) {
            Ok(id) => id,
            Err(err) => {
                println!(
                    "STOP-selftest-btf-hook-missing name={LSM_BTF_FUNC_NAME} err={err}"
                );
                return 1;
            }
        };
        if let Err(err) = obj.relocate_btf(&btf) {
            println!("STOP-selftest-btf-reloc-failed err={err}");
            return 1;
        }
        println!(
            "SELFTEST_OBJ_OK obj={} hook={LSM_BTF_FUNC_NAME} hook_btf_id={hook_btf_id} core_reloc=ok",
            path.display()
        );
    }

    println!("S2-1R-LOADER-SELFTEST-OK");
    0
}

/// Probe a single BPF program against the kernel verifier in an isolated `Ebpf`
/// instance, then drop immediately (unloading the program and temporary maps).
///
/// Runtime kernel behavior is UNVERIFIED until AJ runs Paste S2-1R.
fn probe_single_prog(
    obj_path: &Path,
    btf: &Btf,
    prog_name: &str,
    kind: ProbeKind,
    tag: &str,
) -> Result<bool, String> {
    let mut bpf = match EbpfLoader::new()
        .btf(btf)
        .verifier_log_level(VerifierLogLevel::DEBUG | VerifierLogLevel::STATS)
        .load_file(obj_path)
    {
        Ok(b) => b,
        Err(err) => {
            println!("{tag}=rejected stage=ebpf-load err={err}");
            println!("{tag}-LOG: <empty>");
            return Ok(false);
        }
    };

    let Some(prog) = bpf.program_mut(prog_name) else {
        println!("{tag}=rejected stage=find-prog missing={prog_name}");
        println!("{tag}-LOG: <empty>");
        return Ok(false);
    };

    let load_res = match (kind, prog) {
        (ProbeKind::Lsm, Program::Lsm(p)) => p.load(LSM_HOOK_NAME, btf),
        (ProbeKind::LsmCgroup, Program::LsmCgroup(p)) => p.load(LSM_HOOK_NAME, btf),
        (want, other) => {
            // Revisit trigger 3: attach type missing or parsed as wrong program type.
            let msg = format!(
                "STOP-aya-missing-attach-type trigger=3 prog={prog_name} want={want:?} got={:?}",
                other.prog_type()
            );
            println!("{tag}=rejected stage=attach-type-missing detail={msg}");
            println!("{msg}");
            return Err(msg);
        }
    };

    match load_res {
        Ok(()) => {
            println!("{tag}=accepted");
            println!("{tag}-LOG: <aya-0.16.0-omits-log-on-accept>");
            Ok(true)
        }
        Err(ProgramError::LoadError {
            io_error,
            verifier_log,
        }) => {
            let code = io_error.raw_os_error().unwrap_or(0);
            println!("{tag}=rejected errno={code} ({io_error})");
            for line in format_log_tail(&format!("{tag}-LOG"), &verifier_log.to_string()) {
                println!("{line}");
            }
            Ok(false)
        }
        Err(err) => {
            println!("{tag}=rejected err={err}");
            println!("{tag}-LOG: <empty>");
            Ok(false)
        }
    }
}

struct AttachParams<'a> {
    obj_path: &'a Path,
    pin_dir: &'a Path,
    cgroup_dir: &'a Path,
    btf: &'a Btf,
    use_m1: bool,
    use_obs: bool,
    cfg: CgTestCfg,
}

/// Load, populate maps, create `pin_dir`, pin maps, attach and pin link(s).
///
/// Runtime kernel behavior is UNVERIFIED until AJ runs Paste S2-1R.
fn attach_and_pin(params: &AttachParams<'_>, pin_dir_created: &mut bool) -> Result<(), String> {
    let cg_file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_DIRECTORY)
        .open(params.cgroup_dir)
        .map_err(|e| {
            format!(
                "open cgroup dir {} failed: {e}",
                params.cgroup_dir.display()
            )
        })?;

    let mut bpf = EbpfLoader::new()
        .btf(params.btf)
        .verifier_log_level(VerifierLogLevel::DEBUG | VerifierLogLevel::STATS)
        .load_file(params.obj_path)
        .map_err(|e| format!("EbpfLoader::load_file failed: {e}"))?;

    // Fail-open ordering: populate CGROUP_ARRAY BEFORE enabling cfg and BEFORE
    // attaching any LSM link (mirrors stage2/cgtest/loader.py:293-306).
    if params.use_m1 {
        let cg_map = bpf
            .map_mut("j_s2_cgtest_cg")
            .ok_or_else(|| "missing j_s2_cgtest_cg map".to_owned())?;
        let mut cg_array = CgroupArray::try_from(cg_map)
            .map_err(|e| format!("CgroupArray::try_from(j_s2_cgtest_cg) failed: {e}"))?;
        cg_array
            .set(0, cg_file.as_raw_fd(), 0)
            .map_err(|e| format!("CgroupArray::set(0, cg_fd) failed: {e}"))?;
    }

    {
        let cfg_map = bpf
            .map_mut("j_s2_cgtest_cfg")
            .ok_or_else(|| "missing j_s2_cgtest_cfg map".to_owned())?;
        let mut cfg_array: Array<&mut MapData, [u8; CFG_SIZE]> = Array::try_from(cfg_map)
            .map_err(|e| format!("Array::try_from(j_s2_cgtest_cfg) failed: {e}"))?;
        let raw_cfg = params.cfg.encode();
        cfg_array
            .set(0, &raw_cfg, 0)
            .map_err(|e| format!("Array::set(j_s2_cgtest_cfg[0]) failed: {e}"))?;
    }

    // Create pin_dir exclusively (fail if already exists, matching exist_ok=False).
    DirBuilder::new()
        .mode(0o700)
        .create(params.pin_dir)
        .map_err(|e| format!("mkdir {} failed: {e}", params.pin_dir.display()))?;
    *pin_dir_created = true;

    // Pin maps. When M2 is active without M1, j_s2_cgtest_cg is intentionally
    // left unpinned so it is released when `bpf` drops.
    let mut maps_to_pin = vec!["j_s2_cgtest_cfg", "j_s2_cgtest_st"];
    if params.use_m1 {
        maps_to_pin.push("j_s2_cgtest_cg");
    }
    for mname in maps_to_pin {
        let map = bpf
            .map(mname)
            .ok_or_else(|| format!("missing map {mname} for pinning"))?;
        let mpath = params.pin_dir.join(mname);
        map.pin(&mpath)
            .map_err(|e| format!("map.pin({mname} -> {}) failed: {e}", mpath.display()))?;
    }

    // Load, attach, and pin links. Dropping PinnedLink closes the userspace fd
    // while leaving the bpffs pin holding the kernel link and program alive.
    if params.use_m1 {
        let prog = bpf
            .program_mut("j_s2_cgtest_m1")
            .ok_or_else(|| "missing program j_s2_cgtest_m1".to_owned())?;
        let lsm: &mut Lsm = prog
            .try_into()
            .map_err(|e| format!("j_s2_cgtest_m1 not Lsm (trigger=3): {e}"))?;
        lsm.load(LSM_HOOK_NAME, params.btf)
            .map_err(|e| format!("Lsm::load(j_s2_cgtest_m1) failed: {e}"))?;
        let link_id = lsm
            .attach()
            .map_err(|e| format!("Lsm::attach(j_s2_cgtest_m1) failed: {e}"))?;
        let link = lsm
            .take_link(link_id)
            .map_err(|e| format!("Lsm::take_link(j_s2_cgtest_m1) failed: {e}"))?;
        let fd_link: FdLink = link.into();
        let lpath = params.pin_dir.join("link_m1");
        let _pinned = fd_link
            .pin(&lpath)
            .map_err(|e| format!("FdLink::pin({}) failed: {e}", lpath.display()))?;
    } else {
        let prog = bpf
            .program_mut("j_s2_cgtest_m2")
            .ok_or_else(|| "missing program j_s2_cgtest_m2".to_owned())?;
        let lsm_cg: &mut LsmCgroup = prog
            .try_into()
            .map_err(|e| format!("j_s2_cgtest_m2 not LsmCgroup (trigger=3): {e}"))?;
        lsm_cg
            .load(LSM_HOOK_NAME, params.btf)
            .map_err(|e| format!("LsmCgroup::load(j_s2_cgtest_m2) failed: {e}"))?;
        let link_id = lsm_cg
            .attach(&cg_file)
            .map_err(|e| format!("LsmCgroup::attach(j_s2_cgtest_m2) failed: {e}"))?;
        let link = lsm_cg
            .take_link(link_id)
            .map_err(|e| format!("LsmCgroup::take_link(j_s2_cgtest_m2) failed: {e}"))?;
        let fd_link: FdLink = link.into();
        let lpath = params.pin_dir.join("link_m2");
        let _pinned = fd_link
            .pin(&lpath)
            .map_err(|e| format!("FdLink::pin({}) failed: {e}", lpath.display()))?;

        if params.use_obs {
            let obs_prog = bpf
                .program_mut("j_s2_cgtest_obs")
                .ok_or_else(|| "missing program j_s2_cgtest_obs".to_owned())?;
            let obs: &mut Lsm = obs_prog
                .try_into()
                .map_err(|e| format!("j_s2_cgtest_obs not Lsm (trigger=3): {e}"))?;
            obs.load(LSM_HOOK_NAME, params.btf)
                .map_err(|e| format!("Lsm::load(j_s2_cgtest_obs) failed: {e}"))?;
            let link_id = obs
                .attach()
                .map_err(|e| format!("Lsm::attach(j_s2_cgtest_obs) failed: {e}"))?;
            let link = obs
                .take_link(link_id)
                .map_err(|e| format!("Lsm::take_link(j_s2_cgtest_obs) failed: {e}"))?;
            let fd_link: FdLink = link.into();
            let lpath = params.pin_dir.join("link_obs");
            let _pinned = fd_link
                .pin(&lpath)
                .map_err(|e| format!("FdLink::pin({}) failed: {e}", lpath.display()))?;
        }
    }

    Ok(())
}

/// Probe M1 and M2 against the kernel verifier, select per AJ's Q1/Q2 rules,
/// attach, and pin under `pin_dir`.
///
/// Runtime kernel behavior is UNVERIFIED until AJ runs Paste S2-1R.
pub fn cmd_probe_and_attach(
    obj_path: &Path,
    pin_dir: &Path,
    cgroup_dir: &Path,
    sentinel: &Path,
) -> i32 {
    if !obj_path.is_file() {
        println!("STOP-loader-missing-obj path={}", obj_path.display());
        return 1;
    }
    if !cgroup_dir.is_dir() {
        println!("STOP-loader-missing-cgroup path={}", cgroup_dir.display());
        return 1;
    }
    if !sentinel.is_file() {
        println!("STOP-loader-missing-sentinel path={}", sentinel.display());
        return 1;
    }

    let st_sentinel = match fs::metadata(sentinel) {
        Ok(m) => m,
        Err(err) => {
            println!("STOP-attach-failed detail=stat sentinel failed: {err}");
            return 1;
        }
    };
    let st_cgroup = match fs::metadata(cgroup_dir) {
        Ok(m) => m,
        Err(err) => {
            println!("STOP-attach-failed detail=stat cgroup_dir failed: {err}");
            return 1;
        }
    };

    let sentinel_ino = st_sentinel.ino();
    let st_dev = st_sentinel.dev();
    let sentinel_sdev = match pack_kernel_sdev(st_dev) {
        Ok(v) => v,
        Err(detail) => {
            println!("STOP-attach-failed detail={detail}");
            return 1;
        }
    };
    let target_cgid = st_cgroup.ino();

    println!(
        "TARGET sentinel={} ino={sentinel_ino} st_dev={}:{} kernel_sdev=0x{sentinel_sdev:x} cgroup_dir={} target_cgid={target_cgid}",
        sentinel.display(),
        libc::major(st_dev),
        libc::minor(st_dev),
        cgroup_dir.display()
    );
    let _ = io::stdout().flush();

    let btf = match Btf::from_sys_fs() {
        Ok(b) => b,
        Err(err) => {
            println!("STOP-attach-failed detail=Btf::from_sys_fs failed: {err}");
            return 1;
        }
    };

    // Always probe BOTH M1 and M2 against the kernel verifier (AJ 2026-11-22).
    let m1_ok = match probe_single_prog(obj_path, &btf, "j_s2_cgtest_m1", ProbeKind::Lsm, "VERIFIER-M1") {
        Ok(ok) => ok,
        Err(_) => return 1,
    };
    let m2_ok = match probe_single_prog(
        obj_path,
        &btf,
        "j_s2_cgtest_m2",
        ProbeKind::LsmCgroup,
        "VERIFIER-M2",
    ) {
        Ok(ok) => ok,
        Err(_) => return 1,
    };

    if !m1_ok && !m2_ok {
        println!("STOP-verifier-both-rejected");
        return 1;
    }

    let use_m1 = m1_ok;
    let use_obs = if use_m1 {
        println!("ACTIVE_MECHANISM=M1");
        false
    } else {
        println!("ACTIVE_MECHANISM=M2");
        match probe_single_prog(
            obj_path,
            &btf,
            "j_s2_cgtest_obs",
            ProbeKind::Lsm,
            "VERIFIER-M2-OBS",
        ) {
            Ok(ok) => ok,
            Err(_) => return 1,
        }
    };
    let _ = io::stdout().flush();

    let params = AttachParams {
        obj_path,
        pin_dir,
        cgroup_dir,
        btf: &btf,
        use_m1,
        use_obs,
        cfg: CgTestCfg {
            sentinel_ino,
            target_cgid,
            sentinel_sdev,
            enabled: 1,
        },
    };

    let mut pin_dir_created = false;
    match attach_and_pin(&params, &mut pin_dir_created) {
        Ok(()) => {
            let mech = if use_m1 { "M1" } else { "M2" };
            let obs_str = if use_m1 {
                "na"
            } else if use_obs {
                "yes"
            } else {
                "no"
            };
            println!(
                "ATTACH-DONE mechanism={mech} obs={obs_str} sentinel_ino={sentinel_ino} sentinel_sdev=0x{sentinel_sdev:x} target_cgid={target_cgid}"
            );
            0
        }
        Err(detail) => {
            println!("STOP-attach-failed detail={detail}");
            if pin_dir_created && pin_dir.exists() {
                let _ = fs::remove_dir_all(pin_dir);
            }
            1
        }
    }
}

/// Read the 8 `u64` stat slots from the pinned `j_s2_cgtest_st` array map.
///
/// Runtime kernel behavior is UNVERIFIED until AJ runs Paste S2-1R.
pub fn cmd_read_stats(pin_dir: &Path) -> i32 {
    let st_pin = pin_dir.join("j_s2_cgtest_st");
    let data = match MapData::from_pin(&st_pin) {
        Ok(d) => d,
        Err(err) => {
            println!(
                "STOP-read-stats-open-failed path={} errno={} ({err})",
                st_pin.display(),
                map_error_errno(&err)
            );
            return 1;
        }
    };
    let map = match Map::from_map_data(data) {
        Ok(m) => m,
        Err(err) => {
            println!(
                "STOP-read-stats-open-failed path={} errno={} ({err})",
                st_pin.display(),
                map_error_errno(&err)
            );
            return 1;
        }
    };
    let stats: Array<MapData, u64> = match Array::try_from(map) {
        Ok(a) => a,
        Err(err) => {
            println!(
                "STOP-read-stats-open-failed path={} errno={} ({err})",
                st_pin.display(),
                map_error_errno(&err)
            );
            return 1;
        }
    };

    let mut parts = Vec::with_capacity(STAT_NAMES.len());
    for (idx, name) in STAT_NAMES.iter().enumerate() {
        match stats.get(&(idx as u32), 0) {
            Ok(val) => parts.push(format!("{name}={val}")),
            Err(err) => {
                println!(
                    "STOP-read-stats-lookup-failed slot={idx} errno={} ({err})",
                    map_error_errno(&err)
                );
                return 1;
            }
        }
    }
    println!("STATS {}", parts.join(" "));
    0
}
