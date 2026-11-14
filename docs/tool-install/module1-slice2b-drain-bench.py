#!/usr/bin/env python3
"""Micro-benchmark: userspace reader drain loop on Rock Box (Ryzen 9 9900X).

Simulates RotatingWriter.sink per-record loop: ctypes record pointer copy,
sequence tracking, write buffer packing, and periodic statvfs flush.
"""
import ctypes
import os
import struct
import tempfile
import time

RECORD_LEN = 80
raw = (ctypes.c_char * RECORD_LEN)(*([0] * RECORD_LEN))
ptr = ctypes.addressof(raw)


def bench(n_records=1_000_000):
    t0 = time.perf_counter()
    with tempfile.TemporaryDirectory() as td:
        fd = os.open(os.path.join(td, "bench.bin"), os.O_WRONLY | os.O_CREAT, 0o600)
        write_buf = bytearray(65536)
        w_off = 0
        seq = 0
        for i in range(n_records):
            _now_ns = time.clock_gettime_ns(time.CLOCK_REALTIME)
            data = ctypes.string_at(ptr, RECORD_LEN)
            _seq_lo = struct.unpack_from("<I", data, 0)[0]
            seq = (seq + 1) & 0xFFFFFFFF
            write_buf[w_off : w_off + RECORD_LEN] = data
            w_off += RECORD_LEN
            if w_off + RECORD_LEN > len(write_buf):
                os.write(fd, write_buf[:w_off])
                w_off = 0
            if (i & 255) == 0:
                os.statvfs(td)
        if w_off:
            os.write(fd, write_buf[:w_off])
        os.close(fd)
    elapsed = time.perf_counter() - t0
    rate = n_records / elapsed
    print(f"DRAIN-BENCH: {n_records} records in {elapsed:.3f}s = {rate:,.0f} rec/s")


if __name__ == "__main__":
    bench()
