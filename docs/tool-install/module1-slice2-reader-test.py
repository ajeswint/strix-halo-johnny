#!/usr/bin/python3 -I
"""Johnny Module 1 slice 2: rock-box unit test of johnny-m1s2-reader.py.

No root, no BPF, no Johnny. A synthetic ring (consumer page, producer page and
a 2 x size data area in plain ctypes memory, the double mapping emulated by
writing straight across the size boundary) drives Ring.drain; a fake Bpf class
drives do_run end to end into a temp output dir.

  python3 -I -B module1-slice2-reader-test.py READER_PY

Prints READER-TEST-OK cases=N, or READER-TEST-FAIL <case>: <why> and exits 1.
"""

import ctypes
import importlib.util
import io
import os
import select
import stat
import struct
import sys
import tempfile
import contextlib

SIZE = 4096
CASES = []


def load(path):
    spec = importlib.util.spec_from_file_location("m2reader", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


m = load(sys.argv[1])


def case(fn):
    CASES.append(fn)
    return fn


class Synth:
    """A ring in plain memory. put() writes a record the way the kernel does:
    8-byte header (len | flags, pg_off), payload, 8-byte aligned step."""

    def __init__(self, start=0, size=SIZE):
        self.size = size
        self.cons = ctypes.create_string_buffer(8)
        self.prod = ctypes.create_string_buffer(8)
        self.data = ctypes.create_string_buffer(2 * size)
        self.pos = start
        struct.pack_into("<Q", self.cons, 0, start)
        struct.pack_into("<Q", self.prod, 0, start)
        self.ring = m.Ring(ctypes.addressof(self.cons), ctypes.addressof(self.prod),
                           ctypes.addressof(self.data), size)

    def put(self, raw, hflags=0, ln=None):
        ln = len(raw) if ln is None else ln
        off = self.pos & (self.size - 1)
        struct.pack_into("<II", self.data, off, ln | hflags, 0)
        self.data[off + 8: off + 8 + len(raw)] = raw
        self.pos += (ln + 8 + 7) & ~7
        struct.pack_into("<Q", self.prod, 0, self.pos)
        return off

    def consumer(self):
        return struct.unpack_from("<Q", self.cons, 0)[0]


def rec(rxq=1, seq=0, ver=1, ts=123):
    return m.REC.pack(ver, 0x10, rxq, 60, ts, b"\1" * 6, b"\2" * 6, 0x0800, 5,
                      bytes([10, 0, 0, 1]) + b"\0" * 12, bytes([10, 0, 0, 2]) + b"\0" * 12,
                      6, 64, 40, 1234, 80, 0x12, 0, 0, seq)


class Sink:
    def __init__(self):
        self.got = []

    def __call__(self, raw):
        self.got.append(raw)
        return True


def expect_stop(fn, word):
    try:
        fn()
    except m.Stop as e:
        if word not in str(e):
            raise AssertionError("STOP %r, want %r" % (str(e), word))
        return
    raise AssertionError("no STOP, want %r" % word)


def tmpfile_fd():
    fd, path = tempfile.mkstemp()
    os.unlink(path)
    return fd


# ------------------------------------------------------------------ ring

@case
def drain_basic():
    s = Synth()
    for i in range(5):
        s.put(rec(seq=i))
    k = Sink()
    assert s.ring.drain(100, k) == 5 and len(k.got) == 5
    assert k.got[3] == rec(seq=3)
    assert s.consumer() == s.pos, "consumer not advanced to producer"


@case
def wrap_around():
    # Start 40 bytes before the end: the record spans the size boundary and is
    # read contiguously (the kernel's double mapping).
    s = Synth(start=SIZE - 40)
    for i in range(3):
        s.put(rec(seq=i))
    k = Sink()
    assert s.ring.drain(100, k) == 3
    assert k.got == [rec(seq=i) for i in range(3)]
    assert s.consumer() == SIZE - 40 + 3 * 88


@case
def busy_stops_not_skips():
    s = Synth()
    s.put(rec(seq=0))
    s.put(rec(seq=1), m.RB_BUSY)
    s.put(rec(seq=2))
    k = Sink()
    assert s.ring.drain(100, k) == 1
    assert s.consumer() == 88, "consumer moved past a busy record"


@case
def discard_counted_and_skipped():
    s = Synth()
    s.put(rec(seq=0))
    s.put(rec(seq=1), m.RB_DISCARD)
    s.put(rec(seq=2))
    k = Sink()
    assert s.ring.drain(100, k) == 2 and s.ring.discarded == 1
    assert [struct.unpack_from("<I", r, 76)[0] for r in k.got] == [0, 2]


@case
def corrupt_length():
    s = Synth()
    s.put(rec(), ln=72)
    expect_stop(lambda: s.ring.drain(100, Sink()), "ring-corrupt len=72")
    assert s.consumer() == 0


@case
def corrupt_positions():
    s = Synth()
    struct.pack_into("<Q", s.cons, 0, 200)
    struct.pack_into("<Q", s.prod, 0, 100)
    expect_stop(lambda: s.ring.drain(100, Sink()), "ring-corrupt positions")
    struct.pack_into("<Q", s.cons, 0, 0)
    struct.pack_into("<Q", s.prod, 0, SIZE + 8)
    expect_stop(lambda: s.ring.drain(100, Sink()), "ring-corrupt positions")


@case
def record_past_producer():
    s = Synth()
    s.put(rec())
    struct.pack_into("<Q", s.prod, 0, 40)
    expect_stop(lambda: s.ring.drain(100, Sink()), "ring-corrupt len=80")


@case
def unknown_version_refused():
    s = Synth()
    s.put(rec(ver=2))
    expect_stop(lambda: s.ring.drain(100, Sink()), "ring-corrupt ver=2")
    assert s.consumer() == 0


@case
def ring_size_not_pow2():
    b = ctypes.create_string_buffer(8)
    expect_stop(lambda: m.Ring(ctypes.addressof(b), ctypes.addressof(b),
                               ctypes.addressof(b), 3000), "ring-size")


@case
def max_n_per_drain():
    s = Synth()
    for i in range(10):
        s.put(rec(seq=i))
    assert s.ring.drain(4, Sink()) == 4 and s.consumer() == 4 * 88


# ------------------------------------------------------------------ Run caps

@case
def cap_records():
    fd = tmpfile_fd()
    run = m.Run(fd, 3, 1 << 20)
    s = Synth()
    for i in range(5):
        s.put(rec(seq=i))
    assert s.ring.drain(100, run.sink) == 3 and run.reason == "max-records"
    assert s.consumer() == 3 * 88, "a refused record must stay in the ring"
    run.flush()
    assert os.fstat(fd).st_size == 3 * 80
    os.close(fd)


@case
def cap_bytes():
    fd = tmpfile_fd()
    run = m.Run(fd, 1000, m.HDR.size + 2 * 80 + 79)
    s = Synth()
    for i in range(5):
        s.put(rec(seq=i))
    assert s.ring.drain(100, run.sink) == 2 and run.reason == "max-bytes"
    os.close(fd)


@case
def seq_gaps_per_queue():
    fd = tmpfile_fd()
    run = m.Run(fd, 1000, 1 << 20)
    s = Synth()
    for q, seq in ((1, 0), (1, 1), (1, 5), (2, 7), (2, 8), (1, 6), (2, 0xFFFFFFFF)):
        s.put(rec(rxq=q, seq=seq))
    s.ring.drain(100, run.sink)
    # q1: 1->5 is 3 lost; q2: 8 -> 0xffffffff is 0xfffffff6 lost (wraps mod 2^32).
    assert run.gaps == 3 + ((0xFFFFFFFF - 8 - 1) & 0xFFFFFFFF), run.gaps
    os.close(fd)


@case
def arg_ceilings():
    for name, args in (("max-seconds", ["--max-seconds", "601"]),
                       ("max-seconds", ["--max-seconds", "0"]),
                       ("max-records", ["--max-records", "10000001"]),
                       ("max-bytes", ["--max-bytes", str((256 << 20) + 1)]),
                       ("max-bytes", ["--max-bytes", "100"]),
                       ("keep", ["--keep", "11"]),
                       ("keep", ["--keep", "0"])):
        out = io.StringIO()
        with patched(m.os, "geteuid", lambda: 0), contextlib.redirect_stdout(out):
            rc = m.main(args)
        assert rc == 1 and "STOP-arg-%s" % name in out.getvalue(), (args, out.getvalue())


@case
def not_root_refused():
    if os.geteuid() == 0:
        return
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = m.main([])
    assert rc == 1 and "STOP-not-root" in out.getvalue()


# ------------------------------------------------------------------ output dir

@case
def out_dir_mode():
    with tempfile.TemporaryDirectory() as d:
        os.chmod(d, 0o700)
        m.check_out_dir(d)
        os.chmod(d, 0o750)
        expect_stop(lambda: m.check_out_dir(d), "out-dir-mode")
        os.chmod(d, 0o700)
        link = d + "-link"
        os.symlink(d, link)
        try:
            expect_stop(lambda: m.check_out_dir(link), "out-dir-not-dir")
        finally:
            os.unlink(link)
        expect_stop(lambda: m.check_out_dir(os.path.join(d, "nope")), "out-dir-missing")


@case
def keep_prunes_oldest():
    with tempfile.TemporaryDirectory() as d:
        for t in ("20261101T000000Z", "20261102T000000Z", "20261103T000000Z", "20261104T000000Z"):
            open(os.path.join(d, "run-%s.bin" % t), "w").close()
        open(os.path.join(d, "other.txt"), "w").close()
        with contextlib.redirect_stdout(io.StringIO()):
            m.prune(d, 3)
        assert sorted(os.listdir(d)) == ["other.txt", "run-20261103T000000Z.bin",
                                         "run-20261104T000000Z.bin"], os.listdir(d)


# ------------------------------------------------------------------ do_run E2E

@contextlib.contextmanager
def patched(obj, name, val):
    old = getattr(obj, name)
    setattr(obj, name, val)
    try:
        yield
    finally:
        setattr(obj, name, old)


class FakeBpf:
    """Stands in for Bpf: pipes for map fds (epoll-able), a Synth ring."""

    def __init__(self, synth, ctl0, ctl1, cfg=(1, 4, 2000, 4000), missing=None):
        self.synth = synth
        self.ctl = [ctl0, ctl1]
        self.ctl_reads = 0
        self.cfg = cfg
        self.missing = missing
        self.fds = []

    def obj_get(self, name, mtype, max_entries, rdonly):
        if name == self.missing:
            raise m.Stop("no-pin %s" % os.path.join(m.PIN_DIR, name))
        assert rdonly == (name != "m2_rb"), "only m2_rb may be opened read-write"
        r, w = os.pipe()
        self.fds += [r, w]
        info = m._MapInfo(type=mtype, id=42, max_entries=max_entries, name=name.encode())
        return r, info

    def lookup(self, fd, key, size):
        if size == m.CFG.size:
            return m.CFG.pack(*self.cfg)
        ncpu = size // 8
        which = self.ctl[0] if self.ctl_reads < len(m.CTL_NAMES) else self.ctl[1]
        self.ctl_reads += 1
        return struct.pack("<%dQ" % ncpu, which[key], *([0] * (ncpu - 1)))

    def mmap_ring(self, fd, size):
        assert size == m.RB_BYTES
        return self.synth.ring

    def close(self):
        for f in self.fds:
            os.close(f)


def run_e2e(synth, args, missing=None):
    ctl0 = [10, 1, 2, 0, 7, 0]
    ctl1 = [30, 3, 4, 0, 23, 0]
    fake = FakeBpf(synth, ctl0, ctl1, missing=missing)
    real_check = m.check_out_dir
    out = io.StringIO()
    with tempfile.TemporaryDirectory() as d:
        os.chmod(d, 0o700)
        uid = os.geteuid()
        with patched(m, "OUT_DIR", d), patched(m, "Bpf", lambda: fake), \
                patched(m, "possible_cpus", lambda: 4), \
                patched(m, "check_out_dir", lambda p: owner_check(real_check, uid, p)), \
                patched(m.os, "geteuid", lambda: 0), patched(m, "FREE_MARGIN", 0), \
                contextlib.redirect_stdout(out):
            rc = m.main(args)
        files = m.run_files(d)
        modes = {f: stat.S_IMODE(os.stat(os.path.join(d, f)).st_mode) for f in files}
        dmode = stat.S_IMODE(os.stat(d).st_mode)
        body = open(os.path.join(d, files[0]), "rb").read() if files else b""
        summary = io.StringIO()
        if files:
            with patched(m.os, "geteuid", lambda: 0), contextlib.redirect_stdout(summary):
                src = m.main(["--summary", os.path.join(d, files[0])])
            assert src == 0, summary.getvalue()
    fake.close()
    return rc, out.getvalue(), files, modes, dmode, body, summary.getvalue()


def owner_check(real_check, uid, path):
    # check_out_dir compares st_uid with geteuid(); the temp dir is ours, not root's.
    with patched(m.os, "geteuid", lambda: uid):
        real_check(path)


@case
def e2e_records_cap():
    s = Synth(size=m.RB_BYTES)
    for i in range(7):
        s.put(rec(rxq=i % 2, seq=i // 2, ts=1000 + i))
    rc, out, files, modes, dmode, body, summary = run_e2e(s, ["--max-records", "5", "--max-seconds", "5"])
    assert rc == 0, out
    assert "M1S2-READER-BEGIN" in out and "cfg=ver:1,every:4,rate:2000,burst:4000" in out, out
    end = [l for l in out.splitlines() if l.startswith("M1S2-READER-END")]
    assert end and "reason=max-records records=5 " in end[0], out
    assert "ctl_seen=20 ctl_sampled_out=2 ctl_rate_limited=2 ctl_rb_full=0 ctl_emitted=16" in end[0], end
    assert "backlog=176" in end[0], end
    assert len(files) == 1 and modes[files[0]] == 0o600 and dmode == 0o700, (files, modes, dmode)
    h = m.HDR.unpack(body[:m.HDR.size])
    assert h[0] == m.MAGIC and h[2] == 80 and h[6:10] == (1, 4, 2000, 4000) and h[10:16] == (10, 1, 2, 0, 7, 0), h
    assert len(body) == m.HDR.size + 5 * 80 and body[m.HDR.size:m.HDR.size + 80] == rec(rxq=0, seq=0, ts=1000)
    assert "SUMMARY file=" in summary and "records=5" in summary and "SUMMARY-RXQ 0=3 1=2" in summary, summary
    assert "SUMMARY-TOP-SRC 10.0.0.1 5" in summary, summary


@case
def e2e_seconds_cap_empty_ring():
    s = Synth(size=m.RB_BYTES)
    rc, out, files, _m, _d, body, _s = run_e2e(s, ["--max-seconds", "1"])
    assert rc == 0 and "reason=max-seconds records=0 " in out, out
    assert len(body) == m.HDR.size


@case
def e2e_missing_pin_no_file():
    s = Synth(size=m.RB_BYTES)
    rc, out, files, *_ = run_e2e(s, ["--max-seconds", "1"], missing="m2_rb")
    assert rc == 1 and "STOP-no-pin" in out and files == [], (out, files)


@case
def e2e_corrupt_ring_stops_nonzero():
    s = Synth(size=m.RB_BYTES)
    s.put(rec(seq=0))
    s.put(rec(ver=9))
    rc, out, files, *_ = run_e2e(s, ["--max-seconds", "2"])
    assert rc == 1 and "STOP-ring-corrupt ver=9" in out, out
    assert "M1S2-READER-END" not in out, out


# ------------------------------------------------------------------ static

@case
def no_socket_no_write_maps():
    src = open(sys.argv[1]).read()
    code = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
    for bad in ("import socket", "socket.", "BPF_MAP_UPDATE_ELEM", "BPF_MAP_DELETE_ELEM",
                "BPF_PROG_LOAD", "BPF_LINK_CREATE", "subprocess", "urllib", "http"):
        assert bad not in code, bad
    assert m.REC_FMT == "<BBHIQ6s6sHH16s16sBBHHHBBHI"
    assert select.epoll  # the reader needs epoll on this Python


def main():
    n = 0
    for fn in CASES:
        try:
            fn()
        except Exception as e:  # noqa: BLE001 - report any failure by case name
            print("READER-TEST-FAIL %s: %s: %s" % (fn.__name__, type(e).__name__, e))
            return 1
        n += 1
    print("READER-TEST-OK cases=%d" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
