#!/usr/bin/env python3
"""
Stage 2 S2-1 BPF LSM cgroup-scoping loader and helper.

Uses Rock Box's installed libbpf runtime (/usr/lib/x86_64-linux-gnu/libbpf.so.1)
via ctypes so zero extra packages (no libbpf-dev) are required, while supporting
both Mechanism 1 (SEC("lsm/bprm_check_security") + CGROUP_ARRAY fd population)
and Mechanism 2 (SEC("lsm_cgroup/bprm_check_security") via
bpf_program__attach_cgroup), neither of which bpftool alone can fully drive.

Subcommands:
  self-test        Unprivileged check of libbpf symbols, struct layouts, MKDEV
                   encoding, and compiled ELF program/map names (N12 <=15 chars).
                   Never loads, attaches, or pins anything.
  probe-and-attach Privileged (run by AJ via Paste S2-1): probes BOTH M1 and M2
                   against the kernel verifier, records VERIFIER-M1 / VERIFIER-M2
                   + log tails, then loads/attaches/pins the selected mechanism
                   (preferring M1; falling back to M2 + optional observe-only
                   companion if only M2 is accepted).
  read-stats       Privileged: reads pinned j_s2_cgtest_st map counters.
  exec-check       Asserts /proc/self/cgroup against expected mode, then calls
                   os.execv(sentinel) and reports exact errno (e.g., EPERM=1).
"""

import argparse
import ctypes
import errno
import os
import shutil
import struct
import subprocess
import sys

CFG_FMT = "<QQII"  # sentinel_ino, target_cgid, sentinel_sdev, enabled (24 bytes)
CFG_SIZE = struct.calcsize(CFG_FMT)

STAT_NAMES = (
    "observed_outside",
    "denied_inside",
    "denied_outside",
    "cg_helper_err",
    "last_cgid_out",
    "last_cgid_in",
    "m2_seen",
    "obs_seen",
)

EXPECTED_PROGS = ("j_s2_cgtest_m1", "j_s2_cgtest_m2", "j_s2_cgtest_obs")
EXPECTED_MAPS = ("j_s2_cgtest_cfg", "j_s2_cgtest_st", "j_s2_cgtest_cg")
NAME_PREFIX = "j_s2_cgtest_"
MAX_BPF_NAME_LEN = 15

VERIFIER_LOG_BUF_SIZE = 1024 * 1024  # 1 MiB
VERIFIER_LOG_TAIL_LINES = 25


def pack_kernel_sdev(st_dev: int) -> int:
    """Pack userspace st_dev into Linux kernel dev_t = (major << 20) | minor."""
    return (os.major(st_dev) << 20) | os.minor(st_dev)


def load_libbpf() -> ctypes.CDLL:
    lib = ctypes.CDLL("libbpf.so.1", use_errno=True)

    lib.bpf_object__open_file.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
    lib.bpf_object__open_file.restype = ctypes.c_void_p

    lib.bpf_object__load.argtypes = [ctypes.c_void_p]
    lib.bpf_object__load.restype = ctypes.c_int

    lib.bpf_object__close.argtypes = [ctypes.c_void_p]
    lib.bpf_object__close.restype = None

    lib.bpf_object__find_program_by_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.bpf_object__find_program_by_name.restype = ctypes.c_void_p

    lib.bpf_object__find_map_by_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.bpf_object__find_map_by_name.restype = ctypes.c_void_p

    lib.bpf_program__set_autoload.argtypes = [ctypes.c_void_p, ctypes.c_bool]
    lib.bpf_program__set_autoload.restype = ctypes.c_int

    lib.bpf_program__set_log_buf.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_char),
        ctypes.c_size_t,
    ]
    lib.bpf_program__set_log_buf.restype = ctypes.c_int

    lib.bpf_program__set_log_level.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lib.bpf_program__set_log_level.restype = ctypes.c_int

    lib.bpf_program__type.argtypes = [ctypes.c_void_p]
    lib.bpf_program__type.restype = ctypes.c_int

    lib.bpf_program__expected_attach_type.argtypes = [ctypes.c_void_p]
    lib.bpf_program__expected_attach_type.restype = ctypes.c_int

    lib.bpf_program__attach_lsm.argtypes = [ctypes.c_void_p]
    lib.bpf_program__attach_lsm.restype = ctypes.c_void_p

    lib.bpf_program__attach_cgroup.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.bpf_program__attach_cgroup.restype = ctypes.c_void_p

    lib.bpf_link__pin.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.bpf_link__pin.restype = ctypes.c_int

    lib.bpf_link__destroy.argtypes = [ctypes.c_void_p]
    lib.bpf_link__destroy.restype = ctypes.c_int

    lib.bpf_map__set_autocreate.argtypes = [ctypes.c_void_p, ctypes.c_bool]
    lib.bpf_map__set_autocreate.restype = ctypes.c_int

    lib.bpf_map__pin.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.bpf_map__pin.restype = ctypes.c_int

    lib.bpf_map__fd.argtypes = [ctypes.c_void_p]
    lib.bpf_map__fd.restype = ctypes.c_int

    lib.bpf_map_update_elem.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint64]
    lib.bpf_map_update_elem.restype = ctypes.c_int

    lib.bpf_map_lookup_elem.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
    lib.bpf_map_lookup_elem.restype = ctypes.c_int

    lib.bpf_obj_get.argtypes = [ctypes.c_char_p]
    lib.bpf_obj_get.restype = ctypes.c_int

    return lib


def _errno_from_rc(rc: int) -> int:
    if rc < 0 and rc != -1:
        return -rc
    e = ctypes.get_errno()
    return e if e else abs(rc)


def _print_log_tail(tag: str, raw_bytes: bytes) -> None:
    text = raw_bytes.decode("utf-8", errors="replace").strip()
    if not text:
        print(f"{tag}: <empty>")
        return
    lines = [ln for ln in text.splitlines() if ln.strip()]
    tail = lines[-VERIFIER_LOG_TAIL_LINES:]
    for ln in tail:
        print(f"{tag}: {ln}")


def probe_single_prog(
    lib: ctypes.CDLL,
    obj_path: bytes,
    prog_name: str,
    tag: str,
    create_cg_map: bool,
) -> bool:
    """Load exactly one program from obj_path to test verifier acceptance, then close."""
    obj = lib.bpf_object__open_file(obj_path, None)
    if not obj:
        err = ctypes.get_errno()
        print(f"{tag}=rejected errno={err} ({os.strerror(err)}) stage=open")
        return False

    log_buf = ctypes.create_string_buffer(VERIFIER_LOG_BUF_SIZE)
    try:
        target_prog = None
        for pname in EXPECTED_PROGS:
            p = lib.bpf_object__find_program_by_name(obj, pname.encode())
            if not p:
                print(f"{tag}=rejected stage=find-prog missing={pname}")
                return False
            want = pname == prog_name
            rc = lib.bpf_program__set_autoload(p, want)
            if rc != 0:
                err = _errno_from_rc(rc)
                print(f"{tag}=rejected errno={err} stage=set-autoload")
                return False
            if want:
                target_prog = p

        cg_map = lib.bpf_object__find_map_by_name(obj, b"j_s2_cgtest_cg")
        if cg_map and not create_cg_map:
            lib.bpf_map__set_autocreate(cg_map, False)

        # Capture verifier log even on acceptance (level 1 = basic verifier log).
        lib.bpf_program__set_log_buf(target_prog, log_buf, VERIFIER_LOG_BUF_SIZE)
        lib.bpf_program__set_log_level(target_prog, 1)

        rc = lib.bpf_object__load(obj)
        if rc == 0:
            print(f"{tag}=accepted")
            _print_log_tail(f"{tag}-LOG", log_buf.value)
            return True

        err = _errno_from_rc(rc)
        print(f"{tag}=rejected errno={err} ({os.strerror(err)})")
        _print_log_tail(f"{tag}-LOG", log_buf.value)
        return False
    finally:
        lib.bpf_object__close(obj)


def map_update_u32_bytes(lib: ctypes.CDLL, map_fd: int, key_u32: int, val_bytes: bytes) -> None:
    k = ctypes.c_uint32(key_u32)
    v = ctypes.create_string_buffer(val_bytes, len(val_bytes))
    rc = lib.bpf_map_update_elem(map_fd, ctypes.byref(k), v, 0)
    if rc != 0:
        err = _errno_from_rc(rc)
        raise OSError(err, f"bpf_map_update_elem(key={key_u32}) failed: {os.strerror(err)}")


def cmd_probe_and_attach(args: argparse.Namespace) -> int:
    if not os.path.isfile(args.obj):
        print(f"STOP-loader-missing-obj path={args.obj}")
        return 1
    if not os.path.isdir(args.cgroup_dir):
        print(f"STOP-loader-missing-cgroup path={args.cgroup_dir}")
        return 1
    if not os.path.isfile(args.sentinel):
        print(f"STOP-loader-missing-sentinel path={args.sentinel}")
        return 1

    st_sentinel = os.stat(args.sentinel)
    st_cgroup = os.stat(args.cgroup_dir)
    sentinel_ino = st_sentinel.st_ino
    sentinel_sdev = pack_kernel_sdev(st_sentinel.st_dev)
    target_cgid = st_cgroup.st_ino

    print(
        f"TARGET sentinel={args.sentinel} ino={sentinel_ino} "
        f"st_dev={os.major(st_sentinel.st_dev)}:{os.minor(st_sentinel.st_dev)} "
        f"kernel_sdev=0x{sentinel_sdev:x} cgroup_dir={args.cgroup_dir} target_cgid={target_cgid}"
    )

    lib = load_libbpf()
    obj_path = args.obj.encode()

    # Always probe BOTH M1 and M2 against the kernel verifier (AJ decision 2026-11-22).
    m1_ok = probe_single_prog(lib, obj_path, "j_s2_cgtest_m1", "VERIFIER-M1", create_cg_map=True)
    m2_ok = probe_single_prog(lib, obj_path, "j_s2_cgtest_m2", "VERIFIER-M2", create_cg_map=False)

    if not m1_ok and not m2_ok:
        print("STOP-verifier-both-rejected")
        return 1

    # Prefer M1 if both load; fall back to M2 (+ optional global observer) if only M2 loads.
    use_m1 = m1_ok
    use_obs = False
    if use_m1:
        print("ACTIVE_MECHANISM=M1")
    else:
        print("ACTIVE_MECHANISM=M2")
        use_obs = probe_single_prog(
            lib, obj_path, "j_s2_cgtest_obs", "VERIFIER-M2-OBS", create_cg_map=False
        )

    cg_fd = -1
    obj = None
    links = []
    pin_dir_created = False
    try:
        cg_fd = os.open(args.cgroup_dir, os.O_RDONLY | os.O_DIRECTORY)

        obj = lib.bpf_object__open_file(obj_path, None)
        if not obj:
            err = ctypes.get_errno()
            raise OSError(err, f"bpf_object__open_file failed: {os.strerror(err)}")

        want_progs = {"j_s2_cgtest_m1"} if use_m1 else ({"j_s2_cgtest_m2"} | ({"j_s2_cgtest_obs"} if use_obs else set()))
        for pname in EXPECTED_PROGS:
            p = lib.bpf_object__find_program_by_name(obj, pname.encode())
            if not p:
                raise RuntimeError(f"missing program {pname}")
            rc = lib.bpf_program__set_autoload(p, pname in want_progs)
            if rc != 0:
                err = _errno_from_rc(rc)
                raise OSError(err, f"set_autoload({pname}) failed: {os.strerror(err)}")

        cg_map = lib.bpf_object__find_map_by_name(obj, b"j_s2_cgtest_cg")
        if cg_map and not use_m1:
            lib.bpf_map__set_autocreate(cg_map, False)

        rc = lib.bpf_object__load(obj)
        if rc != 0:
            err = _errno_from_rc(rc)
            raise OSError(err, f"bpf_object__load failed: {os.strerror(err)}")

        cfg_map = lib.bpf_object__find_map_by_name(obj, b"j_s2_cgtest_cfg")
        st_map = lib.bpf_object__find_map_by_name(obj, b"j_s2_cgtest_st")
        if not cfg_map or not st_map:
            raise RuntimeError("missing cfg or stats map")

        # Populate cgroup array BEFORE enabling cfg and BEFORE attaching (fail-open safety).
        if use_m1:
            if not cg_map:
                raise RuntimeError("missing j_s2_cgtest_cg map")
            cg_map_fd = lib.bpf_map__fd(cg_map)
            if cg_map_fd < 0:
                raise RuntimeError("invalid j_s2_cgtest_cg fd")
            map_update_u32_bytes(lib, cg_map_fd, 0, struct.pack("<I", cg_fd))

        cfg_map_fd = lib.bpf_map__fd(cfg_map)
        if cfg_map_fd < 0:
            raise RuntimeError("invalid j_s2_cgtest_cfg fd")
        cfg_bytes = struct.pack(CFG_FMT, sentinel_ino, target_cgid, sentinel_sdev, 1)
        map_update_u32_bytes(lib, cfg_map_fd, 0, cfg_bytes)

        os.makedirs(args.pin_dir, mode=0o700, exist_ok=False)
        pin_dir_created = True

        maps_to_pin = [("j_s2_cgtest_cfg", cfg_map), ("j_s2_cgtest_st", st_map)]
        if use_m1:
            maps_to_pin.append(("j_s2_cgtest_cg", cg_map))
        for mname, mptr in maps_to_pin:
            mpath = os.path.join(args.pin_dir, mname).encode()
            rc = lib.bpf_map__pin(mptr, mpath)
            if rc != 0:
                err = _errno_from_rc(rc)
                raise OSError(err, f"bpf_map__pin({mname}) failed: {os.strerror(err)}")

        if use_m1:
            p_m1 = lib.bpf_object__find_program_by_name(obj, b"j_s2_cgtest_m1")
            link = lib.bpf_program__attach_lsm(p_m1)
            if not link:
                err = ctypes.get_errno()
                raise OSError(err, f"bpf_program__attach_lsm(m1) failed: {os.strerror(err)}")
            links.append(link)
            lpath = os.path.join(args.pin_dir, "link_m1").encode()
            rc = lib.bpf_link__pin(link, lpath)
            if rc != 0:
                err = _errno_from_rc(rc)
                raise OSError(err, f"bpf_link__pin(link_m1) failed: {os.strerror(err)}")
        else:
            p_m2 = lib.bpf_object__find_program_by_name(obj, b"j_s2_cgtest_m2")
            link_m2 = lib.bpf_program__attach_cgroup(p_m2, cg_fd)
            if not link_m2:
                err = ctypes.get_errno()
                raise OSError(err, f"bpf_program__attach_cgroup(m2) failed: {os.strerror(err)}")
            links.append(link_m2)
            lpath = os.path.join(args.pin_dir, "link_m2").encode()
            rc = lib.bpf_link__pin(link_m2, lpath)
            if rc != 0:
                err = _errno_from_rc(rc)
                raise OSError(err, f"bpf_link__pin(link_m2) failed: {os.strerror(err)}")

            if use_obs:
                p_obs = lib.bpf_object__find_program_by_name(obj, b"j_s2_cgtest_obs")
                link_obs = lib.bpf_program__attach_lsm(p_obs)
                if not link_obs:
                    err = ctypes.get_errno()
                    raise OSError(err, f"bpf_program__attach_lsm(obs) failed: {os.strerror(err)}")
                links.append(link_obs)
                lpath_obs = os.path.join(args.pin_dir, "link_obs").encode()
                rc = lib.bpf_link__pin(link_obs, lpath_obs)
                if rc != 0:
                    err = _errno_from_rc(rc)
                    raise OSError(err, f"bpf_link__pin(link_obs) failed: {os.strerror(err)}")

        mech = "M1" if use_m1 else "M2"
        obs_str = "na" if use_m1 else ("yes" if use_obs else "no")
        print(
            f"ATTACH-DONE mechanism={mech} obs={obs_str} "
            f"sentinel_ino={sentinel_ino} sentinel_sdev=0x{sentinel_sdev:x} target_cgid={target_cgid}"
        )
        return 0
    except Exception as exc:
        print(f"STOP-attach-failed detail={exc}")
        if pin_dir_created and os.path.exists(args.pin_dir):
            shutil.rmtree(args.pin_dir, ignore_errors=True)
        return 1
    finally:
        # Closing link fds after pinning leaves the bpffs pins holding the links alive.
        for link in links:
            lib.bpf_link__destroy(link)
        if obj:
            lib.bpf_object__close(obj)
        if cg_fd >= 0:
            os.close(cg_fd)


def cmd_read_stats(args: argparse.Namespace) -> int:
    st_pin = os.path.join(args.pin_dir, "j_s2_cgtest_st")
    lib = load_libbpf()
    fd = lib.bpf_obj_get(st_pin.encode())
    if fd < 0:
        err = _errno_from_rc(fd)
        print(f"STOP-read-stats-open-failed path={st_pin} errno={err} ({os.strerror(err)})")
        return 1
    try:
        parts = []
        for idx, name in enumerate(STAT_NAMES):
            k = ctypes.c_uint32(idx)
            v = ctypes.c_uint64(0)
            rc = lib.bpf_map_lookup_elem(fd, ctypes.byref(k), ctypes.byref(v))
            if rc != 0:
                err = _errno_from_rc(rc)
                print(f"STOP-read-stats-lookup-failed slot={idx} errno={err}")
                return 1
            parts.append(f"{name}={v.value}")
        print("STATS " + " ".join(parts))
        return 0
    finally:
        os.close(fd)


def _read_self_cgroup() -> str:
    with open("/proc/self/cgroup", "r", encoding="utf-8") as fh:
        lines = [ln.strip() for ln in fh if ln.strip()]
    if len(lines) != 1:
        raise RuntimeError(f"unexpected /proc/self/cgroup lines={lines!r}")
    return lines[0]


def cmd_exec_check(args: argparse.Namespace) -> int:
    cg = _read_self_cgroup()
    print(f"SELF_CGROUP {cg}", flush=True)

    if args.mode == "outside":
        forbidden = args.forbidden_cgroup
        if cg == forbidden or cg.startswith(forbidden + "/"):
            print(f"STOP-case-a-in-test-cgroup cgroup={cg}", flush=True)
            return 124
    elif args.mode == "exact":
        if cg != args.expected_cgroup:
            print(f"CGROUP_MISMATCH got={cg} expected={args.expected_cgroup}", flush=True)
            return 124
    else:
        print(f"STOP-exec-check-bad-mode mode={args.mode}", flush=True)
        return 125

    try:
        os.execv(args.sentinel, [args.sentinel])
    except OSError as exc:
        ename = errno.errorcode.get(exc.errno, str(exc.errno))
        print(f"EXEC_RESULT denied errno={exc.errno} name={ename} msg={exc.strerror}", flush=True)
        return 126 if exc.errno == errno.EPERM else 125
    return 0  # unreachable on successful execv


def cmd_self_test(args: argparse.Namespace) -> int:
    """Unprivileged static verification of libbpf symbols, ABI packing, and ELF symbols."""
    # 1. Verify libbpf.so.1 loads and all ctypes signatures resolve.
    load_libbpf()

    # 2. Verify config struct size & packing.
    assert CFG_SIZE == 24, f"unexpected CFG_SIZE={CFG_SIZE}"
    packed = struct.pack(CFG_FMT, 123456, 789012, (259 << 20) | 2, 1)
    assert len(packed) == 24
    assert struct.unpack(CFG_FMT, packed) == (123456, 789012, 0x10300002, 1)

    # 3. Verify kernel s_dev MKDEV encoding for both tmpfs (0:42) and NVMe (259:2).
    assert pack_kernel_sdev(os.makedev(0, 42)) == 42
    assert pack_kernel_sdev(os.makedev(259, 2)) == ((259 << 20) | 2)
    assert pack_kernel_sdev(os.makedev(259, 2)) != os.makedev(259, 2)

    # 4. Enforce N12 naming contract on expected maps & programs.
    for name in EXPECTED_MAPS + EXPECTED_PROGS:
        assert name.startswith(NAME_PREFIX), f"name missing prefix {NAME_PREFIX}: {name}"
        assert len(name) <= MAX_BPF_NAME_LEN, f"name exceeds {MAX_BPF_NAME_LEN} chars: {name} ({len(name)})"

    # 5. If --obj is supplied, inspect ELF symbols/sections and run libbpf
    # userspace-only ELF open (zero bpf() syscalls: never loads/attaches/pins).
    if args.obj:
        if not os.path.isfile(args.obj):
            print(f"STOP-selftest-missing-obj path={args.obj}")
            return 1
        p = subprocess.run(
            ["readelf", "-sW", "-SW", args.obj],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        out = p.stdout
        for sec in (
            "lsm/bprm_check_security",
            "lsm_cgroup/bprm_check_security",
            ".maps",
            ".BTF",
            ".BTF.ext",
            "license",
        ):
            if sec not in out:
                print(f"STOP-selftest-missing-section section={sec}")
                return 1
        for sym in EXPECTED_PROGS + EXPECTED_MAPS:
            if sym not in out:
                print(f"STOP-selftest-missing-symbol symbol={sym}")
                return 1

        lib = load_libbpf()
        obj = lib.bpf_object__open_file(args.obj.encode(), None)
        if not obj:
            err = ctypes.get_errno()
            print(f"STOP-selftest-libbpf-open-failed errno={err}")
            return 1
        try:
            # Kernel enum values: BPF_PROG_TYPE_LSM=29, BPF_LSM_MAC=27, BPF_LSM_CGROUP=43
            expected_meta = {
                "j_s2_cgtest_m1": (29, 27),
                "j_s2_cgtest_m2": (29, 43),
                "j_s2_cgtest_obs": (29, 27),
            }
            for pname, (want_type, want_attach) in expected_meta.items():
                prog = lib.bpf_object__find_program_by_name(obj, pname.encode())
                if not prog:
                    print(f"STOP-selftest-libbpf-missing-prog name={pname}")
                    return 1
                got_type = lib.bpf_program__type(prog)
                got_attach = lib.bpf_program__expected_attach_type(prog)
                if (got_type, got_attach) != (want_type, want_attach):
                    print(
                        f"STOP-selftest-libbpf-prog-meta name={pname} "
                        f"got=({got_type},{got_attach}) want=({want_type},{want_attach})"
                    )
                    return 1
            for mname in EXPECTED_MAPS:
                mp = lib.bpf_object__find_map_by_name(obj, mname.encode())
                if not mp:
                    print(f"STOP-selftest-libbpf-missing-map name={mname}")
                    return 1
        finally:
            lib.bpf_object__close(obj)

    print("S2-CGTEST-LOADER-SELFTEST-OK")
    return 0


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
    parser = argparse.ArgumentParser(description="Johnny Stage 2 S2-1 BPF LSM cgroup test loader")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_pa = sub.add_parser("probe-and-attach")
    p_pa.add_argument("--obj", required=True)
    p_pa.add_argument("--pin-dir", required=True)
    p_pa.add_argument("--cgroup-dir", required=True)
    p_pa.add_argument("--sentinel", required=True)

    p_rs = sub.add_parser("read-stats")
    p_rs.add_argument("--pin-dir", required=True)

    p_ec = sub.add_parser("exec-check")
    p_ec.add_argument("--mode", choices=("outside", "exact"), required=True)
    p_ec.add_argument("--expected-cgroup", default="")
    p_ec.add_argument("--forbidden-cgroup", default="0::/johnny-stage2-test")
    p_ec.add_argument("--sentinel", required=True)

    p_st = sub.add_parser("self-test")
    p_st.add_argument("--obj", default="")

    args = parser.parse_args()
    if args.cmd == "probe-and-attach":
        return cmd_probe_and_attach(args)
    if args.cmd == "read-stats":
        return cmd_read_stats(args)
    if args.cmd == "exec-check":
        return cmd_exec_check(args)
    if args.cmd == "self-test":
        return cmd_self_test(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
