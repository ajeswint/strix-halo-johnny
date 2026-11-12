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
WANT_BOOT_SHA="650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2"
WANT_UNIT_SHA="4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a"
WANT_READER_SHA="e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581"
WANT_RUNIT_SHA="5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c"
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
python3 -m py_compile "$READER" || fail "python compile failed on $READER"
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
        pass
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
    mod.read_ctl = lambda bpf, fd, ncpu: (10, 0, 0, 0, 10, 0)
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
    shutil.rmtree(tmpdir)

print("READER-TESTS-PASSED")
PY
echo READER-TESTS-OK

# ---------------------------------------------------------------- 5. E2E simulated scenarios

E2E_DIR=$(mktemp -d /tmp/m1s2b-e2e.XXXXXX)
trap 'rm -rf "$E2E_DIR"' EXIT

mkdir -p "$E2E_DIR/bin" "$E2E_DIR/root/m1s2b" "$E2E_DIR/etc/johnny" "$E2E_DIR/etc/systemd/system" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b" "$E2E_DIR/var/lib/johnny/m1s2b" "$E2E_DIR/proc/irq" "$E2E_DIR/sysfs/net/eno1np0"

# Copy deployables into fake root
cp "$OBJ" "$E2E_DIR/root/m1s2b/module1-xdp-records.o"
cp "$READER" "$E2E_DIR/bin/johnny-m1s2b-reader.py"
chmod 0644 "$E2E_DIR/bin/johnny-m1s2b-reader.py"
cp "$UNIT" "$E2E_DIR/etc/systemd/system/johnny-capture-xdp-records.service"
cp "$RUNIT" "$E2E_DIR/etc/systemd/system/johnny-m1s2b-reader.service"
cp "$CORES" "$E2E_DIR/etc/johnny/capture-cores"
cp "$IRQ_HELPER" "$E2E_DIR/etc/johnny/irq-affinity.sh"
chmod 0755 "$E2E_DIR/etc/johnny/irq-affinity.sh"

# Mock system commands
cat > "$E2E_DIR/bin/systemctl" <<'EOF'
#!/bin/bash
case "$*" in
  *"is-enabled suricata"*) echo "disabled"; exit 0 ;;
  *"is-active suricata"*) echo "inactive"; exit 0 ;;
  *"is-active johnny-capture-irq.service"*) echo "active"; exit 0 ;;
  *"is-active johnny-capture-tuning.service"*) echo "active"; exit 0 ;;
  *"is-enabled johnny-capture-xdp.service"*) cat /tmp/mock_c1_enabled 2>/dev/null || echo "disabled"; exit 0 ;;
  *"is-active johnny-capture-xdp.service"*) cat /tmp/mock_c1_state 2>/dev/null || echo "inactive"; exit 0 ;;
  *"is-enabled johnny-capture-xdp-records.service"*) cat /tmp/mock_2x_enabled 2>/dev/null || echo "enabled"; exit 0 ;;
  *"is-active johnny-capture-xdp-records.service"*) cat /tmp/mock_2x_state 2>/dev/null || echo "active"; exit 0 ;;
  *"is-enabled johnny-m1s2b-reader.service"*) cat /tmp/mock_2r_enabled 2>/dev/null || echo "enabled"; exit 0 ;;
  *"is-active johnny-m1s2b-reader.service"*) cat /tmp/mock_2r_state 2>/dev/null || echo "active"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$E2E_DIR/bin/systemctl"

cat > "$E2E_DIR/bin/bpftool" <<'EOF'
#!/bin/bash
case "$*" in
  *"-j net show dev eno1np0"*)
    cat /tmp/mock_net_attach 2>/dev/null || echo '[]'
    exit 0
    ;;
  *"net show dev eno1np0"*)
    cat /tmp/mock_net_show_text 2>/dev/null || echo "xdp: eno1np0(4) driver id 138"
    exit 0
    ;;
  *"prog show id "*)
    id=$(echo "$*" | awk '{for(i=1;i<=NF;i++) if($i=="id") print $(i+1)}')
    pname=$(cat /tmp/mock_prog_id_name 2>/dev/null || echo "j_xdp_observe")
    echo "$id: xdp  name $pname  tag b5b852630d7539c7  gpl"
    exit 0
    ;;
  *"-j prog show pinned"*)
    cat /tmp/mock_prog_pinned 2>/dev/null || echo '{"id": 200, "name": "j_xdp_records"}'
    exit 0
    ;;
  *"-j prog show"*)
    cat /tmp/mock_prog_show 2>/dev/null || echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]'
    exit 0
    ;;
  *"prog load"*)
    pdir="${6:-/tmp/mock_pins}"
    mkdir -p "$pdir"
    touch "$pdir/m1_rxq" "$pdir/m1_stats" "$pdir/m2_cfg" "$pdir/m2_ctl" "$pdir/m2_rb" "$pdir/m2_state" "$pdir/prog"
    echo '{"id": 200, "name": "j_xdp_records"}' > /tmp/mock_prog_pinned
    echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > /tmp/mock_prog_show
    exit 0
    ;;
  *"map update pinned"*"m2_cfg"*)
    echo "ver=1 sample_every=1 rate=8000 burst=16000" > /tmp/mock_cfg_val
    exit 0
    ;;
  *"-j map dump pinned"*"m2_cfg"*)
    echo '[{"key": 0, "value": {"ver": 1, "sample_every": 1, "rate": 8000, "burst": 16000}}]'
    exit 0
    ;;
  *"-j map dump pinned"*"m2_ctl"*)
    echo '[{"key": 0, "formatted": {"values": [{"cpu": 0, "value": {"seen": 100, "sampled_out": 0, "rate_limited": 0, "rb_full": 0, "emitted": 100, "discarded": 0}}]}}]'
    exit 0
    ;;
  *"-j map dump pinned"*"m1_stats"*)
    pkts=$(cat /tmp/mock_pkts 2>/dev/null || echo 500)
    echo $((pkts + 50)) > /tmp/mock_pkts
    echo '[{"key": 0, "formatted": {"value": {"packets": '$pkts', "bytes": 40000}}}]'
    exit 0
    ;;
  *"net attach xdpdrv"*)
    echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > /tmp/mock_net_attach
    exit 0
    ;;
  *"net detach"*)
    echo '[]' > /tmp/mock_net_attach
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

cat > "$E2E_DIR/bin/tcpdump" <<'EOF'
#!/bin/bash
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
    do_'"$1"
}

# Test 1: clean start
rm -f /tmp/mock_*
echo '[]' > /tmp/mock_net_attach
echo '[]' > /tmp/mock_prog_show
out=$(run_sub start 2>&1)
grep -q "M1S2B-START-DONE" <<<"$out" || fail "Scenario 1 failed: $out"

# Test 2: already attached (idempotent)
out=$(run_sub start 2>&1)
grep -q "ALREADY-ATTACHED" <<<"$out" || fail "Scenario 2 failed: $out"

# Test 3: observer attached -> refuse
echo '[{"xdp": [{"mode": "driver", "id": 100}]}]' > /tmp/mock_net_attach
echo '[{"id": 100, "name": "j_xdp_observe", "type": "xdp"}]' > /tmp/mock_prog_show
out=$(run_sub start 2>&1 || true)
grep -q "STOP-observer-attached-stop-first" <<<"$out" || fail "Scenario 3 failed: $out"

# Test 4: foreign program attached -> refuse
echo '[{"xdp": [{"mode": "driver", "id": 999}]}]' > /tmp/mock_net_attach
echo '[{"id": 999, "name": "foreign_prog", "type": "xdp"}]' > /tmp/mock_prog_show
out=$(run_sub start 2>&1 || true)
grep -q "STOP-xdp-foreign-attached" <<<"$out" || fail "Scenario 4 failed: $out"

# Test 5: stop when records attached
echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > /tmp/mock_net_attach
echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > /tmp/mock_prog_show
echo '{"id": 200, "name": "j_xdp_records"}' > /tmp/mock_prog_pinned
out=$(run_sub stop 2>&1)
grep -q "M1S2B-STOP-DONE" <<<"$out" || fail "Scenario 5 failed: $out"

# Test 6: stop when observer attached -> KEEP-observer
echo '[{"xdp": [{"mode": "driver", "id": 100}]}]' > /tmp/mock_net_attach
echo '[{"id": 100, "name": "j_xdp_observe", "type": "xdp"}]' > /tmp/mock_prog_show
out=$(run_sub stop 2>&1)
grep -q "KEEP-observer" <<<"$out" || fail "Scenario 6 failed: $out"

# Test 7: status output
echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > /tmp/mock_net_attach
echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > /tmp/mock_prog_show
echo '{"id": 200, "name": "j_xdp_records"}' > /tmp/mock_prog_pinned
mkdir -p "$E2E_DIR/sys/fs/bpf/johnny_m1s2b"
touch "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m1_rxq" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m1_stats" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_cfg" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_ctl" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_rb" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/m2_state" "$E2E_DIR/sys/fs/bpf/johnny_m1s2b/prog"
out=$(run_sub status 2>&1)
grep -q "M1S2B-STATUS-DONE" <<<"$out" || fail "Scenario 7 failed: $out"

# Test 8: verify output
out=$(run_sub verify 2>&1)
grep -q "M1S2B-VERIFY-DONE" <<<"$out" || fail "Scenario 8 failed: $out"

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
echo '[{"xdp": [{"mode": "driver", "id": 200}]}]' > /tmp/mock_net_attach
echo '[{"id": 200, "name": "j_xdp_records", "type": "xdp"}]' > /tmp/mock_prog_show
echo '{"id": 200, "name": "j_xdp_records"}' > /tmp/mock_prog_pinned
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
m = re.search(r"## Rollback.*?\n```bash\n(.*?\n)```", text, re.DOTALL)
if not m:
    sys.stderr.write("Rollback fence not found\n")
    sys.exit(1)
sys.stdout.write(m.group(1))
PY
)
[ -n "$RB_FENCE" ] || fail "could not extract rollback fence from $DOC"

rm -f /tmp/mock_*
echo "xdp: eno1np0(4) driver id 138" > /tmp/mock_net_show_text
echo "j_xdp_observe" > /tmp/mock_prog_id_name
echo "enabled" > /tmp/mock_c1_enabled
echo "active" > /tmp/mock_c1_state
echo "disabled" > /tmp/mock_2x_enabled
echo "inactive" > /tmp/mock_2x_state
echo "disabled" > /tmp/mock_2r_enabled
echo "inactive" > /tmp/mock_2r_state

out=$(PATH="$E2E_DIR/bin:$PATH" bash -c "$RB_FENCE" 2>&1 || true)
grep -q "M1S2B-ROLLBACK-DONE" <<<"$out" || fail "Scenario 11 failed (clean rollback): $out"

# Unclean rollback should fail closed
echo "disabled" > /tmp/mock_c1_enabled
out=$(PATH="$E2E_DIR/bin:$PATH" bash -c "$RB_FENCE" 2>&1 || true)
grep -q "STOP-rollback-not-clean" <<<"$out" || fail "Scenario 11 failed (unclean rollback should fail): $out"

# Clean mock files
rm -f /tmp/mock_*

echo "E2E-OK scenarios=11"

# ---------------------------------------------------------------- 6. runbook validation

[ -f "$DOC" ] || fail "missing runbook $DOC"
python3 -I - "$DOC" "$WANT_OBJ_SHA" "$WANT_BOOT_SHA" "$WANT_UNIT_SHA" "$WANT_READER_SHA" "$WANT_RUNIT_SHA" <<'PY'
import re, shlex, sys
doc_path, obj, boot, unit, rdr, runit = sys.argv[1:7]
text = open(doc_path).read()
lines = text.splitlines()

blocks = []
label = None
i = 0
while i < len(lines):
    s = lines[i].strip()
    if s.startswith("***<u>Run on Rock Box</u>***"):
        label = "rock"
    elif s.startswith("```"):
        lang = s[3:]
        j = i + 1
        body = []
        while j < len(lines) and not lines[j].startswith("```"):
            body.append(lines[j])
            j += 1
        if lang == "bash":
            blocks.append((label, "\n".join(body)))
        label = None
        i = j
    i += 1

def die(msg):
    sys.stderr.write("RUNBOOK-FAIL: " + msg + "\n")
    sys.exit(1)

want = {
    "module1-xdp-records.o": obj,
    "module1-slice2b-boot.sh": boot,
    "johnny-capture-xdp-records.service": unit,
    "johnny-m1s2b-reader.py": rdr,
    "johnny-m1s2b-reader.service": runit,
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
    "M1S2B-COLD-BOOT-VERIFY-DONE", "M1S2B-ROLLBACK-DONE"
]

seen = []
for idx, (lab, body) in enumerate(blocks, 1):
    if lab != "rock":
        die(f"bash block #{idx} not preceded by ***<u>Run on Rock Box</u>***")
    if re.search(r"<[A-Za-z_][^>\n]*>", body):
        die(f"placeholder in block #{idx}")
    for s in outside_single_quotes(body):
        if re.search(r"(^|[;&|(])\s*sudo\b", s.strip()):
            die(f"sudo outside ssh -t single quotes in block #{idx}: {s}")
    if "sudo" in body:
        if not body.startswith("ssh -t aj@192.168.50.152 'sudo -v &&\n"):
            die(f"block #{idx}: a sudo paste must start ssh -t aj@192.168.50.152 'sudo -v &&")
        if body.count("ssh ") != 1:
            die(f"block #{idx}: one ssh -t per sudo paste")
        if not body.rstrip().endswith("'"):
            die(f"block #{idx}: sudo paste must end with a single quote closing ssh")
        if body.count("'") != 2:
            die(f"block #{idx}: nested single quotes in ssh -t argument (found {body.count(chr(39))} single quotes, expected 2)")
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
    for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
        name = path.rsplit("/", 1)[-1]
        if name in want and want[name] != h:
            die(f"block #{idx}: wrong hash for {name}: {h}")
    for t in tokens:
        hit = re.search(r"echo " + re.escape(t) + r"\b", body) or (t == "SELF-TEST-OK" and "module1-slice2b-self-test.sh" in body)
        if hit:
            seen.append(t)

if seen != tokens:
    die(f"paste order/tokens: got {seen} want {tokens}")

rb = text.find("## Rollback")
if rb < 0 or "not part of the paste sequence" not in text[rb:rb + 400]:
    die("rollback section must say it is not part of the paste sequence")

print(f"RUNBOOK-OK blocks={len(blocks)}")
PY

echo SELF-TEST-OK
