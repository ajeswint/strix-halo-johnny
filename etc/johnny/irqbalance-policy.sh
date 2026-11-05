#!/bin/bash
# Johnny step 13. irqbalance policyscript. Not applied by this commit.
# irqbalance 1.9.4 runs: exec <this-script> <pci-device-sysfs> <irq>
# (classify.c run_script_for_policy). Ban MSI IRQs whose PCI device is
# eno1np0 or eno2np1. Print nothing for every other IRQ. Exit 0.
# A nonzero exit makes irqbalance drop the policy for that IRQ.
# This file does not set smp_affinity. It does not mention eno3.

policy_bans() {
  local devpath=$1
  local sysroot=${2:-/sys}
  local nic target got
  [ -n "$devpath" ] || return 1
  got=$(readlink -f -- "$devpath" 2>/dev/null || true)
  [ -n "$got" ] || return 1
  for nic in eno1np0 eno2np1; do
    target="${sysroot}/class/net/${nic}/device"
    [ -e "$target" ] || continue
    if [ "$got" = "$(readlink -f -- "$target")" ]; then
      return 0
    fi
  done
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if policy_bans "${1:-}"; then
    printf 'ban=true\n'
  fi
  exit 0
fi
