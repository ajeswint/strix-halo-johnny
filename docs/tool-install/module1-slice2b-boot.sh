#!/usr/bin/env bash
# Johnny Module 1 slice 2b: boot-time j_xdp_records program on eno1np0 and
# persistent rotating ring-buffer reader.
#
# Design:    docs/tool-install/module1-slice2-ringbuf-design.md
# Runbook:   docs/tool-install/module1-slice2b-boot-unit.md
# Installed: /root/m1s2b/module1-slice2b-boot.sh (0700 root:root)
# Unit:      etc/systemd/system/johnny-capture-xdp-records.service
# Reader:    docs/tool-install/johnny-m1s2b-reader.py -> /usr/local/libexec/johnny/johnny-m1s2b-reader.py
#
# Commands: start | stop | verify | status | apply-cfg | mark-reader | window [SECS] | week [--precheck]

set -euo pipefail

STATE_DIR=/root/m1s2b
PIN_DIR=/sys/fs/bpf/johnny_m1s2b
OUT_DIR=/var/lib/johnny/m1s2b
SAFE_PATH=/usr/sbin:/usr/bin:/sbin:/bin
LOCK_FILE=/run/johnny-m1s2b.lock
IFACE=eno1np0
SYSFS_NET=/sys/class/net
HOST_WANT=johnny
KERNEL_WANT=7.0.0-42-generic

CORES=/etc/johnny/capture-cores
CORES_SHA256=16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b
HELPER=/etc/johnny/irq-affinity.sh
HELPER_SHA256=db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4

OBJ_SHA256=a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481
READER=/usr/local/libexec/johnny/johnny-m1s2b-reader.py
READER_SHA256=476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37
R_UNIT_FILE=/etc/systemd/system/johnny-m1s2b-reader.service
R_UNIT_SHA256=e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c
R_UNIT=johnny-m1s2b-reader.service
UNIT_FILE=/etc/systemd/system/johnny-capture-xdp-records.service
UNIT_SHA256=4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a
UNIT=johnny-capture-xdp-records.service
C1_UNIT=johnny-capture-xdp.service

OBS_NAME=j_xdp_observe
REC_NAME=j_xdp_records
PIN_NAMES="m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state prog"
CTL_NAMES="seen sampled_out rate_limited rb_full emitted discarded"
CFG_WANT="ver=1 sample_every=1 rate=1000000 burst=100000"
CFG_HEX="01 00 00 00 01 00 00 00 40 42 0f 00 a0 86 01 00"
COMBINED_WANT=12
IRQ_WANT=12
WAIT_BOOT_TRIES=30
WAIT_STEP=2
WAIT_NOTE_EVERY=5
VERIFY_SECS=5
SETTLE_SECS=1
FLUSH_WAIT=0.1

STOPS=0
DONE=0
CLEANUP_ON_FAIL=0
XDP_LINES=""
REC_IDS=""
OBS_IDS=""
XDP_TOTAL=0
REC_PIN_ID=""
REC_ID=""
OBS_ID=""
CTL=""

# ---------------------------------------------------------------- helpers

obj_path() { echo "$STATE_DIR/module1-xdp-records.o"; }
baseline_file() { echo "$STATE_DIR/irq-baseline.txt"; }
no_ratecap_baseline_file() { echo "$STATE_DIR/no-ratecap-baseline.txt"; }
boot_log_file() { echo "$STATE_DIR/boot.log"; }

stop() {
  echo "STOP-$*" >&2
  STOPS=$((STOPS + 1))
  exit 1
}

read_trim() {
  local p=$1
  [ -f "$p" ] || return 1
  tr -d '\n\r ' <"$p"
}

kv() {
  local line=$1 k=$2
  awk -v k="$k" '{
    for (i = 1; i <= NF; i++) {
      if (index($i, k "=") == 1) {
        print substr($i, length(k) + 2)
        exit
      }
    }
  }' <<<"$line"
}

owner_ok() {
  local p=$1 o m
  [ -f "$p" ] && [ ! -L "$p" ] || return 1
  o=$(stat -c '%u:%g' "$p" 2>/dev/null || true)
  [ "$o" = "0:0" ] || return 1
  m=$(stat -c '%a' "$p" 2>/dev/null || true)
  [[ $m =~ ^[0-7]*[0145][0145]$ ]]
}

flags_capture_ok() {
  local f=$1
  [[ $f =~ ^0x[0-9a-fA-F]+$ ]] || return 1
  local n=$((f))
  [ $((n & 0x1)) -ne 0 ] || return 1      # IFF_UP
  [ $((n & 0x100)) -ne 0 ] || return 1    # IFF_PROMISC
  [ $((n & 0x80)) -ne 0 ] || return 1     # IFF_NOARP
  return 0
}

start_boot_log() {
  exec > >(tee -a "$(boot_log_file)") 2>&1
}

finish_start() {
  local ec=$?
  if [ "$DONE" -eq 1 ] && [ "$ec" -eq 0 ]; then
    return 0
  fi
  if [ "$CLEANUP_ON_FAIL" -eq 1 ]; then
    echo "REVERTING-TO-CLEAN-UNATTACHED (failure during start, ec=$ec)" >&2
    detach_records || true
    remove_our_pins || true
  fi
  echo "M1S2B-START-STOPS ec=$ec" >&2
}

# ---------------------------------------------------------------- gates & files

gate_host() {
  local h k
  [ "$(id -u)" -eq 0 ] || stop not-root
  h=$(hostname -s 2>/dev/null || hostname)
  [ "$h" = "$HOST_WANT" ] || stop "host $h (want $HOST_WANT)"
  k=$(uname -r)
  [ "$k" = "$KERNEL_WANT" ] || stop "kernel $k (want $KERNEL_WANT)"
  [ -d "$SYSFS_NET/$IFACE" ] || stop "no-iface $IFACE"
}

need_tools() {
  local t
  for t in bpftool systemctl ip ethtool awk python3 sha256sum stat timeout tcpdump mktemp journalctl du df find sort date; do
    command -v "$t" >/dev/null 2>&1 || stop "tool-missing $t"
  done
}

root_file_ok() {
  local what=$1 path=$2 want=$3 got
  owner_ok "$path" || stop "$what-not-root-owned-or-missing $path"
  got=$(sha256sum "$path" | awk '{print $1}')
  [ "$got" = "$want" ] || stop "$what-hash $got (want $want)"
  echo "OK-$what-hash $want"
}

need_files() {
  local got
  root_file_ok object "$(obj_path)" "$OBJ_SHA256"
  root_file_ok reader "$READER" "$READER_SHA256"
  root_file_ok reader-unit "$R_UNIT_FILE" "$R_UNIT_SHA256"
  root_file_ok boot-unit "$UNIT_FILE" "$UNIT_SHA256"
  { [ ! -L "$HELPER" ] && [ -f "$HELPER" ] && [ -x "$HELPER" ]; } || stop "irq-helper-missing $HELPER"
  got=$(sha256sum "$HELPER" | awk '{print $1}')
  [ "$got" = "$HELPER_SHA256" ] || stop "irq-helper-hash $got"
  echo "OK-irq-helper-hash $HELPER_SHA256"
  { [ ! -L "$CORES" ] && [ -f "$CORES" ]; } || stop "cores-missing $CORES"
  got=$(sha256sum "$CORES" | awk '{print $1}')
  [ "$got" = "$CORES_SHA256" ] || stop "cores-hash $got"
  echo "OK-cores-hash $CORES_SHA256"
}

# ---------------------------------------------------------------- status / BPF state

net_attach_lines() {
  local js
  js=$(bpftool -j net show dev "$IFACE" 2>/dev/null) || return 1
  python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(2)
if not isinstance(d, list) or not d:
    sys.exit(0)
row = d[0]
for x in row.get("xdp", []):
    m = x.get("mode")
    i = x.get("id")
    if m and i is not None:
        print("%s %d" % (m, i))
' <<<"$js"
}

pinned_rec_id() {
  local js
  [ -e "$PIN_DIR/prog" ] || return 0
  js=$(bpftool -j prog show pinned "$PIN_DIR/prog" 2>/dev/null) || return 1
  python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(2)
if not isinstance(d, dict) or d.get("name") != sys.argv[1] or type(d.get("id")) is not int:
    sys.exit(2)
print(d["id"])' "$REC_NAME" <<<"$js"
}

progs_from_json() {
  python3 -I -c '
import json, sys
want = sys.argv[1]
try:
    rows = json.load(sys.stdin)
except ValueError:
    sys.exit(2)
ids = [r["id"] for r in rows if isinstance(r, dict) and r.get("name") == want and type(r.get("id")) is int]
total = sum(1 for r in rows if isinstance(r, dict) and r.get("type") == "xdp")
print("total=%d count=%d ids=%s" % (total, len(ids), ",".join(str(i) for i in sorted(ids)) if ids else "none"))
' "$1"
}

scan() {
  local js pr po
  XDP_LINES=$(net_attach_lines) || stop net-show-failed
  js=$(bpftool -j prog show 2>/dev/null) || stop prog-show-failed
  pr=$(progs_from_json "$REC_NAME" <<<"$js") || stop prog-parse-failed
  po=$(progs_from_json "$OBS_NAME" <<<"$js") || stop prog-parse-failed
  XDP_TOTAL=$(kv "$pr" total)
  REC_IDS=$(kv "$pr" ids)
  OBS_IDS=$(kv "$po" ids)
  REC_PIN_ID=$(pinned_rec_id) || stop pinned-prog-show-failed
}

attach_state() {
  local n mode id
  n=$(grep -c . <<<"$XDP_LINES" || true)
  [ "$n" -eq 0 ] && { echo none; return; }
  [ "$n" -eq 1 ] || { echo multi; return; }
  mode=${XDP_LINES%% *}
  id=${XDP_LINES#* }
  if [ "$mode" != driver ]; then
    echo "other $mode $id"
  elif [ -n "$REC_PIN_ID" ] && [ "$id" = "$REC_PIN_ID" ]; then
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

cfg_line() {
  local js
  [ -e "$PIN_DIR/m2_cfg" ] || return 1
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
    elif isinstance(it.get("value"), dict):
        v = it["value"]
        vals = [int(v[k]) for k in ("ver", "sample_every", "rate", "burst")]
    else:
        raw = bytes(int(b, 16) if isinstance(b, str) else int(b) for b in it["value"])
        vals = list(struct.unpack("<IIII", raw))
except (ValueError, KeyError, IndexError, TypeError, struct.error):
    sys.exit(2)
print("ver=%d sample_every=%d rate=%d burst=%d" % tuple(vals))
' <<<"$js"
}

write_and_verify_cfg() {
  local cfg
  # shellcheck disable=SC2086
  bpftool map update pinned "$PIN_DIR/m2_cfg" key hex 00 00 00 00 value hex $CFG_HEX || return 1
  cfg=$(cfg_line) || return 1
  [ "$cfg" = "$CFG_WANT" ] || return 1
  echo "OK-cfg $cfg"
}

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

# "name total" per m2_ctl slot, in CTL_NAMES order. rc 1 on any read/parse error.
ctl_rows() {
  local js rows k t i=0 name
  local -a names
  [ -e "$PIN_DIR/m2_ctl" ] || return 1
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

dump_stats() {
  local js rows k t
  declare -A got=()
  [ -e "$PIN_DIR/m1_stats" ] || return 1
  js=$(bpftool -j map dump pinned "$PIN_DIR/m1_stats" 2>/dev/null) || return 1
  rows=$(percpu_from_json <<<"$js") || return 1
  while read -r k t; do
    [ -n "$k" ] && got[$k]=$t
  done <<<"$rows"
  [ -n "${got[0]:-}" ] && [ -n "${got[1]:-}" ] || return 1
  printf 'pkts=%s bytes=%s\n' "${got[0]}" "${got[1]}"
}

# ---------------------------------------------------------------- network & IRQ

eno3_ok() {
  local a r
  a=$(ip -4 -o addr show dev eno3 2>/dev/null || true)
  [[ $a =~ [[:space:]]192\.168\.50\.152/ ]] || return 1
  r=$(ip -4 route show default dev eno3 2>/dev/null || true)
  [[ $r =~ ^default[[:space:]]+via[[:space:]]+192\.168\.50\.1 ]] || return 1
}

combined_now() {
  ethtool -l "$IFACE" 2>/dev/null | awk '
    $1 == "Current" { in_cur = 1; next }
    in_cur && $1 == "Combined:" { print $2; exit }
  '
}

eno1_ready_now() {
  local flags speed carrier oper mtu a4 a6
  flags=$(read_trim "$SYSFS_NET/$IFACE/flags") || return 1
  speed=$(read_trim "$SYSFS_NET/$IFACE/speed") || return 1
  carrier=$(read_trim "$SYSFS_NET/$IFACE/carrier") || return 1
  oper=$(read_trim "$SYSFS_NET/$IFACE/operstate") || return 1
  mtu=$(read_trim "$SYSFS_NET/$IFACE/mtu") || return 1
  flags_capture_ok "$flags" || return 1
  [ "$speed" = 10000 ] || return 1
  [ "$carrier" = 1 ] || [ "$oper" = up ] || return 1
  [ "$mtu" = 1500 ] || return 1
  a4=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null || true)
  a6=$(ip -6 -o addr show dev "$IFACE" 2>/dev/null || true)
  [ -z "$a4" ] && [ -z "$a6" ]
}

wait_boot_ready() {
  local i=0 r1 r3 rirq irq_ac
  while :; do
    r1=0; r3=0; rirq=0
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

irq_snapshot() {
  local ln num name aff
  while read -r ln; do
    [ -n "$ln" ] || continue
    num=$(awk '{ print $1 }' <<<"$ln")
    num=${num%:}
    name=$(awk '{ print $NF }' <<<"$ln")
    aff=$(read_trim "/proc/irq/$num/smp_affinity_list" 2>/dev/null || true)
    printf 'IRQ %s %s %s\n' "$num" "$name" "$aff"
  done < <(grep 'ice-eno1np0-TxRx-' /proc/interrupts || true)
}

irq_in_cores() {
  local cores count=0 line aff
  cores=$(read_trim "$CORES") || return 1
  [ -n "$cores" ] || return 1
  while read -r line; do
    [ -n "$line" ] || continue
    aff=$(awk '{print $4}' <<<"$line")
    case "$aff" in
      [1-4]) ;;
      *) return 1 ;;
    esac
    count=$((count + 1))
  done
  [ "$count" -eq "$IRQ_WANT" ]
}

verify_attached_invariants() {
  local tag=$1 st snap cur
  scan
  st=$(attach_state)
  case "$st" in
    "records "*) REC_ID=${st#records } ;;
    *) stop "not-records-attached-$tag: $st" ;;
  esac
  [ "$(pins_list)" = "$PIN_NAMES" ] || stop "pins-$tag: $(pins_list)"
  [ "$(cfg_line)" = "$CFG_WANT" ] || stop "cfg-$tag: $(cfg_line)"
  eno1_ready_now || stop "eno1-not-ready-$tag"
  [ "$(combined_now)" = "$COMBINED_WANT" ] || stop "queues-$tag"
  eno3_ok || stop "eno3-not-ok-$tag"
  snap=$(irq_snapshot) || stop "irq-snapshot-$tag"
  irq_in_cores <<<"$snap" || stop "irq-outside-cores-$tag"
  if [ -f "$(baseline_file)" ]; then
    cur=$(awk '{ print $3, $4 }' <<<"$snap" | sort)
    base=$(awk '{ print $3, $4 }' "$(baseline_file)" | sort)
    [ "$cur" = "$base" ] || stop "irq-baseline-diff-$tag"
  fi
  echo "OK-xdp-mode driver id=$REC_ID ($tag)"
  echo "OK-cfg $CFG_WANT ($tag)"
  echo "OK-irq-pins-unchanged ($tag)"
}

# ---------------------------------------------------------------- attach / detach

detach_records() {
  local line mode id kw
  XDP_LINES=$(net_attach_lines 2>/dev/null || true)
  [ -n "$XDP_LINES" ] || { echo NOTHING-ATTACHED; return 0; }
  while read -r line; do
    [ -n "$line" ] || continue
    mode=${line%% *}
    id=${line#* }
    if [ -n "$REC_PIN_ID" ] && [ "$id" = "$REC_PIN_ID" ]; then
      case "$mode" in
        driver) kw=xdpdrv ;;
        generic) kw=xdpgeneric ;;
        *) stop "xdp-mode-unknown $mode" ;;
      esac
      if bpftool net detach "$kw" dev "$IFACE"; then
        echo "DETACHED mode=$mode id=$id $REC_NAME"
      else
        stop "detach-failed mode=$mode id=$id"
      fi
    elif [[ ",$OBS_IDS," == *",$id,"* ]]; then
      echo "KEEP-observer mode=$mode id=$id"
    else
      stop "xdp-foreign mode=$mode id=$id (not our pin $REC_PIN_ID; not detached)"
    fi
  done <<<"$XDP_LINES"
}

remove_our_pins() {
  local f left
  [ -d "$PIN_DIR" ] || { echo PINS-ABSENT; return 0; }
  for f in $PIN_NAMES; do
    [ -e "$PIN_DIR/$f" ] && rm -f "$PIN_DIR/$f"
  done
  if rmdir "$PIN_DIR" 2>/dev/null; then
    echo PINS-REMOVED
  else
    left=$(pins_list)
    stop "pin-leftover $PIN_DIR: $left"
  fi
}

# ---------------------------------------------------------------- actions

do_start() {
  local st snap
  trap finish_start EXIT
  trap 'exit 130' INT TERM
  mkdir -p "$STATE_DIR"
  start_boot_log
  echo "M1S2B-START-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gate_host
  need_tools
  need_files
  wait_boot_ready || stop "boot-wait-timeout tries=$WAIT_BOOT_TRIES step=${WAIT_STEP}s"
  check_common_env

  snap=$(irq_snapshot) || stop irq-snapshot-preflight
  irq_in_cores <<<"$snap" || stop irq-outside-capture-cores-preflight
  [ -f "$(baseline_file)" ] || printf '%s\n' "$snap" > "$(baseline_file)"

  scan
  st=$(attach_state)
  case "$st" in
    "observer "*)
      OBS_ID=${st#observer }
      stop "observer-attached-stop-first: observer $OBS_ID (slice 1c must be stopped/disabled before starting 2b)"
      ;;
    "other "*)
      stop "xdp-foreign-attached: $st"
      ;;
    "records "*)
      REC_ID=${st#records }
      verify_attached_invariants already-attached
      echo "ALREADY-ATTACHED xdpdrv prog_id=$REC_ID"
      DONE=1
      echo M1S2B-START-DONE
      return 0
      ;;
    none)
      ;;
    *)
      stop "unexpected-attach-state: $st"
      ;;
  esac

  # Clean stale pins or loaded records program if any
  if [ "$REC_IDS" != none ] || [ -d "$PIN_DIR" ]; then
    if [ "$XDP_TOTAL" -gt 0 ]; then
      stop "xdp-progs-loaded-pre-attach $XDP_TOTAL"
    fi
    echo NOTE-cleaning-stale-pins-before-load
    remove_our_pins || true
  fi

  CLEANUP_ON_FAIL=1
  mkdir -m 0700 "$PIN_DIR" || stop "mkdir-pin-dir $PIN_DIR"
  bpftool prog load "$(obj_path)" "$PIN_DIR/prog" pinmaps "$PIN_DIR" || stop "prog-load-failed"
  scan
  [[ $REC_IDS =~ ^[0-9]+$ ]] || stop "load-not-visible ids=$REC_IDS"
  REC_ID=$REC_IDS
  [ "$REC_ID" = "$REC_PIN_ID" ] || stop "load-pin-mismatch ids=$REC_IDS pinned=${REC_PIN_ID:-none}"
  [ "$(pins_list)" = "$PIN_NAMES" ] || stop "pins-after-load: $(pins_list)"

  write_and_verify_cfg || stop "cfg-write-verify-failed"

  bpftool net attach xdpdrv pinned "$PIN_DIR/prog" dev "$IFACE" || stop "attach-failed"
  sleep "$SETTLE_SECS"
  verify_attached_invariants post-start
  echo "STATE attached by boot helper (xdpdrv prog_id=$REC_ID)"
  DONE=1
  echo M1S2B-START-DONE
  sleep "$FLUSH_WAIT"
}

do_stop() {
  echo "M1S2B-STOP-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gate_host
  need_tools
  scan
  detach_records
  scan
  st=$(attach_state)
  case "$st" in
    "records "*)
      stop "records-still-attached id=${st#records } (KEEP-PINS)"
      ;;
    *)
      remove_our_pins
      ;;
  esac
  echo M1S2B-STOP-DONE
}

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

do_verify() {
  local u_en u_ac r_en r_ac es0 es1 tc cap kd p0 p1 b0 b1 dp db pct s0 s1 seen_delta
  local CTL0 CTL1 rl0 rl1 rb0 rb1 disc0 disc1 rl_delta rb_delta disc_delta
  echo "M1S2B-VERIFY-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gate_host
  need_tools
  need_files

  u_en=$(systemctl is-enabled "$UNIT" 2>/dev/null || true)
  u_ac=$(systemctl is-active "$UNIT" 2>/dev/null || true)
  [ "$u_en" = enabled ] || stop "unit-not-enabled $UNIT ${u_en:-unknown}"
  [ "$u_ac" = active ] || stop "unit-not-active $UNIT ${u_ac:-unknown}"
  echo "OK-unit $UNIT enabled=$u_en active=$u_ac"

  r_en=$(systemctl is-enabled "$R_UNIT" 2>/dev/null || true)
  r_ac=$(systemctl is-active "$R_UNIT" 2>/dev/null || true)
  [ "$r_en" = enabled ] || stop "reader-not-enabled $R_UNIT ${r_en:-unknown}"
  [ "$r_ac" = active ] || stop "reader-not-active $R_UNIT ${r_ac:-unknown}"
  echo "OK-reader $R_UNIT enabled=$r_en active=$r_ac"

  check_common_env
  verify_attached_invariants verify-before

  st0=$(dump_stats || true)
  p0=$(kv "$st0" pkts || echo 0)
  b0=$(kv "$st0" bytes || echo 0)
  CTL0=$(ctl_rows || true)
  s0=$(awk '$1=="seen"{print $2}' <<<"$CTL0")
  rl0=$(awk '$1=="rate_limited"{print $2}' <<<"$CTL0")
  rb0=$(awk '$1=="rb_full"{print $2}' <<<"$CTL0")
  disc0=$(awk '$1=="discarded"{print $2}' <<<"$CTL0")
  es0=$(ethtool -S "$IFACE" 2>/dev/null || true)

  tc=$(tcpdump_verify_counts "$VERIFY_SECS") || stop "tcpdump-verify-failed"
  cap=${tc%% *}
  kd=${tc#* }

  verify_attached_invariants verify-after
  st1=$(dump_stats || true)
  p1=$(kv "$st1" pkts || echo 0)
  b1=$(kv "$st1" bytes || echo 0)
  CTL1=$(ctl_rows || true)
  s1=$(awk '$1=="seen"{print $2}' <<<"$CTL1")
  rl1=$(awk '$1=="rate_limited"{print $2}' <<<"$CTL1")
  rb1=$(awk '$1=="rb_full"{print $2}' <<<"$CTL1")
  disc1=$(awk '$1=="discarded"{print $2}' <<<"$CTL1")
  es1=$(ethtool -S "$IFACE" 2>/dev/null || true)

  dp=$((p1 - p0))
  db=$((b1 - b0))
  seen_delta=$((s1 - s0))
  rl_delta=$((rl1 - rl0))
  rb_delta=$((rb1 - rb0))
  disc_delta=$((disc1 - disc0))

  echo "VERIFY-WINDOW secs=$VERIFY_SECS xdp-pkts-delta=$dp xdp-bytes-delta=$db ctl-seen-delta=$seen_delta tcpdump-captured=$cap tcpdump-kernel-drops=$kd"
  if [ "$dp" -le 0 ]; then
    stop "no-traffic-verify (SPAN quiet during verify window)"
  fi
  if [ "$cap" -le 0 ]; then
    stop "pass-broken-verify (xdp counted $dp frames, tcpdump captured 0)"
  fi
  pct=$((cap * 100 / dp))
  echo "PASS-RATIO tcpdump=$cap xdp=$dp pct=$pct"
  [ "$pct" -ge 80 ] || echo "NOTE-pass-ratio-low pct=$pct"

  echo "VERIFY-DROPS rate_limited=$rl_delta rb_full=$rb_delta discarded=$disc_delta"
  if [ "$rl_delta" -gt 0 ] || [ "$rb_delta" -gt 0 ] || [ "$disc_delta" -gt 0 ]; then
    stop "drops-in-verify-window rate_limited=$rl_delta rb_full=$rb_delta discarded=$disc_delta"
  fi
  echo OK-no-drops-verify

  emit_ethtool_drop_deltas "$es0" "$es1"
  echo OK-xdp-pass-tcpdump-sees-traffic
  echo M1S2B-VERIFY-DONE
}

do_apply_cfg() {
  local st base tmp b_id st_line ctl_dump
  echo "M1S2B-APPLY-CFG-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gate_host
  need_tools
  need_files

  scan
  st=$(attach_state)
  case "$st" in
    "records "*) REC_ID=${st#records } ;;
    *) stop "not-records-attached: $st" ;;
  esac
  if [ -z "$REC_PIN_ID" ] || [ "$REC_ID" != "$REC_PIN_ID" ]; then
    stop "prog-id-mismatch id=$REC_ID pinned=${REC_PIN_ID:-none}"
  fi
  [ "$(pins_list)" = "$PIN_NAMES" ] || stop "pins: $(pins_list)"

  write_and_verify_cfg || stop "write-cfg-failed"

  base=$(no_ratecap_baseline_file)
  if [ ! -f "$base" ]; then
    b_id=$(tr -d '\n\r ' < /proc/sys/kernel/random/boot_id 2>/dev/null || echo "unknown")
    st_line=$(dump_stats) || stop "stats-unreadable-for-baseline"
    ctl_dump=$(ctl_rows) || stop "ctl-unreadable-for-baseline"
    tmp=$(mktemp "$STATE_DIR/no-ratecap-baseline.XXXXXX") || stop "mktemp-baseline-failed"
    chmod 0600 "$tmp"
    {
      echo "DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "boot_id $b_id"
      echo "records_prog_id $REC_ID"
      echo "STATS $st_line"
      awk '{ print "CTL " $0 }' <<<"$ctl_dump"
    } > "$tmp"
    mv "$tmp" "$base"
    echo "BASELINE-WRITTEN $base"
  else
    echo "BASELINE-EXISTS $base"
  fi

  echo M1S2B-APPLY-CFG-DONE
}

do_mark_reader() {
  local base inv nrest mpid mdate
  gate_host
  need_tools
  base=$(no_ratecap_baseline_file)
  if [ ! -f "$base" ]; then
    stop "baseline-missing $base"
  fi
  if grep -q "^READER-INVOCATION=" "$base" 2>/dev/null; then
    echo "READER-MARK-EXISTS $base"
    echo M1S2B-MARK-READER-DONE
    return 0
  fi
  inv=$(systemctl show -p InvocationID --value "$R_UNIT" 2>/dev/null || true)
  nrest=$(systemctl show -p NRestarts --value "$R_UNIT" 2>/dev/null || true)
  mpid=$(systemctl show -p MainPID --value "$R_UNIT" 2>/dev/null || true)
  mdate=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  [ -n "$inv" ] || stop "reader-invocation-unreadable"
  [ -n "$nrest" ] || stop "reader-nrestarts-unreadable"
  [ -n "$mpid" ] || stop "reader-mainpid-unreadable"

  {
    echo "READER-INVOCATION=$inv"
    echo "READER-NRESTARTS=$nrest"
    echo "READER-MAINPID=$mpid"
    echo "READER-MARK-DATE-UTC=$mdate"
  } >> "$base"
  echo "READER-MARKED $base inv=$inv nrestarts=$nrest mainpid=$mpid date=$mdate"
  echo M1S2B-MARK-READER-DONE
}

do_window() {
  local secs=${1:-60}
  local CTL0 CTL1 ST0 ST1
  local seen0 seen1 rl0 rl1 rb0 rb1 disc0 disc1 emit0 emit1 p0 p1
  local seen_delta rl_delta rb_delta disc_delta emit_delta pkts_delta

  if [[ ! "$secs" =~ ^[0-9]+$ ]] || [ "$secs" -lt 10 ] || [ "$secs" -gt 3600 ]; then
    stop "window-secs-out-of-range: $secs (must be 10..3600)"
  fi

  gate_host
  need_tools

  [ -d "$PIN_DIR" ] || stop "pins-dir-missing"
  [ -e "$PIN_DIR/m2_ctl" ] || stop "m2_ctl-missing"
  [ -e "$PIN_DIR/m1_stats" ] || stop "m1_stats-missing"

  CTL0=$(ctl_rows || true)
  ST0=$(dump_stats || true)
  [ -n "$CTL0" ] || stop "ctl-unreadable-before-window"
  [ -n "$ST0" ] || stop "stats-unreadable-before-window"

  sleep "$secs"

  CTL1=$(ctl_rows || true)
  ST1=$(dump_stats || true)
  [ -n "$CTL1" ] || stop "ctl-unreadable-after-window"
  [ -n "$ST1" ] || stop "stats-unreadable-after-window"

  seen0=$(awk '$1=="seen"{print $2}' <<<"$CTL0")
  seen1=$(awk '$1=="seen"{print $2}' <<<"$CTL1")
  rl0=$(awk '$1=="rate_limited"{print $2}' <<<"$CTL0")
  rl1=$(awk '$1=="rate_limited"{print $2}' <<<"$CTL1")
  rb0=$(awk '$1=="rb_full"{print $2}' <<<"$CTL0")
  rb1=$(awk '$1=="rb_full"{print $2}' <<<"$CTL1")
  disc0=$(awk '$1=="discarded"{print $2}' <<<"$CTL0")
  disc1=$(awk '$1=="discarded"{print $2}' <<<"$CTL1")
  emit0=$(awk '$1=="emitted"{print $2}' <<<"$CTL0")
  emit1=$(awk '$1=="emitted"{print $2}' <<<"$CTL1")
  p0=$(kv "$ST0" pkts || echo 0)
  p1=$(kv "$ST1" pkts || echo 0)

  seen_delta=$((seen1 - seen0))
  rl_delta=$((rl1 - rl0))
  rb_delta=$((rb1 - rb0))
  disc_delta=$((disc1 - disc0))
  emit_delta=$((emit1 - emit0))
  pkts_delta=$((p1 - p0))

  echo "WINDOW secs=$secs seen-delta=$seen_delta rate_limited-delta=$rl_delta rb_full-delta=$rb_delta discarded-delta=$disc_delta emitted-delta=$emit_delta pkts-delta=$pkts_delta"
  if [ "$rl_delta" -gt 0 ] || [ "$rb_delta" -gt 0 ] || [ "$disc_delta" -gt 0 ]; then
    stop "drops-in-window rate_limited=$rl_delta rb_full=$rb_delta discarded=$disc_delta"
  fi
  echo OK-no-drops-window
  echo M1S2B-WINDOW-DONE
}

do_week() {
  local precheck=${1:-}
  local base base_date base_boot_id base_prog_id base_stats
  local base_seen base_so base_rl base_rb base_emit base_disc
  local mark_inv mark_nrestarts mark_mainpid mark_date
  local cur_boot_id st cur_prog_id cur_inv cur_nrestarts cur_result
  local cur_ctl cur_seen cur_rl cur_rb cur_disc cur_emit
  local delta_seen delta_rl delta_rb delta_disc delta_emit
  local out_dir base_epoch now_epoch
  local files=() starts=() mtimes=()
  local f fn ts f_start f_mtime count span newest_mtime oldest_start
  local gap i f_first_start first_delay
  local j_out j_stops du_line df_line du_bytes df_free

  echo "M1S2B-WEEK-BEGIN DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gate_host
  need_tools

  base=$(no_ratecap_baseline_file)
  if [ ! -f "$base" ]; then
    stop "baseline-missing $base"
  fi

  base_date=$(awk '$1=="DATE-UTC"{print $2}' "$base")
  base_boot_id=$(awk '$1=="boot_id"{print $2}' "$base")
  base_prog_id=$(awk '$1=="records_prog_id"{print $2}' "$base")
  base_stats=$(grep "^STATS " "$base" | head -n1 || true)
  base_seen=$(awk '$1=="CTL" && $2=="seen"{print $3}' "$base")
  base_so=$(awk '$1=="CTL" && $2=="sampled_out"{print $3}' "$base")
  base_rl=$(awk '$1=="CTL" && $2=="rate_limited"{print $3}' "$base")
  base_rb=$(awk '$1=="CTL" && $2=="rb_full"{print $3}' "$base")
  base_emit=$(awk '$1=="CTL" && $2=="emitted"{print $3}' "$base")
  base_disc=$(awk '$1=="CTL" && $2=="discarded"{print $3}' "$base")

  mark_inv=$(sed -n 's/^READER-INVOCATION=[[:space:]]*//p' "$base" | head -n1)
  mark_nrestarts=$(sed -n 's/^READER-NRESTARTS=[[:space:]]*//p' "$base" | head -n1)
  mark_mainpid=$(sed -n 's/^READER-MAINPID=[[:space:]]*//p' "$base" | head -n1)
  mark_date=$(sed -n 's/^READER-MARK-DATE-UTC=[[:space:]]*//p' "$base" | head -n1)

  if [ -z "$base_date" ] || [ -z "$base_boot_id" ] || [ -z "$base_prog_id" ] || \
     [ -z "$base_stats" ] || [ -z "$base_seen" ] || [ -z "$base_so" ] || \
     [ -z "$base_rl" ] || [ -z "$base_rb" ] || [ -z "$base_emit" ] || [ -z "$base_disc" ] || \
     [ -z "$mark_inv" ] || [ -z "$mark_nrestarts" ] || [ -z "$mark_mainpid" ] || [ -z "$mark_date" ]; then
    stop "baseline-incomplete: required key missing in $base"
  fi

  cur_boot_id=$(tr -d '\n\r ' < /proc/sys/kernel/random/boot_id 2>/dev/null || echo "")
  if [ "$cur_boot_id" != "$base_boot_id" ]; then
    stop "rebooted-since-apply cur=$cur_boot_id baseline=$base_boot_id"
  fi
  echo "OK-boot-id $cur_boot_id"

  scan
  st=$(attach_state)
  case "$st" in
    "records "*) cur_prog_id=${st#records } ;;
    *) stop "xdp-reattached-since-apply: not records attached ($st)" ;;
  esac
  if [ "$cur_prog_id" != "$base_prog_id" ]; then
    stop "xdp-reattached-since-apply cur=$cur_prog_id baseline=$base_prog_id"
  fi
  echo "OK-records-prog-id $cur_prog_id"

  cur_inv=$(systemctl show -p InvocationID --value "$R_UNIT" 2>/dev/null || true)
  cur_nrestarts=$(systemctl show -p NRestarts --value "$R_UNIT" 2>/dev/null || true)
  cur_result=$(systemctl show -p Result --value "$R_UNIT" 2>/dev/null || true)

  if [ "$cur_inv" != "$mark_inv" ] || [ "$cur_nrestarts" != "$mark_nrestarts" ] || [ "$cur_result" != "success" ]; then
    stop "reader-restarted-since-apply inv=$cur_inv(base=$mark_inv) nrestarts=$cur_nrestarts(base=$mark_nrestarts) result=$cur_result"
  fi
  echo "OK-reader-state invocation=$cur_inv nrestarts=$cur_nrestarts result=$cur_result"

  cur_ctl=$(ctl_rows || true)
  [ -n "$cur_ctl" ] || stop "ctl-unreadable"
  cur_seen=$(awk '$1=="seen"{print $2}' <<<"$cur_ctl")
  cur_rl=$(awk '$1=="rate_limited"{print $2}' <<<"$cur_ctl")
  cur_rb=$(awk '$1=="rb_full"{print $2}' <<<"$cur_ctl")
  cur_disc=$(awk '$1=="discarded"{print $2}' <<<"$cur_ctl")
  cur_emit=$(awk '$1=="emitted"{print $2}' <<<"$cur_ctl")

  if [ -z "$cur_seen" ] || [ -z "$cur_rl" ] || [ -z "$cur_rb" ] || [ -z "$cur_disc" ] || [ -z "$cur_emit" ]; then
    stop "ctl-incomplete"
  fi

  delta_seen=$((cur_seen - base_seen))
  delta_rl=$((cur_rl - base_rl))
  delta_rb=$((cur_rb - base_rb))
  delta_disc=$((cur_disc - base_disc))
  delta_emit=$((cur_emit - base_emit))

  echo "CTL-DELTAS seen=$delta_seen rate_limited=$delta_rl rb_full=$delta_rb discarded=$delta_disc emitted=$delta_emit"

  if [ "$delta_seen" -lt 0 ] || [ "$delta_rl" -lt 0 ] || [ "$delta_rb" -lt 0 ] || [ "$delta_disc" -lt 0 ] || [ "$delta_emit" -lt 0 ]; then
    stop "counter-went-backwards seen=$delta_seen rl=$delta_rl rb=$delta_rb disc=$delta_disc emit=$delta_emit"
  fi

  if [ "$delta_rl" -gt 0 ] || [ "$delta_rb" -gt 0 ] || [ "$delta_disc" -gt 0 ]; then
    stop "drops-since-apply rate_limited=$delta_rl rb_full=$delta_rb discarded=$delta_disc"
  fi
  echo OK-no-drops-since-apply

  if [ "$precheck" = "--precheck" ]; then
    echo OK-baseline-precheck
    echo M1S2B-WEEK-PRECHECK-DONE
    return 0
  fi

  out_dir="$OUT_DIR"
  base_epoch=$(date -u -d "$base_date" +%s 2>/dev/null || echo 0)
  [ "$base_epoch" -gt 0 ] || stop "baseline-date-invalid $base_date"

  # Boundary note: keep only files with start timestamp >= baseline DATE-UTC.
  # This includes the file opened immediately after apply-cfg when johnny-m1s2b-reader.service
  # is restarted, while excluding any files opened prior to apply-cfg.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fn=$(basename "$f")
    ts=${fn#run-}
    ts=${ts%.bin}
    ts=${ts%-*}
    if [[ ! "$ts" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; then
      continue
    fi
    f_start=$(date -u -d "${ts:0:4}-${ts:4:2}-${ts:6:2}T${ts:9:2}:${ts:11:2}:${ts:13:2}Z" +%s 2>/dev/null || echo 0)
    if [ "$f_start" -ge "$base_epoch" ]; then
      f_mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      files+=("$fn")
      starts+=("$f_start")
      mtimes+=("$f_mtime")
    fi
  done < <(find "$out_dir" -maxdepth 1 -name "run-*.bin" -type f 2>/dev/null | sort)

  count=${#files[@]}
  if [ "$count" -lt 168 ]; then
    stop "coverage-short count=$count (want >= 168)"
  fi

  f_first_start=${starts[0]}
  first_delay=$((f_first_start - base_epoch))
  if [ "$first_delay" -gt 3700 ] || [ "$first_delay" -lt 0 ]; then
    stop "coverage-short first-file-delay=$first_delay (want 0..3700)"
  fi

  oldest_start=$f_first_start
  newest_mtime=${mtimes[0]}
  for ((i=0; i<count; i++)); do
    if [ "${mtimes[i]}" -gt "$newest_mtime" ]; then
      newest_mtime=${mtimes[i]}
    fi
    if [ "$i" -gt 0 ]; then
      gap=$((starts[i] - starts[i-1]))
      if [ "$gap" -gt 3700 ]; then
        stop "gap-detected file1=${files[i-1]} file2=${files[i]} gap=$gap"
      fi
    fi
  done

  span=$((newest_mtime - oldest_start))
  if [ "$span" -lt 604800 ]; then
    stop "coverage-short span=$span (want >= 604800)"
  fi

  now_epoch=$(date +%s)
  local mtime_age=$((now_epoch - newest_mtime))
  if [ "$mtime_age" -gt 3700 ]; then
    stop "reader-stale age=$mtime_age (want <= 3700)"
  fi
  echo "OK-run-files count=$count span=$span first_start=$oldest_start newest_mtime=$newest_mtime"

  if ! j_out=$(journalctl -u "$R_UNIT" --since "$base_date" --no-pager 2>&1); then
    stop "journal-unreadable"
  fi
  j_stops=$(grep -c -E "STOP|Traceback" <<<"$j_out" || true)
  if [ "$j_stops" -gt 0 ]; then
    stop "reader-journal-errors count=$j_stops"
  fi
  echo "OK-reader-journal errors=0"

  du_line=$(du -sb "$out_dir" 2>/dev/null || true)
  echo "STORAGE-DU $du_line"
  df_line=$(df -h "$out_dir" 2>/dev/null | tail -n 1 || true)
  echo "STORAGE-DF $df_line"

  du_bytes=$(awk '{print $1}' <<<"$du_line")
  df_free=$(df -B1 --output=avail "$out_dir" 2>/dev/null | tail -n 1 | tr -d ' ')
  [[ "$df_free" =~ ^[0-9]+$ ]] || df_free=$(df -B1 "$out_dir" 2>/dev/null | awk 'NR==2 {print $4}')

  if [ -n "$du_bytes" ] && [ "$du_bytes" -gt 214748364800 ]; then
    stop "out-dir-bytes-exceeded bytes=$du_bytes (cap 214748364800)"
  fi
  if [ -n "$df_free" ] && [ "$df_free" -lt 107374182400 ]; then
    stop "free-space-below-reserve free=$df_free (reserve 107374182400)"
  fi
  echo "OK-storage du_bytes=$du_bytes df_free=$df_free"

  echo "WEEK-SUMMARY files=$count span=$span first_start=$oldest_start newest_mtime=$newest_mtime drops=0"
  echo M1S2B-WEEK-DONE
}

do_status() {
  local cfg st_pkts base
  gate_host
  scan
  echo "HOST $(hostname -s 2>/dev/null || hostname)"
  echo "ATTACH $(attach_state)"
  echo "PROG-XDP-COUNT $XDP_TOTAL records=$REC_IDS observer=$OBS_IDS"
  echo "UNIT-2B enabled=$(systemctl is-enabled "$UNIT" 2>/dev/null || true) active=$(systemctl is-active "$UNIT" 2>/dev/null || true)"
  echo "UNIT-READER enabled=$(systemctl is-enabled "$R_UNIT" 2>/dev/null || true) active=$(systemctl is-active "$R_UNIT" 2>/dev/null || true)"
  echo "UNIT-1C enabled=$(systemctl is-enabled "$C1_UNIT" 2>/dev/null || true) active=$(systemctl is-active "$C1_UNIT" 2>/dev/null || true)"
  if [ -d "$PIN_DIR" ]; then
    echo "PINS $(pins_list)"
    if st_pkts=$(dump_stats); then echo "STATS $st_pkts"; else echo NOTE-stats-unreadable; fi
    if CTL=$(ctl_rows); then awk '{ print "CTL " $0 }' <<<"$CTL"; else echo NOTE-ctl-unreadable; fi
    if cfg=$(cfg_line); then echo "CFG $cfg"; else echo NOTE-cfg-unreadable; fi
  else
    echo "PINS dir=absent"
  fi
  base=$(no_ratecap_baseline_file)
  if [ -f "$base" ]; then
    echo "BASELINE-EXISTS $base"
    sed 's/^/BASELINE /' "$base"
  else
    echo "BASELINE-NONE"
  fi
  echo "LINK $IFACE speed=$(read_trim "$SYSFS_NET/$IFACE/speed" || echo none) carrier=$(read_trim "$SYSFS_NET/$IFACE/carrier" || echo none) oper=$(read_trim "$SYSFS_NET/$IFACE/operstate" || echo none)"
  echo "OUT-DIR $OUT_DIR"
  echo "IRQ-COUNT $(grep -c 'ice-eno1np0-TxRx-' /proc/interrupts || true)"
  echo M1S2B-STATUS-DONE
}

main() {
  umask 077
  export PATH="$SAFE_PATH"
  trap '' HUP PIPE
  ACTION=${1:-}
  case "$ACTION" in
    start | stop | verify | status | apply-cfg | mark-reader)
      [ "$#" -eq 1 ] || stop args
      ;;
    window | week)
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        stop args
      fi
      ;;
    *) stop args ;;
  esac

  if [ "$ACTION" != status ] && [ "$ACTION" != window ] && [ "$ACTION" != week ]; then
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock -n 9 || stop locked
  fi

  case "$ACTION" in
    start) do_start ;;
    stop) do_stop ;;
    verify) do_verify ;;
    status) do_status ;;
    apply-cfg) do_apply_cfg ;;
    mark-reader) do_mark_reader ;;
    window) do_window "${2:-60}" ;;
    week) do_week "${2:-}" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
