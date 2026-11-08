#!/bin/bash
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2317
# Local rock-box self-test for Module 1 slice 2 (j_xdp_records, ring buffer
# reader, records helper). Runs on rock-box WITHOUT root, loads no BPF program,
# touches no NIC and never contacts Johnny.
#
#   bash docs/tool-install/module1-slice2-self-test.sh
#
# Prints SELF-TEST-OK, or SELF-TEST-FAIL <why> / RUNBOOK-FAIL <why> and exits 1.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
TI=$ROOT/docs/tool-install
OBJ=$TI/module1-xdp-records.o
SRC=$TI/module1_xdp_records.c
OBS_SRC=$TI/module1_xdp_observe.c
READER=$TI/johnny-m1s2-reader.py
UNIT=$ROOT/etc/systemd/system/johnny-m1s2-reader.service
REC=$TI/module1-slice2-records.sh
HOST_TEST=$TI/module1-slice2-host-test.c
READER_TEST=$TI/module1-slice2-reader-test.py
LIB=$TI/module1-slice1b-detach.sh
C1_BOOT=$TI/module1-slice1c-boot.sh
C1_UNIT=$ROOT/etc/systemd/system/johnny-capture-xdp.service
CORES=$ROOT/etc/johnny/capture-cores
DOC=$TI/module1-slice2-ringbuf.md
SELF=$TI/module1-slice2-self-test.sh

WANT_OBJ_SHA=451247d8409396f35bf4454bfa8b44f2bc73b2197f97bb7c41818a9709f780e2
WANT_SRC_SHA=ac446e262ad151223784e8a17f41f70e198b25b8511bab73dfd4076f4286f760
WANT_READER_SHA=32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2
WANT_UNIT_SHA=267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52
WANT_REC_SHA=889cb3dbd32cce129fff6cc0d679bca29aab777a5f613d17611e3a9904eb1c83
WANT_HOST_TEST_SHA=f80fb7eea3ceac2e5bf22bb39a561c6e97969df6fc326d7a4a5786f773764f56
WANT_READER_TEST_SHA=3ebfc1970fe66b4b78bbabd0af1aa485a42a60fb65e7c6259ee7e145a304f63a
WANT_LIB_SHA=f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58
WANT_C1_BOOT_SHA=a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06
WANT_C1_UNIT_SHA=2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0
WANT_CORES_SHA=16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "SELF-TEST-FAIL $*" >&2
  exit 1
}

expect_eq() {
  [ "$2" = "$3" ] || fail "$1: got [$2] want [$3]"
}

has() {
  case "$2" in
    *"$3"*) ;;
    *) fail "$1: missing [$3]" ;;
  esac
}

lacks() {
  case "$2" in
    *"$3"*) fail "$1: unexpected [$3]" ;;
  esac
}

sha_of() { sha256sum "$1" | awk '{print $1}'; }
code_of() { sed -E '/^[[:space:]]*#/d' "$1"; }
var_of() { sed -nE "s/^$2=//p" "$1" | head -n 1; }

# ---------------------------------------------------------------- 1. pins

expect_eq "object sha" "$(sha_of "$OBJ")" "$WANT_OBJ_SHA"
expect_eq "source sha" "$(sha_of "$SRC")" "$WANT_SRC_SHA"
expect_eq "reader sha" "$(sha_of "$READER")" "$WANT_READER_SHA"
expect_eq "reader unit sha" "$(sha_of "$UNIT")" "$WANT_UNIT_SHA"
expect_eq "records helper sha" "$(sha_of "$REC")" "$WANT_REC_SHA"
expect_eq "host test sha" "$(sha_of "$HOST_TEST")" "$WANT_HOST_TEST_SHA"
expect_eq "reader test sha" "$(sha_of "$READER_TEST")" "$WANT_READER_TEST_SHA"
expect_eq "slice 1b library sha" "$(sha_of "$LIB")" "$WANT_LIB_SHA"
expect_eq "slice 1c helper sha" "$(sha_of "$C1_BOOT")" "$WANT_C1_BOOT_SHA"
expect_eq "slice 1c unit sha" "$(sha_of "$C1_UNIT")" "$WANT_C1_UNIT_SHA"
expect_eq "capture-cores sha" "$(sha_of "$CORES")" "$WANT_CORES_SHA"
# The helper checks the same files on Johnny; its pins must equal ours.
expect_eq "helper OBJ_SHA256" "$(var_of "$REC" OBJ_SHA256)" "$WANT_OBJ_SHA"
expect_eq "helper READER_SHA256" "$(var_of "$REC" READER_SHA256)" "$WANT_READER_SHA"
expect_eq "helper R_UNIT_SHA256" "$(var_of "$REC" R_UNIT_SHA256)" "$WANT_UNIT_SHA"
expect_eq "helper LIB_SHA256" "$(var_of "$REC" LIB_SHA256)" "$WANT_LIB_SHA"
expect_eq "helper C1_BOOT_SHA256" "$(var_of "$REC" C1_BOOT_SHA256)" "$WANT_C1_BOOT_SHA"
expect_eq "helper C1_UNIT_SHA256" "$(var_of "$REC" C1_UNIT_SHA256)" "$WANT_C1_UNIT_SHA"
expect_eq "helper CORES_SHA256" "$(var_of "$REC" CORES_SHA256)" "$WANT_CORES_SHA"
echo PINS-OK

# ---------------------------------------------------------------- 2. syntax

bash -n "$REC" || fail "bash -n records helper"
bash -n "$SELF" || fail "bash -n self-test"
python3 -I -B -c 'import ast, sys; [ast.parse(open(p).read(), p) for p in sys.argv[1:]]' "$READER" "$READER_TEST" ||
  fail "python syntax"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$REC" "$SELF" || fail shellcheck
  echo SHELLCHECK-OK
else
  echo NOTE-no-shellcheck
fi

# ---------------------------------------------------------------- 3. source rules

src_code=$(sed -E 's#//.*$##' "$SRC" | python3 -I -c 'import re, sys; print(re.sub(r"/\*.*?\*/", "", sys.stdin.read(), flags=re.S))')
for bad in XDP_DROP XDP_TX REDIRECT ABORTED adjust tail_call probe_read ringbuf_output prandom; do
  lacks "forbidden word in records source" "$src_code" "$bad"
done
expect_eq "one return XDP_PASS" "$(grep -c 'return XDP_PASS;' <<<"$src_code")" 1
expect_eq "XDP_PASS is 2" "$(grep -cE '^#define XDP_PASS 2$' <<<"$src_code")" 1
has "license GPL" "$src_code" '"GPL"'
# Slice 1b stats enum, unchanged (ENUM-ORDER-OK).
enum_of() { sed -n '/K_PKTS = 0,/,/K_MAX/p' "$1" | sed -E 's#//.*$##; s/[[:space:]]+//g' | grep -v '^$'; }
expect_eq "stats enum equals slice 1b" "$(enum_of "$SRC")" "$(enum_of "$OBS_SRC")"
echo ENUM-ORDER-OK

# ---------------------------------------------------------------- 4. object

CLANG=
for c in /tmp/m1s1b-llvm*/usr/lib/llvm-22/bin/clang "$(command -v clang-22 2>/dev/null || true)"; do
  if [ -n "$c" ] && [ -x "$c" ] && "$c" --version 2>/dev/null | grep -q 'version 22[.]1[.]8'; then
    CLANG=$c
    break
  fi
done
if [ -n "$CLANG" ]; then
  (cd "$ROOT" && "$CLANG" -O2 -g -Wall -Wextra -Werror -target bpfel -mcpu=v3 -ffile-prefix-map="$ROOT"=. \
    -c docs/tool-install/module1_xdp_records.c -o "$TMP/rebuild.o") || fail "rebuild"
  expect_eq "rebuild reproducible" "$(sha_of "$TMP/rebuild.o")" "$WANT_OBJ_SHA"
  echo "OK-rebuild-reproducible $("$CLANG" --version | head -1)"
else
  echo "NOTE-no-clang-22.1.8: rebuild check skipped (the pinned .o is checked above)"
fi

OBJDUMP=
for c in /tmp/m1s1b-llvm*/usr/lib/llvm-*/bin/llvm-objdump "$(command -v llvm-objdump-22 2>/dev/null || true)" \
  "$(command -v llvm-objdump 2>/dev/null || true)"; do
  if [ -n "$c" ] && [ -x "$c" ] && "$c" --version >/dev/null 2>&1; then
    OBJDUMP=$c
    break
  fi
done
[ -n "$OBJDUMP" ] || fail "no llvm-objdump (the helper allowlist must be checked on the disassembly)"
dis=$("$OBJDUMP" -d --no-show-raw-insn "$OBJ")
has "BPF ELF" "$dis" "file format elf64-bpf"
calls=$(grep -oE '(^|[[:space:]])call 0x[0-9a-f]+$' <<<"$dis" | awk '{print $2}' | sort -u | tr '\n' ' ' | sed 's/ $//')
for c in $calls; do
  case "$c" in
    0x1 | 0x5 | 0x83 | 0x84 | 0x85) ;;
    *) fail "helper $c outside the allowlist {1, 5, 131, 132, 133}" ;;
  esac
done
lacks "no bpf-to-bpf calls" "$dis" "call -"
n_exit=$(grep -cE ':[[:space:]]+exit$' <<<"$dis" || true)
expect_eq "one exit" "$n_exit" 1
before_exit=$(grep -B1 -E ':[[:space:]]+exit$' <<<"$dis" | head -n 1 | sed -E 's/^[^:]*:[[:space:]]*//')
expect_eq "r0 = 2 (XDP_PASS) right before exit" "$before_exit" "w0 = 0x2"
r0const=$(grep -E ':[[:space:]]+[rw]0 = (0x)?-?[0-9a-f]+$' <<<"$dis" | sed -E 's/.*= //' | sort -u | tr '\n' ' ' || true)
for v in $r0const; do
  case "$v" in 0x0 | 0x2) ;; *) fail "r0 constant $v (only 0, an inlined helper result, and 2)" ;; esac
done
sections=$("$OBJDUMP" -h "$OBJ")
has "section xdp" "$sections" " xdp "
has "section license" "$sections" " license "
echo "OBJECT-DISASM-OK exits=$n_exit calls=[$calls]"

if command -v bpftool >/dev/null 2>&1; then
  skel=$(bpftool gen skeleton "$OBJ" name m2 2>&1) || fail "bpftool gen skeleton refused the object: $skel"
  for m in m1_stats m1_rxq m2_ctl m2_cfg m2_state m2_rb; do
    has "skeleton map $m" "$skel" "struct bpf_map *$m;"
  done
  has "skeleton program" "$skel" "struct bpf_program *j_xdp_records;"
  btf=$(bpftool btf dump file "$OBJ" format raw 2>&1) || fail "btf dump"
  has "ringbuf map type 27" "$btf" "nr_elems=27"
  has "ringbuf 4 MiB" "$btf" "nr_elems=4194304"
  has "stats 12 slots" "$btf" "nr_elems=12"
  has "rxq 64 slots" "$btf" "nr_elems=64"
  has "ctl 6 slots" "$btf" "nr_elems=6"
  echo "OBJECT-LIBBPF-PARSE-OK ($(bpftool version | head -1))"
else
  echo "NOTE-no-bpftool: libbpf parse check skipped"
fi
# Pin names the helper expects = bpftool prog load pinmaps (maps) + prog.
expect_eq "helper PIN_NAMES" "$(var_of "$REC" PIN_NAMES)" '"m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state prog"'

# ---------------------------------------------------------------- 5. host test

HCC=
for c in "$CLANG" "$(command -v clang 2>/dev/null || true)" "$(command -v gcc 2>/dev/null || true)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then
    HCC=$c
    break
  fi
done
[ -n "$HCC" ] || fail "no host C compiler for the layout/parse test"
"$HCC" -O1 -Wall -Wextra -Werror -Wno-unknown-pragmas -o "$TMP/host-test" "$HOST_TEST" || fail "host test build"
host_out=$("$TMP/host-test") || { printf '%s\n' "$host_out"; fail "host test"; }
has "host test" "$host_out" "HOST-TEST-OK cases="
rec_fmt=$(sed -n 's/^REC-FMT //p' <<<"$host_out")
reader_fmt=$(sed -nE 's/^REC_FMT = "(.*)"$/\1/p' "$READER")
expect_eq "record layout = reader REC_FMT" "$rec_fmt" "$reader_fmt"
ctl_c=$(sed -nE 's/^CTL-NAMES (.*) C_MAX=[0-9]+$/\1/p' <<<"$host_out")
expect_eq "m2_ctl order = helper CTL_NAMES" "\"$ctl_c\"" "$(var_of "$REC" CTL_NAMES)"
grep '^HOST-TEST-OK' <<<"$host_out"

# ---------------------------------------------------------------- 6. reader

reader_out=$(python3 -I -B "$READER_TEST" "$READER") || { printf '%s\n' "$reader_out"; fail "reader test"; }
grep '^READER-TEST-OK' <<<"$reader_out" || fail "reader test token"
python3 -I -B "$READER" --help >/dev/null || fail "reader --help"
rcode=$(grep -vE '^[[:space:]]*#' "$READER")
for bad in 'import socket' 'from socket' 'AF_INET' 'urllib' 'http.client' 'subprocess' 'BPF_MAP_UPDATE_ELEM' 'BPF_PROG_LOAD' \
  'BPF_LINK_CREATE' 'os.system' 'exec('; do
  lacks "reader code" "$rcode" "$bad"
done
echo READER-STATIC-OK

# ---------------------------------------------------------------- 7. reader unit

ucode=$(grep -vE '^[[:space:]]*#' "$UNIT")
for need in 'PrivateNetwork=yes' 'IPAddressDeny=any' 'RestrictAddressFamilies=none' 'NoNewPrivileges=yes' \
  'CapabilityBoundingSet=' 'AmbientCapabilities=' 'ProtectSystem=strict' 'ReadWritePaths=/sys/fs/bpf/johnny_m1s2/m2_rb' \
  'StateDirectory=johnny/m1s2' 'StateDirectoryMode=0700' 'UMask=0077' 'Restart=no' 'CPUAffinity=0' 'MemoryMax=128M' \
  'User=root' 'MemoryDenyWriteExecute=yes' 'SystemCallFilter=@system-service bpf'; do
  grep -qxF "$need" <<<"$ucode" || fail "reader unit missing line [$need]"
done
lacks "reader unit is never enabled" "$ucode" "[Install]"
lacks "reader unit grants no capability" "$ucode" "CAP_"
expect_eq "unit ExecStart = helper READER" \
  "$(sed -nE 's#^ExecStart=/usr/bin/python3 -I -B ([^ ]+) .*#\1#p' <<<"$ucode")" "$(var_of "$REC" READER)"
has "unit bounded 60 s" "$ucode" "--max-seconds 60 "
has "unit bounded bytes" "$ucode" "--max-bytes 67108864 "
has "unit keeps 3" "$ucode" "--keep 3"
rms=$(sed -nE 's/^RuntimeMaxSec=([0-9]+)$/\1/p' <<<"$ucode")
{ [ -n "$rms" ] && [ "$rms" -gt 60 ] && [ "$rms" -le 120 ]; } || fail "RuntimeMaxSec $rms"
expect_eq "helper PIN_DIR = unit pin" "$(var_of "$REC" PIN_DIR)/m2_rb" "/sys/fs/bpf/johnny_m1s2/m2_rb"
echo UNIT-STATIC-OK

# ---------------------------------------------------------------- 8. helper rules

rc=$(code_of "$REC")
for bad in 'dev "$IFACE" overwrite' 'xdpgeneric pinned' 'xdpoffload' 'net attach xdp ' 'map update' 'sysctl -w' 'ethtool -L' 'ethtool -K' \
  'ethtool -G' 'ethtool -X' 'ip link set' 'ip addr' 'systemctl enable' 'systemctl disable' 'systemctl restart' \
  'johnny-capture-xdp.service.d' 'apt-get' 'apt install' 'dpkg' 'snap install' 'pci=noaer' 'curl' 'wget' 'scp ' 'ssh '; do
  lacks "helper code" "$rc" "$bad"
done
expect_eq "one attach, native, pinned" "$(grep -c 'bpftool net attach' <<<"$rc")" 1
has "native attach" "$rc" 'bpftool net attach xdpdrv pinned "$PIN_DIR/prog" dev "$IFACE"'
expect_eq "C1 unit is only stopped in swap" "$(grep -c 'systemctl stop "$C1_UNIT"' <<<"$rc")" 1
for f in "$C1_BOOT" "$C1_UNIT"; do
  lacks "helper never writes slice 1c" "$rc" "> $f"
done
lacks "helper never installs files" "$rc" "install -m"
expect_eq "modes are m2_* (library do_status must not shadow ours)" "$(grep -cE '^do_[a-z]+\(\)' "$REC" || true)" 0
echo HELPER-STATIC-OK

# ---------------------------------------------------------------- 9. E2E in a fake world

# Fake Johnny: observer id 500 (slice 1c), records id 900 once loaded, a foreign
# id 777 when asked. State lives in files because the helper calls some fakes
# inside $(...) subshells.
e2e() {
  local name=$1 mode=$2 setup=$3
  local W=$TMP/e2e-$name
  mkdir -p "$W/state" "$W/run"
  echo "driver 500" >"$W/attached"
  echo active >"$W/c1"
  echo 1000 >"$W/pkts"
  (
    set +eu
    # shellcheck source=docs/tool-install/module1-slice2-records.sh
    source "$REC"
    LIB=$TI/module1-slice1b-detach.sh
    owner_ok() { [ -f "$1" ]; }
    use_lib >/dev/null || exit 97
    # The library defines its own main/do_status; on Johnny ours is already
    # running when it is sourced. Here, re-source ours on top.
    # shellcheck source=docs/tool-install/module1-slice2-records.sh
    source "$REC"
    PROG_NAME=$REC_NAME
    use_lib() { STOPS=0; }
    STATE_DIR=$W/state
    PIN_DIR=$W/pins
    LOCK_FILE=$W/run/lock
    OUT_DIR=$W/m1s2
    PROC_ROOT=$W/proc
    mkdir -p "$PROC_ROOT"
    echo "bpf /sys/fs/bpf bpf rw 0 0" >"$PROC_ROOT/mounts"
    SAFE_PATH=$PATH
    WAIT_TRIES=1
    WAIT_STEP=0
    gates() { return 0; }
    need_tools() { :; }
    file_ok() { echo "OK-$1-hash $3"; }
    sleep() { :; }
    check_link() { echo "LINK $IFACE fake"; }
    wait_link_up() { return 0; }
    link_facts() { L_FLAGS=0x1103 L_SPEED=10000 L_CARRIER=1 L_OPER=up L_MTU=1500; }
    combined_now() { echo 12; }
    load_cores() { return 0; }
    irq_snapshot() { echo "irq 100 cpu 1"; }
    irq_norm() { cat; }
    irq_in_cores() { cat >/dev/null; }
    nic_drops() { echo "rx_dropped=0 rx_missed_errors=0 rx_fifo_errors=0 rx_errors=0"; }
    drop_deltas() { echo "rx_dropped=0"; }
    read_trim() { echo 2; }
    df() { printf 'Avail\n%s\n' 99999999999; }
    W_=$W
    attached() { cat "$W_/attached"; }
    net_attach_lines() { attached; }
    rec_loaded() { [ -e "$W_/pins/prog" ] || grep -q '^driver 900$' "$W_/attached"; }
    bpftool() {
      case "$*" in
        "-j prog show")
          python3 -I -c '
import json, sys
p = []
if sys.argv[1] == "1": p.append({"id": 500, "type": "xdp", "name": "j_xdp_observe"})
if sys.argv[2] == "1": p.append({"id": 900, "type": "xdp", "name": "j_xdp_records"})
if sys.argv[3] == "1": p.append({"id": 777, "type": "xdp", "name": "evil"})
p.append({"id": 3, "type": "cgroup_skb", "name": "x"})
print(json.dumps(p))' \
            "$(grep -q '^driver 500$' "$W_/attached" && echo 1 || echo 0)" \
            "$(rec_loaded && echo 1 || echo 0)" \
            "$(grep -q ' 777$' "$W_/attached" && echo 1 || echo 0)"
          ;;
        "prog load "*)
          [ -e "$W_/verifier-refuses" ] && { echo "libbpf: verifier says no" >&2; return 255; }
          for f in $PIN_NAMES; do : >"$PIN_DIR/$f"; done
          ;;
        "net attach xdpdrv pinned "*)
          [ -s "$W_/attached" ] && { echo "Error: XDP program already attached" >&2; return 255; }
          [ -e "$W_/foreign-grabs-slot" ] && { echo "generic 777" >"$W_/attached"; return 255; }
          echo "driver 900" >"$W_/attached"
          ;;
        "net detach xdpdrv dev "*) : >"$W_/attached" ;;
        "net detach xdpgeneric dev "*) : >"$W_/attached" ;;
        *) echo "FAKE-BPFTOOL-UNEXPECTED $*" >&2; return 99 ;;
      esac
    }
    unit_active() {
      case "$1" in
        "$C1_UNIT") cat "$W_/c1" ;;
        *) echo inactive ;;
      esac
    }
    systemctl() {
      case "$1 $2" in
        "is-enabled $C1_UNIT") echo enabled ;;
        "stop $C1_UNIT") echo inactive >"$W_/c1"; grep -q '^driver 500$' "$W_/attached" && : >"$W_/attached"; return 0 ;;
        "start $C1_UNIT")
          [ -e "$W_/c1-missing" ] && return 5
          [ -s "$W_/attached" ] && { echo failed >"$W_/c1"; return 1; }
          echo "driver 500" >"$W_/attached"; echo active >"$W_/c1" ;;
        "reset-failed "* | "start $R_UNIT" | "stop $R_UNIT") ;;
        "show -p")
          case "$3" in
            InvocationID) echo 0123456789abcdef0123456789abcdef ;;
            Result) cat "$W_/result" 2>/dev/null || echo success ;;
          esac ;;
        *) echo "FAKE-SYSTEMCTL-UNEXPECTED $*" >&2; return 99 ;;
      esac
    }
    journalctl() { echo "M1S2-READER-END reason=signal-15 records=0 bytes=0"; }
    emit_stats() {
      local p
      p=$(cat "$W_/pkts")
      echo $((p + 500)) >"$W_/pkts"
      [ -e "$PIN_DIR/m1_stats" ] || return 1
      grep -q '^driver 900$' "$W_/attached" || p=0
      LAST_PKTS=$p LAST_L3=0 LAST_L4=0
      echo "$1 pkts $p"
    }
    ctl_rows() {
      local p
      p=$(($(cat "$W_/pkts") - 500))
      grep -q '^driver 900$' "$W_/attached" || p=0
      if [ -e "$W_/ctl-broken" ]; then
        printf 'seen %s\nsampled_out 0\nrate_limited 0\nrb_full 0\nemitted 0\ndiscarded 0\n' "$p"
      else
        printf 'seen %s\nsampled_out 0\nrate_limited 0\nrb_full 0\nemitted %s\ndiscarded 0\n' "$p" "$p"
      fi
    }
    cfg_line() { echo "ver=0 sample_every=1 rate=2000 burst=4000"; }
    eval "$setup"
    main "$mode"
  ) >"$W/out" 2>&1 && E2E_RC=0 || E2E_RC=$?
  E2E_OUT=$(cat "$W/out")
  E2E_W=$W
}

pre_loaded='mkdir -m 0700 "$PIN_DIR"; for f in $PIN_NAMES; do : >"$PIN_DIR/$f"; done'
pre_swapped="$pre_loaded"'; echo "driver 900" >"$W_/attached"; echo inactive >"$W_/c1"; echo "irq 100 cpu 1" >"$STATE_DIR/irq-baseline.txt"'
n=0
e2e_ok() { [ "$E2E_RC" -eq 0 ] || { printf '%s\n' "$E2E_OUT" >&2; fail "E2E $1 rc=$E2E_RC"; }; n=$((n + 1)); }
e2e_stops() { [ "$E2E_RC" -ne 0 ] || { printf '%s\n' "$E2E_OUT" >&2; fail "E2E $1 should stop"; }; n=$((n + 1)); }
attached_is() { expect_eq "E2E $1 attached" "$(cat "$E2E_W/attached")" "$2"; }

e2e probe-ok probe ''
e2e_ok probe-ok; has probe "$E2E_OUT" M1S2-PROBE-DONE; attached_is probe-ok "driver 500"

e2e probe-c1-down probe 'echo inactive >"$W_/c1"; : >"$W_/attached"'
e2e_stops probe-c1-down; has probe-c1-down "$E2E_OUT" STOP-observer-not-attached

e2e load-ok load ''
e2e_ok load-ok; has load "$E2E_OUT" "M1S2-LOAD-DONE prog_id=900"; has load "$E2E_OUT" OK-reader-smoke
attached_is load-ok "driver 500"; expect_eq "load pins" "$(find "$E2E_W/pins" -mindepth 1 -printf "%f\n" | sort | tr '\n' ' ')" "m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state prog "

e2e load-verifier-refuses load 'touch "$W_/verifier-refuses"'
e2e_stops load-verifier-refuses; has refuse "$E2E_OUT" "STOP-load"; has refuse "$E2E_OUT" M1S2-ROLLBACK-DONE
has refuse "$E2E_OUT" M1S2-LOAD-STOPS; attached_is load-verifier-refuses "driver 500"; [ ! -e "$E2E_W/pins" ] || fail "E2E refuse left pins"

# Capability resolution: if Johnny's kernel refuses BPF_OBJ_GET to a
# capability-less uid 0, the load smoke fails closed and rolls back.
e2e load-reader-eperm load 'echo exit-code >"$W_/result"; journalctl() { echo "STOP-obj-get errno=1"; }'
e2e_stops load-reader-eperm; has eperm "$E2E_OUT" "READER-RESULT exit-code"; has eperm "$E2E_OUT" STOP-reader-smoke-result
has eperm "$E2E_OUT" M1S2-ROLLBACK-DONE; has eperm "$E2E_OUT" M1S2-LOAD-STOPS; attached_is load-reader-eperm "driver 500"
[ ! -e "$E2E_W/pins" ] || fail "E2E load-reader-eperm left pins"

e2e load-foreign-attached load 'echo "driver 777" >"$W_/attached"'
e2e_stops load-foreign-attached; has foreign "$E2E_OUT" STOP-observer-not-attached; has foreign "$E2E_OUT" NOTHING-CHANGED
attached_is load-foreign-attached "driver 777"

e2e swap-ok swap "$pre_loaded"
e2e_ok swap-ok; has swap "$E2E_OUT" M1S2-SWAP-DONE; has swap "$E2E_OUT" "OK-xdp-mode driver id=900 j_xdp_records (post-swap)"
attached_is swap-ok "driver 900"; expect_eq "swap leaves c1" "$(cat "$E2E_W/c1")" inactive

e2e swap-slot-taken swap "$pre_loaded"'; touch "$W_/foreign-grabs-slot"'
e2e_stops swap-slot-taken; has slot "$E2E_OUT" STOP-attach; has slot "$E2E_OUT" "STOP-xdp-foreign mode=generic id=777"
has slot "$E2E_OUT" M1S2-SWAP-STOPS; attached_is swap-slot-taken "generic 777"

e2e read-ok read "$pre_swapped"'; journalctl() { echo "M1S2-READER-END reason=max-seconds records=10 bytes=800"; }; mkdir -p "$OUT_DIR"; : >"$OUT_DIR/run-20261108T000000Z.bin"; python3() { if [ "$3" = "$READER" ]; then echo SUMMARY; else command python3 "$@"; fi; }'
e2e_ok read-ok; has read "$E2E_OUT" M1S2-READ-DONE; has read "$E2E_OUT" SUMMARY

e2e read-reader-fails read "$pre_swapped"'; echo exit-code >"$W_/result"; journalctl() { echo "STOP-ring-corrupt"; }'
e2e_stops read-reader-fails; has rdf "$E2E_OUT" STOP-reader-result; lacks rdf "$E2E_OUT" M1S2-READ-DONE

e2e verify-ok verify "$pre_swapped"
e2e_ok verify-ok; has verify "$E2E_OUT" M1S2-VERIFY-DONE; has verify "$E2E_OUT" "OK-ctl-accounting (verify-start)"

e2e verify-ctl-broken verify "$pre_swapped"'; touch "$W_/ctl-broken"'
e2e_stops verify-ctl-broken; has broken "$E2E_OUT" STOP-ctl-accounting-verify-start

e2e verify-irq-moved verify "$pre_swapped"'; echo "irq 100 cpu 7" >"$STATE_DIR/irq-baseline.txt"'
e2e_stops verify-irq-moved; has irq "$E2E_OUT" STOP-irq-pins-moved-verify-start

e2e rollback-from-swap rollback "$pre_swapped"
e2e_ok rollback-from-swap; has rb "$E2E_OUT" "DETACHED mode=driver id=900"; has rb "$E2E_OUT" C1-STARTED
has rb "$E2E_OUT" "OK-xdp-mode driver id=500 j_xdp_observe"; has rb "$E2E_OUT" M1S2-ROLLBACK-DONE
attached_is rollback-from-swap "driver 500"; [ ! -e "$E2E_W/pins" ] || fail "E2E rollback left pins"
[ ! -e "$E2E_W/state/irq-baseline.txt" ] || fail "E2E rollback left baseline"

e2e rollback-noop rollback ''
e2e_ok rollback-noop; has noop "$E2E_OUT" "KEEP-observer mode=driver id=500"; has noop "$E2E_OUT" C1-ALREADY-ACTIVE
has noop "$E2E_OUT" PINS-ABSENT; lacks noop "$E2E_OUT" DETACHED; attached_is rollback-noop "driver 500"

e2e rollback-foreign rollback 'echo "driver 777" >"$W_/attached"; echo inactive >"$W_/c1"'
e2e_stops rollback-foreign; has rbf "$E2E_OUT" "STOP-xdp-foreign mode=driver id=777"; has rbf "$E2E_OUT" M1S2-ROLLBACK-STOPS
attached_is rollback-foreign "driver 777"

e2e rollback-c1-missing rollback "$pre_swapped"'; touch "$W_/c1-missing"'
e2e_stops rollback-c1-missing; has rbc "$E2E_OUT" STOP-c1-start-failed; has rbc "$E2E_OUT" M1S2-ROLLBACK-STOPS

e2e status-ours status "$pre_swapped"
e2e_ok status-ours; has status "$E2E_OUT" "ATTACH records 900"; has status "$E2E_OUT" M1S2-STATUS-DONE
lacks status "$E2E_OUT" M1S1B-

e2e bad-args nonsense ''
e2e_stops bad-args; has args "$E2E_OUT" STOP-args

echo "E2E-OK scenarios=$n"

# ---------------------------------------------------------------- 10. runbook

[ -f "$DOC" ] || fail "missing runbook $DOC"
python3 -I - "$DOC" "$WANT_OBJ_SHA" "$WANT_READER_SHA" "$WANT_UNIT_SHA" "$WANT_REC_SHA" "$WANT_LIB_SHA" \
  "$WANT_C1_BOOT_SHA" "$WANT_C1_UNIT_SHA" "$WANT_SRC_SHA" "$WANT_HOST_TEST_SHA" "$WANT_READER_TEST_SHA" <<'PY'
import re, sys
doc_path, obj, rdr, unit, rec, lib, c1b, c1u, src, ht, rt = sys.argv[1:12]
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
    "johnny-m1s2-reader.py": rdr,
    "johnny-m1s2-reader.service": unit,
    "module1-slice2-records.sh": rec,
    "module1-slice1b-detach.sh": lib,
    "module1-slice1c-boot.sh": c1b,
    "johnny-capture-xdp.service": c1u,
    "module1_xdp_records.c": src,
    "module1-slice2-host-test.c": ht,
    "module1-slice2-reader-test.py": rt,
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

tokens = ["SELF-TEST-OK", "M1S2-COPY-DONE", "M1S2-PROBE-DONE", "M1S2-INSTALL-DONE", "M1S2-LOAD-DONE",
          "M1S2-SWAP-DONE", "M1S2-READ-DONE", "M1S2-VERIFY-DONE", "M1S2-TRIAL-CLOSED",
          "M1S2-UNINSTALL-DONE", "M1S2-RUNFILES-DELETED"]
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
    if "ssh" in body and "192.168.50.152" not in body:
        die(f"block #{idx}: ssh to an unexpected host")
    for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
        name = path.rsplit("/", 1)[-1]
        if name not in want:
            die(f"block #{idx}: unknown pinned file {name}")
        if want[name] != h:
            die(f"block #{idx}: wrong hash for {name}: {h}")
    if "module1-slice2-records.sh" in body and re.search(r"records\.sh (probe|load|swap|read|verify|status|rollback)", body):
        if rec not in body:
            die(f"block #{idx} runs the helper without checking its hash")
    if re.search(r"records\.sh (probe|load|swap|read|verify|status|rollback)[^\n&]*\|", body):
        die(f"block #{idx} pipes the helper (masks its exit code)")
    for t in tokens:
        hit = re.search(r"echo " + re.escape(t) + r"\b", body) or (t == "SELF-TEST-OK" and "self-test.sh" in body)
        m = re.fullmatch(r"M1S2-(PROBE|LOAD|SWAP|READ|VERIFY)-DONE", t)
        # The helper prints its own M1S2-<MODE>-DONE; the paste does not echo it again.
        if m and re.search(r"records\.sh " + m.group(1).lower() + r"\b", body):
            hit = True
        if hit:
            seen.append(t)
    for bad in ("xdpgeneric", "xdpoffload", "overwrite", "pci=noaer", "NOPASSWD", "snap ", "systemctl enable",
                "systemctl disable", "johnny-capture-xdp.service.d", "rm -rf /root/m1s1b", "rm -r /root/m1s1b",
                "/root/m1s1b/module1-slice1c-boot.sh start", "/root/m1s1b/module1-slice1c-boot.sh stop", "reboot"):
        if bad in body:
            die(f"forbidden text in block #{idx}: {bad}")
    for m in re.finditer(r"\binstall\b[^\n]*?(/etc/systemd/system/johnny-capture-xdp\.service|/root/m1s1b/)", body):
        die(f"block #{idx} installs over slice 1c: {m.group(0)}")
    for m in re.finditer(r"\brm\b[^\n]*", body):
        if "m1s1b" in m.group(0) or "johnny-capture-xdp" in m.group(0):
            die(f"block #{idx} removes slice 1c files: {m.group(0)}")

if seen != tokens:
    die(f"paste order/tokens: got {seen} want {tokens}")
# The rollback blocks come after a heading that says they are not part of the paste sequence.
rb = text.find("## Rollback")
if rb < 0 or "not part of the paste sequence" not in text[rb:rb + 400]:
    die("rollback section must say it is not part of the paste sequence")
if text.find("echo M1S2-UNINSTALL-DONE") < rb:
    die("uninstall block must sit under ## Rollback")
joined = "\n".join(b for _, b in blocks)
for name in ("module1-xdp-records.o", "johnny-m1s2-reader.py", "johnny-m1s2-reader.service", "module1-slice2-records.sh"):
    if joined.count(want[name]) < 3:
        die(f"hash for {name} must appear in >=3 paste blocks")
print(f"RUNBOOK-OK blocks={len(blocks)}")
PY

echo SELF-TEST-OK
