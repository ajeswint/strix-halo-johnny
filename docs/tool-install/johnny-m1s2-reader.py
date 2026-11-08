#!/usr/bin/python3 -I
"""Johnny Module 1 slice 2: bounded, root-only, no-egress ring buffer reader.

Design:  docs/tool-install/module1-slice2-ringbuf-design.md section 8
Helper:  docs/tool-install/module1-slice2-records.sh
Unit:    etc/systemd/system/johnny-m1s2-reader.service (not enabled; a paste
         starts it, it runs once, it exits)

  (no args)        drain /sys/fs/bpf/johnny_m1s2/m2_rb into
                   /var/lib/johnny/m1s2/run-<UTC>.bin until the first cap is hit
  --summary FILE   read a run file and print counts (no BPF, no ring)

Bounds (hard caps; the first one hit ends the run): --max-seconds (default 60,
ceiling 600), --max-records (default 1,000,000, ceiling 10,000,000),
--max-bytes for the run file (default 64 MiB, ceiling 256 MiB), --keep run
files in the output dir (default 3, ceiling 10; oldest deleted first, before
the new file is created). It also refuses to start when the output file system
has less than max-bytes + 256 MiB free.

What it does: BPF_OBJ_GET on the pinned ring (read-write: the consumer page is
written), and on m2_cfg / m2_ctl read-only (BPF_F_RDONLY) for the run header
and end counters. It mmaps the consumer page read-write and the producer page
plus the data area read-only, waits with epoll on the map fd, validates every
record header (length = 80, version = 1, bounds) and writes the 80-byte
records unchanged after a fixed 96-byte file header. Any malformed record
stops the run (STOP-ring-corrupt); it never skips ahead.

What it does NOT do: no socket of any kind (it never imports socket), no map
update or delete, no program load or attach, no write outside the output dir.
Python 3 standard library only. Exit 0 = a cap or a signal ended a clean run.
"""

import argparse
import ctypes
import os
import select
import signal
import struct
import sys
import time

PIN_DIR = "/sys/fs/bpf/johnny_m1s2"
OUT_DIR = "/var/lib/johnny/m1s2"
RUN_PREFIX = "run-"
RUN_SUFFIX = ".bin"

# Must match module1_xdp_records.c (M2_RB_BYTES, struct m2_rec, struct m2_cfg,
# the C_* enum). The Phase C self-test compares them.
RB_BYTES = 1 << 22
REC_SIZE = 80
REC_VERSION = 1
REC_FMT = "<BBHIQ6s6sHH16s16sBBHHHBBHI"
REC = struct.Struct(REC_FMT)
REC_FIELDS = ("ver", "flags", "rxq", "wire_len", "ts_ns", "dst_mac", "src_mac",
              "ethertype", "vlan_tci", "src_ip", "dst_ip", "l4_proto", "ttl_hlim",
              "l3_len", "sport", "dport", "tcp_flags", "rsv0", "rsv1", "seq_lo")
CFG = struct.Struct("<IIII")
CTL_NAMES = ("seen", "sampled_out", "rate_limited", "rb_full", "emitted", "discarded")
FLAG_NAMES = ("trunc_l3", "trunc_l4", "frag", "ip6_ext", "vlan", "qinq",
              "rl_recovered", "vlan_deep")

# Run file header, 96 bytes: magic, header version, record size, record
# version, pad, mono->realtime offset (ns), start monotonic ns, m2_cfg
# snapshot (ver, sample_every, rate, burst), m2_ctl start sums (6 x u64).
MAGIC = b"JM1S2RB\0"
HDR_VERSION = 1
HDR = struct.Struct("<8sHHBxxxqQIIII6Q")

DEF_SECONDS, MAX_SECONDS = 60, 600
DEF_RECORDS, MAX_RECORDS = 1_000_000, 10_000_000
DEF_BYTES, MAX_BYTES = 64 << 20, 256 << 20
DEF_KEEP, MAX_KEEP = 3, 10
FREE_MARGIN = 256 << 20
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
    """A STOP-<token>: the run ends non-zero with this token."""


# ------------------------------------------------------------------ ring

class Ring:
    """Consumer side of a BPF_MAP_TYPE_RINGBUF mapping.

    cons_addr: consumer page (read-write); prod_addr: producer page
    (read-only); data_addr: 2 * size bytes (the kernel maps the data area
    twice, back to back, so a record never wraps). Addresses, not objects, so
    the Phase C test can drive it with a synthetic ring in plain memory."""

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
        """Hand up to max_n records to sink(bytes) -> bool (False = stop
        before this record, leaving it in the ring). Returns records handed."""
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
            # Release store after the data reads (x86-64 TSO; design section 8
            # assumption, for Assurance to challenge).
            self.cons.value = cons
        return n


# ------------------------------------------------------------------ bpf

class _ObjGetAttr(ctypes.Structure):
    _fields_ = [("pathname", ctypes.c_uint64), ("bpf_fd", ctypes.c_uint32),
                ("file_flags", ctypes.c_uint32), ("path_fd", ctypes.c_int32),
                ("pad", ctypes.c_uint32)]


class _InfoAttr(ctypes.Structure):
    _fields_ = [("bpf_fd", ctypes.c_uint32), ("info_len", ctypes.c_uint32),
                ("info", ctypes.c_uint64)]


class _MapInfo(ctypes.Structure):
    _fields_ = [("type", ctypes.c_uint32), ("id", ctypes.c_uint32),
                ("key_size", ctypes.c_uint32), ("value_size", ctypes.c_uint32),
                ("max_entries", ctypes.c_uint32), ("map_flags", ctypes.c_uint32),
                ("name", ctypes.c_char * 16)]


class _LookupAttr(ctypes.Structure):
    _fields_ = [("map_fd", ctypes.c_uint32), ("pad", ctypes.c_uint32),
                ("key", ctypes.c_uint64), ("value", ctypes.c_uint64),
                ("flags", ctypes.c_uint64)]


class Bpf:
    def __init__(self):
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.libc.syscall.restype = ctypes.c_long
        self.libc.mmap.restype = ctypes.c_void_p
        self.libc.mmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int,
                                   ctypes.c_int, ctypes.c_int, ctypes.c_long]

    def _sys(self, cmd, attr):
        return self.libc.syscall(SYS_BPF, cmd, ctypes.byref(attr), ctypes.sizeof(attr))

    def obj_get(self, name, mtype, max_entries, rdonly):
        path = os.path.join(PIN_DIR, name)
        if os.path.islink(path) or not os.path.exists(path):
            raise Stop("no-pin %s" % path)
        cpath = ctypes.create_string_buffer(path.encode())
        attr = _ObjGetAttr(pathname=ctypes.addressof(cpath),
                           file_flags=BPF_F_RDONLY if rdonly else 0)
        fd = self._sys(BPF_OBJ_GET, attr)
        if fd < 0:
            raise Stop("obj-get %s errno=%d" % (name, ctypes.get_errno()))
        info = _MapInfo()
        iattr = _InfoAttr(bpf_fd=fd, info_len=ctypes.sizeof(info), info=ctypes.addressof(info))
        if self._sys(BPF_OBJ_GET_INFO_BY_FD, iattr) != 0:
            raise Stop("map-info %s errno=%d" % (name, ctypes.get_errno()))
        got = info.name.decode(errors="replace")
        if info.type != mtype or info.max_entries != max_entries or got != name:
            raise Stop("map-mismatch %s type=%d max_entries=%d name=%s"
                       % (name, info.type, info.max_entries, got))
        return fd, info

    def lookup(self, fd, key, size):
        k = ctypes.c_uint32(key)
        buf = ctypes.create_string_buffer(size)
        attr = _LookupAttr(map_fd=fd, key=ctypes.addressof(k), value=ctypes.addressof(buf))
        if self._sys(BPF_MAP_LOOKUP_ELEM, attr) != 0:
            raise Stop("lookup errno=%d" % ctypes.get_errno())
        return buf.raw

    def mmap_ring(self, fd, size):
        page = os.sysconf("SC_PAGE_SIZE")
        prot_r, prot_w, shared = 0x1, 0x2, 0x01
        failed = ctypes.c_void_p(-1).value
        cons = self.libc.mmap(None, page, prot_r | prot_w, shared, fd, 0)
        if cons in (None, failed):
            raise Stop("mmap-consumer errno=%d" % ctypes.get_errno())
        prod = self.libc.mmap(None, page + 2 * size, prot_r, shared, fd, page)
        if prod in (None, failed):
            raise Stop("mmap-producer errno=%d" % ctypes.get_errno())
        return Ring(cons, prod, prod + page, size)


def possible_cpus(path="/sys/devices/system/cpu/possible"):
    with open(path) as f:
        text = f.read().strip()
    n = 0
    for part in text.split(","):
        lo, _, hi = part.partition("-")
        n = max(n, int(hi or lo) + 1)
    return n


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


def prune(out_dir, keep):
    """Leave at most keep - 1 old run files, so the new one makes keep."""
    files = run_files(out_dir)
    for f in files[:max(0, len(files) - (keep - 1))]:
        os.unlink(os.path.join(out_dir, f))
        print("PRUNED %s" % f)


def mono_to_real_ns():
    r0 = time.clock_gettime_ns(time.CLOCK_REALTIME)
    m = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
    r1 = time.clock_gettime_ns(time.CLOCK_REALTIME)
    return (r0 + r1) // 2 - m


class Run:
    """One bounded run: caps, gap accounting, the output file."""

    def __init__(self, fd_out, max_records, max_bytes):
        self.fd = fd_out
        self.max_records = max_records
        self.max_bytes = max_bytes
        self.bytes = HDR.size
        self.records = 0
        self.gaps = 0
        self.last_seq = {}
        self.reason = None
        self.buf = []

    def sink(self, raw):
        if self.records >= self.max_records:
            self.reason = "max-records"
            return False
        if self.bytes + REC_SIZE > self.max_bytes:
            self.reason = "max-bytes"
            return False
        rxq = raw[2] | (raw[3] << 8)
        seq = struct.unpack_from("<I", raw, 76)[0]
        prev = self.last_seq.get(rxq)
        if prev is not None:
            # Per-queue sequence counts every reserve attempt, so a jump is an
            # RB_FULL drop on that queue. [Assumption] one CPU per queue (the
            # step 13 IRQ pins); a queue served by two CPUs shows false gaps.
            self.gaps += (seq - prev - 1) & 0xFFFFFFFF
        self.last_seq[rxq] = seq
        self.buf.append(raw)
        self.records += 1
        self.bytes += REC_SIZE
        return True

    def flush(self):
        if self.buf:
            data = b"".join(self.buf)
            self.buf = []
            view = memoryview(data)
            while view:
                view = view[os.write(self.fd, view):]


def bounded(name, val, ceiling, floor=1):
    if not floor <= val <= ceiling:
        raise Stop("arg-%s %d not in %d..%d" % (name, val, floor, ceiling))
    return val


def do_run(args):
    if os.geteuid() != 0:
        raise Stop("not-root")
    secs = bounded("max-seconds", args.max_seconds, MAX_SECONDS)
    max_rec = bounded("max-records", args.max_records, MAX_RECORDS)
    max_bytes = bounded("max-bytes", args.max_bytes, MAX_BYTES, HDR.size + REC_SIZE)
    keep = bounded("keep", args.keep, MAX_KEEP)
    check_out_dir(OUT_DIR)
    vfs = os.statvfs(OUT_DIR)
    free = vfs.f_bavail * vfs.f_frsize
    if free < max_bytes + FREE_MARGIN:
        raise Stop("low-disk free=%d need=%d" % (free, max_bytes + FREE_MARGIN))

    bpf = Bpf()
    ncpu = possible_cpus()
    rb_fd, rb_info = bpf.obj_get("m2_rb", BPF_MAP_TYPE_RINGBUF, RB_BYTES, rdonly=False)
    cfg_fd, _ = bpf.obj_get("m2_cfg", BPF_MAP_TYPE_ARRAY, 1, rdonly=True)
    ctl_fd, _ = bpf.obj_get("m2_ctl", BPF_MAP_TYPE_PERCPU_ARRAY, len(CTL_NAMES), rdonly=True)
    ring = bpf.mmap_ring(rb_fd, RB_BYTES)
    cfg = CFG.unpack(bpf.lookup(cfg_fd, 0, CFG.size))
    ctl0 = read_ctl(bpf, ctl_fd, ncpu)

    prune(OUT_DIR, keep)
    name = "%s%s%s" % (RUN_PREFIX, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), RUN_SUFFIX)
    path = os.path.join(OUT_DIR, name)
    fd_out = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    start = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
    os.write(fd_out, HDR.pack(MAGIC, HDR_VERSION, REC_SIZE, REC_VERSION,
                              mono_to_real_ns(), start, *cfg, *ctl0))
    print("M1S2-READER-BEGIN file=%s ring_map_id=%d cfg=ver:%d,every:%d,rate:%d,burst:%d "
          "max_seconds=%d max_records=%d max_bytes=%d keep=%d"
          % (path, rb_info.id, *cfg, secs, max_rec, max_bytes, keep), flush=True)

    run = Run(fd_out, max_rec, max_bytes)
    stop_sig = []
    for s in (signal.SIGTERM, signal.SIGINT):
        signal.signal(s, lambda n, _f: stop_sig.append(n))
    ep = select.epoll()
    ep.register(rb_fd, select.EPOLLIN)
    deadline = start + secs * 1_000_000_000
    try:
        while True:
            ring.drain(BATCH, run.sink)
            run.flush()
            if run.reason:
                break
            if stop_sig:
                run.reason = "signal-%d" % stop_sig[0]
                break
            left_ms = (deadline - time.clock_gettime_ns(time.CLOCK_MONOTONIC)) // 1_000_000
            if left_ms <= 0:
                run.reason = "max-seconds"
                break
            ep.poll(min(POLL_MS, left_ms) / 1000.0)
    finally:
        run.flush()
        os.fsync(fd_out)
        os.close(fd_out)
        ep.close()
    ctl1 = read_ctl(bpf, ctl_fd, ncpu)
    delta = dict(zip(CTL_NAMES, (b - a for a, b in zip(ctl0, ctl1))))
    print("M1S2-READER-END reason=%s records=%d bytes=%d seq_gaps=%d ring_discarded=%d "
          "backlog=%d %s"
          % (run.reason, run.records, run.bytes, run.gaps, ring.discarded,
             ring.prod.value - ring.cons.value,
             " ".join("ctl_%s=%d" % kv for kv in delta.items())), flush=True)
    return 0


# ------------------------------------------------------------------ summary

def fmt_ip(b, is4):
    if is4:
        return ".".join(str(x) for x in b[:4])
    return ":".join("%x" % (b[i] << 8 | b[i + 1]) for i in range(0, 16, 2))


def do_summary(args):
    if os.geteuid() != 0:
        raise Stop("not-root")
    with open(args.file, "rb") as f:
        hdr = f.read(HDR.size)
        if len(hdr) != HDR.size:
            raise Stop("summary-short-header")
        h = HDR.unpack(hdr)
        if h[0] != MAGIC or h[1] != HDR_VERSION or h[2] != REC_SIZE or h[3] != REC_VERSION:
            raise Stop("summary-bad-header")
        n = 0
        flags = [0] * 8
        rxq, proto, talkers = {}, {}, {}
        first = last = None
        while True:
            raw = f.read(REC_SIZE)
            if not raw:
                break
            if len(raw) != REC_SIZE:
                raise Stop("summary-short-record at=%d" % n)
            r = dict(zip(REC_FIELDS, REC.unpack(raw)))
            if r["ver"] != REC_VERSION:
                raise Stop("summary-bad-version at=%d" % n)
            n += 1
            first = r["ts_ns"] if first is None else first
            last = r["ts_ns"]
            for i in range(8):
                if r["flags"] >> i & 1:
                    flags[i] += 1
            rxq[r["rxq"]] = rxq.get(r["rxq"], 0) + 1
            proto[r["l4_proto"]] = proto.get(r["l4_proto"], 0) + 1
            if r["ethertype"] in (0x0800, 0x86DD):
                key = fmt_ip(r["src_ip"], r["ethertype"] == 0x0800)
                talkers[key] = talkers.get(key, 0) + 1
    span = (last - first) / 1e9 if n > 1 else 0.0
    print("SUMMARY file=%s records=%d span_s=%.3f" % (args.file, n, span))
    print("SUMMARY-CFG ver=%d every=%d rate=%d burst=%d" % h[6:10])
    print("SUMMARY-FLAGS " + " ".join("%s=%d" % kv for kv in zip(FLAG_NAMES, flags)))
    print("SUMMARY-RXQ " + " ".join("%d=%d" % kv for kv in sorted(rxq.items())))
    print("SUMMARY-L4 " + " ".join("%d=%d" % kv for kv in sorted(proto.items())))
    for ip, c in sorted(talkers.items(), key=lambda kv: (-kv[1], kv[0]))[:args.top]:
        print("SUMMARY-TOP-SRC %s %d" % (ip, c))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="johnny-m1s2-reader")
    p.add_argument("--max-seconds", type=int, default=DEF_SECONDS)
    p.add_argument("--max-records", type=int, default=DEF_RECORDS)
    p.add_argument("--max-bytes", type=int, default=DEF_BYTES)
    p.add_argument("--keep", type=int, default=DEF_KEEP)
    p.add_argument("--summary", metavar="FILE", dest="file")
    p.add_argument("--top", type=int, default=10)
    args = p.parse_args(argv)
    try:
        if args.file:
            return do_summary(args)
        return do_run(args)
    except Stop as e:
        print("STOP-%s" % e, flush=True)
        return 1
    except OSError as e:
        print("STOP-os-error %s" % e, flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
