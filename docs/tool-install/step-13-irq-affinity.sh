#!/bin/bash
# Johnny step 13 — pin eno1np0 ice IRQs. Not applied by this commit.
# AJ runs it on Johnny, as root, after the four payload files are in
# /home/aj/cis-audit/. Docs: docs/tool-install/step-13-irq-affinity.md
# No reboot. No apt. No GRUB. Does not change eno3's address or netplan.
# SIGHUP and SIGPIPE are ignored so a dropped SSH session still rolls back.
# A failed run that changed the box runs /root/step13-revert.sh before it exits.
# A rerun that changes nothing and then fails leaves the previous config
# (CONFIG-KEPT) when that config is already installed. A first run that
# stops before a change prints NO-CHANGE. After STEP13-IRQ-DONE, do not
# rerun unless that rollback
# is acceptable: a rerun that has to change a file and then fails rolls
# back to the first-run affinity save.

AUDIT=/home/aj/cis-audit
HELPER_SRC=$AUDIT/irq-affinity.sh
POLICY_SRC=$AUDIT/irqbalance-policy.sh
UNIT_SRC=$AUDIT/johnny-capture-irq.service
REVERT_SRC=$AUDIT/step-13-revert.sh
STAGE_HELPER=/root/step13-helper.sh
STAGE_POLICY=/root/step13-policy.sh
STAGE_UNIT=/root/step13-unit.service
HELPER_SHA256=77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e
POLICY_SHA256=7a3eeb944be0ee60ba94099b3ae4da3c905c941003c5c50221921032a9ffb0a8
UNIT_SHA256=a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a
REVERT_SHA256=c9dd1522e278bc3bad3a711a4fdcd18b1b768d9da19dff07376a5db7dfa4cc1d
POLICY_ARG=--policyscript=/etc/johnny/irqbalance-policy.sh
DEFAULT=/etc/default/irqbalance
IRQ_BAK=/var/lib/johnny/irqbalance.default.pre-step13
WAS=/var/lib/johnny/step13-irqbalance-was-active
BEFORE=/var/lib/johnny/irq-affinity-before.tsv
KERNEL_WANT=7.0.0-42-generic

irqbalance_edit() {
  local mode=$1 file=$2
  python3 - "$mode" "$file" "$POLICY_ARG" <<'PY'
import os, sys, tempfile
mode, path, arg = sys.argv[1], sys.argv[2], sys.argv[3]
if mode not in ("check", "write"):
    sys.exit(5)
if os.path.islink(path):
    sys.exit(6)
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()
lines = text.splitlines(keepends=True)
args_idx = []
for i, line in enumerate(lines):
    raw = line.strip()
    if not raw or raw.startswith("#"):
        continue
    if raw.startswith("IRQBALANCE_BANNED_CPUS=") or raw.startswith("IRQBALANCE_BANNED_CPULIST="):
        val = raw.split("=", 1)[1].strip().strip('"').strip("'")
        if val:
            sys.exit(4)
    if raw.startswith("IRQBALANCE_ARGS="):
        args_idx.append(i)
want = "IRQBALANCE_ARGS=%s\n" % arg
if len(args_idx) > 1:
    sys.exit(2)
if len(args_idx) == 1:
    cur = lines[args_idx[0]].strip()
    val = cur.split("=", 1)[1].strip().strip('"').strip("'")
    if val == arg:
        print("UNCHANGED")
        raise SystemExit(0)
    if val != "":
        sys.exit(3)
    lines[args_idx[0]] = want
else:
    if text and not text.endswith("\n"):
        lines.append("\n")
    lines.append("# step 13: ban ice PF MSI IRQs so the eno1np0 pin sticks\n")
    lines.append(want)
if mode == "check":
    print("WOULD-WRITE")
    raise SystemExit(0)
new = "".join(lines)
st = os.stat(path)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
try:
    os.write(fd, new.encode("utf-8"))
    os.fchmod(fd, st.st_mode)
    try:
        os.fchown(fd, st.st_uid, st.st_gid)
    except PermissionError:
        pass
    os.close(fd)
    fd = -1
    os.replace(tmp, path)
    tmp = ""
finally:
    if fd >= 0:
        os.close(fd)
    if tmp:
        os.unlink(tmp)
print("WROTE-irqbalance")
PY
}

unit_interest_lines() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*Environment=/ && /IRQBALANCE_/ { print "STOP-irqbalance-env" }
    /^[[:space:]]*EnvironmentFile=/ {
      s=$0
      sub(/^[[:space:]]*EnvironmentFile=-?/, "", s)
      print s
    }
  ' "$1"
}

sha_ok() {
  local file=$1 want=$2 got
  if [ ! -f "$file" ] || [ -L "$file" ]; then
    echo "STOP-no-file $file"
    return 1
  fi
  got=$(sha256sum "$file" | awk '{print $1}' || true)
  if [ "$got" != "$want" ]; then
    echo "STOP-hash $file"
    return 1
  fi
  return 0
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
  if [ -f /root/step13-apply.log ]; then
    mv -f /root/step13-apply.log /root/step13-apply.log.1
  fi
  exec > >(tee /root/step13-apply.log) 2>&1

  set -eEuo pipefail
  this_run_changed=0
  failed=0
  revert_ready=0
  UNIT_TMP=
  ENO2SNAP=

  # Invoked by the EXIT trap, which shellcheck cannot see.
  # shellcheck disable=SC2317
  cleanup() {
    local rc=$?
    local revert_rc=0
    trap - ERR
    trap - EXIT
    set +e
    if [ "$rc" -ne 0 ]; then
      failed=1
    fi
    if [ "${failed:-0}" -eq 1 ] && [ "${revert_ready:-0}" -eq 1 ] && [ "${this_run_changed:-0}" -eq 1 ]; then
      echo REVERTING || true
      bash /root/step13-revert.sh > /root/step13-revert.out 2>&1
      revert_rc=$?
      cat /root/step13-revert.out || true
      if [ "$revert_rc" -ne 0 ]; then
        echo STOP-revert-failed || true
      fi
    elif [ "${failed:-0}" -eq 1 ] && [ "${revert_ready:-0}" -eq 1 ] && [ "${this_run_changed:-0}" -eq 0 ]; then
      if [ -f /etc/johnny/irq-affinity.sh ] || [ -f /var/lib/johnny/irq-affinity-before.tsv ] || [ -f /etc/systemd/system/johnny-capture-irq.service ]; then
        echo CONFIG-KEPT || true
      else
        echo NO-CHANGE || true
      fi
    fi
    rm -f "${UNIT_TMP:-}" "${ENO2SNAP:-}" "$STAGE_HELPER" "$STAGE_POLICY" "$STAGE_UNIT" || true
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

  mark_changed() {
    this_run_changed=1
  }

  local cmd
  for cmd in python3 ethtool systemctl ip sha256sum install cmp awk flock hostname uname pgrep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "STOP-missing $cmd"
    fi
  done

  # This file cannot store its own sha256: the digest covers the constants
  # below. Copies land under /root, which aj cannot write, and sha_ok runs
  # on those copies. source uses the /root helper, not the cis-audit file.
  # The runbook table lists this file's full sha256.
  install -m 0755 -o root -g root "$HELPER_SRC" "$STAGE_HELPER"
  install -m 0755 -o root -g root "$POLICY_SRC" "$STAGE_POLICY"
  install -m 0644 -o root -g root "$UNIT_SRC" "$STAGE_UNIT"
  install -m 0755 -o root -g root "$REVERT_SRC" /root/step13-revert.sh
  sha_ok "$STAGE_HELPER" "$HELPER_SHA256" || die "STOP-hash $STAGE_HELPER"
  sha_ok "$STAGE_POLICY" "$POLICY_SHA256" || die "STOP-hash $STAGE_POLICY"
  sha_ok "$STAGE_UNIT" "$UNIT_SHA256" || die "STOP-hash $STAGE_UNIT"
  sha_ok /root/step13-revert.sh "$REVERT_SHA256" || die STOP-hash-revert
  revert_ready=1
  echo REVERT-READY

  # shellcheck source=etc/johnny/irq-affinity.sh
  source "$STAGE_HELPER"

  if [ "${SUDO_USER:-}" != "" ] && [ "${SUDO_USER}" != aj ]; then
    die STOP-user
  fi
  if [ -z "${SUDO_USER:-}" ]; then
    echo NOTE-no-sudo-user
  fi

  if [ -r /sys/kernel/security/lockdown ]; then
    LOCKDOWN_BEFORE=$(tr -d '[:space:]' < /sys/kernel/security/lockdown || true)
    echo "LOCKDOWN $LOCKDOWN_BEFORE"
  else
    LOCKDOWN_BEFORE=""
    echo NOTE-no-lockdown
  fi

  preflight || die STOP-preflight

  local irq_state=missing
  local env_tmp env_last
  UNIT_TMP=$(mktemp /root/step13-irqbalance.unit.XXXXXX)
  if ! systemctl cat irqbalance.service >"$UNIT_TMP" 2>/dev/null; then
    if pgrep -x irqbalance >/dev/null 2>&1; then
      die STOP-irqbalance-unknown
    fi
    echo NOTE-no-irqbalance
    irq_state=missing
  else
    if unit_interest_lines "$UNIT_TMP" | grep -q '^STOP-irqbalance-env$'; then
      die STOP-irqbalance-env
    fi
    env_last=$(unit_interest_lines "$UNIT_TMP" | awk 'END{print}')
    if [ "$env_last" != "$DEFAULT" ]; then
      echo "STOP-irqbalance-env ${env_last:-none}"
      die STOP-irqbalance-env
    fi
    if [ -L "$DEFAULT" ] || [ ! -f "$DEFAULT" ]; then
      die STOP-irqbalance-file
    fi
    irq_state=$(systemctl is-active irqbalance.service || true)
    echo "IRQBALANCE-STATE $irq_state"
    case "$irq_state" in
      active|inactive|failed) ;;
      *) die "STOP-irqbalance-state $irq_state" ;;
    esac
    local py_out py_rc
    set +e
    py_out=$(irqbalance_edit check "$DEFAULT")
    py_rc=$?
    set -e
    case "$py_rc" in
      0) echo "IRQBALANCE-PLAN $py_out" ;;
      2|3) die STOP-irqbalance-args ;;
      4) die STOP-irqbalance-banned ;;
      *) die "STOP-irqbalance-edit $py_rc" ;;
    esac
  fi

  local qbefore
  qbefore=$(snapshot_queues QUEUES)
  printf '%s\n' "$qbefore"
  ENO2SNAP=$(mktemp /var/lib/johnny/step13-eno2-pre.XXXXXX)
  snapshot_eno2 "$ENO2SNAP" || die STOP-eno2-snap

  prepare_map || die STOP-map
  local i
  for i in "${!ENO1_IRQS[@]}"; do
    if [ ! -w "/proc/irq/${ENO1_IRQS[$i]}/smp_affinity_list" ]; then
      die "STOP-affinity-ro ${ENO1_IRQS[$i]}"
    fi
  done
  if [ ! -f "$BEFORE" ]; then
    : > "$BEFORE"
    for i in "${!ENO1_IRQS[@]}"; do
      if [ ! -e "/proc/irq/${ENO1_IRQS[$i]}/smp_affinity_list" ]; then
        echo "NOTE-eno1-unrequested ${ENO1_IRQS[$i]}"
        continue
      fi
      printf '%s|%s|%s\n' "${ENO1_IRQS[$i]}" "$(read_affinity "${ENO1_IRQS[$i]}")" "${ENO1_NAMES[$i]}" >> "$BEFORE"
    done
    while IFS='|' read -r irq list name || [ -n "${irq:-}" ]; do
      [ -n "${irq:-}" ] || continue
      [ -n "$list" ] || continue
      printf '%s|%s|%s\n' "$irq" "$list" "${name:-NONAME}" >> "$BEFORE"
    done < "$ENO2SNAP"
    chmod 0644 "$BEFORE"
    echo AFFINITY-BACKUP
    mark_changed
  else
    echo BACKUP-KEPT
  fi

  install_if_diff() {
    local mode=$1 src=$2 dest=$3 have want
    mkdir -p "$(dirname "$dest")"
    want=${mode#0}
    if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest"; then
      have=$(stat -c %a "$dest")
      if [ "$have" = "$want" ]; then
        echo "KEPT $dest"
        return 0
      fi
    fi
    install -m "$mode" -o root -g root "$src" "$dest"
    mark_changed
    echo "INSTALLED $dest"
  }
  install_if_diff 0755 "$STAGE_HELPER" /etc/johnny/irq-affinity.sh
  install_if_diff 0755 "$STAGE_POLICY" /etc/johnny/irqbalance-policy.sh
  install_if_diff 0644 "$STAGE_UNIT" /etc/systemd/system/johnny-capture-irq.service
  sha_ok /etc/johnny/irq-affinity.sh "$HELPER_SHA256" || die STOP-install-hash
  sha_ok /etc/johnny/irqbalance-policy.sh "$POLICY_SHA256" || die STOP-install-hash
  sha_ok /etc/systemd/system/johnny-capture-irq.service "$UNIT_SHA256" || die STOP-install-hash

  systemctl daemon-reload
  if [ "$(systemctl is-enabled johnny-capture-irq.service 2>/dev/null || true)" != enabled ]; then
    systemctl enable johnny-capture-irq.service
    mark_changed
    echo UNIT-ENABLED
  else
    echo UNIT-ALREADY-ENABLED
  fi

  if [ "$irq_state" != missing ]; then
    printf '%s\n' "$irq_state" > "$WAS"
    chmod 0644 "$WAS"
    if [ ! -f "$IRQ_BAK" ]; then
      cp -a "$DEFAULT" "$IRQ_BAK"
      echo BACKUP-IRQBALANCE
    else
      echo IRQBALANCE-BACKUP-KEPT
    fi
    set +e
    py_out=$(irqbalance_edit write "$DEFAULT")
    py_rc=$?
    set -e
    case "$py_rc" in
      0) echo "IRQBALANCE-EDIT $py_out" ;;
      *) die "STOP-irqbalance-edit $py_rc" ;;
    esac
    if [ "$py_out" = WROTE-irqbalance ]; then
      mark_changed
    fi
    if [ "$irq_state" = active ]; then
      if ! irqbalance_cmd_ok; then
        systemctl restart irqbalance.service
        mark_changed
        echo IRQBALANCE-RESTARTED
      fi
      local n
      for n in 1 2 3 4 5; do
        if irqbalance_cmd_ok; then
          echo IRQBALANCE-CMD-OK
          break
        fi
        if [ "$n" -eq 5 ]; then
          die STOP-irqbalance-cmd
        fi
        sleep 1
      done
    else
      echo NOTE-irqbalance-inactive
    fi
  fi

  if map_needs_write; then
    mark_changed
    echo PIN-NEEDED
  else
    echo PIN-ALREADY
  fi

  /etc/johnny/irq-affinity.sh apply

  eno2_unchanged "$ENO2SNAP" || die STOP-eno2-irq-moved
  eno3_ok || die STOP-eno3
  local qafter
  qafter=$(snapshot_queues QUEUES)
  queues_unchanged "$qbefore" "$qafter" || die STOP-queues-changed

  if [ "$irq_state" = active ]; then
    echo IRQBALANCE-WAIT 12
    sleep 12
    if [ "${#ENO1_IRQS[@]}" -lt 1 ]; then
      die STOP-irq-held-empty
    fi
    if map_needs_write; then
      local held_i held_got
      for held_i in "${!ENO1_IRQS[@]}"; do
        held_got=$(read_affinity "${ENO1_IRQS[$held_i]}")
        if ! affinity_is_cpu "$held_got" "${ENO1_CPUS[$held_i]}"; then
          echo "STOP-irq-held ${ENO1_IRQS[$held_i]} ${ENO1_NAMES[$held_i]} want ${ENO1_CPUS[$held_i]} got ${held_got}"
        fi
      done
      die STOP-irq-held
    fi
    eno2_unchanged "$ENO2SNAP" || die STOP-eno2-irq-moved
    eno3_ok || die STOP-eno3
    qafter=$(snapshot_queues QUEUES)
    queues_unchanged "$qbefore" "$qafter" || die STOP-queues-changed
    irqbalance_cmd_ok || die STOP-irqbalance-cmd
    echo IRQ-HELD
  fi

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
  if [ "$this_run_changed" -eq 0 ]; then
    echo ALREADY-APPLIED
  fi
  echo STEP13-IRQ-DONE
}

irqbalance_cmd_ok() {
  local pid cmd
  pid=$(systemctl show -p MainPID --value irqbalance.service || true)
  [ -n "$pid" ] && [ "$pid" != 0 ] || return 1
  [ -r "/proc/${pid}/cmdline" ] || return 1
  cmd=$(tr '\0' '\n' < "/proc/${pid}/cmdline" || true)
  printf '%s\n' "$cmd" | grep -q 'irqbalance' || return 1
  printf '%s\n' "$cmd" | grep -Fxq -- "$POLICY_ARG" || return 1
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
