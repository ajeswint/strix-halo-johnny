#!/usr/bin/env bash
# Johnny Module 1 slice 2b self-test (rock-box only; no root, no SSH).
#
# Tests:
# 1. Pins: sha256 sums of deployables and system dependencies.
# 2. Syntax & Shellcheck: module1-slice2b-boot.sh and this test.
# 3. Static checks: systemd units, python compile, helper command gates.
# 4. Reader tests: synthetic ring, rotation, pruning, dir cap, free space reserve, corrupt ring, summary.
# 5. E2E simulated scenarios: clean attach, idempotent already-attached, observer refuse, foreign refuse,
#    clean stop, keep-observer, status, verify, boot wait timeout, IRQ-renumber, rollback.
# 6. Runbook verification: markdown fence check, tokens, hashes, single-quote sudo.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
cd "$REPO"

DOC="docs/tool-install/module1-slice2b-boot-unit.md"
BOOT_SH="docs/tool-install/module1-slice2b-boot.sh"
UNIT="etc/systemd/system/johnny-capture-xdp-records.service"
READER="docs/tool-install/johnny-m1s2b-reader.py"
RUNIT="etc/systemd/system/johnny-m1s2b-reader.service"
OBJ="docs/tool-install/module1-xdp-records.o"
CORES="etc/johnny/capture-cores"
IRQ_HELPER="etc/johnny/irq-affinity.sh"

WANT_OBJ_SHA="a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481"
WANT_BOOT_SHA="1f449f12a0975f05005e16703f96dc21a5a133b10608c3506dbe49e670f3989d"
WANT_UNIT_SHA="4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a"
WANT_READER_SHA="476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37"
WANT_RUNIT_SHA="e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c"
WANT_CORES_SHA="16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b"
WANT_IRQ_SHA="db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4"

fail() {
  echo "SELF-TEST-FAIL: $*" >&2
  exit 1
}

# ---------------------------------------------------------------- 1. pins

check_hash() {
  local path=$1 want=$2 got
  [ -f "$path" ] || fail "missing file $path"
  got=$(sha256sum "$path" | awk '{print $1}')
  [ "$got" = "$want" ] || fail "hash mismatch $path: got $got want $want"
}

check_hash "$OBJ" "$WANT_OBJ_SHA"
check_hash "$BOOT_SH" "$WANT_BOOT_SHA"
check_hash "$UNIT" "$WANT_UNIT_SHA"
check_hash "$READER" "$WANT_READER_SHA"
check_hash "$RUNIT" "$WANT_RUNIT_SHA"
check_hash "$CORES" "$WANT_CORES_SHA"
check_hash "$IRQ_HELPER" "$WANT_IRQ_SHA"
echo PINS-OK

# ---------------------------------------------------------------- 2. syntax & shellcheck

shellcheck "$BOOT_SH" || fail "shellcheck failed on $BOOT_SH"
shellcheck "$HERE/module1-slice2b-self-test.sh" || fail "shellcheck failed on self-test"
echo SHELLCHECK-OK

# ---------------------------------------------------------------- 3. static checks

if systemd-analyze verify "$UNIT" "$RUNIT" 2>&1 | grep -q "error"; then
  fail "systemd-analyze verify error"
fi
grep -q -- "--file-max-bytes 1073741824" "$RUNIT" || fail "RUNIT missing --file-max-bytes 1073741824"
grep -q -- "--file-max-seconds 3600" "$RUNIT" || fail "RUNIT missing --file-max-seconds 3600"
grep -q -- "--keep 200" "$RUNIT" || fail "RUNIT missing --keep 200"
grep -q -- "--dir-cap-bytes 214748364800" "$RUNIT" || fail "RUNIT missing --dir-cap-bytes 214748364800"
grep -q -- "--reserve-bytes 107374182400" "$RUNIT" || fail "RUNIT missing --reserve-bytes 107374182400"
grep -q "^MemoryMax=1G$" "$RUNIT" || fail "RUNIT missing MemoryMax=1G"
grep -q "^MemorySwapMax=0$" "$RUNIT" || fail "RUNIT missing MemorySwapMax=0"

fsize_str=$(grep "^LimitFSIZE=" "$RUNIT" | cut -d= -f2)
[ -n "$fsize_str" ] || fail "RUNIT missing LimitFSIZE"
fsize_bytes=$(python3 -c '
import re, sys
s = sys.argv[1].strip()
m = re.match(r"^(\d+)([KMGTP]?)$", s)
if not m: sys.exit(1)
val, mult = int(m.group(1)), m.group(2)
scales = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4, "P": 1024**5}
print(val * scales[mult])
' "$fsize_str")
[ "$fsize_bytes" -ge 1073741824 ] || fail "LimitFSIZE $fsize_str ($fsize_bytes B) does not cover 1 GiB file cap (header included)"

python3 -m py_compile "$READER" || fail "python compile failed on $READER"

# Verify cfg hex decodes to the new cfg
python3 -I -c '
import struct
hex_bytes = bytes.fromhex("01 00 00 00 01 00 00 00 40 42 0f 00 a0 86 01 00")
ver, every, rate, burst = struct.unpack("<IIII", hex_bytes)
assert (ver, every, rate, burst) == (1, 1, 1000000, 100000), (ver, every, rate, burst)
' || fail "cfg hex failed to decode to ver=1 sample_every=1 rate=1000000 burst=100000"

grep -q "01 00 00 00 01 00 00 00 40 42 0f 00 a0 86 01 00" "$BOOT_SH" || fail "BOOT_SH missing new cfg hex"
grep -q "apply-cfg" "$BOOT_SH" || fail "BOOT_SH missing apply-cfg"
grep -q "window" "$BOOT_SH" || fail "BOOT_SH missing window"

echo STATIC-CHECKS-OK

# ---------------------------------------------------------------- 4. reader tests

python3 -I - "$READER" <<'PY'
import ctypes, os, shutil, struct, sys, tempfile, time

reader_path = sys.argv[1]
import importlib.util
spec = importlib.util.spec_from_file_location("reader", reader_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# 1. Ring consumer test
size = 4096
cons = (ctypes.c_uint64 * 1)()
prod = (ctypes.c_uint64 * 1)()
data = (ctypes.c_char * (2 * size))()
ring = mod.Ring(ctypes.addressof(cons), ctypes.addressof(prod), ctypes.addressof(data), size)

class Sink:
    def __init__(self):
        self.got = []
    def __call__(self, r):
        self.got.append(r)
        return True

k = Sink()
assert ring.drain(10, k) == 0

# Put 1 valid record
wire_rec = bytearray(mod.REC_SIZE)
wire_rec[0] = mod.REC_VERSION
struct.pack_into("<I", wire_rec, 76, 100) # seq_lo = 100

hdr = mod.REC_SIZE
struct.pack_into("<I", data, 0, hdr)
data[8:8+mod.REC_SIZE] = wire_rec
prod[0] = (mod.REC_SIZE + 8 + 7) & ~7
assert ring.drain(10, k) == 1
assert len(k.got) == 1
assert cons[0] == prod[0]

# Discarded record
struct.pack_into("<I", data, cons[0] & (size - 1), hdr | mod.RB_DISCARD)
prod[0] = cons[0] + ((mod.REC_SIZE + 8 + 7) & ~7)
assert ring.drain(10, k) == 0
assert ring.discarded == 1

# Busy record (should break without advancing)
struct.pack_into("<I", data, cons[0] & (size - 1), hdr | mod.RB_BUSY)
prod[0] = cons[0] + ((mod.REC_SIZE + 8 + 7) & ~7)
assert ring.drain(10, k) == 0

# Corrupt record test: invalid length raises Stop
struct.pack_into("<I", data, cons[0] & (size - 1), 99) # invalid length
try:
    ring.drain(10, k)
    assert False, "expected Stop on corrupt len"
except mod.Stop:
    pass

# Corrupt positions test: prod < cons raises Stop
cons[0] = 500
prod[0] = 400
try:
    ring.drain(10, k)
    assert False, "expected Stop on corrupt positions"
except mod.Stop:
    pass

# 2. File rotation, Pruning, Dir Cap, Summary tests in tempdir
tmpdir = tempfile.mkdtemp(prefix="test_m1s2b_reader_")
orig_check_disk_free = mod.check_disk_free
try:
    # Test prune keep
    for i in range(5):
        p = os.path.join(tmpdir, "run-20261111T12000%dZ.bin" % i)
        with open(p, "wb") as f:
            f.write(b"x" * 100)
    mod.prune(tmpdir, keep=3, dir_cap_bytes=10000, new_file_reserved_bytes=100)
    files = mod.run_files(tmpdir)
    assert len(files) == 2, "expected 2 files remaining after keep=3 prune, got %d" % len(files)
    assert files == ["run-20261111T120003Z.bin", "run-20261111T120004Z.bin"]

    # Test dir cap prune
    mod.prune(tmpdir, keep=10, dir_cap_bytes=150, new_file_reserved_bytes=100)
    files = mod.run_files(tmpdir)
    assert len(files) == 0, "expected 0 files after dir cap prune"

    # Test rotating writer
    class DummyBpf:
        def lookup(self, fd, key, size):
            ncpu = size // 8
            if key == 0:
                return struct.pack("<%dQ" % ncpu, 10, *([0] * (ncpu - 1)))
            elif key == 4:
                return struct.pack("<%dQ" % ncpu, 10, *([0] * (ncpu - 1)))
            return b"\x00" * size

    # Direct test of read_ctl without stubbing (must not stub read_ctl)
    ctl_direct = mod.read_ctl(DummyBpf(), 0, 4)
    assert list(ctl_direct) == [10, 0, 0, 0, 10, 0], f"unexpected read_ctl: {ctl_direct}"

    # Test mmap failure check uses ctypes.c_void_p(-1).value
    class FakeMmap:
        restype = None
        argtypes = None
        def __call__(self, *args):
            return ctypes.c_void_p(-1).value

    class FakeLibc:
        mmap = FakeMmap()

    bpf_test = mod.Bpf.__new__(mod.Bpf)
    bpf_test.libc = FakeLibc()
    try:
        bpf_test.mmap_ring(0, 4096)
        assert False, "expected Stop on MAP_FAILED"
    except mod.Stop as e:
        assert "mmap-consumer" in str(e), f"unexpected Stop: {e}"

    writer = mod.RotatingWriter(
        out_dir=tmpdir,
        file_max_bytes=mod.HDR.size + 2 * mod.REC_SIZE,
        file_max_seconds=3600,
        keep=3,
        dir_cap_bytes=100000,
        reserve_bytes=1024,
        bpf=DummyBpf(),
        cfg=(1, 1, 8000, 16000),
        ctl_fd=0,
        ncpu=4
    )
    mod.check_disk_free = lambda out_dir, res: 1000000

    writer.open_next_file()
    assert writer.total_files == 1
    f1 = writer.path

    # Sink 2 records -> fills file 1
    r1 = bytearray(mod.REC_SIZE)
    r1[0] = 1
    struct.pack_into("<I", r1, 76, 1)
    writer.sink(bytes(r1))
    writer.sink(bytes(r1))

    # Sink 3rd record -> triggers rotation to file 2
    writer.sink(bytes(r1))
    assert writer.total_files == 2
    f2 = writer.path
    assert f1 != f2
    writer.close_current_file()

    # Test summary mode on f1
    class DummyArgs:
        file = f1
        top = 5
    rc = mod.do_summary(DummyArgs())
    assert rc == 0
finally:
    mod.check_disk_free = orig_check_disk_free
    shutil.rmtree(tmpdir)

# 3. New retention arguments bounded() checks
fmb = mod.bounded("file-max-bytes", 1073741824, mod.MAX_FILE_BYTES, mod.HDR.size + mod.REC_SIZE)
assert fmb == 1073741824
fms = mod.bounded("file-max-seconds", 3600, mod.MAX_FILE_SECONDS)
assert fms == 3600
kp = mod.bounded("keep", 200, mod.MAX_KEEP)
assert kp == 200
dcb = mod.bounded("dir-cap-bytes", 214748364800, mod.MAX_DIR_CAP_BYTES, floor=fmb)
assert dcb == 214748364800
rb = mod.bounded("reserve-bytes", 107374182400, mod.MAX_RESERVE_BYTES)
assert rb == 107374182400

try:
    mod.bounded("file-max-bytes", mod.MAX_FILE_BYTES + 1, mod.MAX_FILE_BYTES)
    assert False, "expected Stop on file-max-bytes ceiling"
except mod.Stop:
    pass

try:
    mod.bounded("keep", mod.MAX_KEEP + 1, mod.MAX_KEEP)
    assert False, "expected Stop on keep ceiling"
except mod.Stop:
    pass

try:
    mod.bounded("dir-cap-bytes", 500, mod.MAX_DIR_CAP_BYTES, floor=1000)
    assert False, "expected Stop on dir-cap-bytes floor"
except mod.Stop:
    pass

try:
    mod.bounded("reserve-bytes", 0, mod.MAX_RESERVE_BYTES)
    assert False, "expected Stop on reserve-bytes floor"
except mod.Stop:
    pass

# 4. Prune test: byte cap (not keep) forces oldest-first deletion
tmp_cap = tempfile.mkdtemp(prefix="test_prune_cap_")
try:
    for i in range(5):
        p = os.path.join(tmp_cap, "run-20261114T10000%dZ.bin" % i)
        with open(p, "wb") as f:
            f.write(b"y" * 500)
    # keep=200 is not reached; dir_cap=1600, new_reserved=500. Total 2500 + 500 = 3000 > 1600.
    # Prunes oldest files until total + 500 <= 1600, leaving exactly the 2 newest files (1000 + 500 <= 1600)
    mod.prune(tmp_cap, keep=200, dir_cap_bytes=1600, new_file_reserved_bytes=500)
    files = mod.run_files(tmp_cap)
    assert files == ["run-20261114T100003Z.bin", "run-20261114T100004Z.bin"], f"unexpected prune files: {files}"
    assert sum(os.path.getsize(os.path.join(tmp_cap, f)) for f in files) + 500 <= 1600
finally:
    shutil.rmtree(tmp_cap)

# 5. Disk free reserve check test
tmp_res = tempfile.mkdtemp(prefix="test_reserve_")
try:
    free = mod.check_disk_free(tmp_res, reserve_bytes=0)
    assert free > 0
    try:
        mod.check_disk_free(tmp_res, reserve_bytes=free + 10**12)
        assert False, "expected Stop on low disk free"
    except mod.Stop as e:
        assert "low-disk" in str(e)
finally:
    shutil.rmtree(tmp_res)

print("READER-TESTS-PASSED")
PY
echo READER-TESTS-OK

# ---------------------------------------------------------------- 5. E2E simulated scenarios

E2E_DIR=$(mktemp -d /tmp/m1s2b-e2e.XXXXXX)
trap 'rm -rf "$E2E_DIR"' EXIT

MOCK_DIR="$E2E_DIR/mock_state"
FIXTURES_DIR="$E2E_DIR/fixtures"

mkdir -p "$E2E_DIR/bin" "$E2E_DIR/root/m1s2b" "$E2E_DIR/etc/johnny" "$E2E_DIR/etc/systemd/system" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b" "$E2E_DIR/var/lib/johnny/m1s2b" "$E2E_DIR/proc/irq" "$E2E_DIR/sysfs/net/eno1np0" "$MOCK_DIR" "$FIXTURES_DIR"

# Extract fixtures copied VERBATIM from evidence file
EVIDENCE="docs/findings/module1-slice2b/2026-11-12-evidence-johnny.txt"
[ -f "$EVIDENCE" ] || fail "missing evidence file $EVIDENCE"

M1_STATS_JSON=$(sed -n '/^== m1_stats$/{n;p}' "$EVIDENCE")
M2_CTL_JSON=$(sed -n '/^== m2_ctl$/{n;p}' "$EVIDENCE")
M2_CFG_JSON=$(sed -n '/^== m2_cfg$/{n;p}' "$EVIDENCE")

[ -n "$M1_STATS_JSON" ] || fail "failed to extract m1_stats fixture from $EVIDENCE"
[ -n "$M2_CTL_JSON" ] || fail "failed to extract m2_ctl fixture from $EVIDENCE"
[ -n "$M2_CFG_JSON" ] || fail "failed to extract m2_cfg fixture from $EVIDENCE"

echo "$M1_STATS_JSON" > "$FIXTURES_DIR/m1_stats.json"
echo "$M2_CTL_JSON" > "$FIXTURES_DIR/m2_ctl.json"
echo "$M2_CFG_JSON" > "$FIXTURES_DIR/m2_cfg.json"

# Prepare stats_after.json for verify window delta (+100 packets on CPU 1 of key 0)
python3 -I - "$FIXTURES_DIR/m1_stats.json" "$FIXTURES_DIR/stats_after.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    doc = json.load(f)
doc[0]["formatted"]["values"][1]["value"] += 100
v = doc[0]["formatted"]["values"][1]["value"]
doc[0]["values"][1]["value"] = ["0x%02x" % ((v >> (8 * b)) & 0xFF) for b in range(8)]
with open(dst, "w") as f:
    json.dump(doc, f)
PY

# Prepare ctl_after variations for drops verification
python3 -I - "$FIXTURES_DIR/m2_ctl.json" "$FIXTURES_DIR" <<'PY'
import copy, json, sys
src, dst_dir = sys.argv[1], sys.argv[2]
with open(src) as f:
    doc = json.load(f)

def bump(d, k_idx, delta):
    out = copy.deepcopy(d)
    out[k_idx]["formatted"]["values"][1]["value"] += delta
    v = out[k_idx]["formatted"]["values"][1]["value"]
    out[k_idx]["values"][1]["value"] = ["0x%02x" % ((v >> (8 * b)) & 0xFF) for b in range(8)]
    return out

with open(f"{dst_dir}/ctl_after_rl.json", "w") as f:
    json.dump(bump(doc, 2, 5), f)
with open(f"{dst_dir}/ctl_after_rb.json", "w") as f:
    json.dump(bump(doc, 3, 3), f)
with open(f"{dst_dir}/ctl_after_disc.json", "w") as f:
    json.dump(bump(doc, 5, 2), f)
PY

# Copy deployables into fake root
cp "$OBJ" "$E2E_DIR/root/m1s2b/module1-xdp-records.o"
cp "$READER" "$E2E_DIR/bin/johnny-m1s2b-reader.py"
chmod 0644 "$E2E_DIR/bin/johnny-m1s2b-reader.py"
cp "$UNIT" "$E2E_DIR/etc/systemd/system/johnny-capture-xdp-records.service"
cp "$RUNIT" "$E2E_DIR/etc/systemd/system/johnny-m1s2b-reader.service"
cp "$CORES" "$E2E_DIR/etc/johnny/capture-cores"
cp "$IRQ_HELPER" "$E2E_DIR/etc/johnny/irq-affinity.sh"
chmod 0755 "$E2E_DIR/etc/johnny/irq-affinity.sh"

# Mock system commands using isolated per-test MOCK_DIR (no shared /tmp/mock_* paths)
cat > "$E2E_DIR/bin/systemctl" <<EOF
#!/bin/bash
MOCK_DIR="$MOCK_DIR"
case "\$*" in
  *"is-enabled suricata"*) echo "disabled"; exit 0 ;;
  *"is-active suricata"*) echo "inactive"; exit 0 ;;
  *"is-active johnny-capture-irq.service"*) echo "active"; exit 0 ;;
  *"is-active johnny-capture-tuning.service"*) echo "active"; exit 0 ;;
  *"is-enabled johnny-capture-xdp.service"*) cat "\$MOCK_DIR/c1_enabled" 2>/dev/null || echo "disabled"; exit 0 ;;
  *"is-active johnny-capture-xdp.service"*) cat "\$MOCK_DIR/c1_state" 2>/dev/null || echo "inactive"; exit 0 ;;
  *"is-enabled johnny-capture-xdp-records.service"*) cat "\$MOCK_DIR/2x_enabled" 2>/dev/null || echo "enabled"; exit 0 ;;
  *"is-active johnny-capture-xdp-records.service"*) cat "\$MOCK_DIR/2x_state" 2>/dev/null || echo "active"; exit 0 ;;
  *"is-enabled johnny-m1s2b-reader.service"*) cat "\$MOCK_DIR/2r_enabled" 2>/dev/null || echo "enabled"; exit 0 ;;
  *"is-active johnny-m1s2b-reader.service"*) cat "\$MOCK_DIR/2r_state" 2>/dev/null || echo "active"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$E2E_DIR/bin/systemctl"

cat > "$E2E_DIR/bin/bpftool" <<EOF
#!/bin/bash
MOCK_DIR="$MOCK_DIR"
FIXTURES_DIR="$FIXTURES_DIR"
case "\$*" in
  *"-j net show dev eno1np0"*)
    cat "\$MOCK_DIR/net_attach" 2>/dev/null || echo '[]'
    exit 0
    ;;
  *"net show dev eno1np0"*)
    cat "\$MOCK_DIR/net_show_text" 2>/dev/null || echo "xdp: eno1np0(4) driver id 138"
    exit 0
    ;;
  *"prog show id "*)
    id=\$(echo "\$*" | awk '{for(i=1;i<=NF;i++) if(\$i=="id") print \$(i+1)}')
    pname=\$(cat "\$MOCK_DIR/prog_id_name" 2>/dev/null || echo "j_xdp_observe")
    echo "\$id: xdp  name \$pname  tag b5b852630d7539c7  gpl"
    exit 0
    ;;
  *"-j prog show pinned"*)
    cat "\$MOCK_DIR/prog_pinned" 2>/dev/null || echo '{"id": 200, "name": "j_xdp_records"}'
    exit 0
    ;;
  *"-j prog show"*)
    cat "\$MOCK_DIR/prog_show" 2>/dev/null || echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]'
    exit 0
    ;;
  *"prog load"*)
    pdir="\${6:-$E2E_DIR/sys/fs/bpf/johnny_m1s2b}"
    mkdir -p "\$pdir"
    touch "\$pdir/m1_rxq" "\$pdir/m1_stats" "\$pdir/m2_cfg" "\$pdir/m2_ctl" "\$pdir/m2_rb" "\$pdir/m2_state" "\$pdir/prog"
    echo '{"id": 200, "name": "j_xdp_records"}' > "\$MOCK_DIR/prog_pinned"
    echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > "\$MOCK_DIR/prog_show"
    exit 0
    ;;
  *"map update pinned"*"m2_cfg"*)
    echo "ver=1 sample_every=1 rate=1000000 burst=100000" > "\$MOCK_DIR/cfg_val"
    exit 0
    ;;
  *"-j map dump pinned"*"m2_cfg"*)
    if [ -f "\$MOCK_DIR/cfg_val" ]; then
      cat <<JSON
[{"key": 0, "value": ["0x01", "0x00", "0x00", "0x00", "0x01", "0x00", "0x00", "0x00", "0x40", "0x42", "0x0f", "0x00", "0xa0", "0x86", "0x01", "0x00"], "formatted": {"key": 0, "value": {"ver": 1, "sample_every": 1, "rate": 1000000, "burst": 100000}}}]
JSON
    else
      cat "\$FIXTURES_DIR/m2_cfg.json"
    fi
    exit 0
    ;;
  *"-j map dump pinned"*"m2_ctl"*)
    if [ -f "\$MOCK_DIR/ctl_drop_rl" ]; then
      cat "\$FIXTURES_DIR/ctl_after_rl.json"
    elif [ -f "\$MOCK_DIR/ctl_drop_rb" ]; then
      cat "\$FIXTURES_DIR/ctl_after_rb.json"
    elif [ -f "\$MOCK_DIR/ctl_drop_disc" ]; then
      cat "\$FIXTURES_DIR/ctl_after_disc.json"
    else
      cat "\$FIXTURES_DIR/m2_ctl.json"
    fi
    exit 0
    ;;
  *"-j map dump pinned"*"m1_stats"*)
    if [ -f "\$MOCK_DIR/stats_delta" ]; then
      cat "\$FIXTURES_DIR/stats_after.json"
    else
      cat "\$FIXTURES_DIR/m1_stats.json"
    fi
    exit 0
    ;;
  *"net attach xdpdrv"*)
    echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > "\$MOCK_DIR/net_attach"
    exit 0
    ;;
  *"net detach"*)
    echo '[]' > "\$MOCK_DIR/net_attach"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$E2E_DIR/bin/bpftool"

cat > "$E2E_DIR/bin/ethtool" <<'EOF'
#!/bin/bash
case "$*" in
  *"-l eno1np0"*)
    echo -e "Current hardware settings:\nCombined: 12"
    exit 0
    ;;
  *"-S eno1np0"*)
    echo "rx_dropped: 0"
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$E2E_DIR/bin/ethtool"

cat > "$E2E_DIR/bin/tcpdump" <<EOF
#!/bin/bash
MOCK_DIR="$MOCK_DIR"
touch "\$MOCK_DIR/stats_delta"
if [ -f "\$MOCK_DIR/ctl_drop_rl_on_tcpdump" ]; then
  touch "\$MOCK_DIR/ctl_drop_rl"
fi
if [ -f "\$MOCK_DIR/ctl_drop_rb_on_tcpdump" ]; then
  touch "\$MOCK_DIR/ctl_drop_rb"
fi
echo "100 packets captured" >&2
echo "0 packets dropped by kernel" >&2
exit 0
EOF
chmod +x "$E2E_DIR/bin/tcpdump"

cat > "$E2E_DIR/bin/sudo" <<'EOF'
#!/bin/bash
if [ "$1" = "-v" ]; then
  exit 0
fi
if [ "$1" = "bash" ] && [ "$2" = "/root/m1s2b/module1-slice2b-boot.sh" ]; then
  exit 0
fi
exec "$@"
EOF
chmod +x "$E2E_DIR/bin/sudo"

cat > "$E2E_DIR/bin/sha256sum" <<'EOF'
#!/bin/bash
if [ "$1" = "-c" ]; then
  while read -r hash path; do
    if [ -f "$path" ]; then
      echo "$hash  $path" | /usr/bin/sha256sum -c -
    else
      echo "$path: OK"
    fi
  done
  exit 0
fi
exec /usr/bin/sha256sum "$@"
EOF
chmod +x "$E2E_DIR/bin/sha256sum"

cat > "$E2E_DIR/bin/ssh" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do
  case "$1" in
    -*) shift ;;
    *@*|192.168.*) shift; break ;;
    *) break ;;
  esac
done
remote_cmd="$*"
exec bash -c "$remote_cmd"
EOF
chmod +x "$E2E_DIR/bin/ssh"

# Populate sysfs mock
echo 0x1183 > "$E2E_DIR/sysfs/net/eno1np0/flags"
echo 10000 > "$E2E_DIR/sysfs/net/eno1np0/speed"
echo 1 > "$E2E_DIR/sysfs/net/eno1np0/carrier"
echo up > "$E2E_DIR/sysfs/net/eno1np0/operstate"
echo 1500 > "$E2E_DIR/sysfs/net/eno1np0/mtu"

# Prepare test script adaptation with overridden paths
sed -e "s|STATE_DIR=/root/m1s2b|STATE_DIR=$E2E_DIR/root/m1s2b|g" \
    -e "s|PIN_DIR=/sys/fs/bpf/johnny_m1s2b|PIN_DIR=$E2E_DIR/sys/fs/bpf/johnny_m1s2b|g" \
    -e "s|OUT_DIR=/var/lib/johnny/m1s2b|OUT_DIR=$E2E_DIR/var/lib/johnny/m1s2b|g" \
    -e "s|SAFE_PATH=/usr/sbin:/usr/bin:/sbin:/bin|SAFE_PATH=$E2E_DIR/bin:/usr/sbin:/usr/bin:/sbin:/bin|g" \
    -e "s|LOCK_FILE=/run/johnny-m1s2b.lock|LOCK_FILE=$E2E_DIR/lock|g" \
    -e "s|SYSFS_NET=/sys/class/net|SYSFS_NET=$E2E_DIR/sysfs/net|g" \
    -e "s|READER=/usr/local/libexec/johnny/johnny-m1s2b-reader.py|READER=$E2E_DIR/bin/johnny-m1s2b-reader.py|g" \
    -e "s|R_UNIT_FILE=/etc/systemd/system/johnny-m1s2b-reader.service|R_UNIT_FILE=$E2E_DIR/etc/systemd/system/johnny-m1s2b-reader.service|g" \
    -e "s|UNIT_FILE=/etc/systemd/system/johnny-capture-xdp-records.service|UNIT_FILE=$E2E_DIR/etc/systemd/system/johnny-capture-xdp-records.service|g" \
    -e "s|CORES=/etc/johnny/capture-cores|CORES=$E2E_DIR/etc/johnny/capture-cores|g" \
    -e "s|HELPER=/etc/johnny/irq-affinity.sh|HELPER=$E2E_DIR/etc/johnny/irq-affinity.sh|g" \
    "$BOOT_SH" > "$E2E_DIR/test-helper.sh"
chmod 0700 "$E2E_DIR/test-helper.sh"

export PATH="$E2E_DIR/bin:$PATH"

# Run helper in a subshell with mocked functions for tests
run_sub() {
  local sub="$1"
  shift || true
  bash -c '
    export PATH="'"$E2E_DIR"'/bin:$PATH"
    source '"$E2E_DIR/test-helper.sh"'
    gate_host() { return 0; }
    need_files() { return 0; }
    eno3_ok() { return 0; }
    wait_boot_ready() { return 0; }
    eno1_ready_now() { return 0; }
    sleep() { :; }
    irq_snapshot() {
      for i in {0..11}; do
        echo "IRQ $((100 + i)) ice-eno1np0-TxRx-$i $(((i % 4) + 1))"
      done
    }
    irq_in_cores() { return 0; }
    sub="'"$sub"'"
    sub_fn="do_${sub//-/_}"
    if declare -f "$sub_fn" >/dev/null; then
      "$sub_fn" "$@"
    elif declare -f "do_$sub" >/dev/null; then
      "do_$sub" "$@"
    elif declare -f "$sub" >/dev/null; then
      "$sub" "$@"
    else
      main "$sub" "$@"
    fi
  ' _ "$@"
}

# Ensure pin directory and map dummy files exist for fixture tests
mkdir -p "$E2E_DIR/sys/fs/bpf/johnny_m1s2b"
touch "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m1_rxq" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m1_stats" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_cfg" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_ctl" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_rb" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_state" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/prog"

# Assertions on exact sums on evidence fixtures
# m2_ctl key0 seen = 164180+155070+220713+303884 = 843847; key2 = 407183; key4 = 436664; m1_stats key0 pkts = 843840
out_stats=$(run_sub dump_stats)
[ "$out_stats" = "pkts=843840 bytes=922600250" ] || fail "dump_stats failed on evidence fixture: got '$out_stats' want 'pkts=843840 bytes=922600250'"

out_ctl=$(run_sub ctl_rows)
expected_ctl=$(printf 'seen 843847\nsampled_out 0\nrate_limited 407183\nrb_full 0\nemitted 436664\ndiscarded 0')
[ "$out_ctl" = "$expected_ctl" ] || fail "ctl_rows failed on evidence fixture: got '$out_ctl'"

# Assertions on exact sums mentioned in prompt
[ "$(awk '$1=="seen"{print $2}' <<<"$out_ctl")" = "843847" ] || fail "ctl seen mismatch"
[ "$(awk '$1=="rate_limited"{print $2}' <<<"$out_ctl")" = "407183" ] || fail "ctl rate_limited mismatch"
[ "$(awk '$1=="emitted"{print $2}' <<<"$out_ctl")" = "436664" ] || fail "ctl emitted mismatch"
[ "$(awk -F'[ =]' '{print $2}' <<<"$out_stats")" = "843840" ] || fail "stats pkts mismatch"

out_cfg=$(run_sub cfg_line)
[ "$out_cfg" = "ver=1 sample_every=1 rate=8000 burst=16000" ] || fail "cfg_line failed on evidence fixture: got '$out_cfg'"

# Test 1: clean start
rm -f "$MOCK_DIR"/*
echo '[]' > "$MOCK_DIR/net_attach"
echo '[]' > "$MOCK_DIR/prog_show"
out=$(run_sub start 2>&1)
grep -q "M1S2B-START-DONE" <<<"$out" || fail "Scenario 1 failed: $out"

# Test 2: already attached (idempotent)
out=$(run_sub start 2>&1)
grep -q "ALREADY-ATTACHED" <<<"$out" || fail "Scenario 2 failed: $out"

# Test 3: observer attached -> refuse
echo '[{"xdp": [{"mode": "driver", "id": 100}]}]' > "$MOCK_DIR/net_attach"
echo '[{"id": 100, "name": "j_xdp_observe", "type": "xdp"}]' > "$MOCK_DIR/prog_show"
out=$(run_sub start 2>&1 || true)
grep -q "STOP-observer-attached-stop-first" <<<"$out" || fail "Scenario 3 failed: $out"

# Test 4: foreign program attached -> refuse
echo '[{"xdp": [{"mode": "driver", "id": 999}]}]' > "$MOCK_DIR/net_attach"
echo '[{"id": 999, "name": "foreign_prog", "type": "xdp"}]' > "$MOCK_DIR/prog_show"
out=$(run_sub start 2>&1 || true)
grep -q "STOP-xdp-foreign-attached" <<<"$out" || fail "Scenario 4 failed: $out"

# Test 5: stop when records attached
echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > "$MOCK_DIR/net_attach"
echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > "$MOCK_DIR/prog_show"
echo '{"id": 200, "name": "j_xdp_records"}' > "$MOCK_DIR/prog_pinned"
out=$(run_sub stop 2>&1)
grep -q "M1S2B-STOP-DONE" <<<"$out" || fail "Scenario 5 failed: $out"

# Test 6: stop when observer attached -> KEEP-observer
echo '[{"xdp": [{"mode": "driver", "id": 100}]}]' > "$MOCK_DIR/net_attach"
echo '[{"id": 100, "name": "j_xdp_observe", "type": "xdp"}]' > "$MOCK_DIR/prog_show"
out=$(run_sub stop 2>&1)
grep -q "KEEP-observer" <<<"$out" || fail "Scenario 6 failed: $out"

# Test 7: status output
echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > "$MOCK_DIR/net_attach"
echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > "$MOCK_DIR/prog_show"
echo '{"id": 200, "name": "j_xdp_records"}' > "$MOCK_DIR/prog_pinned"
mkdir -p "$E2E_DIR/sys/fs/bpf/johnny_m1s2b"
touch "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m1_rxq" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m1_stats" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_cfg" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_ctl" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_rb" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_state" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/prog"
out=$(run_sub status 2>&1)
grep -q "M1S2B-STATUS-DONE" <<<"$out" || fail "Scenario 7 failed: $out"

# Test 8: verify output and drops handling
rm -f "$MOCK_DIR"/ctl_drop_* "$MOCK_DIR/stats_delta"
out=$(run_sub verify 2>&1)
grep -q "VERIFY-DROPS rate_limited=0 rb_full=0 discarded=0" <<<"$out" || fail "Scenario 8 failed (clean verify drops): $out"
grep -q "M1S2B-VERIFY-DONE" <<<"$out" || fail "Scenario 8 failed (clean verify done): $out"

# Test 8b: verify STOPs on rate_limited delta > 0
rm -f "$MOCK_DIR"/ctl_drop_* "$MOCK_DIR/stats_delta"
touch "$MOCK_DIR/ctl_drop_rl_on_tcpdump"
out=$(run_sub verify 2>&1 || true)
grep -q "STOP-drops-in-verify-window rate_limited=5 rb_full=0 discarded=0" <<<"$out" || fail "Scenario 8b failed (rate_limited drop should stop): $out"
rm -f "$MOCK_DIR/ctl_drop_rl_on_tcpdump" "$MOCK_DIR/ctl_drop_rl" "$MOCK_DIR/stats_delta"

# Test 8c: verify STOPs on rb_full delta > 0
rm -f "$MOCK_DIR"/ctl_drop_* "$MOCK_DIR/stats_delta"
touch "$MOCK_DIR/ctl_drop_rb_on_tcpdump"
out=$(run_sub verify 2>&1 || true)
grep -q "STOP-drops-in-verify-window rate_limited=0 rb_full=3 discarded=0" <<<"$out" || fail "Scenario 8c failed (rb_full drop should stop): $out"
rm -f "$MOCK_DIR/ctl_drop_rb_on_tcpdump" "$MOCK_DIR/ctl_drop_rb" "$MOCK_DIR/stats_delta"

# Test 9: boot wait timeout
out=$(bash -c '
  source '"$E2E_DIR/test-helper.sh"'
  WAIT_BOOT_TRIES=1 WAIT_STEP=0
  eno1_ready_now() { return 1; }
  eno3_ok() { return 0; }
  systemctl() { echo "active"; }
  if wait_boot_ready; then echo FAIL; else echo TIMEOUT-OK; fi
')
grep -q "TIMEOUT-OK" <<<"$out" || fail "Scenario 9 failed: $out"

# Test 10: IRQ renumbering across boots (name and affinity unchanged, numbers change)
mkdir -p "$E2E_DIR/root/m1s2b"
cat > "$E2E_DIR/root/m1s2b/irq-baseline.txt" <<'EOF'
IRQ 100 ice-eno1np0-TxRx-0 1
IRQ 101 ice-eno1np0-TxRx-1 2
IRQ 102 ice-eno1np0-TxRx-2 3
IRQ 103 ice-eno1np0-TxRx-3 4
IRQ 104 ice-eno1np0-TxRx-4 1
IRQ 105 ice-eno1np0-TxRx-5 2
IRQ 106 ice-eno1np0-TxRx-6 3
IRQ 107 ice-eno1np0-TxRx-7 4
IRQ 108 ice-eno1np0-TxRx-8 1
IRQ 109 ice-eno1np0-TxRx-9 2
IRQ 110 ice-eno1np0-TxRx-10 3
IRQ 111 ice-eno1np0-TxRx-11 4
EOF
echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > "$MOCK_DIR/net_attach"
echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > "$MOCK_DIR/prog_show"
echo '{"id": 200, "name": "j_xdp_records"}' > "$MOCK_DIR/prog_pinned"
out=$(bash -c '
  source '"$E2E_DIR/test-helper.sh"'
  gate_host() { return 0; }
  need_files() { return 0; }
  eno3_ok() { return 0; }
  wait_boot_ready() { return 0; }
  eno1_ready_now() { return 0; }
  irq_snapshot() {
    for i in {0..11}; do
      echo "IRQ $((189 + i)) ice-eno1np0-TxRx-$i $(((i % 4) + 1))"
    done
  }
  irq_in_cores() { return 0; }
  verify_attached_invariants test-renumber
' 2>&1)
grep -q "OK-irq-pins-unchanged (test-renumber)" <<<"$out" || fail "Scenario 10 failed (renumber should pass): $out"

# Check that if affinity actually changes, verify_attached_invariants detects it and stops
out=$(bash -c '
  source '"$E2E_DIR/test-helper.sh"'
  gate_host() { return 0; }
  need_files() { return 0; }
  eno3_ok() { return 0; }
  wait_boot_ready() { return 0; }
  eno1_ready_now() { return 0; }
  irq_snapshot() {
    for i in {0..11}; do
      echo "IRQ $((189 + i)) ice-eno1np0-TxRx-$i 1"
    done
  }
  irq_in_cores() { return 0; }
  verify_attached_invariants test-bad-aff
' 2>&1 || true)
grep -q "STOP-irq-baseline-diff-test-bad-aff" <<<"$out" || fail "Scenario 10 failed (bad affinity should stop): $out"

# Test 11: Rollback verification (driver id 138 -> j_xdp_observe, 1c enabled/active, 2b disabled/inactive)
# Extract actual rollback fence from runbook, simulate outer single-quote parse via fake ssh,
# and run against fixtures requiring M1S2B-ROLLBACK-DONE
RB_FENCE=$(python3 -I - "$DOC" <<'PY'
import re, shlex, sys
text = open(sys.argv[1]).read()
m = re.search(r"\n## Rollback.*?\n```bash\n(.*?\n)```", text, re.DOTALL)
if not m:
    sys.stderr.write("Rollback fence not found\n")
    sys.exit(1)
sys.stdout.write(m.group(1))
PY
)
[ -n "$RB_FENCE" ] || fail "could not extract rollback fence from $DOC"

rm -f "$MOCK_DIR"/*
echo "xdp: eno1np0(4) driver id 138" > "$MOCK_DIR/net_show_text"
echo "j_xdp_observe" > "$MOCK_DIR/prog_id_name"
echo "enabled" > "$MOCK_DIR/c1_enabled"
echo "active" > "$MOCK_DIR/c1_state"
echo "disabled" > "$MOCK_DIR/2x_enabled"
echo "inactive" > "$MOCK_DIR/2x_state"
echo "disabled" > "$MOCK_DIR/2r_enabled"
echo "inactive" > "$MOCK_DIR/2r_state"

out=$(PATH="$E2E_DIR/bin:$PATH" bash -c "$RB_FENCE" 2>&1 || true)
grep -q "M1S2B-ROLLBACK-DONE" <<<"$out" || fail "Scenario 11 failed (clean rollback): $out"

# Unclean rollback should fail closed
echo "disabled" > "$MOCK_DIR/c1_enabled"
out=$(PATH="$E2E_DIR/bin:$PATH" bash -c "$RB_FENCE" 2>&1 || true)
grep -q "STOP-rollback-not-clean" <<<"$out" || fail "Scenario 11 failed (unclean rollback should fail): $out"

# Clean mock files
rm -f "$MOCK_DIR"/*

# Test 12: apply-cfg (happy path, baseline creation mode 0600, idempotency, and refuse when not attached)
rm -f "$E2E_DIR/root/m1s2b/no-ratecap-baseline.txt"
echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > "$MOCK_DIR/net_attach"
echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > "$MOCK_DIR/prog_show"
echo '{"id": 200, "name": "j_xdp_records"}' > "$MOCK_DIR/prog_pinned"
mkdir -p "$E2E_DIR/sys/fs/bpf/johnny_m1s2b"
touch "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m1_rxq" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m1_stats" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_cfg" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_ctl" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_rb" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_state" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/prog"
out=$(run_sub apply-cfg 2>&1)
grep -q "M1S2B-APPLY-CFG-DONE" <<<"$out" || fail "Scenario 12 failed (apply-cfg): $out"
[ -f "$E2E_DIR/root/m1s2b/no-ratecap-baseline.txt" ] || fail "Scenario 12 failed (baseline missing)"
grep -q "DATE-UTC" "$E2E_DIR/root/m1s2b/no-ratecap-baseline.txt" || fail "Scenario 12 failed (baseline missing DATE-UTC)"
grep -q "boot_id" "$E2E_DIR/root/m1s2b/no-ratecap-baseline.txt" || fail "Scenario 12 failed (baseline missing boot_id)"
grep -q "STATS" "$E2E_DIR/root/m1s2b/no-ratecap-baseline.txt" || fail "Scenario 12 failed (baseline missing STATS)"
grep -q "CTL seen" "$E2E_DIR/root/m1s2b/no-ratecap-baseline.txt" || fail "Scenario 12 failed (baseline missing CTL seen)"
base_mode=$(stat -c '%a' "$E2E_DIR/root/m1s2b/no-ratecap-baseline.txt")
[ "$base_mode" = "600" ] || fail "Scenario 12 failed (baseline mode got $base_mode want 600)"

# Idempotency: re-running with cfg already set prints BASELINE-EXISTS and doesn't rewrite
out2=$(run_sub apply-cfg 2>&1)
grep -q "BASELINE-EXISTS" <<<"$out2" || fail "Scenario 12 failed (apply-cfg idempotency): $out2"
grep -q "M1S2B-APPLY-CFG-DONE" <<<"$out2" || fail "Scenario 12 failed (apply-cfg idempotency done): $out2"

# Refuses when not attached
echo '[]' > "$MOCK_DIR/net_attach"
out3=$(run_sub apply-cfg 2>&1 || true)
grep -q "STOP-not-records-attached" <<<"$out3" || fail "Scenario 12 failed (apply-cfg not attached should stop): $out3"

# Test 13: window (zero deltas passes, stops on rate_limited>0, rb_full>0, discarded>0)
echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > "$MOCK_DIR/net_attach"
echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > "$MOCK_DIR/prog_show"
echo '{"id": 200, "name": "j_xdp_records"}' > "$MOCK_DIR/prog_pinned"
rm -f "$MOCK_DIR"/ctl_drop_*
out=$(run_sub window 10 2>&1)
grep -q "WINDOW secs=10 seen-delta=.* rate_limited-delta=0 rb_full-delta=0 discarded-delta=0" <<<"$out" || fail "Scenario 13 failed (window zero deltas): $out"
grep -q "OK-no-drops-window" <<<"$out" || fail "Scenario 13 failed (window no drops): $out"
grep -q "M1S2B-WINDOW-DONE" <<<"$out" || fail "Scenario 13 failed (window done): $out"

# Window STOPs on rate_limited > 0
out_rl=$(bash -c '
  source '"$E2E_DIR/test-helper.sh"'
  gate_host() { return 0; }
  need_tools() { return 0; }
  sleep() { touch "'"$MOCK_DIR"'/ctl_drop_rl"; }
  do_window 10
' 2>&1 || true)
grep -q "STOP-drops-in-window rate_limited=5 rb_full=0 discarded=0" <<<"$out_rl" || fail "Scenario 13 failed (window rate_limited drop should stop): $out_rl"
rm -f "$MOCK_DIR/ctl_drop_rl"

# Window STOPs on rb_full > 0
out_rb=$(bash -c '
  source '"$E2E_DIR/test-helper.sh"'
  gate_host() { return 0; }
  need_tools() { return 0; }
  sleep() { touch "'"$MOCK_DIR"'/ctl_drop_rb"; }
  do_window 10
' 2>&1 || true)
grep -q "STOP-drops-in-window rate_limited=0 rb_full=3 discarded=0" <<<"$out_rb" || fail "Scenario 13 failed (window rb_full drop should stop): $out_rb"
rm -f "$MOCK_DIR/ctl_drop_rb"

# Window STOPs on discarded > 0
out_disc=$(bash -c '
  source '"$E2E_DIR/test-helper.sh"'
  gate_host() { return 0; }
  need_tools() { return 0; }
  sleep() { touch "'"$MOCK_DIR"'/ctl_drop_disc"; }
  do_window 10
' 2>&1 || true)
grep -q "STOP-drops-in-window rate_limited=0 rb_full=0 discarded=2" <<<"$out_disc" || fail "Scenario 13 failed (window discarded drop should stop): $out_disc"
rm -f "$MOCK_DIR/ctl_drop_disc"

# Clean mock files
rm -f "$MOCK_DIR"/*

echo "E2E-OK scenarios=13"

# ---------------------------------------------------------------- 6. runbook validation

[ -f "$DOC" ] || fail "missing runbook $DOC"
python3 -I - "$DOC" "$WANT_OBJ_SHA" "$WANT_BOOT_SHA" "$WANT_UNIT_SHA" "$WANT_READER_SHA" "$WANT_RUNIT_SHA" \
  "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55" \
  "fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573" \
  "5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c" \
  "0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f" <<'PY'
import re, shlex, sys
doc_path, obj, boot_new, unit, rdr_new, runit_new, boot_live, rdr_live, runit_live, boot_ret = sys.argv[1:11]
text = open(doc_path).read()
lines = text.splitlines()

blocks = []
label = None
curr_section = None
i = 0
while i < len(lines):
    s = lines[i].strip()
    if s.startswith("## "):
        curr_section = s[3:].strip()
    elif s.startswith("***<u>Run on Rock Box</u>***"):
        label = "rock"
    elif s.startswith("```"):
        lang = s[3:]
        j = i + 1
        body = []
        while j < len(lines) and not lines[j].startswith("```"):
            body.append(lines[j])
            j += 1
        if lang == "bash":
            blocks.append((label, curr_section, "\n".join(body)))
        label = None
        i = j
    i += 1

def die(msg):
    sys.stderr.write("RUNBOOK-FAIL: " + msg + "\n")
    sys.exit(1)

new_draft_hashes = {
    boot_new,
    "ea799ee6a42e08dec3d15b1c8c7f9dad28ab81e73fda6a6ee5d9c7956873ab3f",
    "e986073148d5bb617c1f8608034fe8a0bf787ea9620595e03c41ce5924e01903",
}
live_hashes = {
    "module1-xdp-records.o": obj,
    "module1-slice2b-boot.sh": boot_live,
    "johnny-capture-xdp-records.service": unit,
    "johnny-m1s2b-reader.py": rdr_live,
    "johnny-m1s2b-reader.service": runit_live,
}
r3_prev_installed = {
    "module1-slice2b-boot.sh": "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2",
    "johnny-m1s2b-reader.py": "e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581",
}

def outside_single_quotes(body):
    inq = False
    for ln in body.split("\n"):
        out = []
        for ch in ln:
            if ch == "'":
                inq = not inq
            elif not inq:
                out.append(ch)
        yield "".join(out)

tokens = [
    "SELF-TEST-OK", "M1S2B-COPY-DONE", "M1S2B-PROBE-DONE", "M1S2B-INSTALL-DONE",
    "M1S2B-CUTOVER-DONE", "M1S2B-VERIFY-DONE", "M1S2B-REBOOT-ISSUED",
    "M1S2B-COLD-BOOT-VERIFY-DONE",
    "SELF-TEST-OK", "M1S2B-FIX-COPY-DONE", "M1S2B-FIX-INSTALL-DONE",
    "M1S2B-VERIFY-DONE",
    "M1S2B-RET-PREFLIGHT-DONE", "M1S2B-RET-APPLY-DONE", "M1S2B-RET-VERIFY-DONE",
    "M1S2B-RET-ROLLBACK-DONE",
    "M1S2B-NORC-PREFLIGHT-DONE", "M1S2B-NORC-APPLY-DONE", "M1S2B-NORC-VERIFY-DONE",
    "M1S2B-NORC-WEEK-DONE", "M1S2B-NORC-ROLLBACK-DONE",
    "M1S2B-ROLLBACK-DONE"
]

seen = []
for idx, (lab, sec, body) in enumerate(blocks, 1):
    if lab != "rock":
        die(f"bash block #{idx} not preceded by ***<u>Run on Rock Box</u>***")
    if re.search(r"<[A-Za-z_][^>\n]*>", body):
        die(f"placeholder in block #{idx}")
    for s in outside_single_quotes(body):
        if re.search(r"(^|[;&|(])\s*sudo\b", s.strip()):
            die(f"sudo outside ssh -t single quotes in block #{idx}: {s}")
    if "sudo" in body:
        if "ssh -t aj@192.168.50.152 'sudo -v &&\n" not in body:
            die(f"block #{idx}: a sudo paste must contain ssh -t aj@192.168.50.152 'sudo -v &&")
        if not body.rstrip().endswith("'"):
            die(f"block #{idx}: sudo paste must end with a single quote closing ssh")
    if "ssh" in body and "192.168.50.152" not in body:
        die(f"block #{idx}: ssh to an unexpected host")

    # Audit all ssh commands in any block for nested quotes breaking the remote command argument
    stoks = shlex.split(body)
    for k, tok in enumerate(stoks):
        if tok == "ssh":
            h_idx = -1
            for m in range(k + 1, len(stoks)):
                if stoks[m].startswith("-"):
                    continue
                if "@" in stoks[m] or "192.168." in stoks[m]:
                    h_idx = m
                    break
            if h_idx < 0:
                die(f"block #{idx}: ssh without destination host")
            end_idx = len(stoks)
            for m in range(h_idx + 1, len(stoks)):
                if stoks[m] in ("&&", ";", "||", "|"):
                    end_idx = m
                    break
            remote_args = stoks[h_idx + 1:end_idx]
            if len(remote_args) != 1:
                die(f"block #{idx}: ssh call at token {k} has {len(remote_args)} remote args instead of 1 single-quoted command string (nested quotes broke the argument): {remote_args[:3]}")

    block_token = None
    for t in set(tokens):
        if re.search(r"echo " + re.escape(t) + r"\b", body) or (t == "SELF-TEST-OK" and "module1-slice2b-self-test.sh" in body):
            block_token = t
            break
    if block_token:
        seen.append(block_token)
    else:
        die(f"block #{idx} did not emit any expected token")

    is_retention = sec and sec.startswith("Retention raise")
    is_norc = sec and sec.startswith("Rate cap removal")
    if not is_retention and not is_norc:
        # Every block outside the retention section must contain only the live (old) hashes
        # and must FAIL if it contains ea799ee6…, 476cf867… or e9860731…
        for dh in new_draft_hashes:
            if dh in body:
                die(f"block #{idx} outside retention section contains unapplied draft hash: {dh}")
        for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
            name = path.rsplit("/", 1)[-1]
            if name in live_hashes:
                if h != live_hashes[name]:
                    if block_token == "M1S2B-FIX-INSTALL-DONE" and h == r3_prev_installed.get(name):
                        pass
                    else:
                        die(f"block #{idx}: wrong hash for {name}: {h} (expected live {live_hashes[name]})")
    elif is_retention:
        # Blocks in the retention section:
        # Carry new hashes as post-install/copy gates and old ones as pre-install/rollback gates
        if boot_new in body:
            die(f"block #{idx} (retention section) contains rate-cap draft hash: {boot_new}")
        if block_token == "M1S2B-RET-PREFLIGHT-DONE":
            for dh in new_draft_hashes:
                if dh in body:
                    die(f"block #{idx} (Paste A) contains new draft hash before apply: {dh}")
            for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
                name = path.rsplit("/", 1)[-1]
                if name in live_hashes and h != live_hashes[name]:
                    die(f"block #{idx} (Paste A): wrong preflight hash for {name}: {h}")
        elif block_token == "M1S2B-RET-APPLY-DONE":
            pairs = re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body)
            expected_pairs = [
                (boot_ret, "module1-slice2b-boot.sh"),
                (rdr_new, "johnny-m1s2b-reader.py"),
                (runit_new, "johnny-m1s2b-reader.service"),
                (boot_live, "/root/m1s2b/module1-slice2b-boot.sh"),
                (rdr_live, "/usr/local/libexec/johnny/johnny-m1s2b-reader.py"),
                (runit_live, "/etc/systemd/system/johnny-m1s2b-reader.service"),
                (boot_ret, "/root/m1s2b/module1-slice2b-boot.sh"),
                (rdr_new, "/usr/local/libexec/johnny/johnny-m1s2b-reader.py"),
                (runit_new, "/etc/systemd/system/johnny-m1s2b-reader.service"),
            ]
            if pairs != expected_pairs:
                die(f"block #{idx} (Paste B): sha256 gates mismatch: got {pairs} want {expected_pairs}")
        elif block_token == "M1S2B-RET-VERIFY-DONE":
            if 'grep -q -- "MemoryMax=1073741824"' not in body:
                die(f"block #{idx} (Paste C): missing MemoryMax=1073741824 grep")
            for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
                name = path.rsplit("/", 1)[-1]
                if name == "module1-slice2b-boot.sh" and h != boot_ret:
                    die(f"block #{idx} (Paste C): wrong post-install hash for {name}: {h}")
        elif block_token == "M1S2B-RET-ROLLBACK-DONE":
            for dh in new_draft_hashes:
                if dh in body:
                    die(f"block #{idx} (retention rollback) contains new draft hash: {dh}")
            for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
                name = path.rsplit("/", 1)[-1]
                if name in live_hashes and h != live_hashes[name]:
                    die(f"block #{idx} (retention rollback): wrong restore hash for {name}: {h}")
    else:
        # Blocks in Rate cap removal section (is_norc)
        if block_token == "M1S2B-NORC-PREFLIGHT-DONE":
            if boot_new in body:
                die(f"block #{idx} (Rate cap Paste A) contains new draft hash before apply: {boot_new}")
            pairs = re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body)
            expected_pairs = [
                (boot_ret, "/root/m1s2b/module1-slice2b-boot.sh"),
                (rdr_new, "/usr/local/libexec/johnny/johnny-m1s2b-reader.py"),
                (runit_new, "/etc/systemd/system/johnny-m1s2b-reader.service"),
                (unit, "/etc/systemd/system/johnny-capture-xdp-records.service"),
                (obj, "/root/m1s2b/module1-xdp-records.o"),
            ]
            if pairs != expected_pairs:
                die(f"block #{idx} (Rate cap Paste A): live five hash mismatch: got {pairs} want {expected_pairs}")
            if 'grep -q "^CFG ver=1 sample_every=1 rate=8000 burst=16000$"' not in body:
                die(f"block #{idx} (Rate cap Paste A): missing old CFG grep")
        elif block_token == "M1S2B-NORC-APPLY-DONE":
            pairs = re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body)
            expected_pairs = [
                (boot_new, "module1-slice2b-boot.sh"),
                (boot_ret, "/root/m1s2b/module1-slice2b-boot.sh"),
                (rdr_new, "/usr/local/libexec/johnny/johnny-m1s2b-reader.py"),
                (runit_new, "/etc/systemd/system/johnny-m1s2b-reader.service"),
                (unit, "/etc/systemd/system/johnny-capture-xdp-records.service"),
                (obj, "/root/m1s2b/module1-xdp-records.o"),
                (boot_new, "/root/m1s2b/module1-slice2b-boot.sh"),
            ]
            if pairs != expected_pairs:
                die(f"block #{idx} (Rate cap Paste B): sha256 gates mismatch: got {pairs} want {expected_pairs}")
            if "apply-cfg" not in body:
                die(f"block #{idx} (Rate cap Paste B): missing apply-cfg call")
            if "restart johnny-m1s2b-reader.service" not in body:
                die(f"block #{idx} (Rate cap Paste B): missing reader service restart")
            if "restart johnny-capture-xdp-records.service" in body:
                die(f"block #{idx} (Rate cap Paste B): XDP unit must not be restarted")
            if 'grep -q "^CFG ver=1 sample_every=1 rate=1000000 burst=100000$"' not in body:
                die(f"block #{idx} (Rate cap Paste B): missing new CFG grep")
        elif block_token == "M1S2B-NORC-VERIFY-DONE":
            for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
                name = path.rsplit("/", 1)[-1]
                if name == "module1-slice2b-boot.sh" and h != boot_new:
                    die(f"block #{idx} (Rate cap Paste C): wrong post-install hash for {name}: {h}")
            if "boot.sh verify" not in body:
                die(f"block #{idx} (Rate cap Paste C): missing boot.sh verify call")
            if "boot.sh window 60" not in body:
                die(f"block #{idx} (Rate cap Paste C): missing boot.sh window 60 call")
            if 'grep -q "^CFG ver=1 sample_every=1 rate=1000000 burst=100000$"' not in body:
                die(f"block #{idx} (Rate cap Paste C): missing new CFG grep")
            if 'grep -q -- "cfg=ver:1,every:1,rate:1000000,burst:100000"' not in body:
                die(f"block #{idx} (Rate cap Paste C): missing reader journal cfg verification")
        elif block_token == "M1S2B-NORC-WEEK-DONE":
            if "BOOT-SAME" not in body:
                die(f"block #{idx} (Rate cap Paste W): missing BOOT-SAME check")
            if "CTL-DELTAS" not in body:
                die(f"block #{idx} (Rate cap Paste W): missing CTL-DELTAS check")
            if "STOP-drops-since-baseline" not in body:
                die(f"block #{idx} (Rate cap Paste W): missing STOP-drops-since-baseline check")
            if "COVERAGE" not in body:
                die(f"block #{idx} (Rate cap Paste W): missing COVERAGE check")
            if "STOP-coverage-short" not in body:
                die(f"block #{idx} (Rate cap Paste W): missing STOP-coverage-short check")
            if "STOP-gap-detected" not in body:
                die(f"block #{idx} (Rate cap Paste W): missing STOP-gap-detected check")
        elif block_token == "M1S2B-NORC-ROLLBACK-DONE":
            for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
                name = path.rsplit("/", 1)[-1]
                if name == "module1-slice2b-boot.sh" and h != boot_ret:
                    die(f"block #{idx} (Rate cap rollback): wrong restore hash for {name}: {h}")
            if "bpftool map update pinned /sys/fs/bpf/johnny_m1s2b/m2_cfg key hex 00 00 00 00 value hex 01 00 00 00 01 00 00 00 40 1f 00 00 80 3e 00 00" not in body:
                die(f"block #{idx} (Rate cap rollback): missing old cfg bpftool map update")
            if 'grep -q "^CFG ver=1 sample_every=1 rate=8000 burst=16000$"' not in body:
                die(f"block #{idx} (Rate cap rollback): missing old CFG grep")

if seen != tokens:
    die(f"paste order/tokens: got {seen} want {tokens}")

rb = text.find("## Rollback")
if rb < 0 or "not part of the paste sequence" not in text[rb:rb + 400]:
    die("rollback section must say it is not part of the paste sequence")

print(f"RUNBOOK-OK blocks={len(blocks)}")
PY

echo SELF-TEST-OK
