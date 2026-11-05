#!/bin/bash
# Rollback for Johnny step 13. The apply script installs this at
# /root/step13-revert.sh before it changes IRQ affinity or irqbalance.
#   sudo bash /root/step13-revert.sh
# Restores eno1np0 smp_affinity_list from the first-run save, puts
# /etc/default/irqbalance back, and removes the step 13 unit and helpers.
# Does not change netplan, promisc, capture-cores, or the tuning service.
# Does not reboot. Safe to run twice.
set -u
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
umask 022

BEFORE=/var/lib/johnny/irq-affinity-before.tsv
IRQ_BAK=/var/lib/johnny/irqbalance.default.pre-step13
WAS=/var/lib/johnny/step13-irqbalance-was-active
DEFAULT=/etc/default/irqbalance
POLICY=/etc/johnny/irqbalance-policy.sh
HELPER=/etc/johnny/irq-affinity.sh
UNIT=/etc/systemd/system/johnny-capture-irq.service

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

rc=0

restore_affinities() {
  local irq list failed=0
  if [ ! -f "$BEFORE" ]; then
    echo NOTE-no-affinity-backup
    return 0
  fi
  if [ -L "$BEFORE" ]; then
    echo STOP-affinity-backup-symlink
    return 1
  fi
  while IFS=$'\t' read -r irq list || [ -n "${irq:-}" ]; do
    [ -n "${irq:-}" ] || continue
    if [[ ! $irq =~ ^[0-9]+$ ]]; then
      echo "NOTE-affinity-skip $irq"
      continue
    fi
    if [ ! -e "/proc/irq/${irq}/smp_affinity_list" ]; then
      echo "NOTE-irq-gone $irq"
      continue
    fi
    if [ ! -w "/proc/irq/${irq}/smp_affinity_list" ]; then
      echo "NOTE-irq-restore-ro $irq"
      failed=1
      continue
    fi
    if ! printf '%s\n' "$list" > "/proc/irq/${irq}/smp_affinity_list"; then
      echo "NOTE-irq-restore-failed $irq"
      failed=1
    fi
  done < "$BEFORE"
  echo AFFINITY-RESTORED
  return "$failed"
}

restore_irqbalance() {
  local was=missing
  if [ -f "$WAS" ] && [ ! -L "$WAS" ]; then
    was=$(tr -d '[:space:]' < "$WAS" || true)
  fi
  if [ -f "$IRQ_BAK" ] && [ ! -L "$IRQ_BAK" ]; then
    if [ -L "$DEFAULT" ]; then
      echo STOP-irqbalance-symlink
      return 1
    fi
    cp -a "$IRQ_BAK" "$DEFAULT"
    echo IRQBALANCE-RESTORED
  else
    echo NOTE-no-irqbalance-backup
  fi
  rm -f "$POLICY"
  echo POLICY-REMOVED
  if [ "$was" = active ]; then
    if systemctl restart irqbalance.service; then
      echo IRQBALANCE-RESTARTED
      echo NOTE-irqbalance-will-balance
    else
      echo STOP-irqbalance-restart
      return 1
    fi
  elif [ "$was" = inactive ]; then
    echo IRQBALANCE-LEFT-INACTIVE
  else
    echo NOTE-irqbalance-was-missing
  fi
  return 0
}

remove_unit() {
  if [ -f "$UNIT" ] || [ -L "$UNIT" ]; then
    systemctl disable --now johnny-capture-irq.service >/dev/null 2>&1 || true
  fi
  rm -f "$UNIT" "$HELPER"
  systemctl daemon-reload || true
  echo UNIT-REMOVED
}

restore_affinities || rc=1
restore_irqbalance || rc=1
remove_unit || rc=1
if [ "$rc" -ne 0 ]; then
  echo STOP-revert-incomplete
  exit 1
fi
echo REVERTED
