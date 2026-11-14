#!/usr/bin/python3 -I
"""Johnny Module 1 slice 2b: persistent rotating ring buffer reader.

Design:  docs/tool-install/module1-slice2-ringbuf-design.md section 8
Helper:  docs/tool-install/module1-slice2b-boot.sh
Unit:    etc/systemd/system/johnny-m1s2b-reader.service (enabled at boot;
         runs continuously as a systemd service, rotating output files)

Usage:
  (no args)        drain /sys/fs/bpf/johnny_m1s2b/m2_rb continuously into
                   rotating files under /var/lib/johnny/m1s2b/run-<UTC>.bin
  --summary FILE   read a run file and print counts (no BPF, no ring)

Bounds & Rotation:
- Rotate rather than exit: default 64 MiB (max 2 GiB) per file or 3600 s (max 86400 s),
  whichever first. Overridable via --file-max-bytes and --file-max-seconds.
- Keep: default 6 files (max 1000). Overridable via --keep.
- Dir cap: default 384 MiB (max 16 TiB; must be >= file-max-bytes). Overridable via --dir-cap-bytes.
- Free space reserve: default 256 MiB reserve (max 16 TiB). Overridable via --reserve-bytes.
  Refuses to start or stops writing if free space is below reserve or the directory cap
  would be exceeded.
- Pruning: oldest first.
- Ring corrupt: stops immediately on corrupt ring; never skips ahead.
"""

import argparse
import ctypes
import errno
import os
import select
import signal
import struct
import sys
import time

PIN_DIR = "/sys/fs/bpf/johnny_m1s2b"
OUT_DIR = "/var/lib/johnny/m1s2b"
RUN_PREFIX = "run-"
RUN_SUFFIX = ".bin"

RB_BYTES = 1 << 22  # 4 MiB ring buffer
REC_SIZE = 80
REC_VERSION = 1
REC_FMT = "<BBHIQ6s6sHH16s16sBBHHHBBHI"
REC = struct.Struct(REC_FMT)
REC_FIELDS = (
    "ver", "flags", "rxq", "wire_len", "ts_ns", "dst_mac", "src_mac",
    "ethertype", "vlan_tci", "src_ip", "dst_ip", "l4_proto", "ttl_hlim",
    "l3_len", "sport", "dport", "tcp_flags", "rsv0", "rsv1", "seq_lo"
)
CFG = struct.Struct("<IIII")
CTL_NAMES = ("seen", "sampled_out", "rate_limited", "rb_full", "emitted", "discarded")
FLAG_NAMES = (
    "trunc_l3", "trunc_l4", "frag", "ip6_ext", "vlan", "qinq",
    "rl_recovered", "vlan_deep"
)

# Run file header, 96 bytes: magic, header version, record size, record
# version, pad, mono->realtime offset (ns), start monotonic ns, m2_cfg
# snapshot (ver, sample_every, rate, burst), m2_ctl start sums (6 x u64).
MAGIC = b"JM1S2RB\0"
HDR_VERSION = 1
HDR = struct.Struct("<8sHHBxxxqQIIII6Q")

DEF_FILE_BYTES, MAX_FILE_BYTES = 64 << 20, 2 << 30       # 64 MiB default, 2 GiB ceiling
DEF_FILE_SECONDS, MAX_FILE_SECONDS = 3600, 86400         # 3600 s default
DEF_KEEP, MAX_KEEP = 6, 1000                             # keep=6 default, 1000 ceiling
DEF_DIR_CAP_BYTES, MAX_DIR_CAP_BYTES = 384 << 20, 16 << 40  # 384 MiB default, 16 TiB ceiling
FREE_MARGIN, MAX_RESERVE_BYTES = 256 << 20, 16 << 40        # 256 MiB reserve default, 16 TiB ceiling
POLL_MS = 200
BATCH = 4096

SYS_BPF = 321  # x86_64
BPF_MAP_LOOKUP_ELEM = 1
BPF_OBJ_GET = 7
BPF_OBJ_GET_INFO_BY_FD = 15
BPF_F_RDONLY = 1 << 3
BPF_MAP_TYPE_PERCPU_ARRAY = 6
BPF_MAP_TYPE_ARRAY = 2
BPF_MAP_TYPE_RINGBUF = 27
RB_BUSY = 1 << 31
RB_DISCARD = 1 << 30
RB_HDR = 8

assert REC.size == REC_SIZE and HDR.size == 96 and CFG.size == 16


class Stop(Exception):
    """A STOP-<token>: exits with this token."""


# ------------------------------------------------------------------ ring

class Ring:
    """Consumer side of a BPF_MAP_TYPE_RINGBUF mapping."""

    def __init__(self, cons_addr, prod_addr, data_addr, size):
        if size <= 0 or size & (size - 1):
            raise Stop("ring-size %d" % size)
        self.size = size
        self.mask = size - 1
        self.cons = ctypes.c_uint64.from_address(cons_addr)
        self.prod = ctypes.c_uint64.from_address(prod_addr)
        self.data_addr = data_addr
        self.discarded = 0

    def drain(self, max_n, sink):
        """Hand up to max_n records to sink(bytes) -> bool.
        Returns records handed."""
        cons = self.cons.value
        prod = self.prod.value
        if prod < cons or prod - cons > self.size:
            raise Stop("ring-corrupt positions cons=%d prod=%d" % (cons, prod))
        n = 0
        while cons < prod and n < max_n:
            off = cons & self.mask
            hdr = ctypes.c_uint32.from_address(self.data_addr + off).value
            if hdr & RB_BUSY:
                break
            ln = hdr & ~(RB_BUSY | RB_DISCARD) & 0xFFFFFFFF
            step = (ln + RB_HDR + 7) & ~7
            if ln != REC_SIZE or cons + step > prod:
                raise Stop("ring-corrupt len=%d cons=%d prod=%d" % (ln, cons, prod))
            if hdr & RB_DISCARD:
                self.discarded += 1
            else:
                raw = ctypes.string_at(self.data_addr + off + RB_HDR, REC_SIZE)
                if raw[0] != REC_VERSION:
                    raise Stop("ring-corrupt ver=%d" % raw[0])
                if not sink(raw):
                    break
                n += 1
            cons += step
            # Release store after the data reads (x86-64 TSO)
            self.cons.value = cons
        return n


# ------------------------------------------------------------------ bpf

class _ObjGetAttr(ctypes.Structure):
    _fields_ = [
        ("pathname", ctypes.c_uint64),
        ("bpf_fd", ctypes.c_uint32),
        ("file_flags", ctypes.c_uint32),
    ]


class _InfoAttr(ctypes.Structure):
    _fields_ = [
        ("bpf_fd", ctypes.c_uint32),
        ("info_len", ctypes.c_uint32),
        ("info", ctypes.c_uint64),
    ]


class _MapInfo(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_uint32),
        ("id", ctypes.c_uint32),
        ("key_size", ctypes.c_uint32),
        ("value_size", ctypes.c_uint32),
        ("max_entries", ctypes.c_uint32),
        ("map_flags", ctypes.c_uint32),
        ("name", ctypes.c_char * 16),
        ("ifindex", ctypes.c_uint32),
        ("btf_vmlinux_value_type_id", ctypes.c_uint32),
        ("netns_dev", ctypes.c_uint64),
        ("netns_ino", ctypes.c_uint64),
        ("btf_id", ctypes.c_uint32),
        ("btf_key_type_id", ctypes.c_uint32),
        ("btf_value_type_id", ctypes.c_uint32),
    ]


class _LookupAttr(ctypes.Structure):
    _fields_ = [
        ("map_fd", ctypes.c_uint32),
        ("pad0", ctypes.c_uint32),
        ("key", ctypes.c_uint64),
        ("value", ctypes.c_uint64),
        ("flags", ctypes.c_uint64),
    ]


class Bpf:
    def __init__(self):
        self.libc = ctypes.CDLL(None, use_errno=True)

    def _call(self, cmd, attr):
        while True:
            rc = self.libc.syscall(
                SYS_BPF, cmd, ctypes.byref(attr), ctypes.sizeof(attr)
            )
            if rc >= 0:
                return rc
            err = ctypes.get_errno()
            if err != errno.EINTR:
                raise OSError(err, os.strerror(err))

    def obj_get(self, pin_path, want_type, want_max_entries, rdonly=False):
        if not os.path.exists(pin_path):
            raise Stop("pin-missing %s" % pin_path)
        path_b = pin_path.encode("utf-8")
        buf = ctypes.create_string_buffer(path_b)
        attr = _ObjGetAttr(
            pathname=ctypes.cast(buf, ctypes.c_void_p).value,
            bpf_fd=0,
            file_flags=BPF_F_RDONLY if rdonly else 0,
        )
        try:
            fd = self._call(BPF_OBJ_GET, attr)
        except OSError as e:
            raise Stop("obj-get %s errno=%d (%s)" % (pin_path, e.errno, e.strerror))
        info = _MapInfo()
        iat = _InfoAttr(
            bpf_fd=fd,
            info_len=ctypes.sizeof(info),
            info=ctypes.cast(ctypes.byref(info), ctypes.c_void_p).value,
        )
        try:
            self._call(BPF_OBJ_GET_INFO_BY_FD, iat)
        except OSError as e:
            os.close(fd)
            raise Stop("obj-info %s errno=%d" % (pin_path, e.errno))
        if info.type != want_type:
            os.close(fd)
            raise Stop("map-type %s got=%d want=%d" % (pin_path, info.type, want_type))
        if info.max_entries != want_max_entries:
            os.close(fd)
            raise Stop("map-entries %s got=%d want=%d" % (pin_path, info.max_entries, want_max_entries))
        return fd, info

    def mmap_ring(self, fd, size):
        page = os.sysconf("SC_PAGE_SIZE")
        c_mmap = self.libc.mmap
        c_mmap.restype = ctypes.c_void_p
        c_mmap.argtypes = [
            ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int,
            ctypes.c_int, ctypes.c_int, ctypes.c_long
        ]
        PROT_READ, PROT_WRITE = 1, 2
        MAP_SHARED = 1
        failed = ctypes.c_void_p(-1).value
        cons_addr = c_mmap(None, page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        if cons_addr in (None, failed):
            err = ctypes.get_errno()
            raise Stop("mmap-consumer errno=%d (%s)" % (err, os.strerror(err)))
        data_addr = c_mmap(None, page + 2 * size, PROT_READ, MAP_SHARED, fd, page)
        if data_addr in (None, failed):
            err = ctypes.get_errno()
            raise Stop("mmap-producer errno=%d (%s)" % (err, os.strerror(err)))
        return Ring(cons_addr, data_addr, data_addr + page, size)

    def lookup(self, fd, key_u32, val_size):
        k = ctypes.c_uint32(key_u32)
        v = (ctypes.c_char * val_size)()
        attr = _LookupAttr(
            map_fd=fd,
            key=ctypes.cast(ctypes.byref(k), ctypes.c_void_p).value,
            value=ctypes.cast(ctypes.byref(v), ctypes.c_void_p).value,
            flags=0,
        )
        self._call(BPF_MAP_LOOKUP_ELEM, attr)
        return bytes(v)


def possible_cpus(path="/sys/devices/system/cpu/possible"):
    try:
        with open(path) as f:
            txt = f.read().strip()
        last = txt.split(",")[-1].split("-")[-1]
        return int(last) + 1
    except (FileNotFoundError, ValueError, IndexError):
        return os.cpu_count() or 1


def read_ctl(bpf, fd, ncpu):
    """m2_ctl summed over CPUs, in CTL_NAMES order."""
    out = []
    for k in range(len(CTL_NAMES)):
        raw = bpf.lookup(fd, k, 8 * ncpu)
        out.append(sum(struct.unpack("<%dQ" % ncpu, raw)))
    return out


# ------------------------------------------------------------------ output

def check_out_dir(path):
    """The output dir must be a real directory, root-owned, mode 0700."""
    if not os.path.exists(path):
        try:
            os.makedirs(path, mode=0o700, exist_ok=True)
        except OSError as e:
            raise Stop("out-dir-mkdir-failed %s (%s)" % (path, e))
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        raise Stop("out-dir-missing %s" % path)
    if not os.path.isdir(path) or os.path.islink(path):
        raise Stop("out-dir-not-dir %s" % path)
    if st.st_uid != os.geteuid() or (st.st_mode & 0o777) != 0o700:
        raise Stop("out-dir-mode %s uid=%d mode=%o" % (path, st.st_uid, st.st_mode & 0o777))


def run_files(out_dir):
    return sorted(f for f in os.listdir(out_dir)
                  if f.startswith(RUN_PREFIX) and f.endswith(RUN_SUFFIX))


def check_disk_free(out_dir, reserve_bytes):
    try:
        vfs = os.statvfs(out_dir)
        free = vfs.f_bavail * vfs.f_frsize
    except OSError as e:
        raise Stop("statvfs-failed %s (%s)" % (out_dir, e))
    if free < reserve_bytes:
        raise Stop("low-disk free=%d reserve=%d" % (free, reserve_bytes))
    return free


def dir_usage(out_dir):
    total = 0
    for f in run_files(out_dir):
        try:
            total += os.path.getsize(os.path.join(out_dir, f))
        except OSError:
            pass
    return total


def prune(out_dir, keep, dir_cap_bytes, new_file_reserved_bytes=0):
    """Enforce keep count and dir cap. Oldest deleted first."""
    files = run_files(out_dir)
    # 1. Enforce keep count: ensure at most keep - 1 existing files remain
    while len(files) >= keep:
        oldest = files.pop(0)
        p = os.path.join(out_dir, oldest)
        try:
            os.unlink(p)
            print("PRUNED %s (keep=%d)" % (oldest, keep), flush=True)
        except OSError as e:
            raise Stop("prune-failed %s (%s)" % (p, e))

    # 2. Enforce dir cap: ensure existing total + new file reserved <= dir_cap_bytes
    total = sum(os.path.getsize(os.path.join(out_dir, f)) for f in files)
    while files and (total + new_file_reserved_bytes > dir_cap_bytes):
        oldest = files.pop(0)
        p = os.path.join(out_dir, oldest)
        try:
            sz = os.path.getsize(p)
            os.unlink(p)
            total -= sz
            print("PRUNED %s (cap=%d)" % (oldest, dir_cap_bytes), flush=True)
        except OSError as e:
            raise Stop("prune-failed %s (%s)" % (p, e))

    if total + new_file_reserved_bytes > dir_cap_bytes:
        raise Stop("dir-cap-exceeded dir_bytes=%d cap=%d" % (total + new_file_reserved_bytes, dir_cap_bytes))


def mono_to_real_ns():
    r0 = time.clock_gettime_ns(time.CLOCK_REALTIME)
    m = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
    r1 = time.clock_gettime_ns(time.CLOCK_REALTIME)
    return (r0 + r1) // 2 - m


class RotatingWriter:
    """Manages active run file, buffer, rotation, and quota checks."""

    def __init__(self, out_dir, file_max_bytes, file_max_seconds, keep,
                 dir_cap_bytes, reserve_bytes, bpf, cfg, ctl_fd, ncpu):
        self.out_dir = out_dir
        self.file_max_bytes = file_max_bytes
        self.file_max_seconds = file_max_seconds
        self.keep = keep
        self.dir_cap_bytes = dir_cap_bytes
        self.reserve_bytes = reserve_bytes
        self.bpf = bpf
        self.cfg = cfg
        self.ctl_fd = ctl_fd
        self.ncpu = ncpu

        self.fd = None
        self.path = None
        self.file_bytes = 0
        self.file_records = 0
        self.file_start_mono = 0
        self.buf = []
        self.last_seq = {}
        self.gaps = 0
        self.total_files = 0
        self.total_records = 0
        self.total_bytes = 0

    def open_next_file(self):
        self.close_current_file()

        check_disk_free(self.out_dir, self.reserve_bytes)
        prune(self.out_dir, self.keep, self.dir_cap_bytes, self.file_max_bytes)
        check_disk_free(self.out_dir, self.reserve_bytes)

        now_utc = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        name = "%s%s%s" % (RUN_PREFIX, now_utc, RUN_SUFFIX)
        path = os.path.join(self.out_dir, name)
        idx = 1
        while os.path.exists(path):
            name = "%s%s-%02d%s" % (RUN_PREFIX, now_utc, idx, RUN_SUFFIX)
            path = os.path.join(self.out_dir, name)
            idx += 1

        self.fd = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600
        )
        self.path = path
        self.file_start_mono = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
        ctl = read_ctl(self.bpf, self.ctl_fd, self.ncpu)
        hdr_bytes = HDR.pack(
            MAGIC, HDR_VERSION, REC_SIZE, REC_VERSION,
            mono_to_real_ns(), self.file_start_mono, *self.cfg, *ctl
        )
        os.write(self.fd, hdr_bytes)
        self.file_bytes = HDR.size
        self.file_records = 0
        self.total_files += 1
        print("M1S2B-FILE-OPEN file=%s file_num=%d DATE-UTC %s"
              % (self.path, self.total_files, now_utc), flush=True)

    def close_current_file(self):
        if self.fd is not None:
            self.flush()
            os.fsync(self.fd)
            os.close(self.fd)
            self.total_bytes += self.file_bytes
            print("M1S2B-FILE-CLOSED file=%s records=%d bytes=%d"
                  % (self.path, self.file_records, self.file_bytes), flush=True)
            self.fd = None
            self.path = None

    def sink(self, raw):
        now_mono = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
        elapsed_s = (now_mono - self.file_start_mono) / 1_000_000_000.0

        if self.fd is None or self.file_bytes + REC_SIZE > self.file_max_bytes or elapsed_s >= self.file_max_seconds:
            self.open_next_file()

        rxq = raw[2] | (raw[3] << 8)
        seq = struct.unpack_from("<I", raw, 76)[0]
        prev = self.last_seq.get(rxq)
        if prev is not None:
            self.gaps += (seq - prev - 1) & 0xFFFFFFFF
        self.last_seq[rxq] = seq

        self.buf.append(raw)
        self.file_records += 1
        self.total_records += 1
        self.file_bytes += REC_SIZE

        if len(self.buf) >= 256:
            self.flush()
        return True

    def flush(self):
        if self.buf and self.fd is not None:
            check_disk_free(self.out_dir, self.reserve_bytes)
            data = b"".join(self.buf)
            self.buf = []
            view = memoryview(data)
            while view:
                n = os.write(self.fd, view)
                view = view[n:]


def bounded(name, val, ceiling, floor=1):
    if not floor <= val <= ceiling:
        raise Stop("arg-%s %d not in %d..%d" % (name, val, floor, ceiling))
    return val


def do_run(args):
    if os.geteuid() != 0:
        raise Stop("not-root")

    file_max_bytes = bounded("file-max-bytes", args.file_max_bytes, MAX_FILE_BYTES, HDR.size + REC_SIZE)
    file_max_seconds = bounded("file-max-seconds", args.file_max_seconds, MAX_FILE_SECONDS)
    keep = bounded("keep", args.keep, MAX_KEEP)
    dir_cap_bytes = bounded("dir-cap-bytes", args.dir_cap_bytes, MAX_DIR_CAP_BYTES, floor=file_max_bytes)
    reserve_bytes = bounded("reserve-bytes", args.reserve_bytes, MAX_RESERVE_BYTES)
    pin_dir = args.pin_dir
    out_dir = args.out_dir

    check_out_dir(out_dir)
    check_disk_free(out_dir, reserve_bytes)

    bpf = Bpf()
    ncpu = possible_cpus()
    rb_pin = os.path.join(pin_dir, "m2_rb")
    cfg_pin = os.path.join(pin_dir, "m2_cfg")
    ctl_pin = os.path.join(pin_dir, "m2_ctl")

    rb_fd, rb_info = bpf.obj_get(rb_pin, BPF_MAP_TYPE_RINGBUF, RB_BYTES, rdonly=False)
    cfg_fd, _ = bpf.obj_get(cfg_pin, BPF_MAP_TYPE_ARRAY, 1, rdonly=True)
    ctl_fd, _ = bpf.obj_get(ctl_pin, BPF_MAP_TYPE_PERCPU_ARRAY, len(CTL_NAMES), rdonly=True)

    ring = bpf.mmap_ring(rb_fd, RB_BYTES)
    cfg = CFG.unpack(bpf.lookup(cfg_fd, 0, CFG.size))

    writer = RotatingWriter(
        out_dir=out_dir,
        file_max_bytes=file_max_bytes,
        file_max_seconds=file_max_seconds,
        keep=keep,
        dir_cap_bytes=dir_cap_bytes,
        reserve_bytes=reserve_bytes,
        bpf=bpf,
        cfg=cfg,
        ctl_fd=ctl_fd,
        ncpu=ncpu,
    )

    print("M1S2B-READER-BEGIN out_dir=%s ring_map_id=%d cfg=ver:%d,every:%d,rate:%d,burst:%d "
          "file_max_bytes=%d file_max_seconds=%d keep=%d dir_cap=%d reserve=%d"
          % (out_dir, rb_info.id, *cfg, file_max_bytes, file_max_seconds, keep, dir_cap_bytes, reserve_bytes),
          flush=True)

    # Initial file open
    writer.open_next_file()

    stop_sig = []
    for s in (signal.SIGTERM, signal.SIGINT):
        signal.signal(s, lambda n, _f: stop_sig.append(n))

    ep = select.epoll()
    ep.register(rb_fd, select.EPOLLIN)

    start_total_mono = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
    end_reason = "normal"

    try:
        while True:
            ring.drain(BATCH, writer.sink)
            writer.flush()

            if stop_sig:
                end_reason = "signal-%d" % stop_sig[0]
                break

            if args.max_total_records and writer.total_records >= args.max_total_records:
                end_reason = "max-total-records"
                break

            now_mono = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
            if args.max_total_seconds:
                if (now_mono - start_total_mono) / 1_000_000_000.0 >= args.max_total_seconds:
                    end_reason = "max-total-seconds"
                    break

            # Poll for new events or timeout to check time rotation / signals
            ep.poll(POLL_MS / 1000.0)

            # Check time rotation even if no packets arrived
            if writer.fd is not None:
                elapsed_s = (time.clock_gettime_ns(time.CLOCK_MONOTONIC) - writer.file_start_mono) / 1_000_000_000.0
                if elapsed_s >= file_max_seconds:
                    writer.open_next_file()

    finally:
        writer.close_current_file()
        ep.close()

    ctl_end = read_ctl(bpf, ctl_fd, ncpu)
    print("M1S2B-READER-END reason=%s total_files=%d total_records=%d total_bytes=%d "
          "seq_gaps=%d ring_discarded=%d backlog=%d"
          % (end_reason, writer.total_files, writer.total_records, writer.total_bytes,
             writer.gaps, ring.discarded, ring.prod.value - ring.cons.value),
          flush=True)
    return 0


# ------------------------------------------------------------------ summary

def fmt_ip(b, is4):
    if is4:
        return "%d.%d.%d.%d" % tuple(b[:4])
    return ":".join("%02x%02x" % (b[i], b[i + 1]) for i in range(0, 16, 2))


def do_summary(args):
    path = args.file
    try:
        f = open(path, "rb")
    except OSError as e:
        raise Stop("open %s: %s" % (path, e))
    with f:
        raw_hdr = f.read(HDR.size)
        if len(raw_hdr) != HDR.size:
            raise Stop("header-short %s len=%d" % (path, len(raw_hdr)))
        magic, h_ver, rec_sz, rec_ver, offset_ns, start_ns, cfg_ver, every, rate, burst, *ctl0 = HDR.unpack(raw_hdr)
        if magic != MAGIC or h_ver != HDR_VERSION or rec_sz != REC_SIZE or rec_ver != REC_VERSION:
            raise Stop("header-corrupt %s" % path)

        utc = time.strftime("%Y-%m-%d %H:%M:%SZ", time.gmtime((start_ns + offset_ns) / 1e9))
        print("FILE %s" % path)
        print("HEADER magic=%s ver=%d start_utc=%s cfg=ver:%d,every:%d,rate:%d,burst:%d"
              % (magic.decode("ascii", errors="replace").rstrip("\0"), h_ver, utc, cfg_ver, every, rate, burst))
        print("CTL-START " + " ".join("%s=%d" % (k, v) for k, v in zip(CTL_NAMES, ctl0)))

        rxq_counts = {}
        proto_counts = {}
        src_counts = {}
        dst_counts = {}
        records = 0
        total_wire = 0
        gaps = 0
        last_seq = {}

        while True:
            chunk = f.read(REC_SIZE * 1024)
            if not chunk:
                break
            for i in range(0, len(chunk) - len(chunk) % REC_SIZE, REC_SIZE):
                rec_bytes = chunk[i:i + REC_SIZE]
                row = REC.unpack(rec_bytes)
                d = dict(zip(REC_FIELDS, row))
                records += 1
                total_wire += d["wire_len"]
                rxq = d["rxq"]
                rxq_counts[rxq] = rxq_counts.get(rxq, 0) + 1
                proto = d["l4_proto"]
                proto_counts[proto] = proto_counts.get(proto, 0) + 1
                is4 = (d["ethertype"] == 0x0800)
                src_counts[fmt_ip(d["src_ip"], is4)] = src_counts.get(fmt_ip(d["src_ip"], is4), 0) + 1
                dst_counts[fmt_ip(d["dst_ip"], is4)] = dst_counts.get(fmt_ip(d["dst_ip"], is4), 0) + 1
                seq = d["seq_lo"]
                prev = last_seq.get(rxq)
                if prev is not None:
                    gaps += (seq - prev - 1) & 0xFFFFFFFF
                last_seq[rxq] = seq

        print("SUMMARY records=%d total_wire_bytes=%d seq_gaps=%d" % (records, total_wire, gaps))
        print("QUEUES " + " ".join("rxq%d=%d" % (k, rxq_counts[k]) for k in sorted(rxq_counts)))
        proto_map = {6: "tcp", 17: "udp", 1: "icmp", 58: "icmp6"}
        print("PROTO " + " ".join("%s=%d" % (proto_map.get(k, str(k)), v)
                                  for k, v in sorted(proto_counts.items(), key=lambda kv: -kv[1])))
        top = args.top
        print("TOP-SRC " + " ".join("%s=%d" % kv for kv in sorted(src_counts.items(), key=lambda kv: -kv[1])[:top]))
        print("TOP-DST " + " ".join("%s=%d" % kv for kv in sorted(dst_counts.items(), key=lambda kv: -kv[1])[:top]))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="johnny-m1s2b-reader")
    p.add_argument("--file-max-bytes", type=int, default=DEF_FILE_BYTES)
    p.add_argument("--file-max-seconds", type=int, default=DEF_FILE_SECONDS)
    p.add_argument("--keep", type=int, default=DEF_KEEP)
    p.add_argument("--dir-cap-bytes", type=int, default=DEF_DIR_CAP_BYTES)
    p.add_argument("--reserve-bytes", type=int, default=FREE_MARGIN)
    p.add_argument("--pin-dir", default=PIN_DIR)
    p.add_argument("--out-dir", default=OUT_DIR)
    p.add_argument("--max-total-records", type=int, default=None)
    p.add_argument("--max-total-seconds", type=int, default=None)
    p.add_argument("--summary", metavar="FILE", dest="file")
    p.add_argument("--top", type=int, default=10)
    args = p.parse_args(argv)

    try:
        if args.file:
            return do_summary(args)
        return do_run(args)
    except Stop as s:
        print("STOP-%s" % s, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
