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

# Shallow C1: intel_idle "C1" or ACPI "C1_ACPI". POLL stays too.
# C1E, C2_ACPI, C3_ACPI, and anything else are deep.
is_shallow_c1() {
  case "$1" in
    C1|C1_ACPI) return 0 ;;
    *) return 1 ;;
  esac
}

is_keep_idle() {
  case "$1" in
    POLL) return 0 ;;
    *) is_shallow_c1 "$1" ;;
  esac
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
      if is_keep_idle "$name"; then
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
    if is_keep_idle "$name"; then
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
