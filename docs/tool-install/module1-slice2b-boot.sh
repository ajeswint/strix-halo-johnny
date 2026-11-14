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
# Commands: start | stop | verify | status

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
  for t in bpftool systemctl ip ethtool awk python3 sha256sum stat timeout tcpdump mktemp; do
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
  bpftool map update pinned "$PIN_DIR/m2_cfg" key hex 00 00 00 00 value hex 01 00 00 00 01 00 00 00 40 1f 00 00 80 3e 00 00 || return 1
  cfg=$(cfg_line) || return 1
  [ "$cfg" = "ver=1 sample_every=1 rate=8000 burst=16000" ] || return 1
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
  [ "$(cfg_line)" = "ver=1 sample_every=1 rate=8000 burst=16000" ] || stop "cfg-$tag: $(cfg_line)"
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
  echo "OK-cfg ver=1 sample_every=1 rate=8000 burst=16000 ($tag)"
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
  CTL=$(ctl_rows || true)
  s0=$(ctl_val seen || echo 0)
  es0=$(ethtool -S "$IFACE" 2>/dev/null || true)

  tc=$(tcpdump_verify_counts "$VERIFY_SECS") || stop "tcpdump-verify-failed"
  cap=${tc%% *}
  kd=${tc#* }

  verify_attached_invariants verify-after
  st1=$(dump_stats || true)
  p1=$(kv "$st1" pkts || echo 0)
  b1=$(kv "$st1" bytes || echo 0)
  CTL=$(ctl_rows || true)
  s1=$(ctl_val seen || echo 0)
  es1=$(ethtool -S "$IFACE" 2>/dev/null || true)

  dp=$((p1 - p0))
  db=$((b1 - b0))
  seen_delta=$((s1 - s0))

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

  emit_ethtool_drop_deltas "$es0" "$es1"
  echo OK-xdp-pass-tcpdump-sees-traffic
  echo M1S2B-VERIFY-DONE
}

do_status() {
  local cfg st_pkts
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
    start | stop | verify | status) ;;
    *) stop args ;;
  esac
  [ "$#" -eq 1 ] || stop args

  if [ "$ACTION" != status ]; then
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock -n 9 || stop locked
  fi

  case "$ACTION" in
    start) do_start ;;
    stop) do_stop ;;
    verify) do_verify ;;
    status) do_status ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
