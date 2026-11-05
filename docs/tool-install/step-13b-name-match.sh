#!/bin/bash
# Johnny step 13b: name-match follow-up to step 13. Not applied by this commit.
# AJ runs it on Johnny, as root, after three files are in /home/aj/cis-audit/.
# Docs: docs/tool-install/step-13-irq-affinity.md (section "Step 13b").
# Replaces /etc/johnny/irq-affinity.sh (c765e01 blob) and the unit (adds
# Wants=network-online.target), re-runs the helper so ice-eno1np0-TxRx-N land on
# capture CPUs 1-4, and puts the irdma-0000:01:00.0-* vectors back on the masks
# saved in /var/lib/johnny/irq-affinity-before.tsv.
# Does NOT re-run the c765e01 paste. Does not touch the backup file, irqbalance,
# netplan, eno2np1, eno3, RSS, RPS, XPS, GRUB, or apt. No reboot.
# SIGHUP and SIGPIPE are ignored. A failure after a change puts back the masks
# and the helper and unit this run saw on entry.

AUDIT=/home/aj/cis-audit
HELPER_SRC=$AUDIT/irq-affinity.sh
UNIT_SRC=$AUDIT/johnny-capture-irq.service
STAGE_HELPER=/root/step13b-helper.sh
STAGE_UNIT=/root/step13b-unit.service
PREV=/var/lib/johnny/step13b-prev
BEFORE=/var/lib/johnny/irq-affinity-before.tsv
LIVE_HELPER=/etc/johnny/irq-affinity.sh
LIVE_UNIT=/etc/systemd/system/johnny-capture-irq.service
HELPER_OLD_SHA256=77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e
HELPER_NEW_SHA256=29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530
UNIT_OLD_SHA256=9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355
UNIT_NEW_SHA256=03ce0ceb5f01501fed42488a2cb3697f81bc8d91ef94d4ee5f68df1a8efc2c6a
KERNEL_WANT=7.0.0-42-generic
IRDMA_PREFIX='irdma-0000:01:00.0-'

sha_of() {
  sha256sum "$1" | awk '{print $1}'
}

sha_ok() {
  local file=$1 want=$2 got
  if [ ! -f "$file" ] || [ -L "$file" ]; then
    echo "STOP-no-file $file"
    return 1
  fi
  got=$(sha_of "$file" || true)
  if [ "$got" != "$want" ]; then
    echo "STOP-hash $file"
    return 1
  fi
  return 0
}

# Prints irq|list|name for each saved irdma vector of 0000:01:00.0.
irdma_backup_lines() {
  local file=$1 irq list name
  while IFS='|' read -r irq list name || [ -n "${irq:-}" ]; do
    [ -n "${irq:-}" ] || continue
    [[ $irq =~ ^[0-9]+$ ]] || continue
    [ -n "$list" ] || continue
    case "$name" in
      "$IRDMA_PREFIX"*) printf '%s|%s|%s\n' "$irq" "$list" "$name" ;;
    esac
  done < "$file"
}

cpulist_flat() {
  local spec=$1 out
  out=$(expand_affinity "$spec" | tr '\n' ' ' || true)
  printf '%s\n' "$out"
}

same_cpulist() {
  local a b
  a=$(cpulist_flat "$1")
  b=$(cpulist_flat "$2")
  [ -n "$a" ] && [ "$a" = "$b" ]
}

main() {
  local host
  host=$(hostname -s 2>/dev/null || hostname)
  if [ "$host" != johnny ]; then
    echo STOP-host
    exit 1
  fi
  if [ "$(uname -r)" != "$KERNEL_WANT" ]; then
    echo "STOP-kernel $(uname -r)"
    exit 1
  fi
  if [ "$(id -u)" -ne 0 ]; then
    echo STOP-not-root
    exit 1
  fi

  umask 022
  export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
  trap '' HUP PIPE
  mkdir -p /run /var/lib/johnny /root
  exec 8>/run/johnny-capture-irq.lock
  if ! flock -n 8; then
    echo STOP-locked
    exit 1
  fi
  export JOHNNY_STEP13_LOCKED=1
  if [ -f /root/step13b-apply.log ]; then
    mv -f /root/step13b-apply.log /root/step13b-apply.log.1
  fi
  exec > >(tee /root/step13b-apply.log) 2>&1

  set -eEuo pipefail
  # Globals on purpose: the EXIT trap runs after main returns.
  this_run_changed=0
  failed=0
  PRE_MASKS=
  ENO2SNAP=

  # Invoked by the EXIT trap, which shellcheck cannot see.
  # shellcheck disable=SC2317
  cleanup() {
    local rc=$?
    local irq list
    trap - ERR
    trap - EXIT
    set +e
    if [ "$rc" -ne 0 ]; then
      failed=1
    fi
    if [ "$failed" -eq 1 ] && [ "$this_run_changed" -eq 1 ]; then
      echo REVERTING-13B
      if [ -n "${PRE_MASKS:-}" ] && [ -s "$PRE_MASKS" ]; then
        while IFS=$'\t' read -r irq list; do
          [ -n "${irq:-}" ] || continue
          printf '%s\n' "$list" > "/proc/irq/${irq}/smp_affinity_list" 2>/dev/null \
            || echo "NOTE-13b-restore-failed $irq"
        done < "$PRE_MASKS"
        echo MASKS-PUT-BACK
      fi
      if [ -f "$PREV/irq-affinity.sh" ]; then
        install -m 0755 -o root -g root "$PREV/irq-affinity.sh" "$LIVE_HELPER"
        echo HELPER-PUT-BACK
      fi
      if [ -f "$PREV/johnny-capture-irq.service" ]; then
        install -m 0644 -o root -g root "$PREV/johnny-capture-irq.service" "$LIVE_UNIT"
        systemctl daemon-reload
        echo UNIT-PUT-BACK
      fi
    elif [ "$failed" -eq 1 ]; then
      echo NO-CHANGE-13B
    fi
    rm -f "${PRE_MASKS:-}" "${ENO2SNAP:-}" "$STAGE_HELPER" "$STAGE_UNIT" || true
    exit "$rc"
  }
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

  local cmd
  for cmd in ethtool systemctl ip sha256sum install cmp awk flock hostname uname; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "STOP-missing $cmd"
    fi
  done

  if [ "${SUDO_USER:-}" != "" ] && [ "${SUDO_USER}" != aj ]; then
    die STOP-user
  fi
  if [ -z "${SUDO_USER:-}" ]; then
    echo NOTE-no-sudo-user
  fi

  # Stage under /root (aj cannot write there), then hash the staged copies.
  install -m 0755 -o root -g root "$HELPER_SRC" "$STAGE_HELPER"
  install -m 0644 -o root -g root "$UNIT_SRC" "$STAGE_UNIT"
  sha_ok "$STAGE_HELPER" "$HELPER_NEW_SHA256" || die "STOP-hash $STAGE_HELPER"
  sha_ok "$STAGE_UNIT" "$UNIT_NEW_SHA256" || die "STOP-hash $STAGE_UNIT"
  echo STAGED-OK

  # Live files must be the step 13 install (old) or already this follow-up (new).
  local have
  have=$(sha_of "$LIVE_HELPER" 2>/dev/null || true)
  if [ "$have" != "$HELPER_OLD_SHA256" ] && [ "$have" != "$HELPER_NEW_SHA256" ]; then
    die "STOP-live-helper-hash ${have:-missing}"
  fi
  have=$(sha_of "$LIVE_UNIT" 2>/dev/null || true)
  if [ "$have" != "$UNIT_OLD_SHA256" ] && [ "$have" != "$UNIT_NEW_SHA256" ]; then
    die "STOP-live-unit-hash ${have:-missing}"
  fi
  if [ -L "$LIVE_HELPER" ] || [ -L "$LIVE_UNIT" ]; then
    die STOP-live-symlink
  fi
  if [ -L "$BEFORE" ] || [ ! -s "$BEFORE" ]; then
    die STOP-no-affinity-backup
  fi
  if [ "$(systemctl is-enabled johnny-capture-irq.service 2>/dev/null || true)" != enabled ]; then
    die STOP-irq-unit-not-enabled
  fi
  if systemctl cat irqbalance.service >/dev/null 2>&1; then
    if [ "$(systemctl is-active irqbalance.service 2>/dev/null || true)" = active ]; then
      die STOP-irqbalance-active
    fi
    echo NOTE-irqbalance-installed-inactive
  else
    echo NOTE-no-irqbalance
  fi

  if [ -r /sys/kernel/security/lockdown ]; then
    LOCKDOWN_BEFORE=$(tr -d '[:space:]' < /sys/kernel/security/lockdown || true)
    echo "LOCKDOWN $LOCKDOWN_BEFORE"
  else
    LOCKDOWN_BEFORE=""
    echo NOTE-no-lockdown
  fi

  # New helper functions only. main() in the staged copy does not run here.
  # shellcheck source=etc/johnny/irq-affinity.sh
  source "$STAGE_HELPER"

  preflight || die STOP-preflight

  local qbefore
  qbefore=$(snapshot_queues QUEUES)
  printf '%s\n' "$qbefore"
  ENO2SNAP=$(mktemp /var/lib/johnny/step13b-eno2.XXXXXX)
  snapshot_eno2 "$ENO2SNAP" || die STOP-eno2-snap

  prepare_map || die STOP-map

  local nq=0 i
  for i in "${!ENO1_IRQS[@]}"; do
    if [ "$(classify_irq_name "${ENO1_NAMES[$i]}")" = queue ]; then
      nq=$((nq + 1))
    fi
    printf 'PLAN %s %s cpu %s\n' "${ENO1_IRQS[$i]}" "${ENO1_NAMES[$i]}" "${ENO1_CPUS[$i]}"
  done
  if [ "$nq" -lt 1 ]; then
    die STOP-no-queue-names
  fi
  echo "PLAN-QUEUES $nq"

  # irdma restore plan, from the first-run save. The IRQ number must still
  # carry the same name, or the save is stale.
  local line irq list name cur
  local -a IRDMA_IRQS=() IRDMA_LISTS=() IRDMA_NAMES=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS='|' read -r irq list name <<<"$line"
    if [ ! -e "/proc/irq/${irq}/smp_affinity_list" ]; then
      die "STOP-irdma-gone $irq"
    fi
    if [ ! -w "/proc/irq/${irq}/smp_affinity_list" ]; then
      die "STOP-irdma-ro $irq"
    fi
    if ! cur=$(irq_name_from_file "$irq" /proc/interrupts); then
      die "STOP-irdma-name $irq"
    fi
    if [ "$cur" != "$name" ]; then
      die "STOP-irdma-renamed $irq $name $cur"
    fi
    IRDMA_IRQS+=("$irq")
    IRDMA_LISTS+=("$list")
    IRDMA_NAMES+=("$name")
  done < <(irdma_backup_lines "$BEFORE")
  if [ "${#IRDMA_IRQS[@]}" -lt 1 ]; then
    die STOP-no-irdma-backup
  fi
  echo "IRDMA-RESTORE-PLAN ${#IRDMA_IRQS[@]}"

  # Pre-run masks of every eno1np0 PCI vector (ice + irdma), for rollback.
  PRE_MASKS=$(mktemp /var/lib/johnny/step13b-pre.XXXXXX)
  while read -r irq; do
    if [[ $irq == STOP-* ]]; then
      die "$irq"
    fi
    [ -e "/proc/irq/${irq}/smp_affinity_list" ] || continue
    printf '%s\t%s\n' "$irq" "$(read_affinity "$irq")" >> "$PRE_MASKS"
  done < <(list_msi eno1np0 | sort -n)
  if [ ! -s "$PRE_MASKS" ]; then
    die STOP-no-pre-masks
  fi
  echo PRE-MASKS-SAVED

  # Save the files this run replaces. Never overwrite a previous save.
  mkdir -p "$PREV"
  if [ ! -f "$PREV/irq-affinity.sh" ]; then
    cp -p "$LIVE_HELPER" "$PREV/irq-affinity.sh"
  fi
  if [ ! -f "$PREV/johnny-capture-irq.service" ]; then
    cp -p "$LIVE_UNIT" "$PREV/johnny-capture-irq.service"
  fi
  echo PREV-SAVED

  this_run_changed=1
  if cmp -s "$STAGE_HELPER" "$LIVE_HELPER"; then
    echo "KEPT $LIVE_HELPER"
  else
    install -m 0755 -o root -g root "$STAGE_HELPER" "$LIVE_HELPER"
    echo "INSTALLED $LIVE_HELPER"
  fi
  if cmp -s "$STAGE_UNIT" "$LIVE_UNIT"; then
    echo "KEPT $LIVE_UNIT"
  else
    install -m 0644 -o root -g root "$STAGE_UNIT" "$LIVE_UNIT"
    echo "INSTALLED $LIVE_UNIT"
  fi
  sha_ok "$LIVE_HELPER" "$HELPER_NEW_SHA256" || die STOP-install-hash
  sha_ok "$LIVE_UNIT" "$UNIT_NEW_SHA256" || die STOP-install-hash
  systemctl daemon-reload
  echo UNIT-RELOADED

  # The helper runs its own preflight, pin, verify, and rollback-to-pre-run.
  "$LIVE_HELPER" apply

  for i in "${!IRDMA_IRQS[@]}"; do
    irq=${IRDMA_IRQS[$i]}
    printf '%s\n' "${IRDMA_LISTS[$i]}" > "/proc/irq/${irq}/smp_affinity_list" \
      || die "STOP-irdma-write $irq"
  done
  for i in "${!IRDMA_IRQS[@]}"; do
    irq=${IRDMA_IRQS[$i]}
    cur=$(read_affinity "$irq")
    if ! same_cpulist "$cur" "${IRDMA_LISTS[$i]}"; then
      die "STOP-irdma-restore $irq want ${IRDMA_LISTS[$i]} got $cur"
    fi
    printf 'IRDMA %s %s mask %s\n' "$irq" "${IRDMA_NAMES[$i]}" "$cur"
  done
  echo IRDMA-RESTORED

  # Independent read of the spread, from /proc/interrupts names.
  local want got q
  local -a COUNT=()
  local c
  for c in "${CAPTURE_CPUS[@]}"; do
    COUNT[c]=0
  done
  while read -r irq name; do
    [ -n "$irq" ] || continue
    if [[ $name =~ ^ice-eno1np0-TxRx-([0-9]+)$ ]]; then
      q=${BASH_REMATCH[1]}
      want=${CAPTURE_CPUS[$((10#$q % ${#CAPTURE_CPUS[@]}))]}
      got=$(read_affinity "$irq")
      if ! affinity_is_cpu "$got" "$want"; then
        die "STOP-spread $irq $name want $want got $got"
      fi
      COUNT[want]=$((COUNT[want] + 1))
      printf 'SPREAD %s %s cpu %s\n' "$irq" "$name" "$got"
    fi
  done < <(awk '$1 ~ /^[0-9]+:$/ && $NF ~ /^ice-eno1np0-TxRx-[0-9]+$/ { irq=$1; sub(/:$/, "", irq); print irq, $NF }' /proc/interrupts)
  local spread=""
  for c in "${CAPTURE_CPUS[@]}"; do
    spread="$spread cpu${c}=${COUNT[c]}"
    if [ "${COUNT[c]}" -lt 1 ]; then
      die "STOP-spread-empty cpu $c"
    fi
  done
  echo "SPREAD-COUNT$spread"

  eno2_unchanged "$ENO2SNAP" || die STOP-eno2-irq-moved
  eno3_ok || die STOP-eno3
  local qafter
  qafter=$(snapshot_queues QUEUES)
  queues_unchanged "$qbefore" "$qafter" || die STOP-queues-changed
  if [ -n "$LOCKDOWN_BEFORE" ]; then
    local lock2
    lock2=$(tr -d '[:space:]' < /sys/kernel/security/lockdown || true)
    if [ "$lock2" != "$LOCKDOWN_BEFORE" ]; then
      die "STOP-lockdown $LOCKDOWN_BEFORE $lock2"
    fi
    echo LOCKDOWN-UNCHANGED
  fi
  echo ENO3-OK
  echo CPU0-CLEAR
  echo STEP13B-NAME-MATCH-DONE
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
