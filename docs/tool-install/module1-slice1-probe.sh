#!/bin/bash
# Module 1 slice 1: read-only capability probe for the passive SPAN / XDP path.
# Runbook: docs/tool-install/module1-slice1-span-xdp.md
#
# Two modes, both read-only:
#   user  as aj, no sudo:   bash module1-slice1-probe.sh user
#   root  as root (sudo):   sudo bash module1-slice1-probe.sh root   (bpftool only)
#
# This script never changes a NIC, a sysctl, a unit, a package, or a file
# outside its own output directory. Every Johnny-state command goes through
# ro(), which refuses anything not on the read-only allowlist (ro_allowed).
# It does not attach, load, pin, or detach a BPF program. It does not open an
# AF_XDP socket. It does not use `bpftool feature probe ... full`.
#
# STOP lines are collected, not fail-fast: a probe should show every fact.
# One or more STOPs withholds the DONE token and exits 1. NOTE lines never do.
set -euo pipefail

# Test seams: the rock-box self-test points these at fixtures. On Johnny they are
# unset, so the defaults below are what run.
IFACE=${M1S1_IFACE:-eno1np0}
SYS=${M1S1_SYS:-/sys}
PROC=${M1S1_PROC:-/proc}
CORES_FILE=${M1S1_CORES_FILE:-/etc/johnny/capture-cores}
SAMPLE_SECS=${M1S1_SAMPLE_SECS:-5}
OUT_USER=${M1S1_OUT:-/home/aj/cis-audit/m1s1-probe}
OUT_ROOT=${M1S1_OUT:-/root/m1s1-probe-root}
EXPECT_KERNEL=7.0.0-42-generic
# shellcheck disable=SC2016  # dpkg-query expands this itself
DPKG_FMT='${Package} ${Version} ${Status}\n'
STOPS=0
OUT=
FLAG_UP=$((0x1))
FLAG_NOARP=$((0x80))
FLAG_PROMISC=$((0x100))

# ---------------------------------------------------------------- allowlist

is_name() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._@:-]*$ ]]
}

# 0 if the argv is on the read-only list, 1 otherwise. No eval, no globbing.
ro_allowed() {
  local n=$#
  [ "$n" -ge 1 ] || return 1
  case "$1" in
    ip)
      [ "$n" -eq 5 ] || return 1
      [ "$2 $3 $4" = "-d link show" ] || [ "$2 $3 $4" = "-br addr show" ] || return 1
      is_name "$5"
      ;;
    ethtool)
      [ "$n" -eq 3 ] || return 1
      case "$2" in
        -i | -k | -g | -l | -x | -n | -S | --show-priv-flags) is_name "$3" ;;
        *) return 1 ;;
      esac
      ;;
    ss)
      [ "$*" = "ss -f xdp -a" ]
      ;;
    systemctl)
      [ "$n" -eq 3 ] || return 1
      case "$2" in
        is-enabled | is-active) is_name "$3" ;;
        show) [ "$3" = "--property=DefaultLimitMEMLOCK" ] ;;
        *) return 1 ;;
      esac
      ;;
    journalctl)
      [ "$*" = "journalctl -k -b --no-pager" ] || [ "$*" = "journalctl -k --no-pager" ]
      ;;
    sysctl)
      [ "$n" -eq 3 ] || return 1
      [ "$2" = "-n" ] || return 1
      [[ $3 =~ ^[a-z0-9_]+(\.[a-z0-9_]+)+$ ]]
      ;;
    findmnt)
      [ "$*" = "findmnt -n /sys/fs/bpf" ] || [ "$*" = "findmnt -n -o FSTYPE,OPTIONS /sys/fs/bpf" ]
      ;;
    dpkg-query)
      [ "$n" -eq 4 ] || return 1
      [ "$2" = "-W" ] || return 1
      [ "$3" = "-f=${DPKG_FMT}" ] || return 1
      is_name "$4"
      ;;
    apt-cache)
      [ "$n" -eq 3 ] || return 1
      [ "$2" = "policy" ] || return 1
      is_name "$3"
      ;;
    bpftool)
      case "$*" in
        "bpftool version" | "bpftool feature probe kernel" | "bpftool -j feature probe kernel" | \
          "bpftool -j net show" | "bpftool -j prog show") return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

ro() {
  if ! ro_allowed "$@"; then
    printf 'STOP-not-readonly %s\n' "$*" >&2
    exit 97
  fi
  "$@"
}

# ---------------------------------------------------------------- pure parsers

# "1-4,7" -> one CPU id per line. Return 1 on any other shape.
cpulist_expand() {
  local spec=$1 part lo hi i
  [[ $spec =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || return 1
  local IFS=,
  # shellcheck disable=SC2086
  for part in $spec; do
    if [[ $part == *-* ]]; then
      lo=${part%-*}
      hi=${part#*-}
    else
      lo=$part
      hi=$part
    fi
    lo=$((10#$lo))
    hi=$((10#$hi))
    [ "$lo" -le "$hi" ] || return 1
    i=$lo
    while [ "$i" -le "$hi" ]; do
      printf '%s\n' "$i"
      i=$((i + 1))
    done
  done
}

# 0 if CPU $1 is in cpulist $2, 1 if not or on any malformed input.
# No pipe into an early-exit reader: under `set -o pipefail` a `grep -q` that
# exits on the first match SIGPIPEs the writer (rc 141) and turns a correct
# "yes" into "no". The expansion is captured first, then matched with `case`.
cpu_in_list() {
  local cpu=$1 list=$2 expanded
  [[ $cpu =~ ^[0-9]+$ ]] || return 1
  cpu=$((10#$cpu))
  expanded=$(cpulist_expand "$list") || return 1
  case $'\n'"$expanded"$'\n' in
    *$'\n'"$cpu"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

flags_well_formed() {
  [[ $1 =~ ^(0[xX][0-9a-fA-F]+|[0-9]+)$ ]]
}

flag_set() {
  local flags=$1 bit=$2
  flags_well_formed "$flags" || return 1
  [ $((flags & bit)) -ne 0 ]
}

# stdin: `ethtool -k`. Prints on | off | on-fixed | off-fixed | absent.
ethtool_feature_state() {
  awk -v want="$1" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      n = index(line, ":")
      if (n == 0) next
      key = substr(line, 1, n - 1)
      val = substr(line, n + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      if (key == want) {
        found = 1
        st = val
        sub(/[[:space:]]*\[.*$/, "", st)
        fixed = (val ~ /\[fixed\]/) ? "-fixed" : ""
        print st fixed
        exit
      }
    }
    END { if (!found) print "absent" }'
}

# stdin: `ethtool -l` or `ethtool -g`. $1 = max | cur, $2 = field name.
ethtool_sect_get() {
  awk -v sect="$1" -v field="$2" '
    /^Pre-set maximums:/ { s = "max"; next }
    /^Current hardware settings:/ { s = "cur"; next }
    s == sect {
      n = index($0, ":")
      if (n && substr($0, 1, n - 1) == field) {
        v = substr($0, n + 1)
        gsub(/[[:space:]]/, "", v)
        print v
        f = 1
        exit
      }
    }
    END { if (!f) print "absent" }'
}

# stdin: `ethtool -i`. $1 = field name. Prints the value or "absent".
ethtool_i_get() {
  awk -v field="$1" '
    {
      n = index($0, ": ")
      if (n && substr($0, 1, n - 1) == field) {
        print substr($0, n + 2)
        f = 1
        exit
      }
    }
    END { if (!f) print "absent" }'
}

# stdin: `ethtool --show-priv-flags`. Prints "name state" per flag.
priv_flags_lines() {
  awk '
    NR == 1 && /^Private flags for/ { next }
    {
      n = index($0, ":")
      if (n == 0) next
      k = substr($0, 1, n - 1)
      v = substr($0, n + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (k != "") print k, v
    }'
}

# stdin: `ip -d link show IFACE`. Prints yes | no.
xdp_attached_from_iplink() {
  if grep -Eq '(^|[[:space:]])(prog/xdp|xdp|xdpgeneric|xdpdrv|xdpoffload)([[:space:]]|$)'; then
    echo yes
  else
    echo no
  fi
}

# stdin: /proc/interrupts. $1 = interface. Prints "irq name" for its queue vectors.
queue_irqs_from_interrupts() {
  awk -v want="$1" '
    {
      irq = $1
      sub(/:$/, "", irq)
      if (irq !~ /^[0-9]+$/) next
      name = $NF
      if (name ~ "^ice-" want "-TxRx-[0-9]+$") print irq, name
    }'
}

# stdin: `ip -br addr show IFACE`. Prints the count of address tokens (fields after state).
addr_count_from_brief() {
  awk 'NR == 1 { c = NF > 2 ? NF - 2 : 0; print c; found = 1 } END { if (!found) print 0 }'
}

# $1 = path to a kernel config, $2 = CONFIG_KEY. Prints y | m | n | absent.
config_value() {
  local file=$1 key=$2 line
  [[ $key =~ ^CONFIG_[A-Z0-9_]+$ ]] || return 1
  if line=$(grep -E "^${key}=" "$file"); then
    printf '%s\n' "${line#*=}"
  elif grep -qE "^# ${key} is not set\$" "$file"; then
    echo n
  else
    echo absent
  fi
}

# stdin: one line like "none [integrity] confidentiality". Prints the bracketed word or "unknown".
bracketed_word() {
  local line m
  read -r line || true
  m=$(printf '%s' "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')
  printf '%s\n' "${m:-unknown}"
}

# $1 before, $2 after, $3 seconds. Integer per-second delta; 0 if the counter went backwards.
rate_per_sec() {
  local b=$1 a=$2 s=$3
  [[ $b =~ ^[0-9]+$ && $a =~ ^[0-9]+$ && $s =~ ^[0-9]+$ ]] || return 1
  [ "$s" -gt 0 ] || return 1
  if [ "$a" -lt "$b" ]; then
    echo 0
  else
    echo $(((a - b) / s))
  fi
}

# stdin: JSON. $1 = key. Prints yes | no | absent (searches every nesting level).
bpf_feature_bool() {
  python3 -I -c '
import json, sys
key = sys.argv[1]
res = []
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == key and isinstance(v, bool):
                res.append(v)
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(json.load(sys.stdin))
print("absent" if not res else ("yes" if all(res) else "no"))
' "$1"
}

# stdin: JSON from `bpftool -j feature probe kernel`. $1 = helper name.
# Prints yes | no | absent for the helper under any "xdp*" prog-type list.
bpf_xdp_helper() {
  python3 -I -c '
import json, sys
want = sys.argv[1]
lists = []
def walk(o, key=None):
    if isinstance(o, dict):
        for k, v in o.items():
            walk(v, k)
    elif isinstance(o, list):
        if key is not None and key.startswith("xdp") and all(isinstance(x, str) for x in o):
            lists.append(o)
        for v in o:
            walk(v, None)
walk(json.load(sys.stdin))
if not lists:
    print("absent")
else:
    print("yes" if all(want in l for l in lists) else "no")
' "$1"
}

# stdin: JSON from `bpftool -j net show`. $1 = devname. Prints the XDP modes attached.
xdp_modes_from_net_json() {
  python3 -I -c '
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

# stdin: JSON from `bpftool -j prog show`. $1 = type. Prints the count.
prog_count_by_type() {
  python3 -I -c '
import json, sys
want = sys.argv[1]
doc = json.load(sys.stdin)
items = doc if isinstance(doc, list) else []
print(sum(1 for p in items if isinstance(p, dict) and p.get("type") == want))
' "$1"
}

# ---------------------------------------------------------------- output helpers

note() {
  printf '%s\n' "$*" | tee -a "$OUT/summary.txt"
}

stop() {
  STOPS=$((STOPS + 1))
  note "STOP-$*"
}

trim_file() {
  tr -d '[:space:]' <"$1"
}

# Run a read-only command, save stdout+stderr to $OUT/$1, return its status.
# Usage: save NAME cmd args...
save() {
  local name=$1
  shift
  local rc=0
  # ro() exits 97 on a refusal, and its message goes to stderr. Check the
  # allowlist before the redirect below, or STOP-not-readonly lands in the
  # saved .err file and the operator sees a silent exit 97.
  ro_allowed "$@" || ro "$@"
  ro "$@" >"$OUT/$name" 2>"$OUT/$name.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    note "NOTE-cmd-failed $name rc=$rc"
  fi
  return "$rc"
}

open_out() {
  local dir=$1
  if [ -e "$dir" ]; then
    mv "$dir" "$dir.prev.$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  mkdir -p "$dir"
  OUT=$dir
}

# ---------------------------------------------------------------- user mode

probe_link() {
  local base=$SYS/class/net/$IFACE flags mtu speed carrier oper
  if [ ! -d "$base" ]; then
    stop "no-iface $IFACE"
    return 0
  fi
  flags=$(trim_file "$base/flags")
  mtu=$(trim_file "$base/mtu")
  speed=$(trim_file "$base/speed" 2>/dev/null || echo unknown)
  carrier=$(trim_file "$base/carrier" 2>/dev/null || echo unknown)
  oper=$(trim_file "$base/operstate")
  note "LINK $IFACE flags=$flags mtu=$mtu speed=$speed carrier=$carrier oper=$oper"

  if ! flags_well_formed "$flags"; then
    stop "flags-form $flags"
  else
    flag_set "$flags" "$FLAG_UP" || stop "eno1-not-up flags=$flags"
    flag_set "$flags" "$FLAG_PROMISC" || stop "eno1-not-promisc flags=$flags"
    flag_set "$flags" "$FLAG_NOARP" || stop "eno1-not-noarp flags=$flags"
  fi
  if ! [[ $mtu =~ ^[0-9]+$ ]]; then
    stop "mtu-form $mtu"
  elif [ "$mtu" -gt 3000 ]; then
    stop "mtu-over-3000 $mtu"
  elif [ "$mtu" -ne 1500 ]; then
    note "NOTE-mtu-not-1500 $mtu"
  else
    note "OK-mtu-1500"
  fi
  if [ "$speed" != 10000 ] || { [ "$carrier" != 1 ] && [ "$oper" != up ]; }; then
    stop "link-not-10g-up speed=$speed carrier=$carrier oper=$oper"
  fi

  save ip-addr.txt ip -br addr show "$IFACE" || true
  local addrs
  addrs=$(addr_count_from_brief <"$OUT/ip-addr.txt")
  if [ "$addrs" -ne 0 ]; then
    stop "eno1-has-address count=$addrs"
  else
    note "OK-no-address"
  fi

  save ip-link.txt ip -d link show "$IFACE" || true
  if [ "$(xdp_attached_from_iplink <"$OUT/ip-link.txt")" = yes ]; then
    stop "xdp-attached-already"
  else
    note "OK-no-xdp-attached"
  fi
}

probe_driver() {
  local drv
  if save ethtool-i.txt ethtool -i "$IFACE"; then
    drv=$(ethtool_i_get driver <"$OUT/ethtool-i.txt")
    note "DRIVER $drv"
    note "DRIVER-VERSION $(ethtool_i_get version <"$OUT/ethtool-i.txt")"
    note "FIRMWARE $(ethtool_i_get firmware-version <"$OUT/ethtool-i.txt")"
    note "BUS $(ethtool_i_get bus-info <"$OUT/ethtool-i.txt")"
    [ "$drv" = ice ] || stop "driver-not-ice $drv"
  else
    stop "ethtool-i"
  fi
}

probe_ddp() {
  local ddp=0 safe=0
  if save klog-this-boot.txt journalctl -k -b --no-pager; then
    ddp=$(grep -ci 'DDP package' "$OUT/klog-this-boot.txt" || true)
    safe=$(grep -ci 'safe mode' "$OUT/klog-this-boot.txt" || true)
    grep -iE 'DDP package|safe mode' "$OUT/klog-this-boot.txt" | head -n 5 | while IFS= read -r l; do note "DDP-LINE $l"; done || true
    if [ "$safe" -gt 0 ]; then
      stop "ddp-safe-mode"
    elif grep -qi 'DDP package.*successfully loaded' "$OUT/klog-this-boot.txt"; then
      note "OK-ddp-loaded"
    else
      note "NOTE-ddp-line-not-found ddp_lines=$ddp"
    fi
    grep -iE 'ice .*(xdp|zc|zero.?copy|error|fail|reset)' "$OUT/klog-this-boot.txt" | tail -n 5 | while IFS= read -r l; do note "KLOG-ICE $l"; done || true
  else
    note "NOTE-journal-unreadable"
  fi
  # Same count as step 11 (`journalctl -k | grep -c martian`, all boots), so the numbers compare.
  local all
  if ro journalctl -k --no-pager >"$OUT/klog-all.tmp" 2>/dev/null; then
    all=$(grep -c martian "$OUT/klog-all.tmp" || true)
    note "MARTIAN-COUNT ${all:-0}"
  else
    note "NOTE-martian-count-unavailable (journalctl -k failed)"
  fi
  rm -f "$OUT/klog-all.tmp"
}

probe_offloads() {
  local f st
  if save ethtool-k.txt ethtool -k "$IFACE"; then
    for f in generic-receive-offload large-receive-offload rx-gro-hw rx-vlan-offload rx-vlan-filter \
      ntuple-filters receive-hashing rx-checksumming hw-tc-offload; do
      st=$(ethtool_feature_state "$f" <"$OUT/ethtool-k.txt")
      note "FEATURE $f $st"
      case "$f:$st" in
        large-receive-offload:on | large-receive-offload:on-fixed) note "NOTE-lro-on" ;;
        rx-vlan-offload:on) note "NOTE-rxvlan-on (tags may be stripped before XDP; [Assumption] ice behavior, not read from source)" ;;
        *) ;;
      esac
    done
  else
    note "NOTE-no-ethtool-k"
  fi
}

probe_queues() {
  local cmax ccur
  if save ethtool-l.txt ethtool -l "$IFACE"; then
    cmax=$(ethtool_sect_get max Combined <"$OUT/ethtool-l.txt")
    ccur=$(ethtool_sect_get cur Combined <"$OUT/ethtool-l.txt")
    note "QUEUES-COMBINED max=$cmax cur=$ccur"
    note "QUEUES-RX-TX rx=$(ethtool_sect_get cur RX <"$OUT/ethtool-l.txt") tx=$(ethtool_sect_get cur TX <"$OUT/ethtool-l.txt")"
    QUEUES_CUR=$ccur
  else
    QUEUES_CUR=absent
    note "NOTE-no-ethtool-l"
  fi
  if save ethtool-g.txt ethtool -g "$IFACE"; then
    note "RING rx=$(ethtool_sect_get cur RX <"$OUT/ethtool-g.txt")/$(ethtool_sect_get max RX <"$OUT/ethtool-g.txt") tx=$(ethtool_sect_get cur TX <"$OUT/ethtool-g.txt")/$(ethtool_sect_get max TX <"$OUT/ethtool-g.txt")"
  fi
  if save ethtool-x.txt ethtool -x "$IFACE"; then
    grep -iE 'toeplitz|xor|crc32|symmetric' "$OUT/ethtool-x.txt" | sed 's/^[[:space:]]*//' | while IFS= read -r l; do note "RSS-HASH $l"; done || true
  fi
  if save ethtool-n.txt ethtool -n "$IFACE"; then
    note "RX-RULES $(grep -iE 'total' "$OUT/ethtool-n.txt" | head -n 1 | sed 's/^[[:space:]]*//' || true)"
  fi
  if save priv-flags.txt ethtool --show-priv-flags "$IFACE"; then
    priv_flags_lines <"$OUT/priv-flags.txt" | while IFS= read -r l; do note "PRIV $l"; done
  fi
}

probe_stats() {
  if save ethtool-S.txt ethtool -S "$IFACE"; then
    grep -E '^[[:space:]]*(rx_unicast\.nic|rx_dropped|rx_discards|rx_crc_errors|rx_length_errors|rx_oversize\.nic|rx_undersize\.nic)[^:]*:' "$OUT/ethtool-S.txt" |
      sed 's/^[[:space:]]*//; s/:[[:space:]]*/ /' | while IFS= read -r l; do note "STAT $l"; done || true
    note "STAT-XDP-LINES $(grep -ci xdp "$OUT/ethtool-S.txt" || true)"
  fi
  local b=$SYS/class/net/$IFACE/statistics p0 p1 y0 y1 pps mbit
  p0=$(trim_file "$b/rx_packets")
  y0=$(trim_file "$b/rx_bytes")
  sleep "$SAMPLE_SECS"
  p1=$(trim_file "$b/rx_packets")
  y1=$(trim_file "$b/rx_bytes")
  pps=$(rate_per_sec "$p0" "$p1" "$SAMPLE_SECS")
  mbit=$(($(rate_per_sec "$y0" "$y1" "$SAMPLE_SECS") * 8 / 1000000))
  note "RX-RATE-${SAMPLE_SECS}S pps=$pps mbit=$mbit"
  if [ "$pps" -eq 0 ]; then
    note "NOTE-span-quiet"
  else
    note "OK-span-traffic"
  fi
}

probe_irqs() {
  local cores_file=$CORES_FILE cores="" irq name eff n bad=0 total=0 line
  if [ ! -r "$cores_file" ]; then
    stop "no-capture-cores"
    return 0
  fi
  while IFS= read -r line; do
    [[ $line =~ ^[0-9]+$ ]] || {
      stop "capture-cores-form"
      return 0
    }
    cores="${cores:+$cores,}$line"
  done <"$cores_file"
  note "CAPTURE-CORES $cores"
  local -A per_core=()
  while read -r irq name; do
    total=$((total + 1))
    eff=$(trim_file "$PROC/irq/$irq/effective_affinity_list" 2>/dev/null || echo unreadable)
    note "IRQ $irq $name effective=$eff smp=$(trim_file "$PROC/irq/$irq/smp_affinity_list" 2>/dev/null || echo unreadable)"
    if [[ $eff =~ ^[0-9]+$ ]] && cpu_in_list "$eff" "$cores"; then
      per_core[$eff]=$((${per_core[$eff]:-0} + 1))
    else
      bad=$((bad + 1))
    fi
  done < <(queue_irqs_from_interrupts "$IFACE" <"$PROC/interrupts")
  if [ "$total" -eq 0 ]; then
    stop "no-queue-irqs"
    return 0
  fi
  # per_core is empty when every IRQ sits outside the capture cores. Then
  # `printf '%s\n' "${!per_core[@]}"` would emit one blank line, and an empty
  # subscript is a fatal `bad array subscript` under set -e. Guard both.
  if [ "${#per_core[@]}" -gt 0 ]; then
    while read -r n; do
      [[ $n =~ ^[0-9]+$ ]] || continue
      note "IRQ-PER-CORE cpu$n=${per_core[$n]:-0}"
    done < <(printf '%s\n' "${!per_core[@]}" | sort -n)
  else
    note "IRQ-PER-CORE none-inside-capture-cores"
  fi
  if [ "$bad" -ne 0 ]; then
    stop "irq-baseline-outside-capture-cores count=$bad"
  else
    note "OK-irq-pins total=$total"
  fi
  if [ "${QUEUES_CUR:-absent}" != absent ] && [ "$QUEUES_CUR" != "$total" ]; then
    note "NOTE-queue-irq-mismatch combined=$QUEUES_CUR irqs=$total"
  fi
  local ncores
  ncores=$(cpulist_expand "$cores" | wc -l)
  note "ZC-QUEUES queues=$total cores=$ncores"
  note "NOTE-zc-one-xsk-per-queue (AF_XDP binds a socket to one queue id; $total queues on $ncores cores)"
}

probe_kernel_env() {
  local cfg key v bpffs diag=unknown
  cfg=${M1S1_KCONFIG:-/boot/config-$(uname -r)}
  if [ -r "$cfg" ]; then
    diag=$(config_value "$cfg" CONFIG_XDP_SOCKETS_DIAG)
    for key in CONFIG_BPF_SYSCALL CONFIG_BPF_JIT CONFIG_BPF_JIT_ALWAYS_ON CONFIG_XDP_SOCKETS \
      CONFIG_XDP_SOCKETS_DIAG CONFIG_DEBUG_INFO_BTF CONFIG_ICE CONFIG_PACKET CONFIG_PAGE_POOL \
      CONFIG_NET_CLS_BPF CONFIG_HUGETLBFS CONFIG_TRANSPARENT_HUGEPAGE; do
      v=$(config_value "$cfg" "$key")
      note "KCONFIG $key $v"
      case "$key:$v" in
        CONFIG_BPF_SYSCALL:y) ;;
        CONFIG_BPF_SYSCALL:*) stop "kconfig-bpf-syscall $v" ;;
        CONFIG_ICE:y | CONFIG_ICE:m) ;;
        CONFIG_ICE:*) stop "kconfig-ice $v" ;;
        CONFIG_XDP_SOCKETS:y) ;;
        CONFIG_XDP_SOCKETS:*) note "NOTE-no-af-xdp ($key=$v)" ;;
        *) ;;
      esac
    done
  else
    note "NOTE-no-kconfig $cfg"
  fi
  if [ -e "$SYS/kernel/btf/vmlinux" ]; then
    note "BTF-VMLINUX present"
  else
    note "NOTE-no-btf-vmlinux"
  fi
  if bpffs=$(ro findmnt -n -o FSTYPE,OPTIONS /sys/fs/bpf 2>/dev/null); then
    note "BPFFS $bpffs"
  else
    note "NOTE-no-bpffs-mount"
  fi
  for key in kernel.unprivileged_bpf_disabled net.core.bpf_jit_enable net.core.bpf_jit_harden \
    net.core.busy_poll net.core.busy_read; do
    if v=$(ro sysctl -n "$key" 2>/dev/null); then
      note "SYSCTL $key $v"
    else
      note "NOTE-sysctl-unreadable $key"
    fi
  done
  if [ -r "$SYS/kernel/security/lockdown" ]; then
    v=$(bracketed_word <"$SYS/kernel/security/lockdown")
    note "LOCKDOWN $v"
    [ "$v" = integrity ] || note "NOTE-lockdown-not-integrity $v"
  else
    note "NOTE-lockdown-unreadable"
  fi
  note "ULIMIT-L-AJ $(ulimit -l)"
  if v=$(ro systemctl show --property=DefaultLimitMEMLOCK 2>/dev/null); then
    note "SYSTEMD $v"
  fi
  note "HUGEPAGES $(awk '/^HugePages_Total:/ {t=$2} /^HugePages_Free:/ {f=$2} /^Hugepagesize:/ {s=$2" "$3} END {print "total=" t " free=" f " size=" s}' "$PROC/meminfo")"
  note "MEM-AVAILABLE-MB $(awk '/^MemAvailable:/ {printf "%d", $2 / 1024}' "$PROC/meminfo")"
  if [ -r "$SYS/kernel/mm/transparent_hugepage/enabled" ]; then
    note "THP $(bracketed_word <"$SYS/kernel/mm/transparent_hugepage/enabled")"
  fi
  if save ss-xdp.txt ss -f xdp -a; then
    v=$(($(wc -l <"$OUT/ss-xdp.txt") - 1))
    [ "$v" -ge 0 ] || v=0
    if [ "$v" -eq 0 ]; then
      case "$diag" in
        y | m) note "OK-no-xsk-sockets" ;;
        *) note "NOTE-xsk-socket-list-unreliable (CONFIG_XDP_SOCKETS_DIAG=$diag; an empty list is not evidence)" ;;
      esac
    else
      note "NOTE-xsk-sockets-present count=$v"
    fi
  else
    note "NOTE-ss-xdp-unavailable"
  fi
}

probe_toolchain() {
  local c p line cand
  for c in clang llc gcc make pahole bpftool xdp-loader xdpdump xdp-bench; do
    if command -v "$c" >/dev/null 2>&1; then
      note "TOOL $c $(command -v "$c")"
    else
      note "TOOL-ABSENT $c"
    fi
  done
  if save bpftool-version.txt bpftool version; then
    note "BPFTOOL $(head -n 1 "$OUT/bpftool-version.txt")"
  fi
  for p in libbpf1 libbpf-dev libxdp1 libxdp-dev xdp-tools clang llvm gcc make libelf-dev; do
    if line=$(ro dpkg-query -W -f="${DPKG_FMT}" "$p" 2>/dev/null); then
      note "PKG $line"
    else
      note "PKG-ABSENT $p"
    fi
    if ro apt-cache policy "$p" >"$OUT/apt-policy-$p.txt" 2>&1; then
      cand=$(awk '/Candidate:/ {print $2; exit}' "$OUT/apt-policy-$p.txt")
      note "APT-CANDIDATE $p ${cand:-none-listed}"
    else
      note "NOTE-apt-policy-failed $p"
    fi
  done
  note "NOTE-apt-lists-not-refreshed (candidates come from cached lists; this probe does not refresh them)"
}

probe_services() {
  local u en ac sur_en="" sur_ac=""
  for u in suricata johnny-capture-irq.service johnny-capture-tuning.service irqbalance; do
    en=$(ro systemctl is-enabled "$u" 2>/dev/null || true)
    ac=$(ro systemctl is-active "$u" 2>/dev/null || true)
    note "UNIT $u enabled=${en:-unknown} active=${ac:-unknown}"
    if [ "$u" = suricata ]; then
      sur_en=$en
      sur_ac=$ac
    fi
  done
  case "$sur_en" in
    enabled | enabled-runtime) stop "suricata-enabled" ;;
    *) ;;
  esac
  [ "$sur_ac" != active ] || stop "suricata-active"
}

main_user() {
  local host kern
  if [ "$(id -u)" -eq 0 ]; then
    echo STOP-root
    exit 1
  fi
  host=$(hostname --short)
  if [ "$host" != johnny ]; then
    echo "STOP-host $host"
    exit 1
  fi
  if [ "$(id -un)" != aj ]; then
    echo "STOP-user $(id -un)"
    exit 1
  fi
  umask 022
  mkdir -p "$(dirname "$OUT_USER")"
  open_out "$OUT_USER"

  kern=$(uname -r)
  note "HOST $host"
  note "KERNEL $kern"
  note "DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  note "EUID $(id -u)"
  [ "$kern" = "$EXPECT_KERNEL" ] || note "NOTE-kernel-changed expected=$EXPECT_KERNEL"
  note "MODE user (read-only; unprivileged, no NIC change)"

  probe_link
  probe_driver
  probe_ddp
  probe_offloads
  probe_queues
  probe_stats
  probe_irqs
  probe_kernel_env
  probe_toolchain
  probe_services

  if [ "$STOPS" -ne 0 ]; then
    note "M1S1-PROBE-STOPS $STOPS"
    exit 1
  fi
  note "M1S1-PROBE-DONE"
}

# ---------------------------------------------------------------- root mode

main_root() {
  local host rc=0 v modes
  if [ "$(id -u)" -ne 0 ]; then
    echo STOP-not-root
    exit 1
  fi
  host=$(hostname --short)
  if [ "$host" != johnny ]; then
    echo "STOP-host $host"
    exit 1
  fi
  umask 077
  open_out "$OUT_ROOT"
  note "HOST $host"
  note "KERNEL $(uname -r)"
  note "DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  note "MODE root (bpftool read-only; no attach, no load, no pin)"

  if save bpftool-version.txt bpftool version; then
    note "BPFTOOL $(head -n 1 "$OUT/bpftool-version.txt")"
  fi

  if save feature-probe.json bpftool -j feature probe kernel; then
    local k
    for k in have_xdp_prog_type have_xskmap_map_type have_array_map_type have_percpu_array_map_type \
      have_hash_map_type have_lru_hash_map_type have_percpu_hash_map_type have_lru_percpu_hash_map_type \
      have_ringbuf_map_type have_devmap_map_type have_cpumap_map_type; do
      v=$(bpf_feature_bool "$k" <"$OUT/feature-probe.json" 2>/dev/null) || v=parse-failed
      note "BPF-FEATURE $k $v"
      case "$k:$v" in
        have_xdp_prog_type:yes) ;;
        have_xdp_prog_type:*) stop "no-xdp-prog-type $v" ;;
        *:yes) ;;
        *:absent) note "NOTE-feature-key-absent $k ([Assumption] key name from memory of bpftool JSON, not a live capture)" ;;
        *:parse-failed) stop "feature-json-parse" ;;
        *) note "NOTE-feature-missing $k" ;;
      esac
    done
    for k in bpf_redirect_map bpf_xdp_adjust_head bpf_xdp_adjust_meta bpf_ktime_get_ns \
      bpf_ringbuf_output bpf_perf_event_output bpf_xdp_load_bytes bpf_map_lookup_elem; do
      v=$(bpf_xdp_helper "$k" <"$OUT/feature-probe.json" 2>/dev/null) || v=parse-failed
      note "BPF-XDP-HELPER $k $v"
      case "$v" in
        yes) ;;
        absent) note "NOTE-helper-lists-absent $k" ;;
        parse-failed) stop "helper-json-parse" ;;
        *) note "NOTE-helper-missing $k" ;;
      esac
    done
  else
    rc=1
    stop "feature-probe-failed"
  fi

  if save net-show.json bpftool -j net show; then
    modes=$(xdp_modes_from_net_json "$IFACE" <"$OUT/net-show.json" 2>/dev/null) || modes=parse-failed
    if [ "$modes" = parse-failed ]; then
      stop "net-json-parse"
    elif [ -n "$modes" ]; then
      stop "xdp-attached-on-$IFACE modes=$modes"
    else
      note "OK-no-xdp-on-$IFACE"
    fi
  else
    rc=1
    stop "net-show-failed"
  fi

  if save prog-show.json bpftool -j prog show; then
    v=$(prog_count_by_type xdp <"$OUT/prog-show.json" 2>/dev/null) || v=parse-failed
    note "PROG-XDP-COUNT $v"
    if [ "$v" != 0 ] && [ "$v" != parse-failed ]; then
      note "NOTE-xdp-progs-loaded $v (not necessarily on $IFACE; net show is the attach check)"
    fi
  else
    rc=1
    note "NOTE-prog-show-failed"
  fi

  [ "$rc" -eq 0 ] || note "NOTE-some-bpftool-commands-failed"
  if [ "$STOPS" -ne 0 ]; then
    note "M1S1-PROBE-ROOT-STOPS $STOPS"
    exit 1
  fi
  note "M1S1-PROBE-ROOT-DONE"
}

# ---------------------------------------------------------------- entry

main() {
  case "${1:-}" in
    user) main_user ;;
    root) main_root ;;
    *)
      echo "usage: module1-slice1-probe.sh user|root" >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
