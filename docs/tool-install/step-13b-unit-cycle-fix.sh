#!/bin/bash
# Johnny step 13b follow-up: install the cycle-fix johnny-capture-irq.service
# (After= no longer lists johnny-capture-tuning.service) and start it once.
# Unit only. The helper /etc/johnny/irq-affinity.sh is NOT replaced; it must
# already be the 13b blob. No reboot, no netplan, no irqbalance change.
# AJ runs it on Johnny, as root, after the unit is in /home/aj/cis-audit/.
# Docs: docs/tool-install/step-13-irq-affinity.md (section "Ordering cycle").
# Success ends with STEP13B-IRQ-UNIT-CYCLE-FIXED. This file has not run.

SRC=/home/aj/cis-audit/johnny-capture-irq-cyclefix.service
LIVE=/etc/systemd/system/johnny-capture-irq.service
HELPER=/etc/johnny/irq-affinity.sh
PREV=/var/lib/johnny/step13b-cyclefix-prev
UNIT_OLD_SHA256=03ce0ceb5f01501fed42488a2cb3697f81bc8d91ef94d4ee5f68df1a8efc2c6a
UNIT_NEW_SHA256=a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a
HELPER_SHA256=29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530

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
  LOG=/root/step13b-cyclefix-$(date -u +%Y%m%dT%H%M%SZ).log
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
  if [ ! -f "$HELPER" ] || [ -L "$HELPER" ] || [ "$(sha_of "$HELPER")" != "$HELPER_SHA256" ]; then
    echo "STOP-helper-hash $HELPER"
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
  echo INPUTS-OK

  # Checkpoint 2: keep the old unit once, then install.
  if [ "$have" = "$UNIT_OLD_SHA256" ]; then
    mkdir -p "$PREV"
    if [ ! -e "$PREV/johnny-capture-irq.service" ]; then
      install -m 0644 -o root -g root "$LIVE" "$PREV/johnny-capture-irq.service"
    fi
    if [ "$(sha_of "$PREV/johnny-capture-irq.service")" != "$UNIT_OLD_SHA256" ]; then
      echo STOP-prev-hash
      exit 1
    fi
    echo PREV-SAVED
  fi
  rollback_unit() {
    if [ -f "$PREV/johnny-capture-irq.service" ]; then
      install -m 0644 -o root -g root "$PREV/johnny-capture-irq.service" "$LIVE" || true
      systemctl daemon-reload || true
      echo "ROLLED-BACK-UNIT (masks not touched)"
    fi
  }
  install -m 0644 -o root -g root "$SRC" "$LIVE.new"
  mv -f "$LIVE.new" "$LIVE"
  if [ "$(sha_of "$LIVE")" != "$UNIT_NEW_SHA256" ]; then
    echo STOP-install-hash
    rollback_unit
    exit 1
  fi
  systemctl daemon-reload
  echo UNIT-INSTALLED

  # Checkpoint 3: the cycle edge is gone from the loaded unit.
  if systemctl show -p After --value johnny-capture-irq.service | tr ' ' '\n' | grep -qx 'johnny-capture-tuning.service'; then
    echo STOP-after-still-lists-tuning
    rollback_unit
    exit 1
  fi
  echo AFTER-OK

  # Checkpoint 4: run the oneshot once (helper applies the pins).
  if ! systemctl start johnny-capture-irq.service; then
    echo STOP-start-failed
    journalctl -u johnny-capture-irq.service -n 30 --no-pager || true
    rollback_unit
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
  : > /run/step13b-cyclefix.spread
  for n in $(seq 0 11); do
    want=$(( n % 4 + 1 ))
    irq=$(awk -v re="^ice-eno1np0-TxRx-$n\$" '$NF ~ re {sub(":","",$1); print $1}' /proc/interrupts)
    got=$(tr -d '[:space:]' < "/proc/irq/$irq/smp_affinity_list")
    echo "TXRX $n irq $irq cpu $got"
    if [ "$got" != "$want" ]; then
      echo "STOP-txrx-mask $n want $want got $got"
      exit 1
    fi
    echo "$got" >> /run/step13b-cyclefix.spread
  done
  echo "SPREAD-COUNT cpu1=$(grep -c '^1$' /run/step13b-cyclefix.spread) cpu2=$(grep -c '^2$' /run/step13b-cyclefix.spread) cpu3=$(grep -c '^3$' /run/step13b-cyclefix.spread) cpu4=$(grep -c '^4$' /run/step13b-cyclefix.spread)"
  rm -f /run/step13b-cyclefix.spread
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
  echo STEP13B-IRQ-UNIT-CYCLE-FIXED
}

main "$@"
