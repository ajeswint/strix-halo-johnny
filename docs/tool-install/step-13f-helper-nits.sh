#!/bin/bash
# Johnny step 13f: helper lint and journal-noise fix. Installs the helper only
# (unit unchanged, must already be the 13d unit). Changes: SC2261 in read_trim,
# unused locals `xdp` and `snap` removed, and affinity_is_cpu no longer abandons
# a process substitution (the source of 11 "printf: write error: Broken pipe"
# boot-journal lines). Pin logic, eno1 + eno3 waits, tuning NOTEs are unchanged.
# Hash-gated: live helper must be the 13d blob (or already the 13f blob).
# Restarts the oneshot once (pins already match, so it writes no masks).
# No reboot, no netplan, no irqbalance, tuning unit and irq unit untouched.
# AJ runs it on Johnny, as root, after the helper is in /home/aj/cis-audit/.
# Docs: docs/tool-install/step-13-irq-affinity.md (section "Step 13f").
# Success ends with STEP13B-HELPER-NITS-FIXED. This file has not run.

LIVE_UNIT=/etc/systemd/system/johnny-capture-irq.service
HELPER=/etc/johnny/irq-affinity.sh
SRC_HELPER=/home/aj/cis-audit/irq-affinity-nits.sh
PREV=/var/lib/johnny/step13f-prev
UNIT_SHA256=6084be53011599d64d7240e4547b53f8dbaa2e2c588d3975f0517a18e6453ed2
HELPER_OLD_SHA256=807f5a5599bc3e6478a6172b3a54eb576c08f0c4609047a69b834ffec8af3804
HELPER_NEW_SHA256=db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4

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

# Run the installed helper's affinity_is_cpu with PIPE ignored, as main() does.
# Sets PROBE_RC (the function's return) and PROBE_ERR (its stderr, must be empty).
# Sourcing is safe: the helper only runs main() when executed, not when sourced.
probe_affinity() {
  local errf
  errf=$(mktemp)
  PROBE_RC=0
  bash -c 'source "$1"; trap "" PIPE; affinity_is_cpu "$2" "$3"' _ "$HELPER" "$1" "$2" 2>"$errf" >/dev/null || PROBE_RC=$?
  PROBE_ERR=$(cat "$errf")
  rm -f "$errf"
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
  LOG=/root/step13f-$(date -u +%Y%m%dT%H%M%SZ).log
  if [ -e "$LOG" ]; then
    echo "STOP-log-exists $LOG"
    exit 1
  fi
  exec > >(tee "$LOG") 2>&1
  echo "LOG $LOG"
  set -euo pipefail

  # Checkpoint 1: inputs.
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
  if [ ! -f "$LIVE_UNIT" ] || [ -L "$LIVE_UNIT" ] || [ "$(sha_of "$LIVE_UNIT")" != "$UNIT_SHA256" ]; then
    echo "STOP-live-unit-hash $LIVE_UNIT"
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

  # Checkpoint 2: keep the old helper once, then install.
  mkdir -p "$PREV"
  if [ "$hhave" = "$HELPER_OLD_SHA256" ] && [ ! -e "$PREV/irq-affinity.sh" ]; then
    install -m 0755 -o root -g root "$HELPER" "$PREV/irq-affinity.sh"
  fi
  if [ -e "$PREV/irq-affinity.sh" ] && [ "$(sha_of "$PREV/irq-affinity.sh")" != "$HELPER_OLD_SHA256" ]; then
    echo STOP-prev-hash
    exit 1
  fi
  echo PREV-SAVED
  rollback() {
    if [ -f "$PREV/irq-affinity.sh" ]; then
      install -m 0755 -o root -g root "$PREV/irq-affinity.sh" "$HELPER" || true
    fi
    echo "ROLLED-BACK (masks not touched)"
  }
  install -m 0755 -o root -g root "$SRC_HELPER" "$HELPER.new"
  mv -f "$HELPER.new" "$HELPER"
  if [ "$(sha_of "$HELPER")" != "$HELPER_NEW_SHA256" ]; then
    echo STOP-install-hash
    rollback
    exit 1
  fi
  echo FILE-INSTALLED

  # Checkpoint 3: the broken-pipe fix, on the installed (root-owned) helper.
  # Old helper: "0-23" vs cpu 1 prints printf write errors on stderr. New: none.
  probe_affinity 0-23 1
  if [ "$PROBE_RC" -ne 1 ] || [ -n "$PROBE_ERR" ]; then
    echo "STOP-probe-wide rc=$PROBE_RC err=$PROBE_ERR"
    rollback
    exit 1
  fi
  probe_affinity 1-2 1
  if [ "$PROBE_RC" -ne 1 ] || [ -n "$PROBE_ERR" ]; then
    echo "STOP-probe-two rc=$PROBE_RC err=$PROBE_ERR"
    rollback
    exit 1
  fi
  probe_affinity 2 2
  if [ "$PROBE_RC" -ne 0 ] || [ -n "$PROBE_ERR" ]; then
    echo "STOP-probe-single rc=$PROBE_RC err=$PROBE_ERR"
    rollback
    exit 1
  fi
  probe_affinity x 1
  if [ "$PROBE_RC" -ne 1 ] || [ -n "$PROBE_ERR" ]; then
    echo "STOP-probe-bad rc=$PROBE_RC err=$PROBE_ERR"
    rollback
    exit 1
  fi
  echo PROBE-OK

  # Checkpoint 4: restart the oneshot once (new helper, pins already match).
  started=$(date '+%Y-%m-%d %H:%M:%S')
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
  pipes=$(journalctl -u johnny-capture-irq.service --since "$started" --no-pager | grep -c 'Broken pipe' || true)
  pinok=$(journalctl -u johnny-capture-irq.service --since "$started" --no-pager | grep -c 'PIN-OK' || true)
  echo "JOURNAL-SINCE-RESTART pin-ok=$pinok broken-pipe=$pipes"
  if [ "$pinok" -lt 1 ]; then
    echo STOP-no-pin-ok-in-journal
    exit 1
  fi
  if [ "$pipes" -ne 0 ]; then
    echo STOP-broken-pipe-in-journal
    exit 1
  fi

  # Checkpoint 5: pins, by name. TxRx-N must be on CPU (N mod 4)+1.
  txrx=$(irqs_named '^ice-eno1np0-TxRx-[0-9]+$')
  count=$(printf '%s\n' "$txrx" | grep -c . || true)
  if [ "$count" -ne 12 ]; then
    echo "STOP-txrx-count $count"
    exit 1
  fi
  : > /run/step13f.spread
  for n in $(seq 0 11); do
    want=$(( n % 4 + 1 ))
    irq=$(awk -v re="^ice-eno1np0-TxRx-$n\$" '$NF ~ re {sub(":","",$1); print $1}' /proc/interrupts)
    got=$(tr -d '[:space:]' < "/proc/irq/$irq/smp_affinity_list")
    echo "TXRX $n irq $irq cpu $got"
    if [ "$got" != "$want" ]; then
      echo "STOP-txrx-mask $n want $want got $got"
      exit 1
    fi
    echo "$got" >> /run/step13f.spread
  done
  echo "SPREAD-COUNT cpu1=$(grep -c '^1$' /run/step13f.spread) cpu2=$(grep -c '^2$' /run/step13f.spread) cpu3=$(grep -c '^3$' /run/step13f.spread) cpu4=$(grep -c '^4$' /run/step13f.spread)"
  rm -f /run/step13f.spread
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
  echo STEP13B-HELPER-NITS-FIXED
}

main "$@"
