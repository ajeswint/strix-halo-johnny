#!/bin/bash
# Johnny step 13d: second boot-race fix. Installs the helper that waits (one
# shared 100s loop) for eno1np0 link+capture flags AND eno3 addr/route/admin-up
# before the hard STOP checks, plus the unit (comment only; TimeoutStartSec=150
# unchanged: 100s wait + 50s slack). Then restarts the oneshot once. Tuning is
# NOTE-only, no After=tuning. Hash-gated: live must be the 13c files.
# No reboot, no netplan, no irqbalance change, tuning unit untouched.
# AJ runs it on Johnny, as root, after both files are in /home/aj/cis-audit/.
# Docs: docs/tool-install/step-13-irq-affinity.md (section "Boot race").
# Success ends with STEP13B-ENO3-WAIT-FIXED. This file has not run.

SRC=/home/aj/cis-audit/johnny-capture-irq-eno3.service
LIVE=/etc/systemd/system/johnny-capture-irq.service
HELPER=/etc/johnny/irq-affinity.sh
SRC_HELPER=/home/aj/cis-audit/irq-affinity-eno3.sh
PREV=/var/lib/johnny/step13d-prev
UNIT_OLD_SHA256=0220ecdff1cd603726b692fbd41a19c580d98640fd70cd68efcf530afa0e04ea
UNIT_NEW_SHA256=6084be53011599d64d7240e4547b53f8dbaa2e2c588d3975f0517a18e6453ed2
HELPER_OLD_SHA256=7c475e4a29d711ea5e104a115f0df3d01730fbf3a452eb68cdc3f8a2953fe388
HELPER_NEW_SHA256=807f5a5599bc3e6478a6172b3a54eb576c08f0c4609047a69b834ffec8af3804

sha_of() {
  sha256sum "$1" | awk '{print $1}'
}

# Names, not IRQ numbers: numbers can change across boots.
# Prints "<irq> <affinity list>" for each /proc/interrupts line whose last field matches $1 (ERE).
irqs_named() {
  awk -v re="$1" '{n=$NF} n ~ re {sub(":","",$1); print $1}' /proc/interrupts | while read -r i; do
    printf '%s %s\n' "$i" "$(tr -d '[:space:]' < "/proc/irq/$i/smp_affinity_list")"
  done
}

main() {
  if [ "$(hostname -s)" != johnny ]; then
    echo STOP-host
    exit 1
  fi
  if [ "$(id -u)" -ne 0 ]; then
    echo STOP-not-root
    exit 1
  fi
  umask 022
  export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
  trap '' HUP PIPE
  mkdir -p /var/lib/johnny /root
  LOG=/root/step13d-$(date -u +%Y%m%dT%H%M%SZ).log
  if [ -e "$LOG" ]; then
    echo "STOP-log-exists $LOG"
    exit 1
  fi
  exec > >(tee "$LOG") 2>&1
  echo "LOG $LOG"
  set -euo pipefail

  # Checkpoint 1: inputs.
  if [ ! -f "$SRC" ] || [ -L "$SRC" ] || [ "$(sha_of "$SRC")" != "$UNIT_NEW_SHA256" ]; then
    echo "STOP-hash $SRC"
    exit 1
  fi
  if [ ! -f "$SRC_HELPER" ] || [ -L "$SRC_HELPER" ] || [ "$(sha_of "$SRC_HELPER")" != "$HELPER_NEW_SHA256" ]; then
    echo "STOP-hash $SRC_HELPER"
    exit 1
  fi
  if [ ! -f "$HELPER" ] || [ -L "$HELPER" ]; then
    echo "STOP-helper-missing $HELPER"
    exit 1
  fi
  hhave=$(sha_of "$HELPER")
  if [ "$hhave" != "$HELPER_OLD_SHA256" ] && [ "$hhave" != "$HELPER_NEW_SHA256" ]; then
    echo "STOP-helper-hash $hhave"
    exit 1
  fi
  if [ ! -f "$LIVE" ] || [ -L "$LIVE" ]; then
    echo "STOP-live-unit-missing $LIVE"
    exit 1
  fi
  have=$(sha_of "$LIVE")
  if [ "$have" != "$UNIT_OLD_SHA256" ] && [ "$have" != "$UNIT_NEW_SHA256" ]; then
    echo "STOP-live-unit-hash $have"
    exit 1
  fi
  if [ "$(systemctl is-enabled johnny-capture-irq.service)" != enabled ]; then
    echo STOP-unit-not-enabled
    exit 1
  fi
  tst=$(systemctl is-active johnny-capture-tuning.service || true)
  if [ "$tst" != active ]; then
    echo "NOTE-tuning-not-active ${tst:-unknown}"
  fi
  echo INPUTS-OK

  # Checkpoint 2: keep the old files once, then install.
  mkdir -p "$PREV"
  if [ "$hhave" = "$HELPER_OLD_SHA256" ] && [ ! -e "$PREV/irq-affinity.sh" ]; then
    install -m 0755 -o root -g root "$HELPER" "$PREV/irq-affinity.sh"
  fi
  if [ "$have" = "$UNIT_OLD_SHA256" ] && [ ! -e "$PREV/johnny-capture-irq.service" ]; then
    install -m 0644 -o root -g root "$LIVE" "$PREV/johnny-capture-irq.service"
  fi
  if [ -e "$PREV/irq-affinity.sh" ] && [ "$(sha_of "$PREV/irq-affinity.sh")" != "$HELPER_OLD_SHA256" ]; then
    echo STOP-prev-hash
    exit 1
  fi
  if [ -e "$PREV/johnny-capture-irq.service" ] && [ "$(sha_of "$PREV/johnny-capture-irq.service")" != "$UNIT_OLD_SHA256" ]; then
    echo STOP-prev-hash
    exit 1
  fi
  echo PREV-SAVED
  rollback() {
    if [ -f "$PREV/irq-affinity.sh" ]; then
      install -m 0755 -o root -g root "$PREV/irq-affinity.sh" "$HELPER" || true
    fi
    if [ -f "$PREV/johnny-capture-irq.service" ]; then
      install -m 0644 -o root -g root "$PREV/johnny-capture-irq.service" "$LIVE" || true
    fi
    systemctl daemon-reload || true
    echo "ROLLED-BACK (masks not touched)"
  }
  install -m 0755 -o root -g root "$SRC_HELPER" "$HELPER.new"
  mv -f "$HELPER.new" "$HELPER"
  install -m 0644 -o root -g root "$SRC" "$LIVE.new"
  mv -f "$LIVE.new" "$LIVE"
  if [ "$(sha_of "$HELPER")" != "$HELPER_NEW_SHA256" ] || [ "$(sha_of "$LIVE")" != "$UNIT_NEW_SHA256" ]; then
    echo STOP-install-hash
    rollback
    exit 1
  fi
  systemctl daemon-reload
  echo FILES-INSTALLED

  # Checkpoint 3: no tuning edge (cycle) and the longer timeout are loaded.
  if systemctl show -p After --value johnny-capture-irq.service | tr ' ' '\n' | grep -qx 'johnny-capture-tuning.service'; then
    echo STOP-after-still-lists-tuning
    rollback
    exit 1
  fi
  if ! grep -qx 'TimeoutStartSec=150' "$LIVE"; then
    echo STOP-timeout-not-150s
    rollback
    exit 1
  fi
  echo AFTER-OK

  # Checkpoint 4: restart the oneshot once (new helper, idempotent pins).
  if ! systemctl restart johnny-capture-irq.service; then
    echo STOP-start-failed
    journalctl -u johnny-capture-irq.service -n 30 --no-pager || true
    rollback
    exit 1
  fi
  state=$(systemctl is-active johnny-capture-irq.service)
  if [ "$state" != active ]; then
    echo "STOP-not-active $state"
    exit 1
  fi
  echo START-OK

  # Checkpoint 5: pins, by name. TxRx-N must be on CPU (N mod 4)+1.
  txrx=$(irqs_named '^ice-eno1np0-TxRx-[0-9]+$')
  count=$(printf '%s\n' "$txrx" | grep -c . || true)
  if [ "$count" -ne 12 ]; then
    echo "STOP-txrx-count $count"
    exit 1
  fi
  : > /run/step13d.spread
  for n in $(seq 0 11); do
    want=$(( n % 4 + 1 ))
    irq=$(awk -v re="^ice-eno1np0-TxRx-$n\$" '$NF ~ re {sub(":","",$1); print $1}' /proc/interrupts)
    got=$(tr -d '[:space:]' < "/proc/irq/$irq/smp_affinity_list")
    echo "TXRX $n irq $irq cpu $got"
    if [ "$got" != "$want" ]; then
      echo "STOP-txrx-mask $n want $want got $got"
      exit 1
    fi
    echo "$got" >> /run/step13d.spread
  done
  echo "SPREAD-COUNT cpu1=$(grep -c '^1$' /run/step13d.spread) cpu2=$(grep -c '^2$' /run/step13d.spread) cpu3=$(grep -c '^3$' /run/step13d.spread) cpu4=$(grep -c '^4$' /run/step13d.spread)"
  rm -f /run/step13d.spread
  for pat in '^ice-0000:01:00.0:misc$' '^ice-0000:01:00.0:ll_ts$' '^ice-0000:01:00.0:ctrl-TxRx-0$'; do
    aux=$(irqs_named "$pat")
    echo "AUX $pat $aux"
    case "$aux" in
      *" 1") ;;
      *)
        echo "STOP-aux-mask $pat"
        exit 1
        ;;
    esac
  done
  echo "IRDMA (left alone; 0-23 expected, not checked as pass/fail):"
  irqs_named '^irdma-0000:01:00.0-' | sed 's/^/IRDMA /'
  echo STEP13B-ENO3-WAIT-FIXED
}

main "$@"
