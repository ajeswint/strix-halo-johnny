#!/bin/bash
# Module 1 slice 2: records trial helper for j_xdp_records on eno1np0.
# Design:  docs/tool-install/module1-slice2-ringbuf-design.md
# Runbook: docs/tool-install/module1-slice2-ringbuf.md
#
#   sudo bash module1-slice2-records.sh probe      read-only preflight (before install)
#   sudo bash /root/m1s2/module1-slice2-records.sh load      load + pin, NO attach; reader smoke
#   sudo bash /root/m1s2/module1-slice2-records.sh swap      stop slice 1c, attach records (native)
#   sudo bash /root/m1s2/module1-slice2-records.sh read      one bounded reader run + summary
#   sudo bash /root/m1s2/module1-slice2-records.sh verify    read-only live checks
#   sudo bash /root/m1s2/module1-slice2-records.sh status    read-only state
#   sudo bash /root/m1s2/module1-slice2-records.sh rollback  back to slice 1c (idempotent)
#
# Root, on Johnny only. Slice 1c stays installed and enabled; this script never
# edits its unit, its helper or /root/m1s1b. It swaps programs only through the
# proven slice 1c paths (systemctl stop/start johnny-capture-xdp.service).
#
# Library: the pinned slice 1b detach script (/root/m1s1b/module1-slice1b-detach.sh,
# sha256-checked, then sourced; its main() does not run when sourced) supplies
# the reviewed bpftool JSON parsers, counter readback, IRQ snapshot and link
# checks. This script re-applies its own variables after sourcing it. Its modes
# are m2_* because the library's own do_status would replace ours when sourced.
#
# Never: XDP_DROP/TX/REDIRECT (the object only returns XDP_PASS), generic/skb
# attach, `overwrite`, detaching a program that is not j_xdp_records, map
# writes, sysctl/NIC/queue/IRQ changes, or anything persistent across a reboot
# (a reboot is a rollback: bpffs pins go away, slice 1c re-attaches at boot).
# Any failure after load/swap changed something runs `rollback` and ends
# M1S2-<MODE>-STOPS.
set -uo pipefail

# Plain variables, not read from the environment. The rock-box self-test
# overrides them after sourcing.
IFACE=eno1np0
SYSFS_NET=/sys/class/net
PROC_ROOT=/proc
STATE_DIR=/root/m1s2
PIN_DIR=/sys/fs/bpf/johnny_m1s2
OUT_DIR=/var/lib/johnny/m1s2
SAFE_PATH=/usr/sbin:/usr/bin:/sbin:/bin
KERNEL_WANT=7.0.0-42-generic
LOCK_FILE=/run/johnny-m1s2.lock
CORES=/etc/johnny/capture-cores
CORES_SHA256=16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b
LIB=/root/m1s1b/module1-slice1b-detach.sh
LIB_SHA256=f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58
C1_BOOT=/root/m1s1b/module1-slice1c-boot.sh
C1_BOOT_SHA256=a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06
C1_UNIT_FILE=/etc/systemd/system/johnny-capture-xdp.service
C1_UNIT_SHA256=2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0
C1_UNIT=johnny-capture-xdp.service
OBJ_SHA256=451247d8409396f35bf4454bfa8b44f2bc73b2197f97bb7c41818a9709f780e2
READER=/usr/local/libexec/johnny/johnny-m1s2-reader.py
READER_SHA256=32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2
R_UNIT_FILE=/etc/systemd/system/johnny-m1s2-reader.service
R_UNIT_SHA256=267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52
R_UNIT=johnny-m1s2-reader.service
OBS_NAME=j_xdp_observe
REC_NAME=j_xdp_records
PIN_NAMES="m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state prog"
# Order MUST match the C_* enum in module1_xdp_records.c (the self-test compares).
CTL_NAMES="seen sampled_out rate_limited rb_full emitted discarded"
COMBINED_WANT=12
SETTLE_SECS=5
SMOKE_SECS=3
READ_WAIT_TRIES=120
JOURNAL_TRIES=10
DONE=0
CLEANUP_ON_FAIL=0
ACTION=
REC_ID=
OBS_ID=

obj_path() { printf '%s/module1-xdp-records.o' "$STATE_DIR"; }
baseline_file() { printf '%s/irq-baseline.txt' "$STATE_DIR"; }

die() {
  printf 'STOP-%s\n' "$*"
  exit 1
}

owner_ok() {
  local o m
  [ ! -L "$1" ] && [ -f "$1" ] || return 1
  o=$(stat -c '%u:%g' "$1")
  [ "$o" = 0:0 ] || return 1
  m=$(stat -c '%a' "$1")
  [[ $m =~ ^[0-7]*[0145][0145]$ ]]
}

file_ok() {
  local what=$1 path=$2 want=$3 got
  owner_ok "$path" || die "$what-not-root-owned-or-missing $path"
  got=$(sha256sum "$path" | awk '{print $1}')
  [ "$got" = "$want" ] || die "$what-hash $got"
  echo "OK-$what-hash $want"
}

# Source the pinned slice 1b library, then put our variables back.
use_lib() {
  local s=("$IFACE" "$SYSFS_NET" "$PROC_ROOT" "$STATE_DIR" "$PIN_DIR" "$SAFE_PATH" "$KERNEL_WANT" "$LOCK_FILE" "$CORES" "$CORES_SHA256")
  file_ok lib "$LIB" "$LIB_SHA256"
  # shellcheck source=/dev/null
  source "$LIB" || die lib-source
  IFACE=${s[0]} SYSFS_NET=${s[1]} PROC_ROOT=${s[2]} STATE_DIR=${s[3]} PIN_DIR=${s[4]}
  SAFE_PATH=${s[5]} KERNEL_WANT=${s[6]} LOCK_FILE=${s[7]} CORES=${s[8]} CORES_SHA256=${s[9]}
  # shellcheck disable=SC2034 # read by the library's progs_summary / wait_no_ours
  PROG_NAME=$REC_NAME
  STOPS=0
}

need_tools() {
  local cmd
  for cmd in bpftool python3 ip ethtool sha256sum awk flock stat sort sed systemctl journalctl find; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing-tool $cmd"
  done
}

need_installed() {
  file_ok object "$(obj_path)" "$OBJ_SHA256"
  file_ok reader "$READER" "$READER_SHA256"
  file_ok reader-unit "$R_UNIT_FILE" "$R_UNIT_SHA256"
}

need_slice1c_files() {
  file_ok c1-helper "$C1_BOOT" "$C1_BOOT_SHA256"
  file_ok c1-unit "$C1_UNIT_FILE" "$C1_UNIT_SHA256"
}

within_tol() {
  local d=$1 pkts=$2 tol
  [[ $d =~ ^-?[0-9]+$ ]] || return 1
  [ "$d" -ge 0 ] || d=$((-d))
  tol=$((pkts / 100))
  [ "$tol" -ge 256 ] || tol=256
  [ "$d" -le "$tol" ]
}

combined_now() {
  local out
  out=$(ethtool -l "$IFACE" 2>/dev/null) || return 1
  awk '/^Current hardware settings/ { c = 1; next } c && /^Combined:/ { print $2; f = 1 } END { exit f ? 0 : 1 }' <<<"$out"
}

unit_active() {
  systemctl is-active "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------- state

# Sets XDP_LINES ("mode id" per attachment), REC_IDS / OBS_IDS (comma lists of
# loaded program ids by name, "none"), XDP_TOTAL (loaded XDP programs).
scan() {
  local js pr po
  XDP_LINES=$(net_attach_lines) || die net-show-failed
  js=$(bpftool -j prog show 2>/dev/null) || die prog-show-failed
  pr=$(progs_from_json "$REC_NAME" <<<"$js") || die prog-parse-failed
  po=$(progs_from_json "$OBS_NAME" <<<"$js") || die prog-parse-failed
  XDP_TOTAL=$(kv "$pr" total)
  REC_IDS=$(kv "$pr" ids)
  OBS_IDS=$(kv "$po" ids)
}

# attach_state: "none", "records ID", "observer ID", or "other MODE ID"/"multi".
attach_state() {
  local n mode id
  n=$(grep -c . <<<"$XDP_LINES" || true)
  [ "$n" -eq 0 ] && { echo none; return; }
  [ "$n" -eq 1 ] || { echo multi; return; }
  mode=${XDP_LINES%% *}
  id=${XDP_LINES#* }
  if [ "$mode" != driver ]; then
    echo "other $mode $id"
  elif [[ ",$REC_IDS," == *",$id,"* ]]; then
    echo "records $id"
  elif [[ ",$OBS_IDS," == *",$id,"* ]]; then
    echo "observer $id"
  else
    echo "other $mode $id"
  fi
}

pins_list() {
  find "$PIN_DIR" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//'
}

# "name total" per m2_ctl slot, in CTL_NAMES order. rc 1 on any read/parse error.
ctl_rows() {
  local js rows k t i=0 name
  local -a names
  js=$(bpftool -j map dump pinned "$PIN_DIR/m2_ctl" 2>/dev/null) || return 1
  rows=$(percpu_from_json <<<"$js") || return 1
  read -r -a names <<<"$CTL_NAMES"
  declare -A got=()
  while read -r k t; do
    [ -n "$k" ] && got[$k]=$t
  done <<<"$rows"
  [ "${#got[@]}" -eq "${#names[@]}" ] || return 1
  for name in "${names[@]}"; do
    printf '%s %s\n' "$name" "${got[$i]}"
    i=$((i + 1))
  done
}

ctl_val() {
  awk -v n="$1" '$1 == n { print $2 }' <<<"$CTL"
}

# m2_cfg as "ver=.. sample_every=.. rate=.. burst=..": BTF-formatted or raw bytes.
cfg_line() {
  local js
  js=$(bpftool -j map dump pinned "$PIN_DIR/m2_cfg" 2>/dev/null) || return 1
  python3 -I -c '
import json, struct, sys
try:
    doc = json.load(sys.stdin)
    it = doc[0]
    f = it.get("formatted")
    if isinstance(f, dict) and isinstance(f.get("value"), dict):
        v = f["value"]
        vals = [int(v[k]) for k in ("ver", "sample_every", "rate", "burst")]
    else:
        raw = bytes(int(b, 16) if isinstance(b, str) else int(b) for b in it["value"])
        vals = list(struct.unpack("<IIII", raw))
except (ValueError, KeyError, IndexError, TypeError, struct.error):
    sys.exit(2)
print("ver=%d sample_every=%d rate=%d burst=%d" % tuple(vals))
' <<<"$js"
}

# Everything that must hold while j_xdp_records is attached. Sets REC_ID, CTL,
# LAST_PKTS. Read-only.
check_records_attached() {
  local tag=$1 st snap cur base combined seen sum d
  scan
  st=$(attach_state)
  case "$st" in
    "records "*) REC_ID=${st#records } ;;
    *) die "not-records-attached-$tag: $st" ;;
  esac
  [ "$XDP_TOTAL" = 1 ] || die "prog-count-$tag $XDP_TOTAL (want 1: records only)"
  [ "$(unit_active "$C1_UNIT")" != active ] || die "c1-unit-active-$tag"
  [ "$(pins_list)" = "$PIN_NAMES" ] || die "pins-$tag: $(pins_list)"
  check_link
  [ "$STOPS" -eq 0 ] || die "link-$tag"
  combined=$(combined_now) || die "ethtool-l-$tag"
  [ "$combined" = "$COMBINED_WANT" ] || die "queues-$tag combined=$combined"
  load_cores || die "cores-$tag $CORES_ERR"
  snap=$(irq_snapshot) || die "irq-snapshot-$tag"
  cur=$(irq_norm <<<"$snap")
  irq_in_cores <<<"$cur" || die "irq-outside-capture-cores-$tag"
  { [ -f "$(baseline_file)" ] && [ ! -L "$(baseline_file)" ]; } || die "irq-baseline-missing-$tag"
  base=$(irq_norm < "$(baseline_file)")
  [ "$base" = "$cur" ] || die "irq-pins-moved-$tag"
  emit_stats STAT || die "stats-read-$tag"
  within_tol "$LAST_L3" "$LAST_PKTS" || die "partition-l3-$tag diff=$LAST_L3"
  within_tol "$LAST_L4" "$LAST_PKTS" || die "partition-l4-$tag diff=$LAST_L4"
  CTL=$(ctl_rows) || die "ctl-read-$tag"
  awk '{ print "CTL " $0 }' <<<"$CTL"
  seen=$(ctl_val seen)
  sum=$(($(ctl_val sampled_out) + $(ctl_val rate_limited) + $(ctl_val rb_full) + $(ctl_val emitted) + $(ctl_val discarded)))
  d=$((seen - sum))
  within_tol "$d" "$seen" || die "ctl-accounting-$tag seen=$seen sum=$sum"
  within_tol "$((LAST_PKTS - seen))" "$LAST_PKTS" || die "ctl-seen-vs-pkts-$tag seen=$seen pkts=$LAST_PKTS"
  echo "OK-xdp-mode driver id=$REC_ID $REC_NAME ($tag)"
  echo "OK-irq-pins-unchanged ($tag)"
  echo "OK-partition ($tag) l3_diff=$LAST_L3 l4_diff=$LAST_L4"
  echo "OK-ctl-accounting ($tag) seen=$seen sum=$sum pkts=$LAST_PKTS"
}

# Read-only: slice 1c observer attached in driver mode and its unit active.
check_observer() {
  local st
  scan
  st=$(attach_state)
  case "$st" in
    "observer "*) OBS_ID=${st#observer } ;;
    *) return 1 ;;
  esac
  [ "$(unit_active "$C1_UNIT")" = active ]
}

nic_drops() {
  local n v out=
  for n in rx_dropped rx_missed_errors rx_fifo_errors rx_errors; do
    v=$(read_trim "$SYSFS_NET/$IFACE/statistics/$n")
    out="$out $n=${v:-na}"
  done
  printf '%s\n' "${out# }"
}

drop_deltas() {
  python3 -I -c '
import sys
a = dict(p.split("=") for p in sys.argv[1].split())
b = dict(p.split("=") for p in sys.argv[2].split())
print(" ".join("%s=%s" % (k, int(b[k]) - int(a[k]) if a[k].isdigit() and b[k].isdigit() else "na") for k in a))
' "$1" "$2"
}

# ---------------------------------------------------------------- journal

# Prints the reader's journal lines for invocation $1 once END or STOP shows.
reader_journal() {
  local inv=$1 i=0 out
  while :; do
    out=$(journalctl _SYSTEMD_INVOCATION_ID="$inv" -o cat --no-pager 2>/dev/null || true)
    case "$out" in
      *M1S2-READER-END* | *STOP-*) printf '%s\n' "$out"; return 0 ;;
    esac
    [ "$i" -lt "$JOURNAL_TRIES" ] || { printf '%s\n' "$out"; return 1; }
    i=$((i + 1))
    sleep 1
  done
}

reader_start() {
  local a
  a=$(unit_active "$R_UNIT")
  case "$a" in
    active | activating | deactivating | reloading) die "reader-already-$a" ;;
  esac
  systemctl reset-failed "$R_UNIT" 2>/dev/null || true
  systemctl start "$R_UNIT" || die reader-start-failed
  R_INV=$(systemctl show -p InvocationID --value "$R_UNIT" 2>/dev/null || true)
  [[ $R_INV =~ ^[0-9a-f]{32}$ ]] || die "reader-invocation ${R_INV:-none}"
}

reader_wait_inactive() {
  local i=0 a
  while :; do
    a=$(unit_active "$R_UNIT")
    case "$a" in
      active | activating | deactivating | reloading) ;;
      *) return 0 ;;
    esac
    [ "$i" -lt "$READ_WAIT_TRIES" ] || return 1
    i=$((i + 1))
    sleep 1
  done
}

reader_result_ok() {
  local r
  r=$(systemctl show -p Result --value "$R_UNIT" 2>/dev/null || true)
  echo "READER-RESULT $r"
  [ "$r" = success ]
}

# ---------------------------------------------------------------- rollback

detach_records() {
  local line mode id kw
  [ -n "$XDP_LINES" ] || { echo NOTHING-ATTACHED; return 0; }
  while read -r line; do
    [ -n "$line" ] || continue
    mode=${line%% *}
    id=${line#* }
    if [[ ",$REC_IDS," == *",$id,"* ]]; then
      case "$mode" in
        driver) kw=xdpdrv ;;
        generic) kw=xdpgeneric ;;
        *) stop "xdp-mode-unknown $mode"; continue ;;
      esac
      if bpftool net detach "$kw" dev "$IFACE"; then
        echo "DETACHED mode=$mode id=$id $REC_NAME"
      else
        stop "detach-failed mode=$mode id=$id"
      fi
    elif [[ ",$OBS_IDS," == *",$id,"* ]]; then
      echo "KEEP-observer mode=$mode id=$id"
    else
      stop "xdp-foreign mode=$mode id=$id (not $REC_NAME; not detached)"
    fi
  done <<<"$XDP_LINES"
}

remove_our_pins() {
  local f left
  [ -d "$PIN_DIR" ] || { echo PINS-ABSENT; return 0; }
  for f in $PIN_NAMES; do
    if [ -e "$PIN_DIR/$f" ]; then
      rm -f "$PIN_DIR/$f" || stop "unpin-failed $f"
    fi
  done
  if rmdir "$PIN_DIR" 2>/dev/null; then
    echo PINS-REMOVED
  else
    left=$(pins_list)
    stop "pin-leftover $PIN_DIR: $left"
  fi
}

wait_records_gone() {
  local i=0
  while :; do
    scan
    [ "$REC_IDS" = none ] && return 0
    [ "$i" -lt "$WAIT_TRIES" ] || return 1
    i=$((i + 1))
    sleep "$WAIT_STEP"
  done
}

wait_observer() {
  local i=0
  while :; do
    check_observer && return 0
    [ "$i" -lt "$WAIT_TRIES" ] || return 1
    i=$((i + 1))
    sleep "$WAIT_STEP"
  done
}

# Collects STOPs (a rollback does every step it can). rc 1 if any.
rollback_core() {
  local a
  STOPS=0
  a=$(unit_active "$R_UNIT")
  case "$a" in
    active | activating | reloading)
      systemctl stop "$R_UNIT" || stop reader-stop-failed
      echo READER-STOPPED
      ;;
  esac
  scan
  detach_records
  scan
  case "$(attach_state)" in
    "records "*) stop "records-still-attached" ;;
  esac
  remove_our_pins
  if wait_records_gone; then
    echo "OK-no-$REC_NAME-loaded"
  else
    stop "prog-linger $REC_NAME ids=$REC_IDS"
  fi
  if [ "$(unit_active "$C1_UNIT")" != active ]; then
    if systemctl start "$C1_UNIT"; then
      echo C1-STARTED
    else
      stop c1-start-failed
    fi
  else
    echo C1-ALREADY-ACTIVE
  fi
  if wait_observer; then
    echo "OK-xdp-mode driver id=$OBS_ID $OBS_NAME"
  else
    stop "observer-not-back: $(attach_state) c1=$(unit_active "$C1_UNIT")"
  fi
  check_link
  [ "$STOPS" -eq 0 ] || return 1
  rm -f "$(baseline_file)"
  return 0
}

finish() {
  local rc=$?
  trap - EXIT INT TERM
  [ "$DONE" -eq 1 ] && exit 0
  [ "$rc" -ne 0 ] || rc=1
  if [ "$CLEANUP_ON_FAIL" -eq 1 ]; then
    echo REVERTING-TO-SLICE-1C
    if rollback_core; then
      echo M1S2-ROLLBACK-DONE
    else
      echo "STOP-rollback-failed. Run: sudo bash $STATE_DIR/module1-slice2-records.sh rollback"
    fi
  else
    echo NOTHING-CHANGED
  fi
  echo "M1S2-${ACTION^^}-STOPS"
  exit "$rc"
}

# ---------------------------------------------------------------- modes

common_gates() {
  gates || exit 1
  need_tools
}

m2_probe() {
  local v free
  common_gates
  need_slice1c_files
  echo "C1-UNIT enabled=$(systemctl is-enabled "$C1_UNIT" 2>/dev/null || true) active=$(unit_active "$C1_UNIT")"
  check_observer || die "observer-not-attached: $(attach_state) c1=$(unit_active "$C1_UNIT")"
  echo "OK-observer driver id=$OBS_ID"
  [ "$XDP_TOTAL" = 1 ] || die "xdp-progs-loaded $XDP_TOTAL (want 1: the observer)"
  [ "$REC_IDS" = none ] || die "records-already-loaded ids=$REC_IDS"
  [ ! -e "$PIN_DIR" ] || die "pin-dir-exists $PIN_DIR"
  grep -qs ' /sys/fs/bpf bpf ' "$PROC_ROOT/mounts" || die bpffs-not-mounted
  echo OK-bpffs
  echo "OK-reader-unit $(unit_active "$R_UNIT")"
  v=$(read_trim "$PROC_ROOT/sys/kernel/unprivileged_bpf_disabled")
  echo "NOTE-unprivileged_bpf_disabled ${v:-unknown}"
  echo "PYTHON $(python3 -I -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')"
  free=$(df -B1 --output=avail /var 2>/dev/null | awk 'NR == 2 { print $1 }')
  if ! [[ ${free:-x} =~ ^[0-9]+$ ]] || [ "$free" -lt $((1 << 30)) ]; then
    die "var-free ${free:-unknown} (want >= 1 GiB)"
  fi
  echo "OK-var-free $free"
  check_link
  [ "$STOPS" -eq 0 ] || exit 1
  echo M1S2-PROBE-DONE
}

m2_load() {
  local st cfg out
  common_gates
  need_slice1c_files
  need_installed
  check_observer || die "observer-not-attached: $(attach_state) c1=$(unit_active "$C1_UNIT")"
  echo "OK-observer driver id=$OBS_ID"
  [ "$XDP_TOTAL" = 1 ] || die "xdp-progs-loaded $XDP_TOTAL (want 1: the observer)"
  [ "$REC_IDS" = none ] || die "records-already-loaded ids=$REC_IDS"
  [ ! -e "$PIN_DIR" ] || die "pin-dir-exists $PIN_DIR"
  CLEANUP_ON_FAIL=1
  mkdir -m 0700 "$PIN_DIR" || die "mkdir-pin-dir $PIN_DIR"
  bpftool prog load "$(obj_path)" "$PIN_DIR/prog" pinmaps "$PIN_DIR" || die "load (verifier or bpftool refused the object; nothing was attached)"
  scan
  [[ $REC_IDS =~ ^[0-9]+$ ]] || die "load-not-visible ids=$REC_IDS"
  REC_ID=$REC_IDS
  [ "$(pins_list)" = "$PIN_NAMES" ] || die "pins-after-load: $(pins_list)"
  st=$(attach_state)
  [ "$st" = "observer $OBS_ID" ] || die "observer-changed-by-load: $st"
  emit_stats STAT || die stats-read-after-load
  [ "$LAST_PKTS" = 0 ] || die "readback-not-zero pkts=$LAST_PKTS"
  CTL=$(ctl_rows) || die ctl-read-after-load
  [ "$(ctl_val seen)" = 0 ] || die "ctl-not-zero seen=$(ctl_val seen)"
  cfg=$(cfg_line) || die cfg-read-after-load
  echo "CFG $cfg (ver 0 = compiled defaults: every 1, rate 2000/s/CPU, burst 4000)"
  echo "LOADED prog_id=$REC_ID (verifier accepted; not attached)"
  echo OK-readback-parse
  # Reader smoke: proves the unit's sandbox and capability set can open the
  # pins and map the ring, on an empty ring (nothing is attached).
  reader_start
  sleep "$SMOKE_SECS"
  systemctl stop "$R_UNIT" || die reader-stop-failed
  reader_wait_inactive || die reader-not-inactive
  out=$(reader_journal "$R_INV") || { printf '%s\n' "$out"; die reader-smoke-no-end; }
  printf '%s\n' "$out"
  reader_result_ok || die reader-smoke-result
  grep -q '^M1S2-READER-END reason=signal-15 records=0 ' <<<"$out" || die reader-smoke-end
  echo OK-reader-smoke
  echo "M1S2-LOAD-DONE prog_id=$REC_ID"
  DONE=1
}

m2_swap() {
  local snap
  common_gates
  need_slice1c_files
  need_installed
  check_observer || die "observer-not-attached: $(attach_state) c1=$(unit_active "$C1_UNIT")"
  [[ $REC_IDS =~ ^[0-9]+$ ]] || die "records-not-loaded ids=$REC_IDS (run load first)"
  REC_ID=$REC_IDS
  [ "$XDP_TOTAL" = 2 ] || die "xdp-progs-loaded $XDP_TOTAL (want 2: observer + records)"
  [ "$(pins_list)" = "$PIN_NAMES" ] || die "pins: $(pins_list)"
  load_cores || die "cores $CORES_ERR"
  snap=$(irq_snapshot) || die irq-snapshot
  irq_in_cores <<<"$(irq_norm <<<"$snap")" || die irq-outside-capture-cores
  { [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ]; } || die "state-dir $STATE_DIR"
  printf '%s\n' "$snap" > "$(baseline_file)" || die irq-baseline-write
  echo "OK-irq-baseline $(grep -c . "$(baseline_file)") lines"
  check_link
  [ "$STOPS" -eq 0 ] || exit 1
  CLEANUP_ON_FAIL=1
  echo "SWAP-BEGIN observer=$OBS_ID records=$REC_ID DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  systemctl stop "$C1_UNIT" || die c1-stop-failed
  wait_no_xdp || die "xdp-still-attached-after-c1-stop"
  echo OK-c1-stopped
  bpftool net attach xdpdrv pinned "$PIN_DIR/prog" dev "$IFACE" || die "attach (native xdpdrv refused; no generic fallback, no overwrite)"
  echo "ATTACHED xdpdrv prog_id=$REC_ID"
  wait_link_up || die link-not-up-after-attach
  sleep "$SETTLE_SECS"
  check_records_attached post-swap
  echo "C1-UNIT enabled=$(systemctl is-enabled "$C1_UNIT" 2>/dev/null || true) active=$(unit_active "$C1_UNIT")"
  echo M1S2-SWAP-DONE
  DONE=1
}

m2_read() {
  local out f
  common_gates
  need_installed
  check_records_attached pre-read
  reader_start
  echo "READER-STARTED invocation=$R_INV"
  reader_wait_inactive || die reader-overran
  out=$(reader_journal "$R_INV") || { printf '%s\n' "$out"; die reader-no-end; }
  printf '%s\n' "$out"
  reader_result_ok || die reader-result
  grep -q '^M1S2-READER-END reason=max-' <<<"$out" || die reader-end-reason
  f=$(find "$OUT_DIR" -maxdepth 1 -type f -name 'run-*.bin' -printf '%f\n' | sort | tail -n 1)
  [ -n "$f" ] || die no-run-file
  echo "RUN-FILE $OUT_DIR/$f mode=$(stat -c '%a %u:%g' "$OUT_DIR/$f") dir=$(stat -c '%a %u:%g' "$OUT_DIR")"
  python3 -I -B "$READER" --summary "$OUT_DIR/$f" --top 5 || die summary-failed
  check_records_attached post-read
  echo M1S2-READ-DONE
}

m2_verify() {
  local p0 s0 e0 d0 d1
  common_gates
  need_installed
  check_records_attached verify-start
  p0=$LAST_PKTS
  s0=$(ctl_val seen)
  e0=$(ctl_val emitted)
  d0=$(nic_drops)
  sleep "$SETTLE_SECS"
  check_records_attached verify-end
  d1=$(nic_drops)
  echo "VERIFY-WINDOW secs=$SETTLE_SECS pkts=$((LAST_PKTS - p0)) seen=$(($(ctl_val seen) - s0)) emitted=$(($(ctl_val emitted) - e0))"
  echo "NIC-DROP-DELTAS $(drop_deltas "$d0" "$d1")"
  [ "$LAST_PKTS" -gt "$p0" ] || die "no-traffic-verify (SPAN quiet?)"
  echo M1S2-VERIFY-DONE
}

m2_status() {
  local cfg
  common_gates
  scan
  echo "HOST $(hostname -s 2>/dev/null || hostname)"
  echo "ATTACH $(attach_state)"
  echo "PROG-XDP-COUNT $XDP_TOTAL records=$REC_IDS observer=$OBS_IDS"
  echo "C1-UNIT enabled=$(systemctl is-enabled "$C1_UNIT" 2>/dev/null || true) active=$(unit_active "$C1_UNIT")"
  echo "READER-UNIT active=$(unit_active "$R_UNIT")"
  if [ -d "$PIN_DIR" ]; then
    echo "PINS $(pins_list)"
    emit_stats STAT || echo NOTE-stats-unreadable
    if CTL=$(ctl_rows); then awk '{ print "CTL " $0 }' <<<"$CTL"; else echo NOTE-ctl-unreadable; fi
    if cfg=$(cfg_line); then echo "CFG $cfg"; else echo NOTE-cfg-unreadable; fi
  else
    echo "PINS dir=absent"
  fi
  link_facts
  echo "LINK $IFACE flags=$L_FLAGS speed=$L_SPEED carrier=$L_CARRIER oper=$L_OPER mtu=$L_MTU"
  echo "NIC $(nic_drops)"
  echo M1S2-STATUS-DONE
}

m2_rollback() {
  common_gates
  echo "M1S2-ROLLBACK-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if rollback_core; then
    echo M1S2-ROLLBACK-DONE
  else
    echo M1S2-ROLLBACK-STOPS
    exit 1
  fi
}

main() {
  umask 077
  export PATH="$SAFE_PATH"
  trap '' HUP PIPE
  ACTION=${1:-}
  case "$ACTION" in
    probe | load | swap | read | verify | status | rollback) ;;
    *) die args ;;
  esac
  [ "$#" -eq 1 ] || die args
  use_lib
  if [ "$ACTION" != probe ] && [ "$ACTION" != status ]; then
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock -n 9 || die locked
  fi
  case "$ACTION" in
    load | swap) trap finish EXIT INT TERM ;;
  esac
  "m2_$ACTION"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
