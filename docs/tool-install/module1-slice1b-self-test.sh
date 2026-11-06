#!/bin/bash
# shellcheck disable=SC2030,SC2031  # env is set inside subshells on purpose
# shellcheck disable=SC2016  # single quotes hold literal script text on purpose
# shellcheck disable=SC2034  # variables are consumed by the sourced scripts
# shellcheck disable=SC2015,SC2012  # simple A && B || fail and ls counts are fine here
# Local checks for Module 1 slice 1b (passive native-XDP observer). Runs on
# rock-box WITHOUT root. Touches no NIC, loads no BPF program, never contacts
# Johnny. The "Johnny" is a temp directory of fake /proc and /sys files plus
# command shims (bpftool, ip, ethtool, tcpdump, systemctl, journalctl, sleep,
# timeout); the real attach and detach scripts run against it.
#
# Fixture text (bpftool JSON, ethtool -l, /proc/interrupts) is illustrative of
# each tool's documented format. It is NOT a live capture from Johnny.
# Prints SELF-TEST-OK at the end, SELF-TEST-FAIL (stderr, exit 1) on the first
# failure.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
TI=$ROOT/docs/tool-install
ATTACH=$TI/module1-slice1b-attach.sh
DETACH=$TI/module1-slice1b-detach.sh
CSRC=$TI/module1_xdp_observe.c
OBJ=$TI/module1-xdp-observe.o
DOC=$TI/module1-slice1b-attach.md
SLICE1_DOC=$TI/module1-slice1-span-xdp.md
SELF=$TI/module1-slice1b-self-test.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "SELF-TEST-FAIL $*" >&2
  exit 1
}

expect_eq() { # name got want
  [ "$2" = "$3" ] || fail "$1: got [$2] want [$3]"
}

has() { # name text pattern (fixed string)
  case "$2" in
    *"$3"*) ;;
    *) fail "$1: missing [$3] in: $(printf '%s' "$2" | tail -15)" ;;
  esac
}

lacks() { # name text pattern (fixed string)
  case "$2" in
    *"$3"*) fail "$1: unexpected [$3] in: $(printf '%s' "$2" | tail -15)" ;;
  esac
}

sha_of() { sha256sum "$1" | awk '{print $1}'; }

# Script text without full-line comments (comments may name forbidden things).
code_of() { sed -E '/^[[:space:]]*#/d' "$1"; }

# ---------------------------------------------------------------- pins

OBJ_SHA=$(sha_of "$OBJ")
ATTACH_SHA=$(sha_of "$ATTACH")
DETACH_SHA=$(sha_of "$DETACH")
CSRC_SHA=$(sha_of "$CSRC")

grep -q '@@' "$ATTACH" && fail "attach script still has an @@ placeholder"
expect_eq "attach embeds object sha" "$(sed -n 's/^OBJ_SHA256=//p' "$ATTACH")" "$OBJ_SHA"
expect_eq "attach embeds detach sha" "$(sed -n 's/^DETACH_SHA256=//p' "$ATTACH")" "$DETACH_SHA"
expect_eq "helper sha in attach" "$(sed -n 's/^HELPER_SHA256=//p' "$ATTACH")" "$(sha_of "$ROOT/etc/johnny/irq-affinity.sh")"
expect_eq "helper sha in detach" "$(sed -n 's/^HELPER_SHA256=//p' "$DETACH")" "$(sha_of "$ROOT/etc/johnny/irq-affinity.sh")"
expect_eq "cores sha in detach" "$(sed -n 's/^CORES_SHA256=//p' "$DETACH")" "$(sha_of "$ROOT/etc/johnny/capture-cores")"
expect_eq "attach helper path" "$(sed -n 's/^HELPER=//p' "$ATTACH")" /etc/johnny/irq-affinity.sh
expect_eq "detach helper path" "$(sed -n 's/^HELPER=//p' "$DETACH")" /etc/johnny/irq-affinity.sh
expect_eq "kernel pin matches" "$(sed -n 's/^KERNEL_WANT=//p' "$ATTACH")" "$(sed -n 's/^KERNEL_WANT=//p' "$DETACH")"
echo "PINS-OK obj=$OBJ_SHA attach=$ATTACH_SHA detach=$DETACH_SHA"

bash -n "$ATTACH" || fail "attach syntax"
bash -n "$DETACH" || fail "detach syntax"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$ATTACH" "$DETACH" "$SELF" || fail "shellcheck"
  echo SHELLCHECK-OK
else
  echo NOTE-no-shellcheck
fi

# ---------------------------------------------------------------- program source

csrc_code=$(python3 -I - "$CSRC" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
t = re.sub(r"//[^\n]*", "", t)
print(t)
PY
)
for bad in XDP_DROP XDP_TX XDP_REDIRECT XDP_ABORTED bpf_redirect bpf_xdp_adjust bpf_ringbuf perf_event \
  bpf_tail_call probe_read probe_write bpf_trace_printk bpf_skb bpf_xdp_load_bytes bpf_xdp_store_bytes \
  XSKMAP xsk BPF_MAP_TYPE_RINGBUF; do
  case "$csrc_code" in
    *"$bad"*) fail "program source mentions $bad outside comments" ;;
  esac
done
n_return=$(grep -c 'return' <<<"$csrc_code" || true)
# 'return;' in the void helper (4 early exits) plus the single XDP entry return.
n_pass=$(grep -c 'return XDP_PASS;' <<<"$csrc_code" || true)
expect_eq "exactly one return XDP_PASS" "$n_pass" 1
n_value_returns=$(grep -E 'return[[:space:]]+[^;[:space:]]' <<<"$csrc_code" | grep -vc 'return XDP_PASS;' || true)
expect_eq "no other value return" "$n_value_returns" 0
has "observe is void" "$csrc_code" "static __always_inline void observe("
has "entry calls observe then passes" "$(tr -d '[:space:]' <<<"$csrc_code")" 'intj_xdp_observe(structxdp_md*ctx){observe(ctx);returnXDP_PASS;}'
helper_ids=$(grep -oE 'bpf_[a-z_]+\(' <<<"$csrc_code" | sort -u | tr '\n' ' ')
expect_eq "only helper is bpf_map_lookup_elem" "$helper_ids" "bpf_map_lookup_elem( "
echo "PROGRAM-SOURCE-OK returns=$n_return"

# enum order vs the name table in the detach script
enum_names=$(python3 -I - "$CSRC" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"enum\s*\{(.*?)\};", t, flags=re.S)
names = [x.strip().split("=")[0].strip() for x in m.group(1).split(",") if x.strip()]
assert names[-1] == "K_MAX", names
print(" ".join(n[2:].lower() for n in names[:-1]))
PY
)
table=$(sed -n 's/^STAT_NAMES="\(.*\)"$/\1/p' "$DETACH")
expect_eq "enum order matches STAT_NAMES" "$enum_names" "$table"
rxq_c=$(sed -n 's/^#define RXQ_MAX \([0-9]*\)$/\1/p' "$CSRC")
rxq_s=$(sed -n 's/^RXQ_MAX=\([0-9]*\)$/\1/p' "$DETACH")
expect_eq "RXQ_MAX matches" "$rxq_c" "$rxq_s"
echo "ENUM-ORDER-OK $enum_names"

# ---------------------------------------------------------------- object

# Optional rebuild: only if a clang is on PATH or in the documented temp dir.
CLANG=
for c in "$(command -v clang 2>/dev/null || true)" /tmp/m1s1b-llvm*/usr/lib/llvm-*/bin/clang; do
  if [ -n "$c" ] && [ -x "$c" ] && "$c" --version >/dev/null 2>&1; then
    CLANG=$c
    break
  fi
done
if [ -n "$CLANG" ]; then
  "$CLANG" -O2 -g -Wall -Wextra -Werror -target bpfel -mcpu=v3 -ffile-prefix-map="$ROOT"=. \
    -c docs/tool-install/module1_xdp_observe.c -o "$TMP/rebuilt.o"
  if [ "$(sha_of "$TMP/rebuilt.o")" = "$OBJ_SHA" ]; then
    echo "OK-rebuild-reproducible $("$CLANG" --version | head -1)"
  else
    echo "NOTE-rebuild-differs ($("$CLANG" --version | head -1)): a different clang gives a different object; the pin is the committed .o"
  fi
else
  echo "NOTE-no-clang: rebuild check skipped (the pinned .o is checked below)"
fi

OBJDUMP=
for c in /tmp/m1s1b-llvm*/usr/lib/llvm-*/bin/llvm-objdump "$(command -v llvm-objdump-22 2>/dev/null || true)" \
  "$(command -v llvm-objdump-18 2>/dev/null || true)" "$(command -v llvm-objdump 2>/dev/null || true)"; do
  if [ -n "$c" ] && [ -x "$c" ] && "$c" --version >/dev/null 2>&1; then
    OBJDUMP=$c
    break
  fi
done
if [ -n "$OBJDUMP" ]; then
  dis=$("$OBJDUMP" -d --no-show-raw-insn "$OBJ")
  case "$dis" in
    *"file format elf64-bpf"*) ;;
    *) fail "object is not a BPF ELF" ;;
  esac
  calls=$(grep -E '(^|[[:space:]])call ' <<<"$dis" | sed -E 's/^[^:]*:[[:space:]]*//' | sort -u | tr '\n' ';' || true)
  expect_eq "object calls only helper 1" "$calls" "call 0x1;"
  r0w=$(grep -E ':[[:space:]]+[rw]0 = ' <<<"$dis" | sed -E 's/^[^:]*:[[:space:]]*//' | sort -u | tr '\n' ';' || true)
  expect_eq "every constant written to r0 is 2 (XDP_PASS)" "$r0w" "w0 = 0x2;"
  n_exit=$(grep -cE ':[[:space:]]+exit$' <<<"$dis" || true)
  [ "$n_exit" -ge 1 ] || fail "object has no exit"
  # r0 is also overwritten by helper return values; every r0 write other than the
  # constant 2 must be absent, and the last r0 write before each exit is the 2.
  expect_eq "r0 assignments: no register-to-r0 moves" "$(grep -cE ':[[:space:]]+[rw]0 = [rw][0-9]' <<<"$dis" || true)" 0
  echo "OBJECT-DISASM-OK exits=$n_exit calls=$calls r0=$r0w"
else
  echo "NOTE-no-llvm-objdump: disassembly check skipped"
fi

if command -v bpftool >/dev/null 2>&1; then
  skel=$(bpftool gen skeleton "$OBJ" name m1s 2>&1) || fail "bpftool gen skeleton refused the object: $skel"
  has "skeleton has stats map" "$skel" "struct bpf_map *m1_stats;"
  has "skeleton has rxq map" "$skel" "struct bpf_map *m1_rxq;"
  has "skeleton has program" "$skel" "struct bpf_program *j_xdp_observe;"
  btf=$(bpftool btf dump file "$OBJ" format raw 2>&1) || fail "btf dump"
  has "stats map is per-cpu array (type 6), 12 slots" "$btf" "nr_elems=12"
  has "rxq map has 64 slots" "$btf" "nr_elems=64"
  has "per-cpu array map type" "$btf" "nr_elems=6"
  echo "OBJECT-LIBBPF-PARSE-OK ($(bpftool version | head -1))"
else
  echo "NOTE-no-bpftool: libbpf parse check skipped"
fi

# ---------------------------------------------------------------- static invocations

nbpf=0
for f in "$ATTACH" "$DETACH"; do
  c=$(code_of "$f")
  for pat in 'ip link set' 'ip link add' 'ip link del' 'ip addr add' 'ip route' 'sysctl -w' 'apt-get' 'apt ' 'dpkg -i' \
    'modprobe' 'insmod' 'rmmod' 'netplan' 'systemctl start' 'systemctl stop' 'systemctl restart' \
    'systemctl enable' 'systemctl disable' 'systemctl mask' 'NOPASSWD' 'noaer' 'snapd' 'snap install' 'snap remove' 'chown' \
    'bpftool prog attach' 'bpftool map update' 'bpftool map delete' 'bpftool prog detach' 'tc qdisc' 'ethtool -K' \
    'ethtool -L' 'ethtool -G' 'ethtool -X' 'ethtool -N' 'ethtool -s' 'ethtool -C' 'set-priv-flags' 'rp_filter' 'log_martians' \
    'suricata.yaml' 'AF_XDP' 'bpf_redirect'; do
    case "$c" in
      *"$pat"*) fail "$(basename "$f") contains forbidden text: $pat" ;;
    esac
  done
  if grep -qE '(^|[;&|(])[[:space:]]*(sudo|reboot|shutdown|poweroff)([[:space:]]|$)' <<<"$c"; then
    fail "$(basename "$f") runs sudo/reboot/shutdown as a command"
  fi
done
# attach: exactly one `net attach`, native only
ac=$(code_of "$ATTACH")
expect_eq "attach: one net attach" "$(grep -c 'bpftool net attach' <<<"$ac" || true)" 1
has "attach is xdpdrv pinned" "$ac" 'bpftool net attach xdpdrv pinned "$(pin_prog)" dev "$IFACE"'
expect_eq "attach: no generic/offload keywords" "$(grep -cE 'xdpgeneric|xdpoffload' <<<"$ac" || true)" 0
expect_eq "attach: no plain xdp attach" "$(grep -cE 'net attach (xdp|xdpgeneric|xdpoffload)([[:space:]]|$)' <<<"$ac" || true)" 0
expect_eq "attach: no net detach (rollback is the installed detach script)" "$(grep -c 'bpftool net detach' <<<"$ac" || true)" 0
# every bpftool call in attach
while IFS= read -r l; do
  case "$l" in
    *'bpftool prog load "$(obj_path)" "$(pin_prog)" pinmaps "$PIN_DIR"'* | \
      *'bpftool net attach xdpdrv pinned "$(pin_prog)" dev "$IFACE"'* | \
      *'for cmd in bpftool '*) nbpf=$((nbpf + 1)) ;;
    *) fail "attach: unexpected bpftool line: $l" ;;
  esac
done < <(grep -E '(^|[[:space:]!(])bpftool[[:space:]]+(-j|prog|net|map|feature|btf|gen|cgroup|perf|version|struct_ops|link|iter)' <<<"$ac" || true)
# detach: no attach/load at all; detach keyword comes from the mode case block
dc=$(code_of "$DETACH")
expect_eq "detach: never attaches" "$(grep -cE 'bpftool (net )?(attach|prog load|prog loadall)' <<<"$dc" || true)" 0
expect_eq "detach: one net detach" "$(grep -c 'bpftool net detach' <<<"$dc" || true)" 1
has "detach keyword table" "$dc" 'driver) kw=xdpdrv ;;'
has "detach keyword table generic" "$dc" 'generic) kw=xdpgeneric ;;'
has "detach keyword table offload" "$dc" 'offload) kw=xdpoffload ;;'
while IFS= read -r l; do
  case "$l" in
    *'bpftool -j net show dev "$IFACE"'* | *'bpftool -j prog show 2>'* | *'bpftool -j map dump pinned "$(pin_stats)"'* | \
      *'bpftool -j map dump pinned "$(pin_rxq)"'* | *'bpftool net detach "$kw" dev "$IFACE"'*) nbpf=$((nbpf + 1)) ;;
    *'command -v bpftool'*) ;;
    *) fail "detach: unexpected bpftool line: $l" ;;
  esac
done < <(grep -E '(^|[[:space:]!(])bpftool[[:space:]]+(-j|prog|net|map|feature|btf|gen|cgroup|perf|version|struct_ops|link|iter)' <<<"$dc" || true)
# ip / ethtool / systemctl / journalctl usage is read-only
while IFS= read -r l; do
  case "$l" in
    *'ip -4 -o addr show dev'* | *'ip -6 -o addr show dev'* | *'ip -4 route show default'*) ;;
    *) fail "unexpected ip usage: $l" ;;
  esac
done < <(grep -hE '(^|[^_a-z-])ip -' <<<"$ac"$'\n'"$dc" || true)
while IFS= read -r l; do
  case "$l" in
    *'ethtool -l "$IFACE"'*) ;;
    *) fail "unexpected ethtool usage: $l" ;;
  esac
done < <(grep -hE '(^|[^_a-z-])ethtool -' <<<"$ac"$'\n'"$dc" | grep -v 'for cmd in' || true)
while IFS= read -r l; do
  case "$l" in
    *'systemctl is-enabled suricata'* | *'systemctl is-active suricata'* | *'systemctl is-active "$svc"'*) ;;
    *'for cmd in '*) ;;
    *) fail "unexpected systemctl usage: $l" ;;
  esac
done < <(grep -hE '(^|[^_a-z-])systemctl ' <<<"$ac"$'\n'"$dc" || true)
echo "STATIC-INVOCATIONS-OK $nbpf"

# ---------------------------------------------------------------- unit tests

# shellcheck source=/dev/null
source "$DETACH"

# net show: none, native, generic, two attachments, other device, bad JSON.
expect_eq "net none" "$(net_xdp_from_json eno1np0 <<<'[{"xdp":[],"tc":[],"flow_dissector":[],"netfilter":[]}]')" ""
expect_eq "net driver" "$(net_xdp_from_json eno1np0 <<<'[{"xdp":[{"devname":"eno1np0","ifindex":3,"mode":"driver","id":41}],"tc":[]}]')" "driver 41"
expect_eq "net generic" "$(net_xdp_from_json eno1np0 <<<'[{"xdp":[{"devname":"eno1np0","ifindex":3,"mode":"generic","id":7}]}]')" "generic 7"
expect_eq "net two" "$(net_xdp_from_json eno1np0 <<<'[{"xdp":[{"devname":"eno1np0","mode":"driver","id":1},{"devname":"eno1np0","mode":"generic","id":2}]}]' | tr '\n' ';')" "driver 1;generic 2;"
expect_eq "net other dev" "$(net_xdp_from_json eno1np0 <<<'[{"xdp":[{"devname":"eno3","mode":"driver","id":9}]}]')" ""
expect_eq "net no id" "$(net_xdp_from_json eno1np0 <<<'[{"xdp":[{"devname":"eno1np0","mode":"driver"}]}]')" "driver none"
rc=0
net_xdp_from_json eno1np0 <<<'not json' >/dev/null 2>&1 || rc=$?
expect_eq "net bad json rc" "$rc" 2

pj='[{"id":3,"type":"cgroup_device","name":"sd_devices"},{"id":41,"type":"xdp","name":"j_xdp_observe","map_ids":[7,8]},{"id":50,"type":"xdp","name":"other"}]'
expect_eq "progs summary" "$(progs_from_json j_xdp_observe <<<"$pj")" "total=2 ours=1 ids=41"
expect_eq "progs empty" "$(progs_from_json j_xdp_observe <<<'[]')" "total=0 ours=0 ids=none"
expect_eq "progs non-xdp only" "$(progs_from_json j_xdp_observe <<<'[{"id":3,"type":"cgroup_device","name":"j_xdp_observe"}]')" "total=0 ours=0 ids=none"
rc=0
progs_from_json j_xdp_observe <<<'{"id":1}' >/dev/null 2>&1 || rc=$?
expect_eq "progs not-a-list rc" "$rc" 2

# per-CPU dump: BTF-formatted shape wins; raw-bytes shape works alone.
fmt='[{"key":["0x00","0x00","0x00","0x00"],"values":[{"cpu":0,"value":["0x05","0x00","0x00","0x00","0x00","0x00","0x00","0x00"]}],"formatted":{"key":0,"values":[{"cpu":0,"value":5},{"cpu":1,"value":7}]}},{"formatted":{"key":1,"values":[{"cpu":0,"value":1000},{"cpu":1,"value":0}]}}]'
expect_eq "percpu formatted" "$(percpu_from_json <<<"$fmt" | tr '\n' ';')" "0 12;1 1000;"
raw='[{"key":["0x02","0x00","0x00","0x00"],"values":[{"cpu":0,"value":["0x00","0x01","0x00","0x00","0x00","0x00","0x00","0x00"]},{"cpu":1,"value":["0x01","0x00","0x00","0x00","0x00","0x00","0x00","0x00"]}]}]'
expect_eq "percpu raw" "$(percpu_from_json <<<"$raw")" "2 257"
expect_eq "percpu raw ints" "$(percpu_from_json <<<'[{"key":[3,0,0,0],"values":[{"cpu":0,"value":[9,0,0,0,0,0,0,0]}]}]')" "3 9"
for bad in '[{"formatted":{"key":0}}]' '[{"key":[0,0,0,0]}]' '{"a":1}' 'x' '[{"formatted":{"key":0,"values":[]}}]'; do
  rc=0
  percpu_from_json <<<"$bad" >/dev/null 2>&1 || rc=$?
  expect_eq "percpu bad shape rc [$bad]" "$rc" 2
done

expect_eq "kv" "$(kv 'total=2 ours=1 ids=41' ours)" 1
rc=0
kv 'a=1' b >/dev/null || rc=$?
expect_eq "kv missing" "$rc" 1

flags_capture_ok 0x1183 || fail "live flags 0x1183"
if flags_capture_ok 0x1003; then fail "no promisc"; fi
if flags_capture_ok 0x1103; then fail "no noarp"; fi
if flags_capture_ok 0x1182; then fail "not up"; fi
if flags_capture_ok zz; then fail "bad flags"; fi

# IRQ snapshot, sort order and capture-core membership against fixture files.
mk_irq_fixture() { # dir
  local d=$1 q irq cpu
  mkdir -p "$d"
  : > "$d/interrupts"
  printf '%s\n' "           CPU0       CPU1" >> "$d/interrupts"
  printf '%s\n' " 187:   0  0  IR-PCI-MSIX-0000:01:00.0   0-edge      ice-0000:01:00.0:misc" >> "$d/interrupts"
  for q in 10 11 0 1 2 3 4 5 6 7 8 9; do
    irq=$((189 + q))
    printf ' %s:   0  0  IR-PCI-MSIX-0000:01:00.0   %s-edge      ice-eno1np0-TxRx-%s\n' "$irq" "$q" "$q" >> "$d/interrupts"
    mkdir -p "$d/irq/$irq"
    cpu=$((q % 4 + 1))
    echo "$cpu" > "$d/irq/$irq/smp_affinity_list"
    echo "$cpu" > "$d/irq/$irq/effective_affinity_list"
  done
  printf ' 201:   0  0  IR-PCI-MSIX-0000:01:00.0   0-edge      ice-0000:01:00.0:ctrl-TxRx-0\n' >> "$d/interrupts"
  printf ' 217:   0  0  IR-PCI-MSIX-0000:01:00.0   0-edge      irdma-0000:01:00.0:comp\n' >> "$d/interrupts"
}
mk_irq_fixture "$TMP/p1"
PROC_ROOT=$TMP/p1
CORES=$ROOT/etc/johnny/capture-cores
load_cores || fail "load_cores on the repo mirror"
expect_eq "cores list" "${CORES_LIST[*]}" "1 2 3 4"
snap=$(irq_snapshot)
expect_eq "snapshot lines" "$(grep -c '^IRQ-SNAP' <<<"$snap")" 12
expect_eq "snapshot first" "$(head -1 <<<"$snap")" "IRQ-SNAP ice-eno1np0-TxRx-0 aff=1 eff=1 irq=189"
expect_eq "snapshot numeric sort" "$(sed -n 11p <<<"$snap" | awk '{print $2}')" "ice-eno1np0-TxRx-10"
expect_eq "snapshot last" "$(tail -1 <<<"$snap" | awk '{print $2}')" "ice-eno1np0-TxRx-11"
irq_in_cores <<<"$(irq_norm <<<"$snap")" || fail "baseline fixture is in cores"
norm=$(irq_norm <<<"$snap")
lacks "irq_norm drops irq number" "$norm" "irq="
echo 0 > "$TMP/p1/irq/191/effective_affinity_list"
if irq_in_cores <<<"$(irq_snapshot | irq_norm)"; then fail "eff outside cores accepted"; fi
echo 3 > "$TMP/p1/irq/191/effective_affinity_list"
echo 1,2 > "$TMP/p1/irq/191/smp_affinity_list"
if irq_in_cores <<<"$(irq_snapshot | irq_norm)"; then fail "multi-cpu affinity accepted"; fi
echo 3 > "$TMP/p1/irq/191/smp_affinity_list"
irq_in_cores <<<"$(irq_snapshot | irq_norm)" || fail "restored fixture"
rm "$TMP/p1/irq/191/effective_affinity_list"
expect_eq "missing effective" "$(irq_snapshot | grep 'TxRx-2 ' | awk '{print $4}')" "eff=missing"
if irq_in_cores <<<"$(irq_snapshot | irq_norm)"; then fail "missing eff accepted"; fi
mk_irq_fixture "$TMP/p2"
sed -i '/TxRx-7$/d' "$TMP/p2/interrupts"
PROC_ROOT=$TMP/p2
if irq_in_cores <<<"$(irq_snapshot | irq_norm)"; then fail "11 queues accepted"; fi
PROC_ROOT=/proc

within=1
# within_tol lives in the attach script; source it after the detach script.
# shellcheck source=/dev/null
source "$ATTACH"
within_tol 0 0 || within=0
within_tol 256 0 || within=0
within_tol -256 0 || within=0
if within_tol 257 0; then within=0; fi
within_tol 9999 1000000 || within=0
if within_tol 10001 1000000; then within=0; fi
if within_tol x 10; then within=0; fi
expect_eq "within_tol cases" "$within" 1

owner_ok /nonexistent && fail "owner_ok accepts missing file"
expect_eq "owner_ok rejects a non-root file" "$(owner_ok "$SELF" && echo accepted || echo refused)" refused
echo UNIT-TESTS-OK

# ---------------------------------------------------------------- gates on this host

out=$(bash "$ATTACH" attach 2>&1 || true)
expect_eq "attach on rock-box first line" "$(head -1 <<<"$out")" "STOP-host"
has "attach on rock-box ends STOPS" "$out" "M1S1B-ATTACH-STOPS"
has "attach on rock-box changed nothing" "$out" "NOTHING-CHANGED"
lacks "attach on rock-box never says DONE" "$out" "M1S1B-ATTACH-DONE"
out=$(bash "$ATTACH" bogus 2>&1 || true)
expect_eq "attach bad arg" "$(head -1 <<<"$out")" "STOP-args"
out=$(bash "$DETACH" status 2>&1 || true)
expect_eq "detach status on rock-box" "$(head -1 <<<"$out")" "STOP-host"
out=$(bash "$DETACH" detach 2>&1 || true)
expect_eq "detach on rock-box" "$(head -1 <<<"$out")" "STOP-host"
out=$(bash "$DETACH" bogus 2>&1 || true)
expect_eq "detach bad arg" "$(head -1 <<<"$out")" "STOP-args"
[ ! -e /root/m1s1b ] || fail "gate test created /root/m1s1b"
echo GATES-OK

# ---------------------------------------------------------------- sandbox "Johnny"

mk_sandbox() { # dir
  local sb=$1 q irq cpu
  mkdir -p "$sb/bin" "$sb/st" "$sb/state" "$sb/pins_parent" "$sb/sys/class/net/eno1np0/statistics" "$sb/proc"
  mk_irq_fixture "$sb/proc"
  cp "$ROOT/etc/johnny/capture-cores" "$sb/cores"
  cp "$OBJ" "$sb/state/module1-xdp-observe.o"
  cp "$DETACH" "$sb/state/module1-slice1b-detach.sh"
  printf '0x1183\n' > "$sb/sys/class/net/eno1np0/flags"
  printf '10000\n' > "$sb/sys/class/net/eno1np0/speed"
  printf '1\n' > "$sb/sys/class/net/eno1np0/carrier"
  printf 'up\n' > "$sb/sys/class/net/eno1np0/operstate"
  printf '1500\n' > "$sb/sys/class/net/eno1np0/mtu"
  printf '1000\n' > "$sb/sys/class/net/eno1np0/statistics/rx_packets"
  printf '0\n' > "$sb/sys/class/net/eno1np0/statistics/rx_dropped"
  mkdir -p "$sb/irq-orig"
  for q in 0 1 2 3 4 5 6 7 8 9 10 11; do
    irq=$((189 + q))
    cpu=$((q % 4 + 1))
    echo "$cpu" > "$sb/irq-orig/$irq"
  done
  cat > "$sb/helper.sh" <<EOF
#!/bin/bash
echo "helper \$*" >> "$sb/calls.log"
for f in "$sb"/irq-orig/*; do
  n=\$(basename "\$f")
  cp "\$f" "$sb/proc/irq/\$n/smp_affinity_list"
  cp "\$f" "$sb/proc/irq/\$n/effective_affinity_list"
done
echo PIN-OK
EOF
  chmod +x "$sb/helper.sh"
  : > "$sb/calls.log"
  cat > "$sb/scen" <<'EOF'
LOAD_FAIL=0
ATTACH_FAIL=0
DETACH_FAIL=0
ATTACH_MODE="driver"
IRQ_MOVE_ON_ATTACH=0
FLAGS_AFTER_ATTACH=""
COMBINED_AFTER_ATTACH=""
PRE_XDP=0
BASE_TD=400
OBS_TD=950
XDP_ADD=1000
NIC_ADD=1000
TCPDUMP_FAIL=0
KILL_PARENT=0
PART_BREAK=0
ZERO_COUNT=0
TCPDUMP_FAIL_ATTACHED=0
EOF
  # ---- shims
  cat > "$sb/bin/bpftool" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
sb = os.environ["M1S1B_SB"]
st = sb + "/st"
S = {}
exec(open(sb + "/scen").read(), S)
args = sys.argv[1:]
with open(sb + "/calls.log", "a") as f:
    f.write("bpftool " + " ".join(args) + "\n")
def rd(name, default=""):
    try:
        return open(st + "/" + name).read().strip()
    except OSError:
        return default
def wr(name, v):
    with open(st + "/" + name, "w") as f:
        f.write(str(v))
def unexpected():
    with open(sb + "/calls.log", "a") as f:
        f.write("UNEXPECTED bpftool " + " ".join(args) + "\n")
    sys.stderr.write("shim: unexpected bpftool call\n")
    sys.exit(99)
pins = sb + "/pins"
ours_id = 41
def ours_loaded():
    return os.path.exists(pins + "/prog") or rd("attached_id") == str(ours_id)
def stats():
    try:
        return json.load(open(st + "/stats.json"))
    except OSError:
        return [0] * 12
def rxq():
    try:
        return json.load(open(st + "/rxq.json"))
    except OSError:
        return [0] * 64
if args == ["-j", "net", "show", "dev", "eno1np0"]:
    mode = rd("attached", "none")
    xdp = [] if mode == "none" else [{"devname": "eno1np0", "ifindex": 3, "mode": mode, "id": int(rd("attached_id", "0"))}]
    print(json.dumps([{"xdp": xdp, "tc": [], "flow_dissector": [], "netfilter": []}]))
elif args == ["-j", "prog", "show"]:
    progs = [{"id": 3, "type": "cgroup_device", "name": "sd_devices", "map_ids": []}]
    if os.path.exists(st + "/foreign"):
        progs.append({"id": 99, "type": "xdp", "name": "other_xdp", "map_ids": [1]})
    if ours_loaded():
        progs.append({"id": ours_id, "type": "xdp", "name": "j_xdp_observe", "tag": "0123456789abcdef", "map_ids": [7, 8]})
    print(json.dumps(progs))
elif len(args) == 6 and args[:2] == ["prog", "load"] and args[4] == "pinmaps":
    obj, path, d = args[2], args[3], args[5]
    if S["LOAD_FAIL"]:
        sys.stderr.write("libbpf: prog 'j_xdp_observe': failed to load: -13\n")
        sys.exit(1)
    if not os.path.isfile(obj) or not os.path.isdir(d):
        sys.stderr.write("shim: bad load args\n")
        sys.exit(1)
    for p in (path, d + "/m1_stats", d + "/m1_rxq"):
        open(p, "w").close()
    wr("stats.json", json.dumps([0] * 12))
    wr("rxq.json", json.dumps([0] * 64))
elif args == ["net", "attach", "xdpdrv", "pinned", pins + "/prog", "dev", "eno1np0"]:
    if S["ATTACH_FAIL"] or rd("attached", "none") != "none":
        sys.stderr.write("Error: attach failed\n")
        sys.exit(1)
    wr("attached", S["ATTACH_MODE"])
    wr("attached_id", ours_id)
    if S["IRQ_MOVE_ON_ATTACH"]:
        for n in range(189, 201):
            for name in ("smp_affinity_list", "effective_affinity_list"):
                with open(sb + "/proc/irq/%d/%s" % (n, name), "w") as f:
                    f.write("0\n")
    if S["FLAGS_AFTER_ATTACH"]:
        with open(sb + "/sys/class/net/eno1np0/flags", "w") as f:
            f.write(S["FLAGS_AFTER_ATTACH"] + "\n")
elif len(args) == 5 and args[:2] == ["net", "detach"] and args[2] in ("xdpdrv", "xdpgeneric", "xdpoffload") and args[3:] == ["dev", "eno1np0"]:
    if S["DETACH_FAIL"] or rd("attached", "none") == "none":
        sys.stderr.write("Error: detach failed\n")
        sys.exit(1)
    wr("attached", "none")
    wr("attached_id", "")
elif len(args) == 5 and args[:4] == ["-j", "map", "dump", "pinned"]:
    p = args[4]
    if not os.path.exists(p):
        sys.stderr.write("Error: bad path\n")
        sys.exit(1)
    if p == pins + "/m1_stats":
        vals = stats()
    elif p == pins + "/m1_rxq":
        vals = rxq()
    else:
        unexpected()
    out = []
    for i, v in enumerate(vals):
        per = [v // 2, v - v // 2, 0]
        raw = [{"cpu": c, "value": ["0x%02x" % ((x >> (8 * b)) & 0xFF) for b in range(8)]} for c, x in enumerate(per)]
        fmt = {"key": i, "values": [{"cpu": c, "value": x} for c, x in enumerate(per)]}
        out.append({"key": ["0x%02x" % i, "0x00", "0x00", "0x00"], "values": raw, "formatted": fmt})
    print(json.dumps(out))
else:
    unexpected()
EOF
  cat > "$sb/bin/tcpdump" <<'EOF'
#!/usr/bin/env python3
import json, os, signal, sys, time
sb = os.environ["M1S1B_SB"]
st = sb + "/st"
S = {}
exec(open(sb + "/scen").read(), S)
args = sys.argv[1:]
with open(sb + "/calls.log", "a") as f:
    f.write("tcpdump " + " ".join(args) + "\n")
if args != ["-p", "-nn", "-i", "eno1np0", "-w", "/dev/null"]:
    with open(sb + "/calls.log", "a") as f:
        f.write("UNEXPECTED tcpdump " + " ".join(args) + "\n")
    sys.exit(99)
def rd(name, default=""):
    try:
        return open(st + "/" + name).read().strip()
    except OSError:
        return default
attached = rd("attached", "none") != "none" and rd("attached_id") == "41"
if S["TCPDUMP_FAIL"] or (attached and S["TCPDUMP_FAIL_ATTACHED"]):
    sys.stderr.write("tcpdump: eno1np0: No such device exists\n")
    sys.exit(1)
captured = S["OBS_TD"] if attached else S["BASE_TD"]
p = sb + "/sys/class/net/eno1np0/statistics/rx_packets"
n = int(open(p).read().strip()) + S["NIC_ADD"]
open(p, "w").write("%d\n" % n)
if attached and not S["ZERO_COUNT"]:
    x = S["XDP_ADD"]
    s = json.load(open(st + "/stats.json"))
    v4, v6, arp = x * 8 // 10, x // 10, x // 20
    oth = x - v4 - v6 - arp
    ip = v4 + v6
    tcp, udp, icmp = ip * 5 // 10, ip * 3 // 10, ip // 10
    l4o = ip - tcp - udp - icmp
    add = [x, x * 100, v4, v6, arp, oth, 0, 0, tcp, udp, icmp, l4o]
    if S["PART_BREAK"]:
        add[0] += 5000
    s = [a + b for a, b in zip(s, add)]
    json.dump(s, open(st + "/stats.json", "w"))
    q = json.load(open(st + "/rxq.json"))
    q[0] += x // 2
    q[1] += x - x // 2
    json.dump(q, open(st + "/rxq.json", "w"))
if attached and S["KILL_PARENT"]:
    os.kill(int(open(sb + "/driver.pid").read()), signal.SIGTERM)
    time.sleep(2)
sys.stderr.write("tcpdump: listening on eno1np0, link-type EN10MB (Ethernet), snapshot length 262144 bytes\n")
sys.stderr.write("%d packets captured\n%d packets received by filter\n0 packets dropped by kernel\n" % (captured, captured))
EOF
  cat > "$sb/bin/ip" <<'EOF'
#!/bin/bash
echo "ip $*" >> "$M1S1B_SB/calls.log"
case "$*" in
  "-4 -o addr show dev eno1np0" | "-6 -o addr show dev eno1np0") ;;
  "-4 -o addr show dev eno3") echo "2: eno3    inet 192.168.50.152/24 brd 192.168.50.255 scope global dynamic eno3" ;;
  "-4 route show default") echo "default via 192.168.50.1 dev eno3 proto dhcp src 192.168.50.152 metric 100" ;;
  *)
    echo "UNEXPECTED ip $*" >> "$M1S1B_SB/calls.log"
    exit 99
    ;;
esac
EOF
  cat > "$sb/bin/ethtool" <<'EOF'
#!/bin/bash
echo "ethtool $*" >> "$M1S1B_SB/calls.log"
. "$M1S1B_SB/scen"
if [ "$*" != "-l eno1np0" ]; then
  echo "UNEXPECTED ethtool $*" >> "$M1S1B_SB/calls.log"
  exit 99
fi
n=12
att=$(cat "$M1S1B_SB/st/attached" 2>/dev/null || echo none)
if [ "$att" != none ] && [ -n "$COMBINED_AFTER_ATTACH" ]; then
  n=$COMBINED_AFTER_ATTACH
fi
cat <<OUT
Channel parameters for eno1np0:
Pre-set maximums:
RX:		n/a
TX:		n/a
Other:		1
Combined:	24
Current hardware settings:
RX:		n/a
TX:		n/a
Other:		1
Combined:	$n
OUT
EOF
  cat > "$sb/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >> "$M1S1B_SB/calls.log"
case "$*" in
  "is-enabled suricata") echo disabled; exit 1 ;;
  "is-active suricata") echo inactive; exit 3 ;;
  "is-active johnny-capture-irq.service" | "is-active johnny-capture-tuning.service") echo active ;;
  *)
    echo "UNEXPECTED systemctl $*" >> "$M1S1B_SB/calls.log"
    exit 99
    ;;
esac
EOF
  cat > "$sb/bin/journalctl" <<'EOF'
#!/bin/bash
echo "journalctl $*" >> "$M1S1B_SB/calls.log"
echo "Nov 06 12:00:00 johnny kernel: ice 0000:01:00.0 eno1np0: NIC Link is Up 10 Gbps Full Duplex"
echo "Nov 06 12:00:00 johnny kernel: usb 1-1: new device"
EOF
  cat > "$sb/bin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$sb/bin/timeout" <<'EOF'
#!/bin/bash
# timeout -s INT SECS cmd...
shift 3
exec "$@"
EOF
  chmod +x "$sb"/bin/*
  # ---- wrappers
  cat > "$sb/run-detach.sh" <<EOF
#!/bin/bash
export M1S1B_SB="$sb"
source "$DETACH"
SYSFS_NET="$sb/sys/class/net"
PROC_ROOT="$sb/proc"
STATE_DIR="$sb/state"
PIN_DIR="$sb/pins"
CORES="$sb/cores"
HELPER="$sb/helper.sh"
HELPER_SHA256=\$(sha256sum "$sb/helper.sh" | awk '{print \$1}')
LOCK_FILE="$sb/lock"
SAFE_PATH="$sb/bin:/usr/bin:/bin"
WAIT_STEP=0
WAIT_TRIES=2
gates() { [ -d "\$SYSFS_NET/\$IFACE" ] || { echo STOP-no-iface; return 1; }; }
main "\$@"
EOF
  cat > "$sb/run-attach.sh" <<EOF
#!/bin/bash
export M1S1B_SB="$sb"
source "$ATTACH"
SYSFS_NET="$sb/sys/class/net"
STATE_DIR="$sb/state"
PIN_DIR="$sb/pins"
LOCK_FILE="$sb/lock"
SAFE_PATH="$sb/bin:/usr/bin:/bin"
HELPER="$sb/helper.sh"
HELPER_SHA256=\$(sha256sum "$sb/helper.sh" | awk '{print \$1}')
WAIT_STEP=0
WAIT_TRIES=3
FLUSH_WAIT=0
gate_host() { :; }
start_log() { :; }
OWNER_REAL=\${OWNER_REAL:-0}
if [ "\$OWNER_REAL" != 1 ]; then owner_ok() { [ -f "\$1" ] && [ ! -L "\$1" ]; }; fi
run_detach() { M1S1B_LOCKED=1 bash "$sb/run-detach.sh" "\$@"; }
echo \$\$ > "$sb/driver.pid"
main "\$@"
EOF
  chmod +x "$sb/run-detach.sh" "$sb/run-attach.sh"
}

# set_scen DIR NAME=VALUE ...   (appends; last assignment wins in bash and python)
set_scen() {
  local sb=$1
  shift
  local kv
  for kv in "$@"; do
    printf '%s\n' "$kv" >> "$sb/scen"
  done
}

scenario() { # name -> sets SB, fresh sandbox
  SB=$TMP/sb-$1
  mk_sandbox "$SB"
  echo none > "$SB/st/attached"
}

run_a() { # runs attach driver, sets OUT and RC
  RC=0
  OUT=$(bash "$SB/run-attach.sh" attach 2>&1) || RC=$?
}

run_d() { # runs detach wrapper with the given mode
  RC=0
  OUT=$(M1S1B_LOCKED=1 bash "$SB/run-detach.sh" "$1" 2>&1) || RC=$?
}

calls() { cat "$SB/calls.log"; }

assert_clean_calls() {
  lacks "$1: unexpected tool call" "$(calls)" "UNEXPECTED"
  lacks "$1: generic or plain xdp attach" "$(grep -E 'net attach' "$SB/calls.log" || true)" "xdpgeneric"
  lacks "$1: plain xdp attach" "$(grep -E 'net attach xdp ' "$SB/calls.log" || true)" "net attach xdp "
}

# ---- 1. happy path, then detach, then detach again
scenario happy
run_a
expect_eq "happy rc" "$RC" 0
has "happy token" "$OUT" "M1S1B-ATTACH-DONE"
has "happy start" "$OUT" "M1S1B-ATTACH-START"
has "happy object hash" "$OUT" "OK-object-hash $OBJ_SHA"
has "happy rollback hash" "$OUT" "OK-rollback-hash $DETACH_SHA"
has "happy baseline window" "$OUT" "BASE-WINDOW secs=5 tcpdump-captured=400 nic-rx-delta=1000"
has "happy loaded" "$OUT" "LOADED prog_id=41"
has "happy readback parse" "$OUT" "OK-readback-parse"
has "happy attached" "$OUT" "ATTACHED xdpdrv prog_id=41"
has "happy mode" "$OUT" "OK-xdp-mode driver id=41 (just-attached)"
has "happy mode after window" "$OUT" "OK-xdp-mode driver id=41 (after-window)"
has "happy irq unchanged" "$OUT" "OK-irq-pins-unchanged (after-window)"
has "happy window" "$OUT" "OBS-WINDOW secs=10 xdp-pkts-delta=1000 xdp-pps=100 xdp-avg-bytes=100 tcpdump-captured=950 nic-rx-delta=1000"
has "happy pass ratio" "$OUT" "PASS-RATIO tcpdump=950 xdp=1000 pct=95"
has "happy pass" "$OUT" "OK-xdp-pass-tcpdump-sees-traffic"
has "happy partition" "$OUT" "OK-partition l3_diff=0 l4_diff=0"
has "happy irq before" "$OUT" "IRQ-BEFORE ice-eno1np0-TxRx-0 aff=1 eff=1 irq=189"
has "happy irq after" "$OUT" "IRQ-AFTER ice-eno1np0-TxRx-11 aff=4 eff=4 irq=200"
expect_eq "happy irq before count" "$(grep -c '^IRQ-BEFORE' <<<"$OUT")" 12
expect_eq "happy irq after count" "$(grep -c '^IRQ-AFTER' <<<"$OUT")" 12
has "happy stat pkts" "$OUT" "STAT pkts 1000"
has "happy stat tcp" "$OUT" "STAT tcp 450"
has "happy rxq" "$OUT" "STAT-RXQ 0 500"
has "happy xdp count" "$OUT" "PROG-XDP-COUNT 1"
has "happy detach hint" "$OUT" "Detach: sudo bash"
lacks "happy no stop" "$OUT" "STOP-"
lacks "happy no revert" "$OUT" "REVERTING"
lacks "happy no STOPS token" "$OUT" "M1S1B-ATTACH-STOPS"
assert_clean_calls happy
expect_eq "happy one load" "$(grep -c '^bpftool prog load' "$SB/calls.log")" 1
expect_eq "happy one attach" "$(grep -c '^bpftool net attach xdpdrv pinned' "$SB/calls.log")" 1
expect_eq "happy no detach yet" "$(grep -c '^bpftool net detach' "$SB/calls.log" || true)" 0
expect_eq "happy no helper run" "$(grep -c '^helper' "$SB/calls.log" || true)" 0
[ -e "$SB/pins/prog" ] && [ -e "$SB/pins/m1_stats" ] && [ -e "$SB/pins/m1_rxq" ] || fail "happy: pins missing"
[ -s "$SB/state/irq-baseline.txt" ] || fail "happy: baseline file missing"
expect_eq "happy baseline lines" "$(grep -c '^IRQ-SNAP' "$SB/state/irq-baseline.txt")" 12

run_d status
expect_eq "status rc" "$RC" 0
has "status token" "$OUT" "M1S1B-STATUS-DONE"
has "status attach" "$OUT" "XDP-ATTACH driver id=41"
has "status ours" "$OUT" "PROG-OURS 1 ids=41"
has "status pins" "$OUT" "PINS dir=present prog=present stats=present rxq=present"
has "status irq" "$OUT" "IRQ-CAPTURE ok"
has "status baseline" "$OUT" "IRQ-BASELINE same"
has "status link" "$OUT" "LINK eno1np0 flags=0x1183 speed=10000 carrier=1 oper=up mtu=1500"

run_d detach
expect_eq "detach rc" "$RC" 0
has "detach token" "$OUT" "M1S1B-DETACH-DONE"
has "detach attached" "$OUT" "DETACHED mode=driver id=41"
has "detach no xdp" "$OUT" "OK-no-xdp-on-eno1np0"
has "detach final stat" "$OUT" "FINAL pkts 1000"
has "detach frozen" "$OUT" "OK-counters-frozen pkts=1000"
has "detach exact partition" "$OUT" "FINAL-PARTITION-OK"
has "detach pins removed" "$OUT" "PINS-REMOVED"
has "detach prog gone" "$OUT" "OK-no-j_xdp_observe-loaded"
has "detach prog count" "$OUT" "PROG-XDP-COUNT 0"
has "detach irq" "$OUT" "IRQ-PINS-OK (matches the attach baseline)"
lacks "detach no stop" "$OUT" "STOP-"
[ ! -e "$SB/pins" ] || fail "detach: pin dir still there"
[ ! -e "$SB/state/irq-baseline.txt" ] || fail "detach: baseline not removed after a clean detach"
expect_eq "detach used native keyword" "$(grep -c '^bpftool net detach xdpdrv dev eno1np0' "$SB/calls.log")" 1
expect_eq "no helper run on clean detach" "$(grep -c '^helper' "$SB/calls.log" || true)" 0

run_d detach
expect_eq "second detach rc" "$RC" 0
has "second detach nothing" "$OUT" "NOTHING-ATTACHED"
has "second detach token" "$OUT" "M1S1B-DETACH-DONE"
has "second detach no final stats" "$OUT" "NOTE-no-final-stats"
has "second detach pins absent" "$OUT" "PINS-ABSENT"
has "second detach irq w/o baseline" "$OUT" "IRQ-PINS-OK (inside capture cores; no attach baseline file)"
assert_clean_calls happy

# ---- 2. pre-existing foreign XDP: attach refuses; detach refuses to touch it
scenario foreign
set_scen "$SB" PRE_XDP=1
echo driver > "$SB/st/attached"
echo 99 > "$SB/st/attached_id"
touch "$SB/st/foreign"
run_a
expect_eq "foreign attach rc" "$RC" 1
has "foreign attach stop" "$OUT" "STOP-xdp-already-attached: XDP-ATTACH driver id=99"
has "foreign nothing changed" "$OUT" "NOTHING-CHANGED"
has "foreign STOPS" "$OUT" "M1S1B-ATTACH-STOPS"
lacks "foreign no revert" "$OUT" "REVERTING"
expect_eq "foreign: no load/attach/detach" "$(grep -cE '^bpftool (prog load|net attach|net detach)' "$SB/calls.log" || true)" 0
[ ! -e "$SB/pins" ] || fail "foreign: pin dir created"
run_d detach
expect_eq "foreign detach rc" "$RC" 1
has "foreign detach refuses" "$OUT" "STOP-xdp-foreign mode=driver id=99"
has "foreign detach token" "$OUT" "M1S1B-DETACH-STOPS"
expect_eq "foreign: detach never called" "$(grep -c '^bpftool net detach' "$SB/calls.log" || true)" 0

# ---- 3. other pre-attach refusals (each must change nothing)
refuse() { # scenario-name expected-stop-text setup-command...
  local name=$1 want=$2
  shift 2
  scenario "$name"
  "$@"
  run_a
  expect_eq "$name rc" "$RC" 1
  has "$name stop" "$OUT" "$want"
  has "$name token" "$OUT" "M1S1B-ATTACH-STOPS"
  has "$name nothing changed" "$OUT" "NOTHING-CHANGED"
  lacks "$name no revert" "$OUT" "REVERTING"
  lacks "$name no DONE" "$OUT" "M1S1B-ATTACH-DONE"
  expect_eq "$name: no load/attach/detach" "$(grep -cE '^bpftool (prog load|net attach|net detach)' "$SB/calls.log" || true)" 0
  [ "$name" = pins ] || [ ! -e "$SB/pins" ] || fail "$name: pin dir created"
  assert_clean_calls "$name"
}
setup_pins() { mkdir -p "$SB/pins"; }
setup_nopromisc() { printf '0x1003\n' > "$SB/sys/class/net/eno1np0/flags"; }
setup_mtu() { printf '9000\n' > "$SB/sys/class/net/eno1np0/mtu"; }
setup_speed() { printf '1000\n' > "$SB/sys/class/net/eno1np0/speed"; }
setup_irq_outside() { echo 0 > "$SB/proc/irq/195/effective_affinity_list"; }
setup_irq_count() { sed -i '/TxRx-7$/d' "$SB/proc/interrupts"; }
setup_no_rollback() { rm -f "$SB/state/module1-slice1b-detach.sh"; }
setup_bad_detach() { echo '# tampered' >> "$SB/state/module1-slice1b-detach.sh"; }
setup_bad_obj() { echo x >> "$SB/state/module1-xdp-observe.o"; }
setup_quiet_span() { set_scen "$SB" BASE_TD=0; }
setup_tcpdump_fail() { set_scen "$SB" TCPDUMP_FAIL=1; }
setup_cores_bad() { echo 9 >> "$SB/cores"; }
refuse pins "STOP-pins-exist: PINS dir=present" setup_pins
refuse nopromisc "STOP-eno1-flags 0x1003" setup_nopromisc
refuse mtu "STOP-mtu-not-1500 9000" setup_mtu
refuse speed "STOP-eno1-speed 1000" setup_speed
refuse irqout "STOP-irq-baseline-outside-capture-cores" setup_irq_outside
refuse irqcount "STOP-irq-count: IRQ-COUNT 11" setup_irq_count
refuse norollback "STOP-no-rollback-installed" setup_no_rollback
refuse baddetach "STOP-rollback-hash" setup_bad_detach
refuse badobj "STOP-object-hash" setup_bad_obj
refuse quiet "STOP-no-traffic-baseline" setup_quiet_span
refuse tdfail "STOP-tcpdump-baseline-failed" setup_tcpdump_fail
refuse corebad "STOP-irq-count:" setup_cores_bad
# the same files owned by a non-root user are refused (real owner_ok)
scenario owner
RC=0
OUT=$(OWNER_REAL=1 bash "$SB/run-attach.sh" attach 2>&1) || RC=$?
expect_eq "owner rc" "$RC" 1
has "owner stop" "$OUT" "STOP-object-not-root-owned-or-missing"
has "owner nothing changed" "$OUT" "NOTHING-CHANGED"

# ---- 4. failures after the first change: rollback must run and finish clean
rollback_case() { # name expected-stop-text [expect-revert-clean yes|no] setup...
  local name=$1 want=$2 clean=$3
  shift 3
  scenario "$name"
  "$@"
  run_a
  expect_eq "$name rc" "$RC" 1
  has "$name stop" "$OUT" "$want"
  has "$name reverting" "$OUT" "REVERTING"
  has "$name STOPS token" "$OUT" "M1S1B-ATTACH-STOPS"
  lacks "$name never DONE" "$OUT" "M1S1B-ATTACH-DONE"
  if [ "$clean" = yes ]; then
    has "$name rollback done" "$OUT" "M1S1B-DETACH-DONE"
    [ ! -e "$SB/pins" ] || fail "$name: pins left after rollback"
    expect_eq "$name: nothing attached after rollback" "$(cat "$SB/st/attached")" none
  fi
  assert_clean_calls "$name"
}
setup_load_fail() { set_scen "$SB" LOAD_FAIL=1; }
setup_attach_fail() { set_scen "$SB" ATTACH_FAIL=1; }
setup_generic() { set_scen "$SB" 'ATTACH_MODE="generic"'; }
setup_irq_move() { set_scen "$SB" IRQ_MOVE_ON_ATTACH=1; }
setup_queues() { set_scen "$SB" COMBINED_AFTER_ATTACH=8; }
setup_td_zero() { set_scen "$SB" OBS_TD=0; }
setup_no_count() { set_scen "$SB" ZERO_COUNT=1; }
setup_part() { set_scen "$SB" PART_BREAK=1 XDP_ADD=100; }
setup_td_fail_attached() { set_scen "$SB" TCPDUMP_FAIL_ATTACHED=1; }
rollback_case loadfail "STOP-load (verifier or bpftool refused" yes setup_load_fail
has "loadfail tried the load" "$(cat "$SB/calls.log")" "bpftool prog load"
lacks "loadfail never attached" "$(cat "$SB/calls.log")" "net attach"
rollback_case attachfail "STOP-attach (native xdpdrv refused; no generic fallback by design)" yes setup_attach_fail
has "attachfail kernel log shown" "$OUT" "KLOG> "
expect_eq "attachfail: one attach try only" "$(grep -c '^bpftool net attach' "$SB/calls.log")" 1
rollback_case generic "STOP-xdp-mode-or-id-just-attached" yes setup_generic
has "generic rollback uses the mode's own keyword" "$(cat "$SB/calls.log")" "bpftool net detach xdpgeneric dev eno1np0"
has "generic rollback notes mode" "$OUT" "NOTE-xdp-mode-not-driver generic"
rollback_case irqmove "STOP-irq-pins-moved-just-attached" yes setup_irq_move
has "irqmove names recovery" "$OUT" "recovery: sudo $SB/helper.sh apply"
has "irqmove disturbed note" "$OUT" "NOTE-irq-pins-disturbed"
has "irqmove helper ran" "$OUT" "HELPER> PIN-OK"
has "irqmove restored" "$OUT" "IRQ-PINS-RESTORED"
expect_eq "irqmove: helper run once" "$(grep -c '^helper apply' "$SB/calls.log")" 1
rollback_case queues "STOP-queues-changed-just-attached before=12 after=8" yes setup_queues
rollback_case pass_broken "STOP-pass-broken" yes setup_td_zero
rollback_case nocount "STOP-observer-no-count" yes setup_no_count
rollback_case partition "STOP-partition-l3" yes setup_part
rollback_case tdfail_att "STOP-tcpdump-failed-while-attached" yes setup_td_fail_attached

# rollback that cannot complete says so and gives the manual command
setup_flags_lost() { set_scen "$SB" 'FLAGS_AFTER_ATTACH="0x1003"'; }
rollback_case flagslost "STOP-eno1-flags-just-attached 0x1003" no setup_flags_lost
has "flagslost detach still ran" "$OUT" "DETACHED mode=driver id=41"
has "flagslost detach flags stop" "$OUT" "STOP-eno1-flags 0x1003"
has "flagslost detach STOPS" "$OUT" "M1S1B-DETACH-STOPS"
has "flagslost manual command" "$OUT" "STOP-rollback-failed. Run: sudo bash"
expect_eq "flagslost: xdp is nevertheless detached" "$(cat "$SB/st/attached")" none
setup_detach_fails() { set_scen "$SB" DETACH_FAIL=1 IRQ_MOVE_ON_ATTACH=1; }
rollback_case detachfail "STOP-irq-pins-moved-just-attached" no setup_detach_fails
has "detachfail reports" "$OUT" "STOP-detach-failed mode=driver id=41"
has "detachfail linger" "$OUT" "STOP-xdp-linger"
has "detachfail manual" "$OUT" "STOP-rollback-failed. Run: sudo bash"
has "detachfail reboot hint" "$OUT" "a reboot removes the attach and the pins"

# ---- 5. SIGTERM while attached: the EXIT trap rolls back
scenario term
set_scen "$SB" KILL_PARENT=1
run_a
has "term reverting" "$OUT" "REVERTING"
has "term rollback done" "$OUT" "M1S1B-DETACH-DONE"
has "term STOPS" "$OUT" "M1S1B-ATTACH-STOPS"
lacks "term never DONE" "$OUT" "M1S1B-ATTACH-DONE"
expect_eq "term rc" "$RC" 130
expect_eq "term: detached" "$(cat "$SB/st/attached")" none
[ ! -e "$SB/pins" ] || fail "term: pins left"

# ---- 6. a low pass ratio is a note, not a stop (tcpdump saw frames)
scenario lowratio
set_scen "$SB" OBS_TD=100
run_a
expect_eq "lowratio rc" "$RC" 0
has "lowratio note" "$OUT" "NOTE-pass-ratio-low pct=10"
has "lowratio done" "$OUT" "M1S1B-ATTACH-DONE"

# ---- 7. detach after a disturbed pin with no attach: helper restores baseline
scenario lateirq
run_a
expect_eq "lateirq attach rc" "$RC" 0
for n in 189 190 191; do
  echo 0 > "$SB/proc/irq/$n/smp_affinity_list"
  echo 0 > "$SB/proc/irq/$n/effective_affinity_list"
done
run_d status
has "status sees moved pins" "$OUT" "IRQ-BASELINE moved"
has "status sees outside" "$OUT" "IRQ-CAPTURE outside"
run_d detach
expect_eq "lateirq detach rc" "$RC" 0
has "lateirq restored" "$OUT" "IRQ-PINS-RESTORED"
has "lateirq done" "$OUT" "M1S1B-DETACH-DONE"

# ---- 8. counters still moving after detach is a stop (the detach did not take)
scenario moving
run_a
expect_eq "moving attach rc" "$RC" 0
cat > "$SB/bin/sleep" <<'EOF'
#!/bin/bash
# bump the stats file on every sleep, as if frames were still being counted
python3 -I - "$M1S1B_SB/st/stats.json" <<'PY'
import json, sys
p = sys.argv[1]
s = json.load(open(p))
s[0] += 1
s[2] += 1
s[8] += 1
json.dump(s, open(p, "w"))
PY
EOF
chmod +x "$SB/bin/sleep"
run_d detach
expect_eq "moving detach rc" "$RC" 1
has "moving stop" "$OUT" "STOP-counters-still-moving"
has "moving token" "$OUT" "M1S1B-DETACH-STOPS"

echo "E2E-OK scenarios=$(ls -d "$TMP"/sb-* | wc -l)"

# ---------------------------------------------------------------- runbook and cross-links

[ -f "$DOC" ] || fail "runbook missing: $DOC"
doc=$(cat "$DOC")
has "runbook status line" "$doc" "Status: **drafted, not applied.**"
for h in "$OBJ_SHA" "$ATTACH_SHA" "$DETACH_SHA" "$CSRC_SHA"; do
  has "runbook has hash $h" "$doc" "$h"
done
for tok in M1S1B-ATTACH-DONE M1S1B-ATTACH-STOPS M1S1B-DETACH-DONE M1S1B-DETACH-STOPS M1S1B-STATUS-DONE \
  M1S1B-COPY-DONE M1S1B-INSTALL-DONE SELF-TEST-OK PROGRAM-SOURCE-OK STATIC-INVOCATIONS-OK; do
  has "runbook token $tok" "$doc" "$tok"
done
has "runbook cites bpftool-net man page" "$doc" "https://man.archlinux.org/man/bpftool-net.8.en"
has "runbook labels rock box" "$doc" "***<ins>Run on Rock Box</ins>***"
has "runbook labels johnny" "$doc" "***<ins>Run on Johnny</ins>***"

python3 -I - "$DOC" "$OBJ_SHA" "$ATTACH_SHA" "$DETACH_SHA" <<'PY' || fail "runbook paste-shape check"
import re, sys
doc, obj, att, det = sys.argv[1:]
text = open(doc).read()
lines = text.split("\n")
blocks = []  # (label, body)
i = 0
label = None
while i < len(lines):
    ln = lines[i]
    if ln.startswith("***<ins>Run on Rock Box</ins>***") or ln.startswith("***<ins>Run on Johnny</ins>***"):
        label = "rock" if "Rock Box" in ln else "johnny"
    if ln.startswith("```bash"):
        j = i + 1
        body = []
        while not lines[j].startswith("```"):
            body.append(lines[j])
            j += 1
        blocks.append((label, "\n".join(body)))
        label = None
        i = j
    i += 1
def die(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)
if not blocks:
    die("no bash blocks")
def outside_quotes(body):
    """Yield each line's text outside single quotes (that is how the pastes pass a remote command)."""
    inq = False
    for ln in body.split("\n"):
        out = []
        for ch in ln:
            if ch == "'":
                inq = not inq
            elif not inq:
                out.append(ch)
        yield "".join(out)
for lab, body in blocks:
    if lab is None and "not part of the paste" not in text:
        die("bash block without a host label: " + body[:80])
    if re.search(r"<[A-Za-z_][^>\n]*>", body):
        die("placeholder in block: " + body[:80])
    for s in outside_quotes(body):
        if re.search(r"(^|[;&|(])\s*sudo\b", s.strip()):
            die("sudo run on rock-box in block: " + s)
shapes = {"rock": 0, "johnny": 0}
for lab, body in blocks:
    if lab:
        shapes[lab] += 1
    if lab == "johnny":
        if "sudo" in body and "ssh -t" not in body:
            die("johnny block uses sudo without ssh -t")
        for ln in body.split("\n"):
            if "ssh -t" in ln and "sudo" in ln and not re.search(r"'sudo -v &&", ln):
                die("ssh -t sudo line must start with sudo -v: " + ln)
    if lab == "rock":
        if "ssh -t" in body:
            die("rock block must not need sudo/tty")
if shapes["rock"] < 2 or shapes["johnny"] < 4:
    die("expected >=2 rock and >=4 johnny blocks, got %r" % shapes)
joined = "\n".join(b for _, b in blocks)
want = {"module1-xdp-observe.o": obj, "module1-slice1b-attach.sh": att, "module1-slice1b-detach.sh": det}
# Every "hash  path" pair in any paste must be the right hash for that file name.
for lab, body in blocks:
    pairs = re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body)
    for h, path in pairs:
        name = path.rsplit("/", 1)[-1]
        if name in want and want[name] != h:
            die("wrong hash for %s in a paste block: %s" % (name, h))
        if name not in want and not path.startswith("docs/"):
            die("hash for an unknown file in a paste block: " + path)
    names = {pp.rsplit("/", 1)[-1] for _, pp in pairs}
    def need(*fs):
        for f in fs:
            if f not in names:
                die("paste block runs/copies %s without its hash line:\n%s" % (f, body[:200]))
    if "module1-slice1b-attach.sh attach" in body or "scp " in body or "install -m" in body:
        need("module1-xdp-observe.o", "module1-slice1b-attach.sh", "module1-slice1b-detach.sh")
    if "module1-slice1b-detach.sh" in body and ("status" in body or "detach" in body) and lab == "johnny":
        need("module1-slice1b-detach.sh")
    if "self-test.sh" in body:
        need("module1-xdp-observe.o", "module1-slice1b-attach.sh", "module1-slice1b-detach.sh")
for name, h in want.items():
    if joined.count(h) < 2:
        die("hash for %s must appear in at least two paste blocks" % name)
for forbidden in ("xdpgeneric", "net attach xdp ", "pci=noaer", "NOPASSWD"):
    if forbidden in joined:
        die("forbidden text in a paste block: " + forbidden)
johnny_joined = "\n".join(b for l, b in blocks if l == "johnny")
for forbidden in ("apt ", "apt-get", "dpkg -i", "ip link set", "ethtool -L", "ethtool -K", "sysctl -w", "systemctl stop", "systemctl disable", "modprobe", "reboot", "netplan"):
    if forbidden in johnny_joined:
        die("forbidden text in a Johnny paste block: " + forbidden)
print("PASTE-SHAPE-OK rock=%d johnny=%d" % (shapes["rock"], shapes["johnny"]))
PY

# every johnny attach/detach/status paste re-verifies hashes before running
for need in 'sha256sum -c' '/root/m1s1b/module1-slice1b-attach.sh attach' '/root/m1s1b/module1-slice1b-detach.sh detach' \
  '/root/m1s1b/module1-slice1b-detach.sh status' '192.168.50.152'; do
  has "runbook mentions $need" "$doc" "$need"
done
has "slice1 doc links 1b" "$(cat "$SLICE1_DOC")" "module1-slice1b-attach.md"
echo RUNBOOK-OK

echo SELF-TEST-OK
