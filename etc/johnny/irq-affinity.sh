#!/bin/bash
# Johnny step 13. Pin eno1np0 ice MSI-X IRQs onto /etc/johnny/capture-cores.
# The step 13 paste installs this. Boot re-applies it via
# johnny-capture-irq.service. Not applied by the commit that adds it.
# Does not change eno2np1 affinity, eno3, RSS, RPS, XPS, queues, or netplan.
# Docs: docs/tool-install/step-13-irq-affinity.md

CORES=/etc/johnny/capture-cores
CORES_SHA256=16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b
KERNEL_WANT=7.0.0-42-generic

expand_affinity() {
  local spec=$1 part start end i
  spec=${spec//,/ }
  for part in $spec; do
    if [[ $part == *-* ]]; then
      start=${part%-*}
      end=${part#*-}
      if [[ ! $start =~ ^[0-9]+$ || ! $end =~ ^[0-9]+$ ]]; then
        echo STOP-cpulist
        return 1
      fi
      if [ "$end" -lt "$start" ]; then
        echo STOP-cpulist
        return 1
      fi
      for ((i = start; i <= end; i++)); do
        printf '%s\n' "$i"
      done
    else
      if [[ ! $part =~ ^[0-9]+$ ]]; then
        echo STOP-cpulist
        return 1
      fi
      printf '%s\n' "$part"
    fi
  done
}

affinity_is_cpu() {
  local list=$1 cpu=$2 c count=0
  while read -r c; do
    [ -n "$c" ] || continue
    if [ "$c" = STOP-cpulist ]; then
      return 1
    fi
    if [ "$c" != "$cpu" ]; then
      return 1
    fi
    count=$((count + 1))
  done < <(expand_affinity "$list")
  [ "$count" -eq 1 ]
}

read_capture_cpus() {
  local file=$1 line
  local -a seen=()
  if [ -L "$file" ] || [ ! -f "$file" ]; then
    echo STOP-cores-file
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line//$'\r'/}
    [ -n "$line" ] || continue
    if [[ ! $line =~ ^[0-9]+$ ]]; then
      echo STOP-cores-token
      return 1
    fi
    if [ "$line" = 0 ]; then
      echo STOP-cpu0-in-set
      return 1
    fi
    if [ -n "${seen[$line]:-}" ]; then
      echo STOP-cores-dup
      return 1
    fi
    seen[$line]=1
    printf '%s\n' "$line"
  done < "$file"
}

assign_cpu() {
  local name=$1
  shift
  local -a cpus=("$@")
  local n=${#cpus[@]} idx
  if [ "$n" -lt 1 ]; then
    echo STOP-no-cpus
    return 1
  fi
  if [[ $name =~ ^eno1np0-(TxRx|rx|tx)-([0-9]+)$ ]]; then
    idx=${BASH_REMATCH[2]}
    printf '%s\n' "${cpus[$((10#$idx % n))]}"
    return 0
  fi
  printf '%s\n' "${cpus[0]}"
}

irq_name_from_file() {
  local irq=$1 file=$2
  awk -v n="$irq" '
    $1 == n":" { print $NF; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$file"
}

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
  [ $((f & 1)) -ne 0 ] && [ $((f & 256)) -ne 0 ] && [ $((f & 128)) -ne 0 ]
}

eno1_link_ok() {
  local speed=$1 flags=$2 carrier=$3 oper=$4
  flags_admin_up "$flags" || return 1
  [ "$speed" = 10000 ] || return 1
  [ "$carrier" = 1 ] || [ "$oper" = up ]
}

read_trim() {
  tr -d '[:space:]' < "$1" || true
}

cpu_online() {
  local cpu=$1 online
  online="/sys/devices/system/cpu/cpu${cpu}/online"
  if [ ! -e "$online" ]; then
    echo "STOP-cpu-online $cpu"
    return 1
  fi
  [ "$(read_trim "$online")" = 1 ]
}

foreign_irq_name() {
  local name=$1
  [[ $name =~ (^|[^A-Za-z0-9])eno2np1([^A-Za-z0-9]|$) ]] && return 0
  [[ $name =~ (^|[^A-Za-z0-9])eno3([^A-Za-z0-9]|$) ]] && return 0
  [[ $name =~ (^|[^A-Za-z0-9])eno4([^A-Za-z0-9]|$) ]] && return 0
  return 1
}

list_msi() {
  local nic=$1 d base
  base="/sys/class/net/${nic}/device/msi_irqs"
  if [ ! -d "$base" ]; then
    echo "STOP-no-msi $nic"
    return 1
  fi
  local n=0
  for d in "$base"/*; do
    [ -e "$d" ] || continue
    base=$(basename "$d")
    if [[ ! $base =~ ^[0-9]+$ ]]; then
      echo "STOP-msi-name $nic $base"
      return 1
    fi
    printf '%s\n' "$base"
    n=$((n + 1))
  done
  if [ "$n" -lt 1 ]; then
    echo "STOP-no-msi $nic"
    return 1
  fi
  if [ "$n" -gt 4096 ]; then
    echo "STOP-msi-count $nic $n"
    return 1
  fi
}

# Load CAPTURE_CPUS. Echoes STOP-* and returns 1 on failure.
load_capture_cpus() {
  local line sha
  CAPTURE_CPUS=()
  if [ -L "$CORES" ] || [ ! -f "$CORES" ]; then
    echo STOP-cores-file
    return 1
  fi
  sha=$(sha256sum "$CORES" | awk '{print $1}' || true)
  if [ "$sha" != "$CORES_SHA256" ]; then
    echo "STOP-cores-hash $sha"
    return 1
  fi
  while read -r line; do
    if [[ $line == STOP-* ]]; then
      printf '%s\n' "$line"
      return 1
    fi
    CAPTURE_CPUS+=("$line")
  done < <(read_capture_cpus "$CORES")
  if [ "${#CAPTURE_CPUS[@]}" -lt 1 ]; then
    echo STOP-cores-empty
    return 1
  fi
  return 0
}

preflight() {
  local host kern nic driver flags speed carrier oper bdf1 bdf2
  local link xdp
  host=$(hostname -s 2>/dev/null || hostname)
  if [ "$host" != johnny ]; then
    echo STOP-host
    return 1
  fi
  kern=$(uname -r)
  if [ "$kern" != "$KERNEL_WANT" ]; then
    echo "STOP-kernel $kern"
    return 1
  fi
  if [ "$(id -u)" -ne 0 ]; then
    echo STOP-not-root
    return 1
  fi
  for nic in eno1np0 eno2np1 eno3; do
    if [ ! -d "/sys/class/net/$nic" ]; then
      echo "STOP-no-nic $nic"
      return 1
    fi
    if [ -L "/sys/class/net/$nic" ]; then
      :
    fi
  done
  if ! load_capture_cpus; then
    return 1
  fi
  local cpu
  for cpu in "${CAPTURE_CPUS[@]}"; do
    if ! cpu_online "$cpu"; then
      echo "STOP-cpu-offline $cpu"
      return 1
    fi
  done
  if ! command -v ethtool >/dev/null 2>&1; then
    echo STOP-missing-ethtool
    return 1
  fi
  for nic in eno1np0 eno2np1; do
    driver=$(ethtool -i "$nic" 2>/dev/null | awk -F': ' '$1=="driver"{print $2}' || true)
    if [ "$driver" != ice ]; then
      echo "STOP-driver $nic ${driver:-missing}"
      return 1
    fi
  done
  bdf1=$(basename "$(readlink -f /sys/class/net/eno1np0/device)")
  bdf2=$(basename "$(readlink -f /sys/class/net/eno2np1/device)")
  if [ -z "$bdf1" ] || [ -z "$bdf2" ]; then
    echo STOP-pci
    return 1
  fi
  if [ "$bdf1" = "$bdf2" ]; then
    echo STOP-eno2-same-pci
    return 1
  fi
  echo "PCI eno1np0 $bdf1 eno2np1 $bdf2"
  flags=$(read_trim /sys/class/net/eno1np0/flags)
  speed=$(read_trim /sys/class/net/eno1np0/speed)
  carrier=$(read_trim /sys/class/net/eno1np0/carrier || true)
  oper=$(read_trim /sys/class/net/eno1np0/operstate || true)
  if ! eno1_link_ok "$speed" "$flags" "$carrier" "$oper"; then
    echo "STOP-eno1-link speed=$speed flags=$flags carrier=$carrier oper=$oper"
    return 1
  fi
  if ! flags_capture_ok "$flags"; then
    echo "STOP-eno1-flags $flags"
    return 1
  fi
  if [ -n "$(ip -4 -o addr show dev eno1np0)" ] || [ -n "$(ip -6 -o addr show dev eno1np0)" ]; then
    echo STOP-eno1-addr
    return 1
  fi
  flags=$(read_trim /sys/class/net/eno2np1/flags)
  if ! flags_well_formed "$flags"; then
    echo STOP-flags
    return 1
  fi
  if flags_admin_up "$flags"; then
    echo STOP-eno2-up
    return 1
  fi
  if [ -n "$(ip -4 -o addr show dev eno2np1)" ] || [ -n "$(ip -6 -o addr show dev eno2np1)" ]; then
    echo STOP-eno2-addr
    return 1
  fi
  if ! ip -4 -o addr show dev eno3 | grep -q 'inet 192\.168\.50\.152/'; then
    echo STOP-eno3-addr
    return 1
  fi
  if ! ip -4 route show default | grep -q 'dev eno3'; then
    echo STOP-eno3-route
    return 1
  fi
  flags=$(read_trim /sys/class/net/eno3/flags)
  if ! flags_admin_up "$flags"; then
    echo STOP-eno3-down
    return 1
  fi
  link=$(ip -d link show dev eno1np0 2>/dev/null || true)
  if printf '%s\n' "$link" | grep -Eq 'prog/xdp|(^|[[:space:]])xdp(drv|generic)?([[:space:]]|$)'; then
    echo STOP-xdp-present
    return 1
  fi
  if [ ! -d /sys/class/net/eno1np0/queues/rx-0 ]; then
    echo STOP-no-rx-queue
    return 1
  fi
  if [ "$(systemctl is-active johnny-capture-tuning.service 2>/dev/null || true)" != active ]; then
    echo STOP-tuning
    return 1
  fi
  if [ "$(systemctl is-enabled johnny-capture-tuning.service 2>/dev/null || true)" != enabled ]; then
    echo STOP-tuning
    return 1
  fi
  local epp
  for cpu in "${CAPTURE_CPUS[@]}"; do
    epp=$(read_trim "/sys/devices/system/cpu/cpu${cpu}/cpufreq/energy_performance_preference")
    if [ "$epp" != performance ]; then
      echo "STOP-tuning-epp $cpu ${epp:-missing}"
      return 1
    fi
  done
  echo "CAPTURE-CPUS ${CAPTURE_CPUS[*]}"
  echo OK-tuning
  return 0
}

eno3_ok() {
  local flags
  if ! ip -4 -o addr show dev eno3 | grep -q 'inet 192\.168\.50\.152/'; then
    echo STOP-eno3-addr
    return 1
  fi
  if ! ip -4 route show default | grep -q 'dev eno3'; then
    echo STOP-eno3-route
    return 1
  fi
  flags=$(read_trim /sys/class/net/eno3/flags)
  if ! flags_admin_up "$flags"; then
    echo STOP-eno3-down
    return 1
  fi
  return 0
}

queue_mask() {
  local path=$1
  if [ ! -r "$path" ]; then
    echo missing
    return 0
  fi
  read_trim "$path"
}

snapshot_queues() {
  local tag=$1 nrx ntx
  nrx=$(find /sys/class/net/eno1np0/queues -maxdepth 1 -type d -name 'rx-*' | wc -l)
  ntx=$(find /sys/class/net/eno1np0/queues -maxdepth 1 -type d -name 'tx-*' | wc -l)
  printf '%s RX-QUEUES %s\n' "$tag" "$nrx"
  printf '%s TX-QUEUES %s\n' "$tag" "$ntx"
  printf '%s RPS-RX0 %s\n' "$tag" "$(queue_mask /sys/class/net/eno1np0/queues/rx-0/rps_cpus)"
  printf '%s XPS-TX0 %s\n' "$tag" "$(queue_mask /sys/class/net/eno1np0/queues/tx-0/xps_cpus)"
}

queues_unchanged() {
  local before=$1 after=$2
  if [ "$before" != "$after" ]; then
    echo STOP-queues-changed
    printf 'QUEUES-BEFORE %s\n' "$before"
    printf 'QUEUES-AFTER %s\n' "$after"
    return 1
  fi
  return 0
}

collect_eno1_map() {
  local irq name
  ENO1_IRQS=()
  ENO1_NAMES=()
  ENO1_CPUS=()
  while read -r irq; do
    if [[ $irq == STOP-* ]]; then
      printf '%s\n' "$irq"
      return 1
    fi
    if [ ! -e "/proc/irq/${irq}/smp_affinity_list" ]; then
      echo "STOP-eno1-unrequested $irq"
      return 1
    fi
    if ! name=$(irq_name_from_file "$irq" /proc/interrupts); then
      echo "STOP-irq-name $irq"
      return 1
    fi
    if [[ ! $name =~ ^eno1np0-(TxRx|rx|tx)-[0-9]+$ ]]; then
      echo "NOTE-irq-fallback $irq $name"
    fi
    if foreign_irq_name "$name"; then
      echo "STOP-irq-foreign $irq $name"
      return 1
    fi
    if [[ $name == *eno1np0* ]] || [[ $name == ice-* ]]; then
      :
    else
      echo "NOTE-irq-name $irq $name"
    fi
    ENO1_IRQS+=("$irq")
    ENO1_NAMES+=("$name")
  done < <(list_msi eno1np0 | sort -n)
  local i cpu
  for i in "${!ENO1_IRQS[@]}"; do
    if ! cpu=$(assign_cpu "${ENO1_NAMES[$i]}" "${CAPTURE_CPUS[@]}"); then
      printf '%s\n' "$cpu"
      return 1
    fi
    if [ "$cpu" = 0 ]; then
      echo STOP-cpu0-assigned
      return 1
    fi
    ENO1_CPUS+=("$cpu")
  done
  if [ "${#ENO1_IRQS[@]}" -lt 1 ]; then
    echo STOP-no-msi eno1np0
    return 1
  fi
  return 0
}

outside_msi_names() {
  local irq name
  while read -r irq name; do
    [ -n "$irq" ] || continue
    local known=0 i
    for i in "${!ENO1_IRQS[@]}"; do
      if [ "${ENO1_IRQS[$i]}" = "$irq" ]; then
        known=1
        break
      fi
    done
    if [ "$known" -eq 0 ]; then
      echo "STOP-irq-outside-msi $irq $name"
      return 1
    fi
  done < <(awk '
    $1 ~ /^[0-9]+:$/ && $0 ~ /eno1np0/ {
      irq = $1
      sub(/:$/, "", irq)
      print irq, $NF
    }
  ' /proc/interrupts)
  return 0
}

write_affinity() {
  local irq=$1 cpu=$2
  local path="/proc/irq/${irq}/smp_affinity_list"
  if [ ! -w "$path" ]; then
    echo "STOP-affinity-ro $irq"
    return 1
  fi
  printf '%s\n' "$cpu" > "$path" || {
    echo "STOP-affinity-write $irq"
    return 1
  }
}

read_affinity() {
  read_trim "/proc/irq/$1/smp_affinity_list"
}

read_effective() {
  local path="/proc/irq/$1/effective_affinity_list"
  if [ ! -e "$path" ]; then
    echo missing
    return 0
  fi
  read_trim "$path"
}

verify_one() {
  local irq=$1 cpu=$2 name=$3
  local got eff
  got=$(read_affinity "$irq")
  if ! affinity_is_cpu "$got" "$cpu"; then
    echo "STOP-affinity $irq $name want $cpu got $got"
    return 1
  fi
  eff=$(read_effective "$irq")
  if [ "$eff" = missing ]; then
    echo "NOTE-no-effective $irq"
  elif [ -z "$eff" ]; then
    echo "NOTE-effective-empty $irq"
  elif ! affinity_is_cpu "$eff" "$cpu"; then
    echo "STOP-effective $irq $name want $cpu got $eff"
    return 1
  fi
  if affinity_is_cpu "$got" 0; then
    echo "STOP-cpu0 $irq"
    return 1
  fi
  printf 'IRQ %s %s cpu %s\n' "$irq" "$name" "$cpu"
  return 0
}

restore_snapshot() {
  local file=$1 irq list
  local rc=0
  while IFS=$'\t' read -r irq list; do
    [ -n "$irq" ] || continue
    if [ ! -w "/proc/irq/${irq}/smp_affinity_list" ]; then
      echo "NOTE-irq-restore-ro $irq"
      rc=1
      continue
    fi
    if ! printf '%s\n' "$list" > "/proc/irq/${irq}/smp_affinity_list"; then
      echo "NOTE-irq-restore-failed $irq"
      rc=1
    fi
  done < "$file"
  return "$rc"
}

# Snap lines are irq|mask|name. The separator is not IFS whitespace, so an
# empty mask stays an empty field. Tab would collapse "irq\t\tname".
split_snap() {
  local line=$1
  local irq list name
  IFS='|' read -r irq list name <<<"$line"
  printf '%s\n' "$irq" "$list" "$name"
}

snapshot_eno2() {
  local irq name list n=0
  : > "$1"
  while read -r irq; do
    if [[ $irq == STOP-* ]]; then
      printf '%s\n' "$irq"
      return 1
    fi
    if [ ! -e "/proc/irq/${irq}/smp_affinity_list" ]; then
      echo "NOTE-eno2-unrequested $irq"
      continue
    fi
    if ! name=$(irq_name_from_file "$irq" /proc/interrupts); then
      name=NONAME
    fi
    list=$(read_affinity "$irq")
    if [ -z "$list" ]; then
      echo "NOTE-eno2-unrequested $irq"
      continue
    fi
    printf '%s|%s|%s\n' "$irq" "$list" "$name" >> "$1"
    n=$((n + 1))
  done < <(list_msi eno2np1 | sort -n)
  if [ "$n" -eq 0 ]; then
    echo NOTE-eno2-no-proc
  fi
  return 0
}

eno2_unchanged() {
  local file=$1 irq list name now
  if [ ! -s "$file" ]; then
    echo NOTE-eno2-no-proc
    echo ENO2-IRQ-UNCHANGED
    return 0
  fi
  while IFS='|' read -r irq list name || [ -n "${irq:-}" ]; do
    [ -n "${irq:-}" ] || continue
    if [ ! -e "/proc/irq/${irq}/smp_affinity_list" ]; then
      echo "STOP-eno2-irq-gone $irq"
      return 1
    fi
    now=$(read_affinity "$irq")
    if [ "$now" != "$list" ]; then
      echo "STOP-eno2-irq-moved $irq ${name:-NONAME} $list $now"
      return 1
    fi
  done < "$file"
  echo ENO2-IRQ-UNCHANGED
}

prepare_map() {
  collect_eno1_map || return 1
  outside_msi_names || return 1
}

map_needs_write() {
  local i
  for i in "${!ENO1_IRQS[@]}"; do
    if ! affinity_is_cpu "$(read_affinity "${ENO1_IRQS[$i]}")" "${ENO1_CPUS[$i]}"; then
      return 0
    fi
  done
  return 1
}

pin_apply() {
  local i irq cpu snap qbefore qafter
  local tmp
  if ! collect_eno1_map; then
    return 1
  fi
  if ! outside_msi_names; then
    return 1
  fi
  for i in "${!ENO1_IRQS[@]}"; do
    irq=${ENO1_IRQS[$i]}
    if [ ! -w "/proc/irq/${irq}/smp_affinity_list" ]; then
      echo "STOP-affinity-ro $irq"
      return 1
    fi
  done
  tmp=$(mktemp /var/lib/johnny/step13-pin.XXXXXX)
  for i in "${!ENO1_IRQS[@]}"; do
    irq=${ENO1_IRQS[$i]}
    printf '%s\t%s\n' "$irq" "$(read_affinity "$irq")" >> "$tmp"
  done
  qbefore=$(snapshot_queues QUEUES)
  for i in "${!ENO1_IRQS[@]}"; do
    irq=${ENO1_IRQS[$i]}
    cpu=${ENO1_CPUS[$i]}
    if ! affinity_is_cpu "$(read_affinity "$irq")" "$cpu"; then
      if ! write_affinity "$irq" "$cpu"; then
        restore_snapshot "$tmp" || echo STOP-pin-rollback
        rm -f "$tmp"
        return 1
      fi
    fi
  done
  local ok=0
  for i in "${!ENO1_IRQS[@]}"; do
    if ! verify_one "${ENO1_IRQS[$i]}" "${ENO1_CPUS[$i]}" "${ENO1_NAMES[$i]}"; then
      ok=1
    fi
  done
  qafter=$(snapshot_queues QUEUES)
  if ! queues_unchanged "$qbefore" "$qafter"; then
    ok=1
  fi
  if ! eno3_ok; then
    ok=1
  fi
  if [ "$ok" -ne 0 ]; then
    restore_snapshot "$tmp" || echo STOP-pin-rollback
    rm -f "$tmp"
    echo STOP-pin
    return 1
  fi
  rm -f "$tmp"
  echo CPU0-CLEAR
  printf '%s\n' "$qafter"
  return 0
}

main() {
  umask 022
  export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
  trap '' HUP PIPE
  if [ "${1:-}" != apply ]; then
    echo STOP-args
    exit 1
  fi
  if [ "${JOHNNY_STEP13_LOCKED:-}" != 1 ]; then
    mkdir -p /run
    exec 8>/run/johnny-capture-irq.lock
    if ! flock -n 8; then
      echo STOP-locked
      exit 1
    fi
  fi
  mkdir -p /var/lib/johnny
  if ! preflight; then
    exit 1
  fi
  local eno2snap
  eno2snap=$(mktemp /var/lib/johnny/step13-eno2.XXXXXX)
  if ! snapshot_eno2 "$eno2snap"; then
    rm -f "$eno2snap"
    exit 1
  fi
  if ! pin_apply; then
    rm -f "$eno2snap"
    exit 1
  fi
  if ! eno2_unchanged "$eno2snap"; then
    rm -f "$eno2snap"
    exit 1
  fi
  rm -f "$eno2snap"
  if ! eno3_ok; then
    exit 1
  fi
  echo ENO3-OK
  echo PIN-OK
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
