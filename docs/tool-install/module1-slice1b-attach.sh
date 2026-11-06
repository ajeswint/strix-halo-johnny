#!/bin/bash
# Module 1 slice 1b: attach the passive, observe-only native-XDP program to
# eno1np0 (SPAN port), verify it, leave it attached. Runbook:
# docs/tool-install/module1-slice1b-attach.md
#
#   sudo bash /root/m1s1b/module1-slice1b-attach.sh attach
#
# Root, on Johnny only. Fail-fast until the first change; after that, any STOP,
# error, INT or TERM runs the installed rollback (module1-slice1b-detach.sh
# detach) and ends M1S1B-ATTACH-STOPS. Success ends M1S1B-ATTACH-DONE.
#
# What it changes: it loads module1-xdp-observe.o with bpftool, pins the program
# and its two maps under /sys/fs/bpf/johnny_m1s1b/, and attaches the program to
# eno1np0 in native (driver) mode with `bpftool net attach xdpdrv`. Nothing
# else: no ip link set, no ethtool setter, no sysctl, no unit, no package, no
# queue-count or MTU change, no AF_XDP socket, no Suricata. The program always
# returns XDP_PASS. There is no generic-XDP fallback: the plain `xdp` keyword
# and `xdpgeneric` are never used, so a native failure stays loud.
#
# The attach lasts until detach or reboot. Nothing re-attaches it at boot (a
# boot unit is a later slice).
#
# Refuses to run unless the root-owned rollback copy and the object are
# installed under /root/m1s1b/ with the pinned sha256 (step 11 pattern: the
# rollback is installed before the change).
set -uo pipefail

# Plain variables, not read from the environment. The rock-box self-test
# overrides them after sourcing.
IFACE=eno1np0
SYSFS_NET=/sys/class/net
STATE_DIR=/root/m1s1b
PIN_DIR=/sys/fs/bpf/johnny_m1s1b
SAFE_PATH=/usr/sbin:/usr/bin:/sbin:/bin
OBJ_SHA256=8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d
DETACH_SHA256=f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58
HELPER=/etc/johnny/irq-affinity.sh
HELPER_SHA256=db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4
KERNEL_WANT=7.0.0-42-generic
LOCK_FILE=/run/johnny-m1s1b.lock
IRQ_WANT=12
BASE_SECS=5
OBSERVE_SECS=10
WAIT_STEP=1
WAIT_TRIES=30
FLUSH_WAIT=1
CHANGED=0
DONE=0
ST=
PROG_ID=
COMBINED_BEFORE=

obj_path() { printf '%s/module1-xdp-observe.o' "$STATE_DIR"; }
detach_path() { printf '%s/module1-slice1b-detach.sh' "$STATE_DIR"; }
pin_prog() { printf '%s/prog' "$PIN_DIR"; }
baseline_file() { printf '%s/irq-baseline.txt' "$STATE_DIR"; }
log_file() { printf '%s/attach.log' "$STATE_DIR"; }

# Main shell only (it exits). Never call inside $( ).
stop() {
  printf 'STOP-%s\n' "$*"
  exit 1
}

read_trim() {
  { tr -d '[:space:]' < "$1"; } 2>/dev/null || true
}

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

flags_capture_ok() {
  local f=$1
  [[ $f =~ ^(0[xX])?[0-9a-fA-F]+$ ]] || return 1
  [ $((f & 1)) -ne 0 ] && [ $((f & 256)) -ne 0 ] && [ $((f & 128)) -ne 0 ]
}

# Test seams: functions, so the self-test can redefine them after sourcing.
run_detach() {
  M1S1B_LOCKED=1 bash "$(detach_path)" "$@"
}

owner_ok() {
  local o m
  [ ! -L "$1" ] && [ -f "$1" ] || return 1
  o=$(stat -c '%u:%g' "$1")
  [ "$o" = 0:0 ] || return 1
  m=$(stat -c '%a' "$1")
  [[ $m =~ ^[0-7]*[0145][0145]$ ]]
}

start_log() {
  exec > >(tee -a "$(log_file)") 2>&1
}

# ---------------------------------------------------------------- rollback

finish() {
  local rc=$?
  trap - EXIT INT TERM
  if [ "$DONE" -eq 1 ]; then
    exit 0
  fi
  [ "$rc" -ne 0 ] || rc=1
  if [ "$CHANGED" -eq 1 ]; then
    echo REVERTING
    if ! run_detach detach; then
      echo "STOP-rollback-failed. Run: sudo bash $(detach_path) detach"
      echo "If that fails, a reboot removes the attach and the pins (no unit re-attaches it)."
    fi
  else
    echo NOTHING-CHANGED
  fi
  echo M1S1B-ATTACH-STOPS
  sleep "$FLUSH_WAIT"
  exit "$rc"
}

# ---------------------------------------------------------------- checks

gate_host() {
  local host kern
  host=$(hostname -s 2>/dev/null || hostname)
  [ "$host" = johnny ] || stop host
  [ "$(id -u)" -eq 0 ] || stop not-root
  kern=$(uname -r)
  [ "$kern" = "$KERNEL_WANT" ] || stop "kernel $kern"
}

need_tools() {
  local cmd
  for cmd in bpftool python3 ip ethtool tcpdump timeout sha256sum awk flock stat sort sed systemctl journalctl; do
    command -v "$cmd" >/dev/null 2>&1 || stop "missing-tool $cmd"
  done
}

root_file_ok() {
  local what=$1 path=$2 want=$3 got
  owner_ok "$path" || stop "$what-not-root-owned-or-missing $path"
  got=$(sha256sum "$path" | awk '{print $1}')
  [ "$got" = "$want" ] || stop "$what-hash $got"
  echo "OK-$what-hash $want"
}

need_files() {
  local got
  root_file_ok object "$(obj_path)" "$OBJ_SHA256"
  if [ ! -e "$(detach_path)" ]; then
    stop "no-rollback-installed: $(detach_path) missing; do Paste 2 (install) first"
  fi
  root_file_ok rollback "$(detach_path)" "$DETACH_SHA256"
  [ -x "$HELPER" ] || stop "irq-helper-missing $HELPER"
  got=$(sha256sum "$HELPER" | awk '{print $1}')
  [ "$got" = "$HELPER_SHA256" ] || stop "irq-helper-hash $got"
  echo "OK-irq-helper-hash $HELPER_SHA256"
}

get_status() {
  ST=$(run_detach status 2>&1) || return 1
  case "$ST" in
    *M1S1B-STATUS-DONE*) return 0 ;;
    *) return 1 ;;
  esac
}

st_first() {
  awk -v p="$1" 'index($0, p) == 1 && !f { print; f = 1 }' <<<"$ST"
}

stat_val() {
  awk -v n="$1" '$1 == "STAT" && $2 == n { print $3 }' <<<"$ST"
}

nic_stat() {
  read_trim "$SYSFS_NET/$IFACE/statistics/$1"
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

# Combined channel count under "Current hardware settings".
combined_now() {
  local out
  out=$(ethtool -l "$IFACE" 2>/dev/null) || return 1
  awk '/^Current hardware settings/ { c = 1; next } c && /^Combined:/ { print $2; f = 1 } END { exit f ? 0 : 1 }' <<<"$out"
}

# Frames AF_PACKET sees in SECS seconds. tcpdump's own summary line is the count.
tcpdump_count() {
  local secs=$1 err n
  err=$(mktemp "$STATE_DIR/tcpdump.XXXXXX") || return 1
  timeout -s INT "$secs" tcpdump -p -nn -i "$IFACE" -w /dev/null 2>"$err" || true
  n=$(awk '/ packets captured$/ { print $1 }' "$err")
  rm -f "$err"
  [[ $n =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$n"
}

# 0 if |d| <= max(256, pkts / 100). Counters are read slot by slot while frames
# arrive, so a live read is not exact.
within_tol() {
  local d=$1 pkts=$2 tol
  [[ $d =~ ^-?[0-9]+$ ]] || return 1
  [ "$d" -ge 0 ] || d=$((-d))
  tol=$((pkts / 100))
  [ "$tol" -ge 256 ] || tol=256
  [ "$d" -le "$tol" ]
}

klog() {
  local out line
  out=$(journalctl -k -n 60 --no-pager 2>/dev/null | grep -Ei 'xdp|ice |ice:|ddp' || true)
  while read -r line; do
    [ -n "$line" ] && printf 'KLOG> %s\n' "$line"
  done <<<"$out"
}

# ---------------------------------------------------------------- stages

preflight_state() {
  local line flags speed carrier oper mtu en ac svc
  get_status || {
    printf '%s\n' "$ST"
    stop status-failed
  }
  [ "$(st_first XDP-ATTACH)" = "XDP-ATTACH none" ] || stop "xdp-already-attached: $(st_first XDP-ATTACH)"
  [ "$(st_first PROG-XDP-COUNT)" = "PROG-XDP-COUNT 0" ] || stop "xdp-progs-loaded: $(st_first PROG-XDP-COUNT)"
  [ "$(st_first PINS)" = "PINS dir=absent" ] || stop "pins-exist: $(st_first PINS)"
  [ "$(st_first IRQ-COUNT)" = "IRQ-COUNT $IRQ_WANT" ] || stop "irq-count: $(st_first IRQ-COUNT)"
  [ "$(st_first IRQ-CAPTURE)" = "IRQ-CAPTURE ok" ] || stop irq-baseline-outside-capture-cores
  case "$ST" in
    *NOTE-eno1-has-address*) stop eno1-has-address ;;
  esac
  line=$(st_first LINK)
  flags=$(kv "$line" flags || true)
  speed=$(kv "$line" speed || true)
  carrier=$(kv "$line" carrier || true)
  oper=$(kv "$line" oper || true)
  mtu=$(kv "$line" mtu || true)
  flags_capture_ok "$flags" || stop "eno1-flags $flags (need UP, PROMISC, NOARP)"
  [ "$speed" = 10000 ] || stop "eno1-speed ${speed:-none}"
  [ "$carrier" = 1 ] || [ "$oper" = up ] || stop "eno1-link carrier=$carrier oper=$oper"
  [ "$mtu" = 1500 ] || stop "mtu-not-1500 ${mtu:-none}"
  echo "OK-link $line"
  eno3_ok || stop eno3-not-as-recorded
  echo OK-eno3
  en=$(systemctl is-enabled suricata 2>/dev/null || true)
  ac=$(systemctl is-active suricata 2>/dev/null || true)
  { [ "$en" = disabled ] && [ "$ac" = inactive ]; } || stop "suricata ${en:-?}/${ac:-?}"
  echo "OK-suricata $en/$ac"
  for svc in johnny-capture-irq.service johnny-capture-tuning.service; do
    ac=$(systemctl is-active "$svc" 2>/dev/null || true)
    [ "$ac" = active ] || echo "NOTE-$svc $ac"
  done
  COMBINED_BEFORE=$(combined_now) || stop ethtool-l
  echo "COMBINED-BEFORE $COMBINED_BEFORE"
  # The IRQ baseline the after-attach checks compare against.
  awk 'index($0, "IRQ-SNAP ") == 1' <<<"$ST" > "$(baseline_file)"
  chmod 600 "$(baseline_file)"
  echo "IRQ-BASELINE-SAVED $(baseline_file)"
  awk 'index($0, "IRQ-SNAP ") == 1 { sub(/^IRQ-SNAP/, "IRQ-BEFORE"); print }' <<<"$ST"
}

baseline_traffic() {
  local n0 n1 d0 d1 t
  n0=$(nic_stat rx_packets)
  d0=$(nic_stat rx_dropped)
  t=$(tcpdump_count "$BASE_SECS") || stop tcpdump-baseline-failed
  n1=$(nic_stat rx_packets)
  d1=$(nic_stat rx_dropped)
  echo "BASE-WINDOW secs=$BASE_SECS tcpdump-captured=$t nic-rx-delta=$((n1 - n0)) nic-rx-dropped-delta=$((d1 - d0))"
  [ "$t" -gt 0 ] || stop "no-traffic-baseline (SPAN quiet or tcpdump blind; nothing was changed)"
}

load_stage() {
  local line n pid
  CHANGED=1
  mkdir "$PIN_DIR" || stop "mkdir-pin-dir $PIN_DIR"
  if ! bpftool prog load "$(obj_path)" "$(pin_prog)" pinmaps "$PIN_DIR"; then
    stop "load (verifier or bpftool refused the object; nothing was attached)"
  fi
  get_status || {
    printf '%s\n' "$ST"
    stop status-failed-after-load
  }
  line=$(st_first PROG-OURS)
  case "$line" in
    "PROG-OURS 1 ids="*) pid=${line#*ids=} ;;
    *) stop "load-not-visible: $line" ;;
  esac
  PROG_ID=$pid
  [ "$(st_first PROG-XDP-COUNT)" = "PROG-XDP-COUNT 1" ] || stop "prog-count-after-load: $(st_first PROG-XDP-COUNT)"
  case "$(st_first PINS)" in
    "PINS dir=present prog=present stats=present rxq=present") ;;
    *) stop "pins-after-load: $(st_first PINS)" ;;
  esac
  [ "$(st_first IRQ-BASELINE)" = "IRQ-BASELINE same" ] || stop "irq-moved-by-load: $(st_first IRQ-BASELINE)"
  # Prove the counter readback parses on this bpftool's real output BEFORE attach.
  for n in pkts bytes ipv4 ipv6 arp other trunc vlan tcp udp icmp l4_other; do
    [ "$(stat_val "$n")" = 0 ] || stop "readback-not-zero-before-attach $n=$(stat_val "$n")"
  done
  echo "LOADED prog_id=$PROG_ID (verifier accepted; not attached yet)"
  echo OK-readback-parse
}

attach_stage() {
  if ! bpftool net attach xdpdrv pinned "$(pin_prog)" dev "$IFACE"; then
    klog
    stop "attach (native xdpdrv refused; no generic fallback by design)"
  fi
  echo "ATTACHED xdpdrv prog_id=$PROG_ID"
  klog
}

wait_link() {
  local i=0 speed carrier oper
  while :; do
    speed=$(read_trim "$SYSFS_NET/$IFACE/speed")
    carrier=$(read_trim "$SYSFS_NET/$IFACE/carrier")
    oper=$(read_trim "$SYSFS_NET/$IFACE/operstate")
    if [ "$speed" = 10000 ] && { [ "$carrier" = 1 ] || [ "$oper" = up ]; }; then
      return 0
    fi
    [ "$i" -lt "$WAIT_TRIES" ] || return 1
    [ $((i % 5)) -ne 0 ] || echo "NOTE-wait-link try=$i speed=$speed carrier=$carrier oper=$oper"
    i=$((i + 1))
    sleep "$WAIT_STEP"
  done
}

# Everything that must hold while attached. Used right after attach and after
# the observe window.
check_attached() {
  local tag=$1 line flags mtu combined
  get_status || {
    printf '%s\n' "$ST"
    stop "status-failed-$tag"
  }
  [ "$(st_first XDP-ATTACH)" = "XDP-ATTACH driver id=$PROG_ID" ] || stop "xdp-mode-or-id-$tag: $(st_first XDP-ATTACH) (want driver id=$PROG_ID)"
  [ "$(st_first PROG-XDP-COUNT)" = "PROG-XDP-COUNT 1" ] || stop "prog-count-$tag: $(st_first PROG-XDP-COUNT)"
  [ "$(st_first PROG-OURS)" = "PROG-OURS 1 ids=$PROG_ID" ] || stop "prog-ours-$tag: $(st_first PROG-OURS)"
  line=$(st_first LINK)
  flags=$(kv "$line" flags || true)
  mtu=$(kv "$line" mtu || true)
  flags_capture_ok "$flags" || stop "eno1-flags-$tag $flags (UP, PROMISC, NOARP lost)"
  [ "$mtu" = 1500 ] || stop "mtu-$tag $mtu"
  case "$ST" in
    *NOTE-eno1-has-address*) stop "eno1-address-$tag" ;;
  esac
  combined=$(combined_now) || stop "ethtool-l-$tag"
  [ "$combined" = "$COMBINED_BEFORE" ] || stop "queues-changed-$tag before=$COMBINED_BEFORE after=$combined"
  eno3_ok || stop "eno3-changed-$tag"
  [ "$(st_first IRQ-COUNT)" = "IRQ-COUNT $IRQ_WANT" ] || stop "irq-count-$tag: $(st_first IRQ-COUNT)"
  [ "$(st_first IRQ-BASELINE)" = "IRQ-BASELINE same" ] || stop "irq-pins-moved-$tag (recovery: sudo $HELPER apply)"
  [ "$(st_first IRQ-CAPTURE)" = "IRQ-CAPTURE ok" ] || stop "irq-outside-capture-cores-$tag (recovery: sudo $HELPER apply)"
  echo "OK-xdp-mode driver id=$PROG_ID ($tag)"
  echo "OK-irq-pins-unchanged ($tag)"
  echo "OK-link-queues-eno3 ($tag) combined=$combined $line"
}

observe_window() {
  local p0 p1 b0 b1 n0 n1 r0 r1 t dp db dn dr pct pps avg
  get_status || stop status-failed-window
  p0=$(stat_val pkts)
  b0=$(stat_val bytes)
  n0=$(nic_stat rx_packets)
  r0=$(nic_stat rx_dropped)
  t=$(tcpdump_count "$OBSERVE_SECS") || stop "tcpdump-failed-while-attached"
  get_status || stop status-failed-window
  p1=$(stat_val pkts)
  b1=$(stat_val bytes)
  n1=$(nic_stat rx_packets)
  r1=$(nic_stat rx_dropped)
  dp=$((p1 - p0))
  db=$((b1 - b0))
  dn=$((n1 - n0))
  dr=$((r1 - r0))
  pps=$((dp / OBSERVE_SECS))
  avg=0
  [ "$dp" -le 0 ] || avg=$((db / dp))
  echo "OBS-WINDOW secs=$OBSERVE_SECS xdp-pkts-delta=$dp xdp-pps=$pps xdp-avg-bytes=$avg tcpdump-captured=$t nic-rx-delta=$dn nic-rx-dropped-delta=$dr"
  if [ "$dp" -le 0 ]; then
    if [ "$dn" -gt 0 ]; then
      stop "observer-no-count (the NIC received $dn frames, the program counted none)"
    fi
    stop "no-traffic (SPAN quiet during the window)"
  fi
  if [ "$t" -le 0 ]; then
    stop "pass-broken (the program counted $dp frames but tcpdump saw none: frames are not reaching the stack)"
  fi
  pct=$((t * 100 / dp))
  echo "PASS-RATIO tcpdump=$t xdp=$dp pct=$pct"
  [ "$pct" -ge 80 ] || echo "NOTE-pass-ratio-low pct=$pct (tcpdump start-up skew or pcap drops under load; tcpdump saw frames, so XDP_PASS holds)"
  [ "$dr" -le 0 ] || echo "NOTE-nic-rx-dropped-up delta=$dr (compare BASE-WINDOW nic-rx-dropped-delta)"
  echo OK-xdp-pass-tcpdump-sees-traffic
}

final_verify() {
  local pkts l3 l4 line
  check_attached after-window
  pkts=$(stat_val pkts)
  line=$(awk '$1 == "PART" { print; exit }' <<<"$ST")
  l3=$(kv "$line" l3_diff || true)
  l4=$(kv "$line" l4_diff || true)
  within_tol "$l3" "$pkts" || stop "partition-l3 diff=$l3 pkts=$pkts"
  within_tol "$l4" "$pkts" || stop "partition-l4 diff=$l4 pkts=$pkts"
  echo "OK-partition l3_diff=$l3 l4_diff=$l4 (live read; exact check is the detach FINAL-PARTITION-OK)"
  awk 'index($0, "IRQ-SNAP ") == 1 { sub(/^IRQ-SNAP/, "IRQ-AFTER"); print }' <<<"$ST"
  awk '$1 == "STAT" || $1 == "STAT-RXQ" || $1 == "PART" || $1 == "PROG-XDP-COUNT"' <<<"$ST"
}

main() {
  umask 077
  export PATH="$SAFE_PATH"
  trap '' HUP PIPE
  trap finish EXIT
  trap 'exit 130' INT TERM
  [ "${1:-}" = attach ] || {
    echo STOP-args
    exit 1
  }
  gate_host
  mkdir -p "$STATE_DIR"
  start_log
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  flock -n 9 || stop locked
  echo "M1S1B-ATTACH-START DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  need_tools
  need_files
  preflight_state
  baseline_traffic
  load_stage
  attach_stage
  wait_link || stop "link-after-attach"
  check_attached just-attached
  observe_window
  final_verify
  DONE=1
  echo "STATE attached, native (driver) mode, for this boot only; nothing re-attaches it at boot."
  echo "Detach: sudo bash $(detach_path) detach"
  echo "Read:   sudo bash $(detach_path) status"
  echo M1S1B-ATTACH-DONE
  sleep "$FLUSH_WAIT"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
