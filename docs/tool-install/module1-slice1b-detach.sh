#!/bin/bash
# Module 1 slice 1b: detach the observe-only XDP program from eno1np0, and read
# its state. Runbook: docs/tool-install/module1-slice1b-attach.md
#
#   sudo bash module1-slice1b-detach.sh detach   undo the attach (idempotent)
#   sudo bash module1-slice1b-detach.sh status   read-only state and counters
#
# Runs as root on Johnny only. The runbook installs a root-owned copy at
# /root/m1s1b/module1-slice1b-detach.sh BEFORE the attach script may run, and the
# attach script refuses to run without it (and re-checks its sha256).
#
# detach: if an XDP program is on eno1np0 and it is ours (name j_xdp_observe),
# detach it in the mode it is in; never detach a program that is not ours. Wait
# until eno1np0 shows no XDP. Read the counters one last time (they must be
# frozen once detached). Remove our bpffs pins. Wait until no j_xdp_observe
# program is loaded. If the step 13 IRQ pins moved, put them back with the pinned
# helper /etc/johnny/irq-affinity.sh apply (hash-checked). Check eno1np0 still
# has UP, PROMISC, NOARP, 10G, MTU 1500, no address, and eno3 is untouched.
# STOP lines are collected (a rollback should do every step it can). Any STOP
# withholds M1S1B-DETACH-DONE and exits 1.
#
# status: no change. Prints XDP attach mode/id, program counts, pins, IRQ pin
# snapshot, link facts and the counters. Ends M1S1B-STATUS-DONE.
#
# This script never attaches or loads a program, never changes the NIC, queues,
# MTU, offloads, sysctls, units or packages. The only writes are: detach, unlink
# of our own pins, removal of $STATE_DIR/irq-baseline.txt after a clean detach,
# and (only if the IRQ pins moved) the step 13 helper. Native only: it does not
# use `xdp` (generic fallback) to attach, and it never attaches at all.
set -uo pipefail

# Plain variables, not read from the environment. The rock-box self-test
# overrides them after sourcing.
IFACE=eno1np0
SYSFS_NET=/sys/class/net
PROC_ROOT=/proc
STATE_DIR=/root/m1s1b
PIN_DIR=/sys/fs/bpf/johnny_m1s1b
CORES=/etc/johnny/capture-cores
CORES_SHA256=16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b
HELPER=/etc/johnny/irq-affinity.sh
HELPER_SHA256=db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4
KERNEL_WANT=7.0.0-42-generic
LOCK_FILE=/run/johnny-m1s1b.lock
SAFE_PATH=/usr/sbin:/usr/bin:/sbin:/bin
PROG_NAME=j_xdp_observe
IRQ_WANT=12
WAIT_STEP=1
WAIT_TRIES=15
# Order MUST match the enum in module1_xdp_observe.c (the self-test compares).
STAT_NAMES="pkts bytes ipv4 ipv6 arp other trunc vlan tcp udp icmp l4_other"
RXQ_MAX=64
STOPS=0

stop() {
  STOPS=$((STOPS + 1))
  printf 'STOP-%s\n' "$*"
}

pin_prog() { printf '%s/prog' "$PIN_DIR"; }
pin_stats() { printf '%s/m1_stats' "$PIN_DIR"; }
pin_rxq() { printf '%s/m1_rxq' "$PIN_DIR"; }
baseline_file() { printf '%s/irq-baseline.txt' "$STATE_DIR"; }

# Empty output when the file is missing or unreadable (sysfs returns EINVAL
# for speed and carrier while the link is down).
read_trim() {
  { tr -d '[:space:]' < "$1"; } 2>/dev/null || true
}

flags_well_formed() {
  [[ $1 =~ ^(0[xX])?[0-9a-fA-F]+$ ]]
}

# UP (0x1), NOARP (0x80), PROMISC (0x100): what steps 11 and 13 left on eno1np0.
flags_capture_ok() {
  local f=$1
  flags_well_formed "$f" || return 1
  [ $((f & 1)) -ne 0 ] && [ $((f & 256)) -ne 0 ] && [ $((f & 128)) -ne 0 ]
}

# ---------------------------------------------------------------- JSON parsers
# Each reads bpftool -j output on stdin. Exit 2 on any shape it does not expect.

# "mode id" per XDP attachment on the device (id is "none" when absent).
net_xdp_from_json() {
  python3 -I -c '
import json, sys
dev = sys.argv[1]
found = []
def walk(o):
    if isinstance(o, dict):
        if o.get("devname") == dev and "mode" in o:
            found.append("%s %s" % (o["mode"], o.get("id", "none")))
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
try:
    walk(json.load(sys.stdin))
except ValueError:
    sys.exit(2)
for line in found:
    print(line)
' "$1"
}

# One line: "total=N ours=M ids=a,b" (ids of our named programs, "none" if empty).
progs_from_json() {
  python3 -I -c '
import json, sys
name = sys.argv[1]
try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(2)
if not isinstance(doc, list):
    sys.exit(2)
total = 0
ours = []
for p in doc:
    if not isinstance(p, dict):
        sys.exit(2)
    if p.get("type") == "xdp":
        total += 1
        if p.get("name") == name:
            ours.append(str(p.get("id")))
print("total=%d ours=%d ids=%s" % (total, len(ours), ",".join(ours) if ours else "none"))
' "$1"
}

# `bpftool -j map dump` of a per-CPU array: one "key total" line per entry,
# values summed over CPUs. Accepts the BTF-formatted shape and the raw-bytes
# shape. **[Assumption]** both shapes are from bpftool's documented JSON, not a
# live capture of this map; the attach script proves the parse on the real
# output BEFORE it attaches anything.
percpu_from_json() {
  python3 -I -c '
import json, sys
def le(seq):
    n = 0
    for i, b in enumerate(seq):
        if isinstance(b, str):
            b = int(b, 16) if b.lower().startswith("0x") else int(b)
        n |= (int(b) & 0xFF) << (8 * i)
    return n
def num(v):
    return v if isinstance(v, int) else le(v)
try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(2)
if not isinstance(doc, list):
    sys.exit(2)
for it in doc:
    if not isinstance(it, dict):
        sys.exit(2)
    f = it.get("formatted")
    if isinstance(f, dict):
        key, vals = f.get("key"), f.get("values")
    else:
        key, vals = it.get("key"), it.get("values")
    if key is None or not isinstance(vals, list) or not vals:
        sys.exit(2)
    key = num(key)
    total = 0
    for v in vals:
        if not isinstance(v, dict) or "value" not in v:
            sys.exit(2)
        total += num(v["value"])
    print("%d %d" % (key, total))
'
}

# ---------------------------------------------------------------- state readers

# net_attach_lines: "mode id" per attachment on $IFACE. rc 1 if bpftool or the
# parse failed (the caller says which).
net_attach_lines() {
  local js
  js=$(bpftool -j net show dev "$IFACE" 2>/dev/null) || return 1
  net_xdp_from_json "$IFACE" <<<"$js"
}

progs_summary() {
  local js
  js=$(bpftool -j prog show 2>/dev/null) || return 1
  progs_from_json "$PROG_NAME" <<<"$js"
}

# field NAME from a "k=v k=v" line
kv() {
  local line=$1 key=$2 part
  for part in $line; do
    if [ "${part%%=*}" = "$key" ]; then
      printf '%s\n' "${part#*=}"
      return 0
    fi
  done
  return 1
}

# Silent: sets CORES_LIST on success, CORES_ERR on failure.
CORES_ERR=
load_cores() {
  local sha line
  CORES_LIST=()
  CORES_ERR=
  if [ -L "$CORES" ] || [ ! -f "$CORES" ]; then
    CORES_ERR=cores-file
    return 1
  fi
  sha=$(sha256sum "$CORES" | awk '{print $1}' || true)
  if [ "$sha" != "$CORES_SHA256" ]; then
    CORES_ERR="cores-hash $sha"
    return 1
  fi
  while read -r line; do
    [ -n "$line" ] || continue
    if [[ ! $line =~ ^[0-9]+$ ]]; then
      CORES_ERR=cores-form
      return 1
    fi
    CORES_LIST+=("$line")
  done < "$CORES"
  if [ "${#CORES_LIST[@]}" -lt 1 ]; then
    CORES_ERR=cores-empty
    return 1
  fi
}

cpu_in_cores() {
  local c
  [[ $1 =~ ^[0-9]+$ ]] || return 1
  for c in "${CORES_LIST[@]}"; do
    [ "$c" = "$1" ] && return 0
  done
  return 1
}

# IRQ-SNAP lines, one per ice-eno1np0-TxRx-N vector, sorted by N, irq last.
irq_snapshot() {
  local lines irq name aff eff
  [ -r "$PROC_ROOT/interrupts" ] || return 1
  lines=$(awk '
    $1 ~ /^[0-9]+:$/ && $NF ~ /^ice-eno1np0-TxRx-[0-9]+$/ {
      irq = $1
      sub(/:$/, "", irq)
      n = $NF
      sub(/^.*-/, "", n)
      print n, irq, $NF
    }
  ' "$PROC_ROOT/interrupts" | sort -n) || return 1
  while read -r _ irq name; do
    [ -n "$irq" ] || continue
    aff=$(read_trim "$PROC_ROOT/irq/$irq/smp_affinity_list")
    [ -n "$aff" ] || aff=missing
    eff=$(read_trim "$PROC_ROOT/irq/$irq/effective_affinity_list")
    [ -n "$eff" ] || eff=missing
    printf 'IRQ-SNAP %s aff=%s eff=%s irq=%s\n' "$name" "$aff" "$eff" "$irq"
  done <<<"$lines"
}

# Same lines without the irq number: what must not change. IRQ numbers may be
# re-assigned if the driver rebuilds queues; the pin per queue name is what counts.
irq_norm() {
  sed 's/ irq=[0-9]*$//'
}

# 0 if the snapshot has IRQ_WANT lines and every aff and eff is one CPU in the
# capture cores. Reads the snapshot on stdin.
irq_in_cores() {
  local snap n=0 line a e
  snap=$(cat)
  while read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    a=$(kv "$line" aff || true)
    e=$(kv "$line" eff || true)
    cpu_in_cores "$a" || return 1
    cpu_in_cores "$e" || return 1
  done <<<"$snap"
  [ "$n" -eq "$IRQ_WANT" ]
}

link_facts() {
  L_FLAGS=$(read_trim "$SYSFS_NET/$IFACE/flags")
  L_SPEED=$(read_trim "$SYSFS_NET/$IFACE/speed")
  L_CARRIER=$(read_trim "$SYSFS_NET/$IFACE/carrier")
  L_OPER=$(read_trim "$SYSFS_NET/$IFACE/operstate")
  L_MTU=$(read_trim "$SYSFS_NET/$IFACE/mtu")
}

link_up() {
  link_facts
  [ "$L_SPEED" = 10000 ] && { [ "$L_CARRIER" = 1 ] || [ "$L_OPER" = up ]; }
}

has_address() {
  local a4 a6
  a4=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null || true)
  a6=$(ip -6 -o addr show dev "$IFACE" 2>/dev/null || true)
  [ -n "$a4" ] || [ -n "$a6" ]
}

eno3_ok() {
  local a r
  a=$(ip -4 -o addr show dev eno3 2>/dev/null || true)
  case "$a" in
    *"inet 192.168.50.152/"*) ;;
    *) return 1 ;;
  esac
  r=$(ip -4 route show default 2>/dev/null || true)
  case "$r" in
    *"dev eno3"*) return 0 ;;
    *) return 1 ;;
  esac
}

# emit_stats PREFIX: read our pinned stats and rxq maps. Prints
# "PREFIX name value" per stat, "PREFIX-RXQ q value" for non-zero queues, and
# "PART l3_diff=D l4_diff=E". rc 1 if a map is missing or a parse failed.
LAST_PKTS=
LAST_L3=
LAST_L4=
emit_stats() {
  local prefix=$1 js rows name val k t i=0
  local -a names
  LAST_PKTS=
  LAST_L3=
  LAST_L4=
  [ -e "$(pin_stats)" ] && [ -e "$(pin_rxq)" ] || return 1
  js=$(bpftool -j map dump pinned "$(pin_stats)" 2>/dev/null) || return 1
  rows=$(percpu_from_json <<<"$js") || return 1
  read -r -a names <<<"$STAT_NAMES"
  declare -A got=()
  while read -r k t; do
    [ -n "$k" ] || continue
    got[$k]=$t
  done <<<"$rows"
  for name in "${names[@]}"; do
    val=${got[$i]:-}
    [ -n "$val" ] || return 1
    printf '%s %s %s\n' "$prefix" "$name" "$val"
    i=$((i + 1))
  done
  [ "${#got[@]}" -eq "${#names[@]}" ] || return 1
  LAST_PKTS=${got[0]}
  LAST_L3=$((got[0] - got[2] - got[3] - got[4] - got[5] - got[6]))
  LAST_L4=$((got[2] + got[3] - got[8] - got[9] - got[10] - got[11]))
  printf 'PART l3_diff=%s l4_diff=%s\n' "$LAST_L3" "$LAST_L4"
  js=$(bpftool -j map dump pinned "$(pin_rxq)" 2>/dev/null) || return 1
  rows=$(percpu_from_json <<<"$js") || return 1
  while read -r k t; do
    [ -n "$k" ] || continue
    if [ "$k" -ge "$RXQ_MAX" ]; then
      return 1
    fi
    if [ "$t" -gt 0 ]; then
      printf '%s-RXQ %s %s\n' "$prefix" "$k" "$t"
    fi
  done <<<"$rows"
  return 0
}

# ---------------------------------------------------------------- common gates

gates() {
  local host kern
  host=$(hostname -s 2>/dev/null || hostname)
  if [ "$host" != johnny ]; then
    echo STOP-host
    return 1
  fi
  if [ "$(id -u)" -ne 0 ]; then
    echo STOP-not-root
    return 1
  fi
  kern=$(uname -r)
  if [ "$kern" != "$KERNEL_WANT" ]; then
    echo "STOP-kernel $kern"
    return 1
  fi
  if ! command -v bpftool >/dev/null 2>&1; then
    echo STOP-no-bpftool
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo STOP-no-python3
    return 1
  fi
  if [ ! -d "$SYSFS_NET/$IFACE" ]; then
    echo STOP-no-iface
    return 1
  fi
}

# ---------------------------------------------------------------- status

do_status() {
  local lines line prog_line ours snap cur base
  echo "HOST $(hostname -s 2>/dev/null || hostname)"
  echo "KERNEL $(uname -r)"
  if ! lines=$(net_attach_lines); then
    stop net-show-failed
    lines=
  elif [ -z "$lines" ]; then
    echo "XDP-ATTACH none"
  else
    while read -r line; do
      [ -n "$line" ] || continue
      echo "XDP-ATTACH ${line%% *} id=${line#* }"
    done <<<"$lines"
  fi
  if ! prog_line=$(progs_summary); then
    stop prog-show-failed
    prog_line=
  else
    echo "PROG-XDP-COUNT $(kv "$prog_line" total || echo unknown)"
    ours=$(kv "$prog_line" ours || echo unknown)
    echo "PROG-OURS $ours ids=$(kv "$prog_line" ids || echo unknown)"
  fi
  if [ -d "$PIN_DIR" ]; then
    echo "PINS dir=present prog=$([ -e "$(pin_prog)" ] && echo present || echo absent) stats=$([ -e "$(pin_stats)" ] && echo present || echo absent) rxq=$([ -e "$(pin_rxq)" ] && echo present || echo absent)"
  else
    echo "PINS dir=absent"
  fi
  link_facts
  echo "LINK $IFACE flags=$L_FLAGS speed=$L_SPEED carrier=$L_CARRIER oper=$L_OPER mtu=$L_MTU"
  if has_address; then
    echo NOTE-eno1-has-address
  fi
  if load_cores; then
    snap=$(irq_snapshot || true)
    if [ -z "$snap" ]; then
      echo NOTE-no-queue-irqs
    else
      printf '%s\n' "$snap"
      cur=$(irq_norm <<<"$snap")
      echo "IRQ-COUNT $(grep -c '^IRQ-SNAP' <<<"$snap" || true)"
      if irq_in_cores <<<"$cur"; then
        echo IRQ-CAPTURE ok
      else
        echo IRQ-CAPTURE outside
      fi
      if [ -f "$(baseline_file)" ] && [ ! -L "$(baseline_file)" ]; then
        base=$(irq_norm < "$(baseline_file)")
        if [ "$base" = "$cur" ]; then
          echo IRQ-BASELINE same
        else
          echo IRQ-BASELINE moved
        fi
      else
        echo IRQ-BASELINE none
      fi
    fi
  else
    echo "NOTE-cores-unreadable $CORES_ERR"
  fi
  if [ -e "$(pin_stats)" ]; then
    if ! emit_stats STAT; then
      stop stats-read-failed
    fi
  else
    echo NOTE-no-stats-pin
  fi
  if [ "$STOPS" -ne 0 ]; then
    echo M1S1B-STATUS-STOPS
    return 1
  fi
  echo M1S1B-STATUS-DONE
}

# ---------------------------------------------------------------- detach

wait_no_xdp() {
  local i=0 lines
  while :; do
    if lines=$(net_attach_lines) && [ -z "$lines" ]; then
      return 0
    fi
    [ "$i" -lt "$WAIT_TRIES" ] || return 1
    i=$((i + 1))
    sleep "$WAIT_STEP"
  done
}

wait_no_ours() {
  local i=0 line
  while :; do
    if line=$(progs_summary) && [ "$(kv "$line" ours || echo x)" = 0 ]; then
      return 0
    fi
    [ "$i" -lt "$WAIT_TRIES" ] || return 1
    i=$((i + 1))
    sleep "$WAIT_STEP"
  done
}

detach_ours() {
  local lines line mode id kw pl ids
  if ! lines=$(net_attach_lines); then
    stop net-show-failed
    return 1
  fi
  if [ -z "$lines" ]; then
    echo NOTHING-ATTACHED
    return 0
  fi
  if ! pl=$(progs_summary); then
    stop prog-show-failed
    return 1
  fi
  ids=$(kv "$pl" ids || echo none)
  while read -r line; do
    [ -n "$line" ] || continue
    mode=${line%% *}
    id=${line#* }
    case ",$ids," in
      *",$id,"*) ;;
      *)
        stop "xdp-foreign mode=$mode id=$id (not $PROG_NAME; not detached)"
        continue
        ;;
    esac
    case "$mode" in
      driver) kw=xdpdrv ;;
      generic) kw=xdpgeneric ;;
      offload) kw=xdpoffload ;;
      *)
        stop "xdp-mode-unknown $mode"
        continue
        ;;
    esac
    [ "$mode" = driver ] || echo "NOTE-xdp-mode-not-driver $mode"
    if bpftool net detach "$kw" dev "$IFACE"; then
      echo "DETACHED mode=$mode id=$id"
    else
      stop "detach-failed mode=$mode id=$id"
    fi
  done <<<"$lines"
}

remove_pins() {
  local f left
  for f in "$(pin_prog)" "$(pin_stats)" "$(pin_rxq)"; do
    if [ -e "$f" ]; then
      rm -f "$f" || stop "unpin-failed $f"
    fi
  done
  if [ -d "$PIN_DIR" ]; then
    if ! rmdir "$PIN_DIR" 2>/dev/null; then
      left=$(find "$PIN_DIR" -mindepth 1 -maxdepth 1 -printf '%f ' 2>/dev/null || true)
      stop "pin-leftover $PIN_DIR: $left"
      return 1
    fi
    echo PINS-REMOVED
  else
    echo PINS-ABSENT
  fi
}

# Put the step 13 pins back only if they moved. Pinned helper, hash-checked.
restore_irq_pins() {
  local cur base snap sha out after line
  if ! load_cores; then
    stop "irq-cores-unreadable $CORES_ERR"
    return 1
  fi
  snap=$(irq_snapshot || true)
  if [ -z "$snap" ]; then
    stop irq-no-queue-irqs
    return 1
  fi
  cur=$(irq_norm <<<"$snap")
  base=
  if [ -f "$(baseline_file)" ] && [ ! -L "$(baseline_file)" ]; then
    base=$(irq_norm < "$(baseline_file)")
  fi
  if [ -n "$base" ]; then
    if [ "$cur" = "$base" ]; then
      echo "IRQ-PINS-OK (matches the attach baseline)"
      return 0
    fi
  elif irq_in_cores <<<"$cur"; then
    echo "IRQ-PINS-OK (inside capture cores; no attach baseline file)"
    return 0
  fi
  echo "NOTE-irq-pins-disturbed: recovery is /etc/johnny/irq-affinity.sh apply (step 13)"
  sha=$(sha256sum "$HELPER" 2>/dev/null | awk '{print $1}' || true)
  if [ "$sha" != "$HELPER_SHA256" ] || [ ! -x "$HELPER" ]; then
    stop "irq-helper-hash ${sha:-missing}"
    return 1
  fi
  out=$("$HELPER" apply 2>&1) || true
  while read -r line; do
    [ -n "$line" ] && printf 'HELPER> %s\n' "$line"
  done <<<"$out"
  after=$(irq_snapshot | irq_norm || true)
  if [ -n "$base" ]; then
    if [ "$after" = "$base" ]; then
      echo IRQ-PINS-RESTORED
      return 0
    fi
  elif irq_in_cores <<<"$after"; then
    echo IRQ-PINS-RESTORED
    return 0
  fi
  stop irq-not-restored
  return 1
}

# A native attach or detach may bounce the link for a moment (the driver
# restarts its queues). Wait for it before judging.
wait_link_up() {
  local i=0
  while :; do
    link_up && return 0
    [ "$i" -lt "$WAIT_TRIES" ] || return 1
    i=$((i + 1))
    sleep "$WAIT_STEP"
  done
}

check_link() {
  wait_link_up || true
  link_facts
  if ! flags_capture_ok "$L_FLAGS"; then
    stop "eno1-flags $L_FLAGS (need UP, PROMISC, NOARP; this script does not change them)"
  fi
  if [ "$L_MTU" != 1500 ]; then
    stop "eno1-mtu $L_MTU"
  fi
  if ! link_up; then
    stop "eno1-link speed=$L_SPEED carrier=$L_CARRIER oper=$L_OPER"
  fi
  if has_address; then
    stop eno1-has-address
  fi
  if ! eno3_ok; then
    stop eno3-changed
  fi
  echo "LINK $IFACE flags=$L_FLAGS speed=$L_SPEED carrier=$L_CARRIER oper=$L_OPER mtu=$L_MTU"
}

do_detach() {
  local p1 p2 d1 d2 pl total
  detach_ours || true
  if wait_no_xdp; then
    echo "OK-no-xdp-on-$IFACE"
  else
    stop "xdp-linger"
  fi
  # Counters must be frozen once detached. Read before the pins go.
  if [ -e "$(pin_stats)" ] && [ -e "$(pin_rxq)" ]; then
    if emit_stats FINAL; then
      p1=$LAST_PKTS
      d1=$LAST_L3
      d2=$LAST_L4
      sleep "$WAIT_STEP"
      if emit_stats FINAL2 >/dev/null; then
        p2=$LAST_PKTS
        if [ "$p1" = "$p2" ]; then
          echo "OK-counters-frozen pkts=$p1"
        else
          stop "counters-still-moving $p1 -> $p2"
        fi
      else
        echo NOTE-final-reread-failed
      fi
      if [ "$d1" = 0 ] && [ "$d2" = 0 ]; then
        echo FINAL-PARTITION-OK
      else
        echo "NOTE-final-partition-off l3_diff=$d1 l4_diff=$d2"
      fi
    else
      echo NOTE-final-stats-unreadable
    fi
  else
    echo NOTE-no-final-stats
  fi
  remove_pins || true
  if wait_no_ours; then
    echo "OK-no-$PROG_NAME-loaded"
  else
    stop "prog-linger $PROG_NAME"
  fi
  if pl=$(progs_summary); then
    total=$(kv "$pl" total || echo unknown)
    echo "PROG-XDP-COUNT $total"
    if [ "$total" != 0 ]; then
      echo "NOTE-other-xdp-progs-loaded total=$total (not ours; not touched)"
    fi
  else
    stop prog-show-failed
  fi
  restore_irq_pins || true
  check_link
  if [ "$STOPS" -ne 0 ]; then
    echo M1S1B-DETACH-STOPS
    return 1
  fi
  rm -f "$(baseline_file)"
  echo M1S1B-DETACH-DONE
}

main() {
  umask 077
  export PATH="$SAFE_PATH"
  trap '' HUP PIPE
  case "${1:-}" in
    detach | status) ;;
    *)
      echo STOP-args
      exit 1
      ;;
  esac
  if ! gates; then
    exit 1
  fi
  if [ "$1" = status ]; then
    do_status
    return
  fi
  mkdir -p "$STATE_DIR"
  # The attach script calls this with M1S1B_LOCKED=1 while it holds the lock.
  if [ "${M1S1B_LOCKED:-}" != 1 ]; then
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 8>"$LOCK_FILE"
    if ! flock -n 8; then
      echo STOP-locked
      exit 1
    fi
  fi
  do_detach
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
