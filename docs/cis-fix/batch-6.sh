#!/bin/bash
# CIS L1 Batch 6. The deliverable AJ runs from SSH, no argument, is PASTE 1 only:
#   sudo bash ~/cis-audit/batch-6.sh
# PASTE 2 is the KVM lockout path and does not run unless AJ passes 2:
#   sudo bash ~/cis-audit/batch-6.sh 2
# Rollback: docs/cis-fix/batch-6.md ## Rollback.

set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo STOP-args
  exit 1
fi
paste=1
if [ "$#" -eq 1 ]; then
  paste=$1
fi
case "$paste" in
  1|2) ;;
  *)
    echo STOP-args
    exit 1
    ;;
esac

if [ "$paste" = 1 ]; then
# PASTE 1
# RUNS IN: SSH
set -euo pipefail
# Rollback: docs/cis-fix/batch-6.md ## Rollback.
# A failed enable in this paste runs `ufw --force disable` and leaves
# johnny-ufw-rollback.timer armed. KVM lockout is PASTE 2.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

SSH_RULE='ufw allow in on eno3 from 192.168.50.0/24 to any port 22 proto tcp'
SSH_IPT='-A ufw-user-input -i eno3 -p tcp --dport 22 -s 192.168.50.0/24 -j ACCEPT'
UFW_SYSCTL=/etc/ufw/sysctl.conf
JOHNNY=/etc/sysctl.d/60-johnny-cis-network.conf
DHCP_LINE='-A ufw-before-input -p udp --sport 67 --dport 68 -j ACCEPT'
ESTAB_LINE='-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT'

enabled_this_run=0
rollback_armed=0
timer_active=0

backup_once() {
  src=$1
  dest=$2
  if [ -e "$dest" ]; then
    echo "BACKUP-KEPT $dest"
    return 0
  fi
  if [ ! -e "$src" ]; then
    echo "STOP-backup-missing $src"
    exit 1
  fi
  if ! cp -a "$src" "$dest"; then
    echo "STOP-backup $src"
    exit 1
  fi
  echo "BACKUP $dest"
}

rule_present() {
  if ! ufw show added | grep -Fx -- "$SSH_RULE" >/dev/null; then
    return 1
  fi
  if ! grep -Fx -- "$SSH_IPT" /etc/ufw/user.rules >/dev/null; then
    return 1
  fi
  return 0
}

die() {
  echo "$1"
  if [ "$enabled_this_run" -eq 1 ]; then
    ufw --force disable || true
    echo 'ROLLBACK-DISABLE The enable from this run was reversed. johnny-ufw-rollback.timer stays armed.'
  fi
  exit 1
}

arm_rollback() {
  if [ "$rollback_armed" -eq 1 ] || [ "$timer_active" -eq 1 ]; then
    rollback_armed=1
    echo ROLLBACK-ARMED
    return 0
  fi
  if [ ! -x /usr/bin/systemd-run ]; then
    echo STOP-systemd-run
    exit 1
  fi
  if systemctl is-active --quiet johnny-ufw-rollback.timer; then
    echo STOP-rollback-timer-exists
    exit 1
  fi
  if ! arm_out=$(systemd-run --unit=johnny-ufw-rollback --on-active=5min /usr/sbin/ufw --force disable); then
    echo STOP-rollback-arm
    exit 1
  fi
  printf '%s\n' "$arm_out"
  if ! systemctl is-active --quiet johnny-ufw-rollback.timer; then
    echo STOP-rollback-timer
    systemctl stop johnny-ufw-rollback.timer || true
    systemctl stop johnny-ufw-rollback.service || true
    exit 1
  fi
  timer_active=1
  rollback_armed=1
  echo ROLLBACK-ARMED
}

ufw_path=$(command -v ufw || true)
if [ "$ufw_path" != /usr/sbin/ufw ]; then
  echo "STOP-ufw-path ${ufw_path:-missing}"
  exit 1
fi

if ! ufw_status=$(ufw status); then
  echo STOP-ufw-status
  exit 1
fi
if printf '%s\n' "$ufw_status" | grep -qx 'Status: active'; then
  ufw_active=1
elif printf '%s\n' "$ufw_status" | grep -qx 'Status: inactive'; then
  ufw_active=0
else
  echo STOP-ufw-status
  printf '%s\n' "$ufw_status"
  exit 1
fi

if grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf; then
  enabled_file=yes
elif grep -qx 'ENABLED=no' /etc/ufw/ufw.conf; then
  enabled_file=no
else
  echo STOP-ufw-enabled-file
  exit 1
fi

if grep -qx 'DEFAULT_INPUT_POLICY="DROP"' /etc/default/ufw; then
  input_drop=1
else
  input_drop=0
fi
if ! grep -qx 'DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
  echo STOP-forward-policy
  exit 1
fi
if ! grep -qx 'DEFAULT_OUTPUT_POLICY="ACCEPT"' /etc/default/ufw; then
  echo STOP-output-policy
  exit 1
fi
if ! grep -qx 'IPV6=yes' /etc/default/ufw; then
  echo STOP-ipv6-policy
  exit 1
fi

log_all=$(sysctl -n net.ipv4.conf.all.log_martians)
log_default=$(sysctl -n net.ipv4.conf.default.log_martians)
ip_forward=$(sysctl -n net.ipv4.ip_forward)

if systemctl is-active --quiet johnny-ufw-rollback.timer; then
  timer_active=1
  rollback_armed=1
fi

echo "STATE ufw_active=$ufw_active enabled_file=$enabled_file input_drop=$input_drop log_all=$log_all log_default=$log_default ip_forward=$ip_forward timer_active=$timer_active"

if [ "$timer_active" -eq 1 ] && [ "$ufw_active" -eq 0 ]; then
  echo STOP-rollback-timer-pending
  echo 'johnny-ufw-rollback.timer is active and ufw is inactive.'
  echo 'Stop that timer only when a working session is about to retry this script:'
  echo 'sudo systemctl stop johnny-ufw-rollback.timer'
  exit 1
fi

if [ "$ufw_active" -eq 1 ] && [ "$enabled_file" != yes ]; then
  echo STOP-ufw-enabled-mismatch
  exit 1
fi
if [ "$ufw_active" -eq 0 ] && [ "$enabled_file" != no ]; then
  echo STOP-ufw-enabled-mismatch
  exit 1
fi

if ! ip link show dev eno3 >/dev/null 2>&1; then
  echo STOP-eno3
  exit 1
fi
if ! ip link show dev eno1np0 >/dev/null 2>&1; then
  echo STOP-eno1np0
  exit 1
fi
if ! grep -qx -- "$DHCP_LINE" /etc/ufw/before.rules; then
  echo STOP-dhcp
  exit 1
fi
if ! grep -qx -- "$ESTAB_LINE" /etc/ufw/before.rules; then
  echo STOP-established
  exit 1
fi

# log_martians. Skip when Paste 1 already landed.
if [ ! -f "$UFW_SYSCTL" ]; then
  echo STOP-ufw-sysctl-missing
  exit 1
fi
active_count=$(grep -Ec '^[[:space:]]*([^#[:space:]].*)?log_martians' "$UFW_SYSCTL" || true)
if [ "$active_count" -eq 0 ]; then
  if ! grep -qx '# net/ipv4/conf/all/log_martians=0' "$UFW_SYSCTL" \
     || ! grep -qx '# net/ipv4/conf/default/log_martians=0' "$UFW_SYSCTL"; then
    echo STOP-ufw-sysctl-comment
    exit 1
  fi
  echo SKIP-ufw-sysctl-comment
elif [ "$active_count" -eq 2 ] \
   && grep -qx 'net/ipv4/conf/all/log_martians=0' "$UFW_SYSCTL" \
   && grep -qx 'net/ipv4/conf/default/log_martians=0' "$UFW_SYSCTL"; then
  backup_once "$UFW_SYSCTL" /root/ufw.sysctl.conf.pre-batch6
  sed -i 's|^net/ipv4/conf/all/log_martians=0$|# net/ipv4/conf/all/log_martians=0|' "$UFW_SYSCTL"
  sed -i 's|^net/ipv4/conf/default/log_martians=0$|# net/ipv4/conf/default/log_martians=0|' "$UFW_SYSCTL"
  active_count=$(grep -Ec '^[[:space:]]*([^#[:space:]].*)?log_martians' "$UFW_SYSCTL" || true)
  if [ "$active_count" -ne 0 ] \
     || ! grep -qx '# net/ipv4/conf/all/log_martians=0' "$UFW_SYSCTL" \
     || ! grep -qx '# net/ipv4/conf/default/log_martians=0' "$UFW_SYSCTL"; then
    echo STOP-ufw-sysctl-comment
    exit 1
  fi
else
  echo STOP-ufw-sysctl-active
  exit 1
fi

if [ ! -f "$JOHNNY" ]; then
  echo STOP-johnny-missing
  exit 1
fi
all_n=$(grep -c '^net.ipv4.conf.all.log_martians' "$JOHNNY" || true)
def_n=$(grep -c '^net.ipv4.conf.default.log_martians' "$JOHNNY" || true)
if [ "$all_n" -eq 1 ] && [ "$def_n" -eq 1 ] \
   && grep -qx 'net.ipv4.conf.all.log_martians = 1' "$JOHNNY" \
   && grep -qx 'net.ipv4.conf.default.log_martians = 1' "$JOHNNY"; then
  echo SKIP-log-martians-file
elif [ "$all_n" -eq 0 ] && [ "$def_n" -eq 0 ]; then
  backup_once "$JOHNNY" /root/60-johnny-cis-network.conf.pre-batch6
  last=$(tail -c 1 "$JOHNNY" | od -An -tu1 | tr -d '[:space:]')
  if [ "$last" != 10 ]; then
    echo STOP-johnny-no-newline
    exit 1
  fi
  printf '%s\n' '# 3.3.1.16 and 3.3.1.17. The matching lines in /etc/ufw/sysctl.conf are commented so ufw enable does not force 0.' \
    'net.ipv4.conf.all.log_martians = 1' \
    'net.ipv4.conf.default.log_martians = 1' >> "$JOHNNY"
else
  echo STOP-log-martians-file
  exit 1
fi

log_all=$(sysctl -n net.ipv4.conf.all.log_martians)
log_default=$(sysctl -n net.ipv4.conf.default.log_martians)
if [ "$log_all" = 1 ] && [ "$log_default" = 1 ]; then
  echo SKIP-log-martians-running
else
  if [ "$ip_forward" != 0 ]; then
    echo STOP-ip-forward
    exit 1
  fi
  if ! sysctl -p "$JOHNNY" >/dev/null; then
    echo STOP-sysctl-apply
    exit 1
  fi
  log_all=$(sysctl -n net.ipv4.conf.all.log_martians)
  log_default=$(sysctl -n net.ipv4.conf.default.log_martians)
  if [ "$log_all" != 1 ] || [ "$log_default" != 1 ]; then
    echo STOP-log-martians-running
    exit 1
  fi
fi

ss_out=$(ss -Htn state established '( sport = :22 )')
outsider=0
peer_n=0
if [ -n "$ss_out" ]; then
  while read -r recvq sendq local peer extra; do
    [ -n "${peer:-}" ] || continue
    echo "SSH-SOCK local=$local peer=$peer"
    peer_host=${peer%:*}
    case "$peer_host" in
      192.168.50.152)
        echo "NOTE-ssh-self $peer_host"
        ;;
      192.168.50.*)
        peer_n=$((peer_n + 1))
        echo "SSH-PEER $peer_host"
        ;;
      *)
        outsider=1
        echo "NOTE-ssh-peer $peer_host"
        ;;
    esac
  done <<< "$ss_out"
fi
echo "SSH-PEER-COUNT $peer_n"

# SSH allow is staged and verified before any default deny and before enable.
if rule_present; then
  echo SKIP-ssh-rule
else
  if [ "$ufw_active" -eq 1 ] && [ "$outsider" -eq 1 ]; then
    echo STOP-ssh-peer
    exit 1
  fi
  backup_once /etc/ufw/user.rules /root/ufw.user.rules.pre-batch6
  backup_once /etc/ufw/user6.rules /root/ufw.user6.rules.pre-batch6
  if ! ufw allow in on eno3 from 192.168.50.0/24 to any port 22 proto tcp; then
    echo STOP-ssh-rule-add
    exit 1
  fi
  echo RULE-ADDED
fi
if ! rule_present; then
  ufw show added || true
  echo STOP-ssh-rule
  exit 1
fi
echo SSH-RULE-OK

# No `ufw default deny` and no `ufw --force enable` run before SSH-RULE-OK.
if [ "$input_drop" -eq 1 ]; then
  echo SKIP-input-policy
else
  if [ "$ufw_active" -eq 1 ] && [ "$outsider" -eq 1 ]; then
    echo STOP-ssh-peer
    exit 1
  fi
  backup_once /etc/default/ufw /root/default.ufw.pre-batch6
  if [ "$ufw_active" -eq 1 ]; then
    arm_rollback
  fi
  if ! ufw default deny incoming; then
    echo STOP-input-policy
    exit 1
  fi
  if ! grep -qx 'DEFAULT_INPUT_POLICY="DROP"' /etc/default/ufw; then
    echo STOP-input-policy
    exit 1
  fi
  echo INPUT-POLICY-SET
fi

if [ "$ufw_active" -eq 0 ]; then
  if [ "$outsider" -eq 1 ]; then
    echo STOP-ssh-peer
    exit 1
  fi
  if ip -4 addr show dev eno1np0 | grep 'inet ' >/dev/null; then
    echo STOP-eno1np0-addr
    exit 1
  fi
  if ! rule_present; then
    echo STOP-ssh-rule
    exit 1
  fi
  arm_rollback
  backup_once /etc/ufw/ufw.conf /root/ufw.conf.pre-batch6
  if ! ufw --force enable; then
    echo STOP-ufw-enable
    exit 1
  fi
  enabled_this_run=1
  echo UFW-ENABLED
else
  echo SKIP-enable
fi

log_all=$(sysctl -n net.ipv4.conf.all.log_martians)
log_default=$(sysctl -n net.ipv4.conf.default.log_martians)
if [ "$log_all" != 1 ] || [ "$log_default" != 1 ]; then
  if [ "$(sysctl -n net.ipv4.ip_forward)" != 0 ]; then
    die STOP-ip-forward
  fi
  if ! sysctl -p "$JOHNNY" >/dev/null; then
    die STOP-sysctl-apply
  fi
  log_all=$(sysctl -n net.ipv4.conf.all.log_martians)
  log_default=$(sysctl -n net.ipv4.conf.default.log_martians)
fi

if ! ufw_status=$(ufw status); then
  die STOP-ufw-status
fi
if ! ufw_verbose=$(ufw status verbose); then
  die STOP-ufw-status
fi

echo '=== VERIFY ==='
printf '%s\n' "$ufw_verbose"
echo '=== SHOW ADDED ==='
ufw show added || true
echo "log_martians_all=$log_all"
echo "log_martians_default=$log_default"
grep -n log_martians "$UFW_SYSCTL" || true
grep -n log_martians "$JOHNNY" || true
echo -n 'rollback-timer '
systemctl is-active johnny-ufw-rollback.timer || true
ip -br link show eno1np0
ip -br addr show eno1np0
echo BEGIN-user.rules
cat /etc/ufw/user.rules
echo END-user.rules
echo BEGIN-user6.rules
cat /etc/ufw/user6.rules
echo END-user6.rules
sha256sum /etc/ufw/ufw.conf /etc/ufw/user.rules /etc/ufw/user6.rules "$UFW_SYSCTL" "$JOHNNY" /etc/default/ufw
echo '=== END VERIFY ==='

if ! printf '%s\n' "$ufw_verbose" | grep -qx 'Status: active'; then
  die STOP-ufw-not-active
fi
if ! printf '%s\n' "$ufw_verbose" | grep -F 'deny (incoming)' >/dev/null; then
  die STOP-input-runtime
fi
if printf '%s\n' "$ufw_verbose" | grep -F 'allow (routed)' >/dev/null; then
  die STOP-routed-allow
fi
if ! printf '%s\n' "$ufw_verbose" | grep -F 'disabled (routed)' >/dev/null \
   && ! printf '%s\n' "$ufw_verbose" | grep -F 'deny (routed)' >/dev/null; then
  die STOP-routed-missing
fi
if ! rule_present; then
  die STOP-ssh-rule-missing
fi
rule_line_ok=0
while IFS= read -r line; do
  case "$line" in
    *192.168.50.0/24*)
      case "$line" in
        *eno3*)
          case "$line" in
            *22*) rule_line_ok=1 ;;
          esac
          ;;
      esac
      ;;
  esac
  case "$line" in
    *22/tcp*' (v6)'*)
      echo "V6-SSH $line"
      die STOP-ipv6-ssh-allow
      ;;
  esac
done <<< "$ufw_verbose"
if [ "$rule_line_ok" -ne 1 ]; then
  die STOP-ssh-rule-missing
fi
if [ "$log_all" != 1 ] || [ "$log_default" != 1 ]; then
  die STOP-log-martians-after-enable
fi
if grep -Eq '^[[:space:]]*([^#[:space:]].*)?log_martians' "$UFW_SYSCTL"; then
  die STOP-ufw-sysctl-active
fi
if ! grep -qx 'DEFAULT_INPUT_POLICY="DROP"' /etc/default/ufw; then
  die STOP-input-policy
fi
if ! grep -qx 'DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
  die STOP-forward-policy
fi

if [ "$rollback_armed" -eq 1 ]; then
  echo 'Open a NEW ssh session from aj-rock-box to Johnny.'
  echo 'Only after that new session reaches a shell, cancel the timer:'
  echo 'sudo systemctl stop johnny-ufw-rollback.timer'
  echo 'If the new session fails, type PASTE 2 at the KVM console: sudo bash ~/cis-audit/batch-6.sh 2'
  echo 'The timer runs /usr/sbin/ufw --force disable about 5 minutes after it was armed.'
else
  echo SKIP-rollback-timer
  echo 'This run did not arm johnny-ufw-rollback.timer.'
fi

echo OK-batch-6
exit 0
fi

if [ "$paste" = 2 ]; then
# PASTE 2
# RUNS IN: KVM
set -euo pipefail
# Rollback: this paste is the lockout rollback. It forces ufw off and stops the timer.
# Full file restore is docs/cis-fix/batch-6.md ## Rollback.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi
ufw --force disable
systemctl stop johnny-ufw-rollback.timer || true
ufw status verbose || true
echo OK-kvm-disable
exit 0
fi
