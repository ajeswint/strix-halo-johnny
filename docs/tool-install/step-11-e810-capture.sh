#!/bin/bash
# Johnny step 11 — E810 capture config. Not applied by this commit.
# AJ runs it on Johnny, after the two files are in /home/aj/cis-audit/:
#   sudo bash /home/aj/cis-audit/step-11-e810-capture.sh
# No reboot. No apt. No GRUB. No sudoers. Does not change eno3's netplan stanza.
# Rollback, including from the KVM console: sudo bash /root/step11-revert.sh
# SIGHUP and SIGPIPE are ignored so a dropped SSH session still runs that rollback.
# A failed run that changed the box runs that rollback before it exits.
# A rerun that changes nothing and then fails leaves the previous config
# (CONFIG-KEPT). Docs: docs/tool-install/step-11-e810-capture.md

XDP_OBJ=/home/aj/cis-audit/xdp-pass-count.o
XDP_SHA256=2fe90f6c84c4ca5b07e34f4dd319e443a7609ff538587327aaebcfa1fccf0398
NETPLAN=/etc/netplan/00-installer-config.yaml
DROPIN=/etc/systemd/network/10-netplan-eno1np0.network.d/60-johnny-capture.conf

expand_cpulist() {
  local spec=$1 part start end i
  spec=${spec//,/ }
  for part in $spec; do
    if [[ $part == *-* ]]; then
      start=${part%-*}
      end=${part#*-}
      if [[ ! $start =~ ^[0-9]+$ || ! $end =~ ^[0-9]+$ ]]; then
        echo STOP-cpulist >&2
        return 1
      fi
      if [ "$end" -lt "$start" ]; then
        echo STOP-cpulist >&2
        return 1
      fi
      for ((i = start; i <= end; i++)); do
        printf '%s\n' "$i"
      done
    else
      if [[ ! $part =~ ^[0-9]+$ ]]; then
        echo STOP-cpulist >&2
        return 1
      fi
      printf '%s\n' "$part"
    fi
  done
}

pick_capture_cpus() {
  local pcore_list=$1 sibling_list=$2
  local cpu s
  local -a chosen=()
  local -A sib=()
  if [[ ! $pcore_list =~ ^[0-9]+([,-][0-9]+)*$ ]]; then
    echo STOP-cpulist
    return 1
  fi
  if [[ ! $sibling_list =~ ^[0-9]+([,-][0-9]+)*$ ]]; then
    echo STOP-cpulist
    return 1
  fi
  while read -r s; do
    [ -n "$s" ] || continue
    sib[$s]=1
  done < <(expand_cpulist "$sibling_list")
  while read -r cpu; do
    [ -n "$cpu" ] || continue
    if [ -n "${sib[$cpu]:-}" ]; then
      continue
    fi
    chosen+=("$cpu")
    if [ "${#chosen[@]}" -eq 4 ]; then
      break
    fi
  done < <(expand_cpulist "$pcore_list" | sort -n | uniq)
  if [ "${#chosen[@]}" -ne 4 ]; then
    echo STOP-capture-cpu-count
    return 1
  fi
  for cpu in "${chosen[@]}"; do
    if [ "$cpu" = 0 ]; then
      echo STOP-cpu0-in-set
      return 1
    fi
  done
  printf '%s\n' "${chosen[@]}"
}

# Membership test. comm(1) wants lexicographic order; sort -n on 8-23 is
# not that order, so comm exits 1 on a real empty overlap and set -e stops.
# Returns 1 and prints the shared ids when the lists overlap. Returns 0
# and prints nothing when they do not.
cpu_lists_overlap() {
  local left=$1 right=$2 cpu hit=0
  local -A seen=()
  while read -r cpu; do
    [ -n "$cpu" ] || continue
    seen[$cpu]=1
  done < <(expand_cpulist "$left")
  while read -r cpu; do
    [ -n "$cpu" ] || continue
    if [ -n "${seen[$cpu]:-}" ]; then
      printf '%s\n' "$cpu"
      hit=1
    fi
  done < <(expand_cpulist "$right")
  return "$hit"
}

# sysfs flags on this kernel are hex ("0x1003"), not decimal, and do not
# set IFF_LOWER_UP even when carrier=1 and operstate=up. Link-up is
# speed, carrier or operstate, and IFF_UP. Promisc and NOARP are separate.
flags_well_formed() {
  local f=$1
  [[ $f =~ ^(0[xX])?[0-9a-fA-F]+$ ]]
}

flags_admin_up() {
  local f=$1
  flags_well_formed "$f" || return 1
  [ $((f & 1)) -ne 0 ]
}

flags_capture_ok() {
  local f=$1
  flags_well_formed "$f" || return 1
  # IFF_UP, IFF_PROMISC (0x100), IFF_NOARP (0x80). Not IFF_LOWER_UP.
  [ $((f & 1)) -ne 0 ] && [ $((f & 256)) -ne 0 ] && [ $((f & 128)) -ne 0 ]
}

eno1_link_ok() {
  local speed=$1 flags=$2 carrier=$3 oper=$4
  flags_admin_up "$flags" || return 1
  [ "$speed" = 10000 ] || return 1
  [ "$carrier" = 1 ] || [ "$oper" = up ]
}

map_id_from_json() {
  python3 -c '
import json, sys
found = []
def walk(o):
    if isinstance(o, dict):
        ids = o.get("map_ids")
        if isinstance(ids, list):
            found.append(ids)
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(json.load(sys.stdin))
if len(found) != 1 or len(found[0]) != 1:
    sys.exit(2)
print(found[0][0])
'
}

map_value_from_json() {
  python3 -c '
import json, sys
def le(seq):
    n = 0
    for i, b in enumerate(seq):
        if isinstance(b, str):
            b = int(b, 16) if b.lower().startswith("0x") else int(b)
        n |= (int(b) & 0xFF) << (8 * i)
    return n
doc = json.load(sys.stdin)
items = doc if isinstance(doc, list) else [doc]
if not items or not isinstance(items[0], dict):
    sys.exit(2)
item = items[0]
fmt = item.get("formatted")
if isinstance(fmt, dict) and isinstance(fmt.get("value"), int):
    print(fmt["value"])
    raise SystemExit(0)
if "value" not in item:
    sys.exit(2)
print(le(item["value"]))
'
}

xdp_modes_from_json() {
  python3 -c '
import json, sys
dev = sys.argv[1]
found = []
def walk(o):
    if isinstance(o, dict):
        if o.get("devname") == dev and "mode" in o:
            found.append(str(o["mode"]))
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(json.load(sys.stdin))
print(" ".join(found))
' "$1"
}

edit_netplan() {
  python3 - "$1" <<'PY'
import os, sys, tempfile
def stop(code):
    print(code)
    raise SystemExit(1)
path = sys.argv[1]
if os.path.islink(path):
    stop("STOP-netplan-symlink")
with open(path, "r", encoding="utf-8", newline="") as fh:
    text = fh.read()
if "\t" in text:
    stop("STOP-netplan-tab")
lines = text.splitlines(keepends=True)
if not lines or not text.endswith("\n"):
    stop("STOP-netplan-shape")

def key_line(key):
    want = f"    {key}:\n"
    hits = [i for i, line in enumerate(lines) if line == want]
    if len(hits) != 1:
        stop("STOP-netplan-shape")
    return hits[0]

keys = ["eno3", "eno1np0", "eno2np1", "eno4"]
try:
    idx = {k: key_line(k) for k in keys}
except SystemExit:
    raise
order = [idx[k] for k in keys]
if order != sorted(order):
    stop("STOP-netplan-shape")

def section_end(start):
    for i in range(start + 1, len(lines)):
        raw = lines[i]
        if raw.startswith("    ") and not raw.startswith("     ") and raw.strip().endswith(":"):
            return i
    return len(lines)

ends = {k: section_end(idx[k]) for k in keys}
if ends["eno3"] != idx["eno1np0"] or ends["eno1np0"] != idx["eno2np1"] or ends["eno2np1"] != idx["eno4"]:
    stop("STOP-netplan-shape")

def body(key):
    return "".join(lines[idx[key]:ends[key]])

before = {k: body(k) for k in keys}
macs = {
    "eno3": "38:05:25:3a:a3:71",
    "eno1np0": "38:05:25:3a:ac:da",
    "eno2np1": "38:05:25:3a:ac:db",
    "eno4": "38:05:25:3a:a3:70",
}
for key, mac in macs.items():
    if mac not in before[key]:
        stop("STOP-netplan-mac")
if "dhcp4: true" not in before["eno3"] or "activation-mode:" in before["eno3"]:
    stop("STOP-netplan-eno3")
if "dhcp4: false" not in before["eno1np0"] or "dhcp4: false" not in before["eno2np1"]:
    stop("STOP-netplan-shape")
if "activation-mode:" in before["eno1np0"] or "activation-mode:" in before["eno4"]:
    stop("STOP-activation-mode")

block = lines[idx["eno2np1"]:ends["eno2np1"]]
act = [ln for ln in block if "activation-mode:" in ln]
if len(act) > 1:
    stop("STOP-activation-mode")
if len(act) == 1:
    if act[0] != "      activation-mode: off\n":
        stop("STOP-activation-mode")
    print("ALREADY-yaml")
    raise SystemExit(0)

insert = [
    "      # step 11: keep this port admin-down (SFP+8 end is out)\n",
    "      activation-mode: off\n",
]
out_lines = lines[:idx["eno4"]] + insert + lines[idx["eno4"]:]
new = "".join(out_lines)
if before["eno3"] not in new or before["eno1np0"] not in new or before["eno4"] not in new:
    stop("STOP-netplan-other")
if new.count("\n      activation-mode:") != 1:
    stop("STOP-activation-mode")
st = os.stat(path)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
try:
    os.write(fd, new.encode("utf-8"))
    os.fchmod(fd, st.st_mode)
    os.fchown(fd, st.st_uid, st.st_gid)
    os.close(fd)
    fd = -1
    os.replace(tmp, path)
    tmp = ""
finally:
    if fd >= 0:
        os.close(fd)
    if tmp:
        os.unlink(tmp)
print("WROTE-yaml")
PY
}

main() {
  set -eEuo pipefail
  trap '' HUP PIPE
  export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
  umask 022

  exec 9>/run/johnny-step11.lock
  if ! flock -n 9; then
    echo STOP-locked
    exit 1
  fi

  exec > >(tee /root/step11-apply.log) 2>&1

  this_run_changed=0
  failed=0
  revert_ready=0
  xdp_attached=0
  ENO4_WAS_UP=0
  CPU0_EPP=""
  CPU0_IDLE_PATH=""
  CPU0_IDLE_DIS=""
  CAPTURE_TEXT=""

  # Invoked by the EXIT trap, which shellcheck cannot see.
  # shellcheck disable=SC2317
  cleanup() {
    local rc=$?
    local revert_rc=0
    trap - ERR
    trap - EXIT
    # A dead SSH pipe must not stop the rollback. ERR is not inherited by
    # functions unless -E is set; a nonzero exit is still a failure.
    set +e
    if [ "$rc" -ne 0 ]; then
      failed=1
    fi
    if [ "${xdp_attached:-0}" -eq 1 ]; then
      bpftool net detach xdpdrv dev eno1np0 >/dev/null 2>&1 || true
      xdp_attached=0
    fi
    rm -f /sys/fs/bpf/johnny_xdp_count || true
    if [ "${failed:-0}" -eq 1 ] && [ "${revert_ready:-0}" -eq 1 ] && [ "${this_run_changed:-0}" -eq 1 ]; then
      echo REVERTING || true
      bash /root/step11-revert.sh > /root/step11-revert.out 2>&1
      revert_rc=$?
      cat /root/step11-revert.out >> /root/step11-apply.log || true
      cat /root/step11-revert.out || true
      if [ "$revert_rc" -ne 0 ]; then
        echo STOP-revert-failed || true
      fi
    elif [ "${failed:-0}" -eq 1 ] && [ "${revert_ready:-0}" -eq 1 ] && [ "${this_run_changed:-0}" -eq 0 ]; then
      echo CONFIG-KEPT || true
    fi
    exit "$rc"
  }
  # Invoked by the ERR trap, which shellcheck cannot see.
  # shellcheck disable=SC2317
  on_err() {
    local rc=$?
    failed=1
    echo "STOP-err line ${BASH_LINENO[0]} rc ${rc}" || true
    exit "$rc"
  }
  trap on_err ERR
  trap cleanup EXIT

  die() {
    printf '%s\n' "$1"
    failed=1
    exit 1
  }

  mark_changed() {
    this_run_changed=1
  }

  if [ "$(id -u)" -ne 0 ]; then
    die STOP-not-root
  fi

  local cmd
  for cmd in python3 bpftool ethtool networkctl netplan systemctl ip sysctl journalctl sha256sum install cmp awk flock timeout mkdir cp mv chmod mountpoint comm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "STOP-missing $cmd"
    fi
  done

  if [ ! -f "$XDP_OBJ" ]; then
    die STOP-no-xdp-obj
  fi
  local got
  got=$(sha256sum "$XDP_OBJ" | awk '{print $1}')
  if [ "$got" != "$XDP_SHA256" ]; then
    die STOP-xdp-hash
  fi
  echo "XDP-OBJECT $XDP_SHA256"

  local nic
  for nic in eno1np0 eno2np1 eno3 eno4; do
    if [ ! -d "/sys/class/net/$nic" ]; then
      die "STOP-no-nic $nic"
    fi
  done

  local driver
  for nic in eno1np0 eno2np1; do
    driver=$(ethtool -i "$nic" | awk -F': ' '$1=="driver"{print $2}')
    if [ "$driver" != ice ]; then
      die "STOP-driver $nic $driver"
    fi
  done
  ethtool -i eno1np0 | awk 'NR<=6 {print "ETHTOOL " $0}'

  local mtu speed flags carrier oper
  mtu=$(tr -d '[:space:]' < /sys/class/net/eno1np0/mtu)
  if [ "$mtu" -gt 3000 ]; then
    die "STOP-mtu $mtu"
  fi
  echo "MTU $mtu"
  speed=$(tr -d '[:space:]' < /sys/class/net/eno1np0/speed)
  flags=$(tr -d '[:space:]' < /sys/class/net/eno1np0/flags)
  carrier=$(tr -d '[:space:]' < /sys/class/net/eno1np0/carrier || true)
  oper=$(tr -d '[:space:]' < /sys/class/net/eno1np0/operstate || true)
  if ! flags_well_formed "$flags"; then
    die STOP-flags
  fi
  if ! eno1_link_ok "$speed" "$flags" "$carrier" "$oper"; then
    die "STOP-eno1-link speed=$speed flags=$flags carrier=$carrier oper=$oper"
  fi
  if [ -n "$(ip -4 -o addr show dev eno1np0)" ] || [ -n "$(ip -6 -o addr show dev eno1np0)" ]; then
    die STOP-eno1-addr
  fi
  if [ -n "$(ip -4 -o addr show dev eno2np1)" ] || [ -n "$(ip -6 -o addr show dev eno2np1)" ]; then
    die STOP-eno2-addr
  fi
  if ! ip -4 -o addr show dev eno3 | grep -q 'inet 192\.168\.50\.152/'; then
    die STOP-eno3-addr
  fi
  if ! ip -4 route show default | grep -q 'dev eno3'; then
    die STOP-eno3-route
  fi
  if [ -n "$(ip -4 -o addr show dev eno4)" ] || [ -n "$(ip -6 -o addr show dev eno4)" ]; then
    die STOP-eno4-addr
  fi
  flags=$(tr -d '[:space:]' < /sys/class/net/eno4/flags)
  if ! flags_well_formed "$flags"; then
    die STOP-flags
  fi
  if flags_admin_up "$flags"; then
    ENO4_WAS_UP=1
  fi

  if ! mountpoint -q /sys/fs/bpf; then
    die STOP-bpffs
  fi
  local mode_now
  mode_now=$(bpftool -j net show dev eno1np0 | xdp_modes_from_json eno1np0)
  if [ -n "$mode_now" ]; then
    die "STOP-xdp-busy $mode_now"
  fi
  if [ -e /sys/fs/bpf/johnny_xdp_count ]; then
    die STOP-xdp-pin-exists
  fi

  local v6_all v6_eno1 rp lm
  v6_all=$(sysctl -n net.ipv6.conf.all.disable_ipv6)
  v6_eno1=$(sysctl -n net.ipv6.conf.eno1np0.disable_ipv6)
  echo "IPV6 all=$v6_all eno1np0=$v6_eno1"
  if [ "$v6_all" != 1 ] || [ "$v6_eno1" != 1 ]; then
    die STOP-ipv6
  fi
  rp=$(sysctl -n net.ipv4.conf.all.rp_filter)
  lm=$(sysctl -n net.ipv4.conf.all.log_martians)
  echo "RP-FILTER all=$rp eno1np0=$(sysctl -n net.ipv4.conf.eno1np0.rp_filter)"
  echo "LOG-MARTIANS all=$lm"
  if [ "$rp" != 1 ]; then
    die STOP-rp-filter
  fi
  if [ "$lm" != 1 ]; then
    die STOP-log-martians
  fi

  if [ ! -f /sys/devices/cpu_core/cpus ] || [ ! -f /sys/devices/cpu_atom/cpus ]; then
    die STOP-no-hybrid-pmu
  fi
  local pcores ecores sibs
  pcores=$(tr -d ' \n' < /sys/devices/cpu_core/cpus)
  ecores=$(tr -d ' \n' < /sys/devices/cpu_atom/cpus)
  sibs=$(tr -d ' \n' < /sys/devices/system/cpu/cpu0/topology/core_cpus_list)
  echo "PCORES $pcores"
  echo "ECORES $ecores"
  echo "CPU0-SIBLINGS $sibs"
  local overlap
  if ! expand_cpulist "$pcores" >/dev/null || ! expand_cpulist "$ecores" >/dev/null; then
    die STOP-cpulist
  fi
  if ! overlap=$(cpu_lists_overlap "$pcores" "$ecores"); then
    printf '%s\n' "$overlap"
    die STOP-hybrid-overlap
  fi
  if ! CAPTURE_TEXT=$(pick_capture_cpus "$pcores" "$sibs"); then
    die "${CAPTURE_TEXT:-STOP-capture-cpu-count}"
  fi
  echo "CAPTURE-CPUS $(printf '%s' "$CAPTURE_TEXT" | tr '\n' ' ')"

  local cpu gov avail
  if [ ! -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver ]; then
    die STOP-not-intel-pstate
  fi
  if [ "$(tr -d '\n' < /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver)" != intel_pstate ]; then
    die STOP-not-intel-pstate
  fi
  CPU0_EPP=$(tr -d '\n' < /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)
  echo "CPU0-EPP $CPU0_EPP"
  local state name
  for state in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
    [ -d "$state" ] || continue
    name=$(tr -d '\n' < "$state/name")
    if [ "$name" != POLL ] && [ "$name" != C1 ]; then
      CPU0_IDLE_PATH="$state/disable"
      CPU0_IDLE_DIS=$(tr -d '\n' < "$CPU0_IDLE_PATH")
      break
    fi
  done

  while read -r cpu; do
    [ -n "$cpu" ] || continue
    if [ ! -f "/sys/devices/system/cpu/cpu${cpu}/online" ] || [ "$(tr -d '\n' < "/sys/devices/system/cpu/cpu${cpu}/online")" != 1 ]; then
      die "STOP-cpu-offline $cpu"
    fi
    if [ "$(tr -d '\n' < "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_driver")" != intel_pstate ]; then
      die "STOP-not-intel-pstate $cpu"
    fi
    avail="/sys/devices/system/cpu/cpu${cpu}/cpufreq/energy_performance_available_preferences"
    if ! grep -qw performance "$avail"; then
      die "STOP-no-epp $cpu"
    fi
    gov=$(tr -d '\n' < "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor")
    echo "GOVERNOR $cpu $gov"
    local deep=0 have_c1=0
    for state in /sys/devices/system/cpu/cpu"${cpu}"/cpuidle/state*; do
      [ -d "$state" ] || continue
      name=$(tr -d '\n' < "$state/name")
      if [ "$name" = C1 ]; then
        have_c1=1
      fi
      if [ "$name" != POLL ] && [ "$name" != C1 ]; then
        deep=1
      fi
    done
    if [ "$have_c1" -ne 1 ]; then
      die "STOP-no-c1 $cpu"
    fi
    if [ "$deep" -ne 1 ]; then
      die "STOP-no-deep-state $cpu"
    fi
  done <<< "$CAPTURE_TEXT"

  if [ -f /etc/johnny/capture-cores ]; then
    local coretmp
    coretmp=$(mktemp)
    printf '%s\n' "$CAPTURE_TEXT" > "$coretmp"
    if ! cmp -s "$coretmp" /etc/johnny/capture-cores; then
      rm -f "$coretmp"
      die STOP-cores-drift
    fi
    rm -f "$coretmp"
  fi

  local yaml_count
  yaml_count=$(find /etc/netplan -maxdepth 1 -type f -name '*.yaml' | wc -l)
  if [ "$yaml_count" -ne 1 ]; then
    die STOP-netplan-extra
  fi
  if [ -L "$NETPLAN" ]; then
    die STOP-netplan-symlink
  fi
  local preview tmpyaml
  tmpyaml=$(mktemp)
  cp -a "$NETPLAN" "$tmpyaml"
  if ! preview=$(edit_netplan "$tmpyaml"); then
    rm -f "$tmpyaml"
    die "${preview:-STOP-netplan-shape}"
  fi
  rm -f "$tmpyaml"
  echo "YAML-PREVIEW $preview"

  local nicfile
  for nic in eno3 eno1np0 eno2np1 eno4; do
    nicfile="/run/systemd/network/10-netplan-${nic}.network"
    if [ ! -f "$nicfile" ]; then
      die "STOP-no-generated $nic"
    fi
  done
  if ! systemctl is-active --quiet systemd-networkd; then
    die STOP-networkd
  fi
  if systemctl is-active --quiet NetworkManager; then
    die STOP-networkmanager
  fi

  # EMBED docs/tool-install/step-11-revert.sh 0700
  local revert_line
  if ! revert_line=$(install_overwrite 0700 /root/step11-revert.sh <<'EOF'
#!/bin/bash
# Rollback for Johnny step 11. The apply script installs this at
# /root/step11-revert.sh before it changes the box. Safe to run twice.
#   sudo bash /root/step11-revert.sh
# Restores the first-run netplan backup, removes the capture drop-in,
# clears promisc and NOARP on eno1np0, and restores EPP and cpuidle.
set -euo pipefail
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
umask 022

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

rc=0

detach_xdp() {
  if command -v bpftool >/dev/null 2>&1 && [ -d /sys/class/net/eno1np0 ]; then
    bpftool net detach xdpdrv dev eno1np0 >/dev/null 2>&1 || true
    bpftool net detach xdp dev eno1np0 >/dev/null 2>&1 || true
  fi
  rm -f /sys/fs/bpf/johnny_xdp_count
  echo XDP-DETACHED
}

restore_tuning() {
  if [ -f /etc/systemd/system/johnny-capture-tuning.service ]; then
    systemctl disable --now johnny-capture-tuning.service || true
  fi
  if [ -x /etc/johnny/capture-tuning.sh ] && [ -f /var/lib/johnny/capture-tuning-before.tsv ]; then
    /etc/johnny/capture-tuning.sh revert || return 1
  fi
  rm -f /etc/systemd/system/johnny-capture-tuning.service
  rm -f /etc/johnny/capture-tuning.sh
  rm -f /etc/johnny/capture-cores
  rmdir /etc/johnny 2>/dev/null || true
  systemctl daemon-reload
  echo TUNING-REMOVED
}

restore_netplan() {
  local live=/etc/netplan/00-installer-config.yaml
  local bak=/root/00-installer-config.yaml.pre-step11
  local drop=/etc/systemd/network/10-netplan-eno1np0.network.d/60-johnny-capture.conf
  local reload_failed=0
  if [ -f "$drop" ] || [ -L "$drop" ]; then
    rm -f "$drop"
    rmdir /etc/systemd/network/10-netplan-eno1np0.network.d 2>/dev/null || true
    echo DROPIN-REMOVED
  fi
  if [ -f "$bak" ] && [ -f "$live" ] && ! cmp -s "$bak" "$live"; then
    cp -a "$bak" "$live"
    netplan generate
    netplan apply
    echo NETPLAN-RESTORED
  else
    # Drop-in file is already gone. Reload so networkd drops Promiscuous= and ARP=.
    if ! networkctl reload; then
      echo STOP-networkctl-reload
      reload_failed=1
    fi
    echo NETPLAN-UNCHANGED
  fi
  if [ -d /sys/class/net/eno1np0 ]; then
    ip link set dev eno1np0 promisc off
    ip link set dev eno1np0 arp on
    echo ENO1-FLAGS-CLEARED
  fi
  return "$reload_failed"
}

detach_xdp || rc=1
restore_tuning || rc=1
restore_netplan || rc=1
if [ "$rc" -ne 0 ]; then
  echo STOP-revert-incomplete
  exit 1
fi
echo REVERTED
EOF
  ); then
    printf '%s\n' "$revert_line"
    failed=1
    exit 1
  fi
  printf '%s\n' "$revert_line"
  revert_ready=1

  if [ -e /root/00-installer-config.yaml.pre-step11 ]; then
    echo BACKUP-KEPT /root/00-installer-config.yaml.pre-step11
  else
    cp -a "$NETPLAN" /root/00-installer-config.yaml.pre-step11
    echo BACKUP /root/00-installer-config.yaml.pre-step11
  fi

  mkdir -p /root/step11-pre
  for nic in eno3 eno1np0 eno2np1 eno4; do
    cp -a "/run/systemd/network/10-netplan-${nic}.network" "/root/step11-pre/${nic}.network"
  done

  local line
  # EMBED etc/systemd/network/10-netplan-eno1np0.network.d/60-johnny-capture.conf 0644
  if ! line=$(install_text 0644 "$DROPIN" <<'EOF'
# Johnny step 11. Merged into netplan's 10-netplan-eno1np0.network.
# [Link] Promiscuous= and ARP= (systemd.network(5); Promiscuous= since 248, ARP= since 232).
[Link]
Promiscuous=yes
ARP=no
EOF
  ); then
    printf '%s\n' "$line"
    failed=1
    exit 1
  fi
  printf '%s\n' "$line"
  case "$line" in
    WROTE*) mark_changed ;;
  esac

  flags=$(tr -d '[:space:]' < /sys/class/net/eno1np0/flags)
  if flags_capture_ok "$flags"; then
    echo ALREADY-promisc
  else
    networkctl reload
    networkctl reconfigure eno1np0
    if ! wait_capture_port; then
      die STOP-promisc
    fi
    echo OK-promisc
  fi

  if ! line=$(edit_netplan "$NETPLAN"); then
    die "${line:-STOP-netplan-edit}"
  fi
  echo "$line"
  case "$line" in
    WROTE-yaml) mark_changed ;;
  esac

  timeout 30 netplan generate
  for nic in eno3 eno1np0 eno4; do
    if ! cmp -s "/root/step11-pre/${nic}.network" "/run/systemd/network/10-netplan-${nic}.network"; then
      die "STOP-generate-$nic"
    fi
  done
  if ! grep -qx 'ActivationPolicy=always-down' /run/systemd/network/10-netplan-eno2np1.network; then
    die STOP-activation-policy
  fi
  flags=$(tr -d '[:space:]' < /sys/class/net/eno2np1/flags)
  if flags_well_formed "$flags" && cmp -s /root/step11-pre/eno2np1.network /run/systemd/network/10-netplan-eno2np1.network && ! flags_admin_up "$flags"; then
    echo ALREADY-eno2
  else
    mark_changed
    timeout 90 netplan apply
    echo NETPLAN-APPLIED
  fi

  if ! wait_eno2_down; then
    die STOP-eno2-up
  fi
  echo OK-eno2
  if ! wait_eno3; then
    die STOP-eno3-after
  fi
  echo OK-eno3
  if [ "$ENO4_WAS_UP" -eq 1 ]; then
    flags=$(tr -d '[:space:]' < /sys/class/net/eno4/flags)
    if ! flags_admin_up "$flags"; then
      die STOP-eno4-down
    fi
  fi
  if [ -n "$(ip -4 -o addr show dev eno4)" ] || [ -n "$(ip -6 -o addr show dev eno4)" ]; then
    die STOP-eno4-addr
  fi
  if ! wait_capture_port; then
    networkctl reload
    networkctl reconfigure eno1np0
  fi
  if ! wait_capture_port; then
    die STOP-promisc
  fi
  if [ -n "$(ip -4 -o addr show dev eno1np0)" ] || [ -n "$(ip -6 -o addr show dev eno1np0)" ]; then
    die STOP-eno1-addr
  fi
  speed=$(tr -d '\n' < /sys/class/net/eno1np0/speed)
  if [ "$speed" != 10000 ]; then
    die "STOP-eno1-speed $speed"
  fi
  echo OK-eno1

  local before_m
  before_m=$(martian_count) || die STOP-martian-read
  echo "MARTIAN-BEFORE $before_m"

  if ! run_xdp; then
    failed=1
    exit 1
  fi

  local after_m
  after_m=$(martian_count) || die STOP-martian-read
  echo "MARTIAN-AFTER $after_m"

  install_tuning
  echo STEP11-DONE
  echo "Log: /root/step11-apply.log"
  exit 0
}

install_overwrite() {
  local mode=$1 dest=$2 tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [ -L "$dest" ]; then
    rm -f "$tmp"
    echo "STOP-symlink $dest"
    return 1
  fi
  install -m "$mode" -o root -g root "$tmp" "$dest"
  rm -f "$tmp"
  echo "WROTE $dest"
}

install_text() {
  local mode=$1 dest=$2 tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [ -L "$dest" ]; then
    rm -f "$tmp"
    echo "STOP-symlink $dest"
    return 1
  fi
  if [ -e "$dest" ]; then
    if cmp -s "$tmp" "$dest"; then
      rm -f "$tmp"
      echo "KEPT $dest"
      return 0
    fi
    rm -f "$tmp"
    echo "STOP-drift $dest"
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  install -m "$mode" -o root -g root "$tmp" "$dest"
  rm -f "$tmp"
  echo "WROTE $dest"
}

wait_capture_port() {
  local i f s carrier oper
  for i in 1 2 3 4 5 6 7 8 9 10; do
    f=$(tr -d '[:space:]' < /sys/class/net/eno1np0/flags)
    s=$(tr -d '[:space:]' < /sys/class/net/eno1np0/speed || true)
    carrier=$(tr -d '[:space:]' < /sys/class/net/eno1np0/carrier || true)
    oper=$(tr -d '[:space:]' < /sys/class/net/eno1np0/operstate || true)
    if flags_capture_ok "$f" && eno1_link_ok "$s" "$f" "$carrier" "$oper"; then
      if [ -z "$(ip -4 -o addr show dev eno1np0)" ] && [ -z "$(ip -6 -o addr show dev eno1np0)" ]; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

wait_eno2_down() {
  local i f
  for i in 1 2 3 4 5 6 7 8 9 10; do
    f=$(tr -d '[:space:]' < /sys/class/net/eno2np1/flags)
    if flags_well_formed "$f" && ! flags_admin_up "$f"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_eno3() {
  local i f
  for i in 1 2 3 4 5 6 7 8 9 10; do
    f=$(tr -d '[:space:]' < /sys/class/net/eno3/flags)
    if ip -4 -o addr show dev eno3 | grep -q 'inet 192\.168\.50\.152/' \
      && ip -4 route show default | grep -q 'dev eno3' \
      && flags_admin_up "$f"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

martian_count() {
  local n
  n=$(journalctl -k | grep -c martian || true)
  if [[ ! $n =~ ^[0-9]+$ ]]; then
    echo STOP-martian-read
    return 1
  fi
  printf '%s\n' "$n"
}

nic_rx() {
  local n
  if n=$(ethtool -S eno1np0 | awk '/^[[:space:]]*rx_unicast\.nic:/{print $2; found=1} END{if (!found) exit 1}'); then
    printf '%s\n' "$n"
    return 0
  fi
  echo NOTE-nic-counter-fallback >&2
  tr -d '\n' < /sys/class/net/eno1np0/statistics/rx_packets
  printf '\n'
}

run_xdp() {
  local before after nic0 nic1 mode id
  if ! bpftool prog load "$XDP_OBJ" /sys/fs/bpf/johnny_xdp_count; then
    echo STOP-xdp-load
    rm -f /sys/fs/bpf/johnny_xdp_count
    return 1
  fi
  if ! bpftool net attach xdpdrv pinned /sys/fs/bpf/johnny_xdp_count dev eno1np0; then
    echo STOP-xdp-attach
    ethtool -k eno1np0 | awk '/generic-receive-offload|large-receive-offload|rx-checksum|receive-hashing/{print "OFFLOAD " $0}' || true
    journalctl -k -n 50 --no-pager | grep -Ei 'xdp|ice|ddp' || true
    rm -f /sys/fs/bpf/johnny_xdp_count
    return 1
  fi
  xdp_attached=1
  mode=$(bpftool -j net show dev eno1np0 | xdp_modes_from_json eno1np0)
  if [ "$mode" != driver ]; then
    echo "STOP-xdp-mode ${mode:-empty}"
    return 1
  fi
  if ! id=$(bpftool -j prog show pinned /sys/fs/bpf/johnny_xdp_count | map_id_from_json); then
    echo STOP-xdp-map
    return 1
  fi
  if ! before=$(bpftool -j map dump id "$id" | map_value_from_json); then
    echo STOP-xdp-map
    return 1
  fi
  nic0=$(nic_rx)
  sleep 5
  if ! after=$(bpftool -j map dump id "$id" | map_value_from_json); then
    echo STOP-xdp-map
    return 1
  fi
  if [ "$after" -le "$before" ]; then
    sleep 10
    if ! after=$(bpftool -j map dump id "$id" | map_value_from_json); then
      echo STOP-xdp-map
      return 1
    fi
  fi
  nic1=$(nic_rx)
  bpftool net detach xdpdrv dev eno1np0
  xdp_attached=0
  rm -f /sys/fs/bpf/johnny_xdp_count
  mode=$(bpftool -j net show dev eno1np0 | xdp_modes_from_json eno1np0)
  if [ -n "$mode" ]; then
    echo "STOP-xdp-linger $mode"
    return 1
  fi
  echo "XDP-MODE driver"
  echo "XDP-COUNT $before $after"
  echo "NIC-RX $nic0 $nic1"
  if [ "$after" -gt "$before" ]; then
    echo XDP-OK
    return 0
  fi
  if [ "$nic1" -gt "$nic0" ]; then
    echo STOP-xdp-no-count
    return 1
  fi
  echo STOP-xdp-no-traffic
  return 1
}

install_tuning() {
  local line dest=/etc/johnny/capture-cores tmp
  mkdir -p /etc/johnny
  tmp=$(mktemp)
  printf '%s\n' "$CAPTURE_TEXT" > "$tmp"
  if [ -L "$dest" ]; then
    rm -f "$tmp"
    die "STOP-symlink $dest"
  fi
  if [ -e "$dest" ]; then
    if ! cmp -s "$tmp" "$dest"; then
      rm -f "$tmp"
      die STOP-cores-drift
    fi
    rm -f "$tmp"
    echo "KEPT $dest"
  else
    install -m 0644 -o root -g root "$tmp" "$dest"
    rm -f "$tmp"
    echo "WROTE $dest"
    mark_changed
  fi

  # EMBED etc/johnny/capture-tuning.sh 0755
  if ! line=$(install_text 0755 /etc/johnny/capture-tuning.sh <<'EOF'
#!/bin/bash
# Johnny step 11. Apply or restore EPP and per-CPU idle on the CPUs in
# /etc/johnny/capture-cores. The apply script installs this. A reboot
# re-applies it via johnny-capture-tuning.service. revert writes the
# saved values back. The save file is kept so a later apply still
# restores the original values.
set -euo pipefail
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
umask 022

CORES=/etc/johnny/capture-cores
BEFORE=/var/lib/johnny/capture-tuning-before.tsv
ACTION=${1:-}

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi
if [ "$ACTION" != apply ] && [ "$ACTION" != revert ]; then
  echo STOP-tuning-args
  exit 1
fi
if [ -L "$BEFORE" ] || [ -L "$CORES" ]; then
  echo STOP-tuning-symlink
  exit 1
fi

read_trim() {
  tr -d '\n' < "$1"
}

collect_before() {
  local cpu state name dis tmp
  tmp=$(mktemp /var/lib/johnny/before.XXXXXX)
  while read -r cpu; do
    [ -n "$cpu" ] || continue
    printf 'epp\t%s\t%s\n' "$cpu" "$(read_trim "/sys/devices/system/cpu/cpu${cpu}/cpufreq/energy_performance_preference")" >> "$tmp"
    for state in /sys/devices/system/cpu/cpu"${cpu}"/cpuidle/state*; do
      [ -d "$state" ] || continue
      name=$(read_trim "$state/name")
      if [ "$name" = POLL ] || [ "$name" = C1 ]; then
        continue
      fi
      dis=$(read_trim "$state/disable")
      printf 'idle\t%s\t%s\t%s\t%s\n' "$cpu" "$(basename "$state")" "$name" "$dis" >> "$tmp"
    done
  done < "$CORES"
  chmod 0644 "$tmp"
  mv "$tmp" "$BEFORE"
}

cpu_ready() {
  local cpu=$1 online
  online="/sys/devices/system/cpu/cpu${cpu}/online"
  if [ ! -f "$online" ] || [ "$(read_trim "$online")" != 1 ]; then
    echo "STOP-cpu-offline $cpu"
    exit 1
  fi
}

apply_one() {
  local cpu=$1 state name epp_path deep
  cpu_ready "$cpu"
  epp_path="/sys/devices/system/cpu/cpu${cpu}/cpufreq/energy_performance_preference"
  printf '%s\n' performance > "$epp_path"
  if [ "$(read_trim "$epp_path")" != performance ]; then
    echo "STOP-epp-write $cpu"
    exit 1
  fi
  deep=0
  for state in /sys/devices/system/cpu/cpu"${cpu}"/cpuidle/state*; do
    [ -d "$state" ] || continue
    name=$(read_trim "$state/name")
    if [ "$name" = POLL ] || [ "$name" = C1 ]; then
      continue
    fi
    deep=1
    printf '%s\n' 1 > "$state/disable"
    if [ "$(read_trim "$state/disable")" != 1 ]; then
      echo "STOP-idle-write $cpu $name"
      exit 1
    fi
  done
  if [ "$deep" -ne 1 ]; then
    echo "STOP-no-deep-state $cpu"
    exit 1
  fi
}

apply_all() {
  local cpu
  if [ ! -f "$CORES" ]; then
    echo STOP-no-cores
    exit 1
  fi
  mkdir -p /var/lib/johnny
  if [ ! -f "$BEFORE" ]; then
    collect_before
    echo "SAVED $BEFORE"
  else
    echo "BACKUP-KEPT $BEFORE"
  fi
  while read -r cpu; do
    [ -n "$cpu" ] || continue
    apply_one "$cpu"
    echo "TUNED $cpu"
  done < "$CORES"
}

revert_all() {
  local kind cpu field3 field4 field5 path
  if [ ! -f "$BEFORE" ]; then
    echo NOTE-no-before
    return 0
  fi
  while IFS=$'\t' read -r kind cpu field3 field4 field5; do
    [ -n "${kind:-}" ] || continue
    case "$kind" in
      epp)
        path="/sys/devices/system/cpu/cpu${cpu}/cpufreq/energy_performance_preference"
        printf '%s\n' "$field3" > "$path"
        if [ "$(read_trim "$path")" != "$field3" ]; then
          echo "STOP-epp-restore $cpu"
          exit 1
        fi
        ;;
      idle)
        path="/sys/devices/system/cpu/cpu${cpu}/cpuidle/${field3}/disable"
        printf '%s\n' "$field5" > "$path"
        if [ "$(read_trim "$path")" != "$field5" ]; then
          echo "STOP-idle-restore $cpu $field3 $field4"
          exit 1
        fi
        ;;
      *)
        echo "STOP-before-line $kind"
        exit 1
        ;;
    esac
  done < "$BEFORE"
  echo TUNING-RESTORED
}

case "$ACTION" in
  apply) apply_all ;;
  revert) revert_all ;;
esac
EOF
  ); then
    printf '%s\n' "$line"
    failed=1
    exit 1
  fi
  printf '%s\n' "$line"
  case "$line" in
    WROTE*) mark_changed ;;
  esac

  # EMBED etc/systemd/system/johnny-capture-tuning.service 0644
  if ! line=$(install_text 0644 /etc/systemd/system/johnny-capture-tuning.service <<'EOF'
[Unit]
Description=Johnny capture-core EPP and idle tuning
After=multi-user.target
ConditionPathExists=/etc/johnny/capture-cores
ConditionPathExists=/etc/johnny/capture-tuning.sh

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/etc/johnny/capture-tuning.sh apply
ExecStop=/etc/johnny/capture-tuning.sh revert
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF
  ); then
    printf '%s\n' "$line"
    failed=1
    exit 1
  fi
  printf '%s\n' "$line"
  case "$line" in
    WROTE*) mark_changed ;;
  esac

  local before_active st en
  before_active=$(systemctl is-active johnny-capture-tuning.service || true)
  systemctl daemon-reload
  if ! systemctl enable --now johnny-capture-tuning.service; then
    mark_changed
    die STOP-tuning-unit
  fi
  if [ "$before_active" != active ]; then
    mark_changed
  fi
  st=$(systemctl is-active johnny-capture-tuning.service || true)
  en=$(systemctl is-enabled johnny-capture-tuning.service || true)
  if [ "$st" != active ] || [ "$en" != enabled ]; then
    die "STOP-tuning-unit $st $en"
  fi
  verify_tuning
  echo OK-tuning
  sha256sum \
    "$DROPIN" \
    /etc/johnny/capture-tuning.sh \
    /etc/systemd/system/johnny-capture-tuning.service \
    "$NETPLAN" \
    /etc/johnny/capture-cores
}

verify_tuning() {
  local cpu epp state name now
  while read -r cpu; do
    [ -n "$cpu" ] || continue
    epp=$(tr -d '\n' < "/sys/devices/system/cpu/cpu${cpu}/cpufreq/energy_performance_preference")
    if [ "$epp" != performance ]; then
      die "STOP-epp-verify $cpu $epp"
    fi
    for state in /sys/devices/system/cpu/cpu"${cpu}"/cpuidle/state*; do
      [ -d "$state" ] || continue
      name=$(tr -d '\n' < "$state/name")
      if [ "$name" = POLL ] || [ "$name" = C1 ]; then
        continue
      fi
      if [ "$(tr -d '\n' < "$state/disable")" != 1 ]; then
        die "STOP-idle-verify $cpu $name"
      fi
    done
    echo "VERIFY-TUNED $cpu"
  done < /etc/johnny/capture-cores
  now=$(tr -d '\n' < /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)
  if [ "$now" != "$CPU0_EPP" ]; then
    die "STOP-cpu0-epp $CPU0_EPP $now"
  fi
  if [ -n "$CPU0_IDLE_PATH" ]; then
    now=$(tr -d '\n' < "$CPU0_IDLE_PATH")
    if [ "$now" != "$CPU0_IDLE_DIS" ]; then
      die "STOP-cpu0-idle $CPU0_IDLE_DIS $now"
    fi
  fi
  echo CPU0-UNCHANGED
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
