#!/bin/bash
# Module 1 slice 1c: boot-persistence helper for the passive, observe-only
# native-XDP program (j_xdp_observe) on eno1np0.
# Runbook: docs/tool-install/module1-slice1c-boot-unit.md
# Unit:    /etc/systemd/system/johnny-capture-xdp.service
#
#   sudo bash /root/m1s1b/module1-slice1c-boot.sh start    attach at boot (or verify if already attached)
#   sudo bash /root/m1s1b/module1-slice1c-boot.sh stop     detach our observer (idempotent)
#   sudo bash /root/m1s1b/module1-slice1c-boot.sh verify   read-only live verify + ethtool -S drop deltas
#   sudo bash /root/m1s1b/module1-slice1c-boot.sh status   read-only unit + observer status
#
# Root, on Johnny only. Installed at /root/m1s1b/module1-slice1c-boot.sh (0700,
# root:root) alongside the pinned slice 1b object, attach script, and detach
# script.
#
# Ordering and rev 89/90 cycle avoidance:
# - johnny-capture-xdp.service is ordered After=network-online.target and
#   After=johnny-capture-irq.service, WantedBy=multi-user.target.
# - Step 13 (irq-affinity.sh) refuses with STOP-xdp-present if XDP is already on
#   eno1np0, so johnny-capture-irq.service MUST finish before XDP attaches.
# - Neither the unit nor this script waits on johnny-capture-tuning.service
#   (which has After=multi-user.target): ordering Before multi-user.target and
#   After tuning caused the rev 89/90 systemd ordering cycle, and waiting for
#   tuning active inside a pre-multi-user.target oneshot caused the step 13c B1
#   boot deadlock. Tuning state is logged as a NOTE only.
# - WantedBy=multi-user.target (no Requires=/BindsTo=) makes any start failure
#   non-fatal to boot. On any failure after our program is loaded/attached,
#   this script runs the pinned detach helper so failure leaves nothing attached.
# - Native driver mode (xdpdrv) only; no generic/skb fallback; XDP_PASS only.
set -uo pipefail

# Plain variables, not read from the environment. The rock-box self-test
# overrides them after sourcing.
IFACE=eno1np0
SYSFS_NET=/sys/class/net
STATE_DIR=/root/m1s1b
SAFE_PATH=/usr/sbin:/usr/bin:/sbin:/bin
OBJ_SHA256=8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d
ATTACH_SHA256=f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb
DETACH_SHA256=f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58
HELPER=/etc/johnny/irq-affinity.sh
HELPER_SHA256=db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4
CORES=/etc/johnny/capture-cores
CORES_SHA256=16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b
UNIT_FILE=/etc/systemd/system/johnny-capture-xdp.service
UNIT_SHA256=2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0
KERNEL_WANT=7.0.0-42-generic
BOOT_LOCK_FILE=/run/johnny-m1s1c-boot.lock
IRQ_WANT=12
COMBINED_WANT=12
WAIT_STEP=2
WAIT_BOOT_TRIES=30
WAIT_NOTE_EVERY=3
VERIFY_SECS=5
FLUSH_WAIT=1
CLEANUP_ON_FAIL=0
DONE=0
ACTION=
ST=
PROG_ID=

obj_path() { printf '%s/module1-xdp-observe.o' "$STATE_DIR"; }
attach_path() { printf '%s/module1-slice1b-attach.sh' "$STATE_DIR"; }
detach_path() { printf '%s/module1-slice1b-detach.sh' "$STATE_DIR"; }
baseline_file() { printf '%s/irq-baseline.txt' "$STATE_DIR"; }
boot_log_file() { printf '%s/boot.log' "$STATE_DIR"; }

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

# Test seams: functions, so the rock-box self-test can redefine them.
run_attach() {
  bash "$(attach_path)" attach
}

run_detach() {
  bash "$(detach_path)" "$@"
}

owner_ok() {
  local o m
  [ ! -L "$1" ] && [ -f "$1" ] || return 1
  o=$(stat -c '%u:%g' "$1")
  [ "$o" = 0:0 ] || return 1
  m=$(stat -c '%a' "$1")
  [[ $m =~ ^[0-7]*[0145][0145]$ ]]
}

start_boot_log() {
  exec > >(tee -a "$(boot_log_file)") 2>&1
}

finish_start() {
  local rc=$?
  trap - EXIT INT TERM
  if [ "$DONE" -eq 1 ]; then
    exit 0
  fi
  [ "$rc" -ne 0 ] || rc=1
  if [ "$CLEANUP_ON_FAIL" -eq 1 ]; then
    echo REVERTING-TO-CLEAN-UNATTACHED
    if ! run_detach detach; then
      echo "STOP-rollback-failed. Run: sudo bash $(detach_path) detach"
    fi
  else
    echo NOTHING-CHANGED
  fi
  echo M1S1C-START-STOPS
  sleep "$FLUSH_WAIT"
  exit "$rc"
}

gate_host() {
  local host kern
  host=$(hostname -s 2>/dev/null || hostname)
  [ "$host" = johnny ] || stop host
  [ "$(id -u)" -eq 0 ] || stop not-root
  kern=$(uname -r)
  [ "$kern" = "$KERNEL_WANT" ] || stop "kernel $kern"
  [ -d "$SYSFS_NET/$IFACE" ] || stop "no-iface $IFACE"
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
  root_file_ok attach "$(attach_path)" "$ATTACH_SHA256"
  root_file_ok rollback "$(detach_path)" "$DETACH_SHA256"
  { [ ! -L "$HELPER" ] && [ -f "$HELPER" ] && [ -x "$HELPER" ]; } || stop "irq-helper-missing $HELPER"
  got=$(sha256sum "$HELPER" | awk '{print $1}')
  [ "$got" = "$HELPER_SHA256" ] || stop "irq-helper-hash $got"
  echo "OK-irq-helper-hash $HELPER_SHA256"
  { [ ! -L "$CORES" ] && [ -f "$CORES" ]; } || stop "cores-missing $CORES"
  got=$(sha256sum "$CORES" | awk '{print $1}')
  [ "$got" = "$CORES_SHA256" ] || stop "cores-hash $got"
  echo "OK-cores-hash $CORES_SHA256"
}

need_unit_file() {
  root_file_ok unit "$UNIT_FILE" "$UNIT_SHA256"
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

combined_now() {
  local out
  out=$(ethtool -l "$IFACE" 2>/dev/null) || return 1
  awk '/^Current hardware settings/ { c = 1; next } c && /^Combined:/ { print $2; f = 1 } END { exit f ? 0 : 1 }' <<<"$out"
}

within_tol() {
  local d=$1 pkts=$2 tol
  [[ $d =~ ^-?[0-9]+$ ]] || return 1
  [ "$d" -ge 0 ] || d=$((-d))
  tol=$((pkts / 100))
  [ "$tol" -ge 256 ] || tol=256
  [ "$d" -le "$tol" ]
}

eno1_ready_now() {
  local flags speed carrier oper mtu a4 a6
  flags=$(read_trim "$SYSFS_NET/$IFACE/flags")
  speed=$(read_trim "$SYSFS_NET/$IFACE/speed")
  carrier=$(read_trim "$SYSFS_NET/$IFACE/carrier")
  oper=$(read_trim "$SYSFS_NET/$IFACE/operstate")
  mtu=$(read_trim "$SYSFS_NET/$IFACE/mtu")
  flags_capture_ok "$flags" || return 1
  [ "$speed" = 10000 ] || return 1
  [ "$carrier" = 1 ] || [ "$oper" = up ] || return 1
  [ "$mtu" = 1500 ] || return 1
  a4=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null || true)
  a6=$(ip -6 -o addr show dev "$IFACE" 2>/dev/null || true)
  [ -z "$a4" ] && [ -z "$a6" ]
}

# Bounded boot wait (step 13c/13d lesson): wait for eno1np0 link/flags/MTU,
# eno3 mgmt IPv4 + default route, and johnny-capture-irq.service active.
# Never wait on johnny-capture-tuning.service (After=multi-user.target).
wait_boot_ready() {
  local i=0 r1 r3 rirq irq_ac
  while :; do
    r1=0
    r3=0
    rirq=0
    eno1_ready_now || r1=1
    eno3_ok || r3=1
    irq_ac=$(systemctl is-active johnny-capture-irq.service 2>/dev/null || true)
    [ "$irq_ac" = active ] || rirq=1
    if [ "$r1" -eq 0 ] && [ "$r3" -eq 0 ] && [ "$rirq" -eq 0 ]; then
      return 0
    fi
    if [ "$i" -ge "$WAIT_BOOT_TRIES" ]; then
      return 1
    fi
    if [ $((i % WAIT_NOTE_EVERY)) -eq 0 ]; then
      [ "$r1" -eq 0 ] || echo "NOTE-wait-eno1 try=$i"
      [ "$r3" -eq 0 ] || echo "NOTE-wait-eno3 try=$i"
      [ "$rirq" -eq 0 ] || echo "NOTE-wait-irq-service try=$i state=${irq_ac:-unknown}"
    fi
    i=$((i + 1))
    sleep "$WAIT_STEP"
  done
}

check_common_env() {
  local en ac irq_ac tun_ac
  en=$(systemctl is-enabled suricata 2>/dev/null || true)
  ac=$(systemctl is-active suricata 2>/dev/null || true)
  { [ "$en" = disabled ] && [ "$ac" = inactive ]; } || stop "suricata ${en:-?}/${ac:-?}"
  echo "OK-suricata $en/$ac"
  irq_ac=$(systemctl is-active johnny-capture-irq.service 2>/dev/null || true)
  [ "$irq_ac" = active ] || stop "irq-service-not-active ${irq_ac:-unknown}"
  echo "OK-irq-service $irq_ac"
  tun_ac=$(systemctl is-active johnny-capture-tuning.service 2>/dev/null || true)
  if [ "$tun_ac" = active ]; then
    echo "OK-tuning-service active"
  else
    echo "NOTE-johnny-capture-tuning.service ${tun_ac:-unknown}"
  fi
  eno3_ok || stop eno3-not-as-recorded
  echo OK-eno3
}

# Verify all post-attach / live invariants from $ST (populated by get_status).
verify_attached_invariants() {
  local tag=$1 xdp_line ours_line pid line flags speed carrier oper mtu combined pkts part_line l3 l4
  get_status || {
    printf '%s\n' "$ST"
    stop "status-failed-$tag"
  }
  xdp_line=$(st_first XDP-ATTACH)
  ours_line=$(st_first PROG-OURS)
  case "$ours_line" in
    "PROG-OURS 1 ids="*) pid=${ours_line#*ids=} ;;
    *) stop "prog-ours-$tag: $ours_line" ;;
  esac
  [[ $pid =~ ^[0-9]+$ ]] || stop "prog-id-$tag: $pid"
  PROG_ID=$pid
  [ "$xdp_line" = "XDP-ATTACH driver id=$PROG_ID" ] || stop "xdp-mode-or-id-$tag: $xdp_line (want driver id=$PROG_ID)"
  [ "$(st_first PROG-XDP-COUNT)" = "PROG-XDP-COUNT 1" ] || stop "prog-count-$tag: $(st_first PROG-XDP-COUNT)"
  case "$(st_first PINS)" in
    "PINS dir=present prog=present stats=present rxq=present") ;;
    *) stop "pins-$tag: $(st_first PINS)" ;;
  esac
  line=$(st_first LINK)
  flags=$(kv "$line" flags || true)
  speed=$(kv "$line" speed || true)
  carrier=$(kv "$line" carrier || true)
  oper=$(kv "$line" oper || true)
  mtu=$(kv "$line" mtu || true)
  flags_capture_ok "$flags" || stop "eno1-flags-$tag $flags (need UP, PROMISC, NOARP)"
  [ "$speed" = 10000 ] || stop "eno1-speed-$tag ${speed:-none}"
  [ "$carrier" = 1 ] || [ "$oper" = up ] || stop "eno1-link-$tag carrier=$carrier oper=$oper"
  [ "$mtu" = 1500 ] || stop "mtu-$tag ${mtu:-none}"
  case "$ST" in
    *NOTE-eno1-has-address*) stop "eno1-address-$tag" ;;
  esac
  combined=$(combined_now) || stop "ethtool-l-$tag"
  [ "$combined" = "$COMBINED_WANT" ] || stop "queues-$tag combined=$combined (want $COMBINED_WANT)"
  eno3_ok || stop "eno3-changed-$tag"
  [ "$(st_first IRQ-COUNT)" = "IRQ-COUNT $IRQ_WANT" ] || stop "irq-count-$tag: $(st_first IRQ-COUNT)"
  [ "$(st_first IRQ-CAPTURE)" = "IRQ-CAPTURE ok" ] || stop "irq-outside-capture-cores-$tag"
  [ "$(st_first IRQ-BASELINE)" = "IRQ-BASELINE same" ] || stop "irq-pins-moved-$tag: $(st_first IRQ-BASELINE)"
  pkts=$(stat_val pkts)
  [[ $pkts =~ ^[0-9]+$ ]] || stop "stat-pkts-$tag"
  part_line=$(awk '$1 == "PART" { print; exit }' <<<"$ST")
  l3=$(kv "$part_line" l3_diff || true)
  l4=$(kv "$part_line" l4_diff || true)
  within_tol "$l3" "$pkts" || stop "partition-l3-$tag diff=$l3 pkts=$pkts"
  within_tol "$l4" "$pkts" || stop "partition-l4-$tag diff=$l4 pkts=$pkts"
  echo "OK-xdp-mode driver id=$PROG_ID ($tag)"
  echo "OK-irq-pins-unchanged ($tag)"
  echo "OK-link-queues-eno3 ($tag) combined=$combined $line"
  echo "OK-partition ($tag) l3_diff=$l3 l4_diff=$l4"
}

do_start() {
  local xdp_line prog_count ours_line pid attach_out
  trap finish_start EXIT
  trap 'exit 130' INT TERM
  mkdir -p "$STATE_DIR"
  start_boot_log
  echo "M1S1C-START-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  need_tools
  need_files
  wait_boot_ready || true
  check_common_env
  get_status || {
    printf '%s\n' "$ST"
    stop status-failed-preflight
  }
  [ "$(st_first IRQ-COUNT)" = "IRQ-COUNT $IRQ_WANT" ] || stop "irq-count-preflight: $(st_first IRQ-COUNT)"
  [ "$(st_first IRQ-CAPTURE)" = "IRQ-CAPTURE ok" ] || stop "irq-outside-capture-cores-preflight"
  xdp_line=$(st_first XDP-ATTACH)
  prog_count=$(st_first PROG-XDP-COUNT)
  ours_line=$(st_first PROG-OURS)
  if [ "$xdp_line" = "XDP-ATTACH none" ]; then
    # Cold boot or unattached state. If leftover pins or unattached j_xdp_observe
    # exist (and no foreign XDP program is loaded), clean them before attaching.
    if [ "$prog_count" != "PROG-XDP-COUNT 0" ] || [ "$(st_first PINS)" != "PINS dir=absent" ]; then
      case "$ours_line" in
        "PROG-OURS 0 "*)
          if [ "$prog_count" != "PROG-XDP-COUNT 0" ]; then
            stop "xdp-foreign-progs-loaded: $prog_count"
          fi
          ;;
      esac
      echo "NOTE-cleaning-stale-ours-before-attach"
      CLEANUP_ON_FAIL=1
      run_detach detach || stop "stale-cleanup-failed"
    fi
    CLEANUP_ON_FAIL=1
    if ! attach_out=$(run_attach 2>&1); then
      printf '%s\n' "$attach_out"
      stop "attach-helper-failed"
    fi
    printf '%s\n' "$attach_out"
    case "$attach_out" in
      *M1S1B-ATTACH-DONE*) ;;
      *) stop "attach-helper-missing-token" ;;
    esac
    verify_attached_invariants post-start
    echo "STATE attached by boot helper (xdpdrv prog_id=$PROG_ID)"
  elif [[ $xdp_line =~ ^XDP-ATTACH[[:space:]]+driver[[:space:]]+id=([0-9]+)$ ]]; then
    pid=${BASH_REMATCH[1]}
    if [ "$ours_line" != "PROG-OURS 1 ids=$pid" ] || [ "$prog_count" != "PROG-XDP-COUNT 1" ]; then
      stop "xdp-foreign-attached: $xdp_line ($ours_line, $prog_count)"
    fi
    # Our program is already attached in native driver mode (e.g. slice 1b this boot).
    # Any invariant failure on our own attachment detaches cleanly.
    CLEANUP_ON_FAIL=1
    if [ "$(st_first IRQ-BASELINE)" = "IRQ-BASELINE none" ]; then
      awk 'index($0, "IRQ-SNAP ") == 1' <<<"$ST" > "$(baseline_file)"
      chmod 600 "$(baseline_file)"
      echo "IRQ-BASELINE-SAVED $(baseline_file)"
    fi
    verify_attached_invariants already-attached
    echo "ALREADY-ATTACHED xdpdrv prog_id=$PROG_ID"
  else
    # Generic or offload or malformed attachment. If it is ours, detach it and fail.
    case "$ours_line" in
      "PROG-OURS 1 ids="*)
        CLEANUP_ON_FAIL=1
        stop "xdp-mode-not-driver: $xdp_line"
        ;;
      *)
        stop "xdp-foreign-or-unexpected: $xdp_line"
        ;;
    esac
  fi
  DONE=1
  echo M1S1C-START-DONE
  sleep "$FLUSH_WAIT"
}

do_stop() {
  local det_out
  echo "M1S1C-STOP-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  need_tools
  root_file_ok rollback "$(detach_path)" "$DETACH_SHA256"
  { [ ! -L "$HELPER" ] && [ -f "$HELPER" ] && [ -x "$HELPER" ]; } || stop "irq-helper-missing $HELPER"
  [ "$(sha256sum "$HELPER" | awk '{print $1}')" = "$HELPER_SHA256" ] || stop "irq-helper-hash"
  { [ ! -L "$CORES" ] && [ -f "$CORES" ]; } || stop "cores-missing $CORES"
  [ "$(sha256sum "$CORES" | awk '{print $1}')" = "$CORES_SHA256" ] || stop "cores-hash"
  if ! det_out=$(run_detach detach 2>&1); then
    printf '%s\n' "$det_out"
    echo M1S1C-STOP-STOPS
    exit 1
  fi
  printf '%s\n' "$det_out"
  case "$det_out" in
    *M1S1B-DETACH-DONE*) ;;
    *)
      echo M1S1C-STOP-STOPS
      exit 1
      ;;
  esac
  get_status || {
    printf '%s\n' "$ST"
    echo M1S1C-STOP-STOPS
    exit 1
  }
  [ "$(st_first XDP-ATTACH)" = "XDP-ATTACH none" ] || {
    echo "STOP-still-attached: $(st_first XDP-ATTACH)"
    echo M1S1C-STOP-STOPS
    exit 1
  }
  [ "$(st_first PINS)" = "PINS dir=absent" ] || {
    echo "STOP-pins-remain: $(st_first PINS)"
    echo M1S1C-STOP-STOPS
    exit 1
  }
  [ "$(st_first IRQ-COUNT)" = "IRQ-COUNT $IRQ_WANT" ] || {
    echo "STOP-irq-count-after-stop: $(st_first IRQ-COUNT)"
    echo M1S1C-STOP-STOPS
    exit 1
  }
  [ "$(st_first IRQ-CAPTURE)" = "IRQ-CAPTURE ok" ] || {
    echo "STOP-irq-outside-after-stop: $(st_first IRQ-CAPTURE)"
    echo M1S1C-STOP-STOPS
    exit 1
  }
  echo M1S1C-STOP-DONE
}

# Read-only tcpdump capture for VERIFY_SECS: outputs "captured kernel_drops".
tcpdump_verify_counts() {
  local secs=$1 err cap kd
  err=$(mktemp "$STATE_DIR/tcpdump-verify.XXXXXX") || return 1
  timeout -s INT "$secs" tcpdump -p -nn -i "$IFACE" -w /dev/null 2>"$err" || true
  cap=$(awk '/ packets captured$/ { print $1 }' "$err")
  kd=$(awk '/ packets dropped by kernel$/ { print $1 }' "$err")
  rm -f "$err"
  [[ $cap =~ ^[0-9]+$ ]] || return 1
  [[ $kd =~ ^[0-9]+$ ]] || kd=unknown
  printf '%s %s\n' "$cap" "$kd"
}

# Per-reason ethtool -S drop/error/discard counter deltas across the verify
# window for the open nic-rx-dropped observation. No root-cause claim.
emit_ethtool_drop_deltas() {
  local before=$1 after=$2
  if [ -z "$before" ] || [ -z "$after" ]; then
    echo "NOTE-ethtool-S-unavailable"
    return 0
  fi
  awk '
    $0 == "---AFTER---" { in_after = 1; next }
    NF == 2 {
      k = $1
      v = $2
      if (k ~ /:$/) {
        sub(/:$/, "", k)
        if (k ~ /^[A-Za-z0-9_.-]+$/ && v ~ /^[0-9]+$/) {
          if (!in_after) {
            b[k] = v + 0
          } else if (k in b) {
            d = (v + 0) - b[k]
            if (k ~ /(drop|disc|err|miss|over|fifo|oob|fail|alloc|crc|csum|jabber|undersize|oversize|frag|unknown)/) {
              seen++
              if (d != 0) {
                printf "ETHTOOL-DROP-DELTA %s=%d (before=%d after=%d)\n", k, d, b[k], v + 0
                nz++
              }
            }
          }
        }
      }
    }
    END {
      if (nz + 0 == 0) {
        printf "ETHTOOL-DROP-DELTAS none (checked=%d)\n", seen + 0
      }
    }
  ' <<<"$before"$'\n---AFTER---\n'"$after"
}

do_verify() {
  local u_en u_ac p0 p1 b0 b1 n0 n1 r0 r1 es0 es1 tc cap kd dp db dn dr pct
  echo "M1S1C-VERIFY-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  need_tools
  need_files
  need_unit_file
  u_en=$(systemctl is-enabled johnny-capture-xdp.service 2>/dev/null || true)
  u_ac=$(systemctl is-active johnny-capture-xdp.service 2>/dev/null || true)
  [ "$u_en" = enabled ] || stop "unit-not-enabled ${u_en:-unknown}"
  [ "$u_ac" = active ] || stop "unit-not-active ${u_ac:-unknown}"
  echo "OK-unit johnny-capture-xdp.service enabled=$u_en active=$u_ac"
  check_common_env
  verify_attached_invariants verify-before
  p0=$(stat_val pkts)
  b0=$(stat_val bytes)
  n0=$(nic_stat rx_packets)
  r0=$(nic_stat rx_dropped)
  es0=$(ethtool -S "$IFACE" 2>/dev/null || true)
  tc=$(tcpdump_verify_counts "$VERIFY_SECS") || stop "tcpdump-verify-failed"
  cap=${tc%% *}
  kd=${tc#* }
  verify_attached_invariants verify-after
  p1=$(stat_val pkts)
  b1=$(stat_val bytes)
  n1=$(nic_stat rx_packets)
  r1=$(nic_stat rx_dropped)
  es1=$(ethtool -S "$IFACE" 2>/dev/null || true)
  dp=$((p1 - p0))
  db=$((b1 - b0))
  dn=$((n1 - n0))
  dr=$((r1 - r0))
  echo "VERIFY-WINDOW secs=$VERIFY_SECS xdp-pkts-delta=$dp xdp-bytes-delta=$db tcpdump-captured=$cap tcpdump-kernel-drops=$kd nic-rx-delta=$dn nic-rx-dropped-delta=$dr"
  if [ "$dp" -le 0 ]; then
    if [ "$dn" -gt 0 ]; then
      stop "observer-no-count (NIC rx_packets delta=$dn, xdp pkts delta=0)"
    fi
    stop "no-traffic-verify (SPAN quiet during verify window)"
  fi
  if [ "$cap" -le 0 ]; then
    stop "pass-broken-verify (xdp counted $dp frames, tcpdump captured 0)"
  fi
  pct=$((cap * 100 / dp))
  echo "PASS-RATIO tcpdump=$cap xdp=$dp pct=$pct"
  [ "$pct" -ge 80 ] || echo "NOTE-pass-ratio-low pct=$pct"
  [ "$dr" -le 0 ] || echo "NOTE-nic-rx-dropped-up delta=$dr (see ETHTOOL-DROP-DELTA lines below; no root cause claimed)"
  emit_ethtool_drop_deltas "$es0" "$es1"
  echo OK-xdp-pass-tcpdump-sees-traffic
  awk 'index($0, "IRQ-SNAP ") == 1 { sub(/^IRQ-SNAP/, "IRQ-VERIFY"); print }' <<<"$ST"
  awk '$1 == "STAT" || $1 == "STAT-RXQ" || $1 == "PART" || $1 == "PROG-XDP-COUNT"' <<<"$ST"
  echo M1S1C-VERIFY-DONE
}

do_status() {
  local svc en ac
  need_tools
  need_files
  if [ -e "$UNIT_FILE" ]; then
    need_unit_file
  else
    echo "NOTE-unit-file-absent $UNIT_FILE"
  fi
  for svc in johnny-capture-xdp.service johnny-capture-irq.service johnny-capture-tuning.service suricata; do
    en=$(systemctl is-enabled "$svc" 2>/dev/null || true)
    ac=$(systemctl is-active "$svc" 2>/dev/null || true)
    echo "UNIT $svc enabled=${en:-unknown} active=${ac:-unknown}"
  done
  if ! get_status; then
    printf '%s\n' "$ST"
    echo M1S1C-STATUS-STOPS
    exit 1
  fi
  printf '%s\n' "$ST"
  echo M1S1C-STATUS-DONE
}

main() {
  umask 077
  export PATH="$SAFE_PATH"
  trap '' HUP PIPE
  ACTION=${1:-}
  case "$ACTION" in
    start | stop | verify | status) ;;
    *)
      echo STOP-args
      exit 1
      ;;
  esac
  gate_host
  if [ "$ACTION" = status ]; then
    do_status
    return
  fi
  mkdir -p "$STATE_DIR"
  mkdir -p "$(dirname "$BOOT_LOCK_FILE")"
  exec 7>"$BOOT_LOCK_FILE"
  flock -n 7 || stop locked
  case "$ACTION" in
    start) do_start ;;
    stop) do_stop ;;
    verify) do_verify ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
