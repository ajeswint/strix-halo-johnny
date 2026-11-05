#!/bin/bash
# CIS L1 Batch 8. The deliverable AJ runs from SSH:
#   sudo bash ~/cis-audit/batch-8.sh
#   sudo bash ~/cis-audit/batch-8.sh 2
# PASTE 3 is KVM recovery and does not run unless AJ passes 3:
#   sudo bash ~/cis-audit/batch-8.sh 3
# NO REBOOT. Does not restart ssh.socket. Does not edit GRUB.
# Rollback: docs/cis-fix/batch-8.md ## Rollback.

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
  1|2|3) ;;
  *)
    echo STOP-args
    exit 1
    ;;
esac

if [ "$paste" = 1 ]; then
# RUNS ON: JOHNNY (SSH)
# PASTE 1
# RUNS IN: SSH
set -euo pipefail
# Rollback: docs/cis-fix/batch-8.md ## Rollback.
# sshd revert is /root/batch8-sshd-revert.sh, also armed for 300s.
# sudo, environment, and pam_wheel are not inside that timer.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

SSHD=/etc/ssh/sshd_config
SSHD_DIR=/etc/ssh/sshd_config.d
DROPIN=$SSHD_DIR/00-johnny-cis.conf
CLOUD=$SSHD_DIR/50-cloud-init.conf
ENV=/etc/environment
SUDOERS=/etc/sudoers
TIMEOUT=/etc/sudoers.d/60-johnny-cis-timeout
PAMSU=/etc/pam.d/su
REVERT=/root/batch8-sshd-revert.sh
COUNTFILE=/run/johnny-batch8-ssh-count
BANNER='Authorized use only. Activity is monitored.'
SECURE_OLD='Defaults	secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"'
SECURE_NEW='Defaults	secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"'
WHEEL='auth required pam_wheel.so use_uid group=sugroup'
MACS='hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256'

backup_once() {
  src=$1
  dest=$2
  if [ -e "$dest" ]; then
    if ! cmp -s "$src" "$dest"; then
      echo "BACKUP-DIFFERS $dest"
      echo "The kept backup is not the current live file. Rollback restores this copy, not the file as it is now."
    fi
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

listen_v4_22() {
  ss -H -lnt sport = :22 | awk 'BEGIN { found = 0 } $4 == "0.0.0.0:22" { found = 1 } END { exit (found ? 0 : 1) }'
}

lan_ssh_count() {
  ss -H -tn sport = :22 | awk '$1=="ESTAB"{print $5}' | sed 's/:[0-9]*$//' | awk '
    $0 == "" { next }
    $0 == "192.168.50.152" { next }
    $0 ~ /^192\.168\.50\./ { n++; next }
    { print "STOP-ssh-peer " $0 > "/dev/stderr"; bad = 1 }
    END { if (bad) exit 2; print n+0 }
  '
}

sshd_ok() {
  t=$(sshd -T)
  printf '%s\n' "$t" | awk -v macs="$MACS" '
    $1=="allowusers" && $2=="aj" { a=1 }
    $1=="banner" && $2=="/etc/issue.net" { b=1 }
    $1=="clientaliveinterval" && $2=="15" { c=1 }
    $1=="clientalivecountmax" && $2=="3" { d=1 }
    $1=="disableforwarding" && $2=="yes" { e=1 }
    $1=="logingracetime" && $2=="60" { f=1 }
    $1=="macs" && $2==macs { g=1 }
    $1=="maxauthtries" && $2=="4" { h=1 }
    $1=="maxstartups" && $2=="10:30:60" { i=1 }
    $1=="permitrootlogin" && $2=="no" { j=1 }
    END { exit (a&&b&&c&&d&&e&&f&&g&&h&&i&&j ? 0 : 1) }
  '
}

write_dropin() {
  cat > "$DROPIN" <<EOF
# Johnny CIS batch 8. Lexical order before 50-cloud-init.conf.
AllowUsers aj
Banner /etc/issue.net
ClientAliveInterval 15
ClientAliveCountMax 3
DisableForwarding yes
LoginGraceTime 60
MACs $MACS
MaxAuthTries 4
MaxStartups 10:30:60
PermitRootLogin no
EOF
  chmod 0600 "$DROPIN"
}

echo "=== STATE ==="
ss -H -lnt sport = :22 || true
ss -H -tn sport = :22 || true
stat -c '%a %U %G %n' "$SSHD" "$SSHD_DIR" || true
ls -la "$SSHD_DIR" || true
echo "=== END STATE ==="

if ! listen_v4_22; then
  echo STOP-no-v4-ssh
  exit 1
fi
set +e
lan=$(lan_ssh_count)
lan_rc=$?
set -e
if [ "$lan_rc" -ne 0 ]; then
  exit 1
fi
if [ "$lan" -lt 2 ]; then
  echo STOP-need-two-lan-ssh
  exit 1
fi
echo "LAN-SSH $lan"

if [ "$(head -n 1 /etc/issue.net)" != "$BANNER" ] || [ "$(wc -l < /etc/issue.net)" -ne 1 ]; then
  echo STOP-banner
  exit 1
fi
if [ ! -f "$CLOUD" ]; then
  echo STOP-cloud-init-missing
  exit 1
fi

if getent group sugroup >/dev/null; then
  members=$(getent group sugroup | awk -F: '{print $4}')
  if [ -n "$members" ]; then
    echo STOP-sugroup-members
    exit 1
  fi
fi

if grep -q snap "$ENV"; then
  if ! grep -Fq ':/snap/bin"' "$ENV"; then
    echo STOP-environment
    exit 1
  fi
fi

# --- 5.4.2.5 environment, before pam_wheel ---
backup_once "$ENV" /root/environment.pre-batch8
if grep -Fq ':/snap/bin"' "$ENV"; then
  tmp=$(mktemp)
  sed 's#:\/snap\/bin"#"#' "$ENV" > "$tmp"
  if grep -q snap "$tmp"; then
    rm -f "$tmp"
    echo STOP-environment
    exit 1
  fi
  cat "$tmp" > "$ENV"
  rm -f "$tmp"
  echo WROTE-environment
else
  echo SKIP-environment
fi

# --- 5.4.2.5 secure_path and 5.2.6 ---
backup_once "$SUDOERS" /root/sudoers.pre-batch8
if grep -Fq "$SECURE_NEW" "$SUDOERS"; then
  echo SKIP-secure-path
elif grep -Fq "$SECURE_OLD" "$SUDOERS"; then
  tmp=$(mktemp)
  sed "s#$SECURE_OLD#$SECURE_NEW#" "$SUDOERS" > "$tmp"
  if ! visudo -c -f "$tmp"; then
    rm -f "$tmp"
    echo STOP-visudo
    exit 1
  fi
  install -m 0440 -o root -g root "$tmp" "$SUDOERS"
  rm -f "$tmp"
  echo WROTE-secure-path
else
  echo STOP-secure-path
  exit 1
fi

if [ -f "$TIMEOUT" ]; then
  if ! cmp -s - "$TIMEOUT" <<'EOF'
Defaults timestamp_timeout=15
EOF
  then
    echo STOP-timestamp
    exit 1
  fi
  echo SKIP-timestamp
else
  tmp=$(mktemp)
  printf '%s\n' 'Defaults timestamp_timeout=15' > "$tmp"
  if ! visudo -c -f "$tmp"; then
    rm -f "$tmp"
    echo STOP-visudo
    exit 1
  fi
  install -m 0440 -o root -g root "$tmp" "$TIMEOUT"
  rm -f "$tmp"
  echo WROTE-timestamp
fi
if ! visudo -c; then
  echo STOP-visudo
  exit 1
fi

# PATH check while su still works, then 5.2.7.
path_now=$(su - root -c 'printf %s "$PATH"')
echo "ROOT-PATH $path_now"
case "$path_now" in
  *snap*)
    echo STOP-root-path
    exit 1
    ;;
esac
IFS=':' read -ra path_elems <<< "$path_now"
if [ "${#path_elems[@]}" -eq 0 ]; then
  echo STOP-root-path
  exit 1
fi
for el in "${path_elems[@]}"; do
  if [ ! -d "$el" ]; then
    echo "STOP-root-path $el"
    exit 1
  fi
done

if getent group sugroup >/dev/null; then
  echo SKIP-group
else
  groupadd --system sugroup
  echo WROTE-group
fi
members=$(getent group sugroup | awk -F: '{print $4}')
if [ -n "$members" ]; then
  echo STOP-sugroup-members
  exit 1
fi

backup_once "$PAMSU" /root/pam-su.pre-batch8
if grep -Eq '^[[:space:]]*auth[[:space:]]+(required|requisite)[[:space:]]+pam_wheel\.so' "$PAMSU"; then
  if grep -Fxq "$WHEEL" "$PAMSU"; then
    echo SKIP-pam-wheel
  else
    echo STOP-pam-wheel
    exit 1
  fi
else
  printf '\n%s\n' "$WHEEL" >> "$PAMSU"
  echo WROTE-pam-wheel
fi
members=$(getent group sugroup | awk -F: '{print $4}')
if [ -n "$members" ]; then
  echo STOP-sugroup-members
  exit 1
fi

# --- sshd. Timer stays armed until PASTE 2. ---
if systemctl is-active --quiet johnny-cis-batch8-revert.timer; then
  echo STOP-timer-armed
  exit 1
fi

dirmode=$(stat -c '%a' "$SSHD_DIR")
filemode=$(stat -c '%a' "$SSHD")
dropin_match=0
if [ -f "$DROPIN" ]; then
  if cmp -s - "$DROPIN" <<EOF
# Johnny CIS batch 8. Lexical order before 50-cloud-init.conf.
AllowUsers aj
Banner /etc/issue.net
ClientAliveInterval 15
ClientAliveCountMax 3
DisableForwarding yes
LoginGraceTime 60
MACs $MACS
MaxAuthTries 4
MaxStartups 10:30:60
PermitRootLogin no
EOF
  then
    dropin_match=1
  else
    echo STOP-sshd-dropin
    exit 1
  fi
fi

if [ "$filemode" = 600 ] && [ "$dirmode" = 700 ] && [ "$dropin_match" -eq 1 ] && sshd_ok; then
  echo SKIP-sshd-reload
  echo OK-batch-8
  exit 0
fi

backup_once "$SSHD" /root/sshd_config.pre-batch8
cat > "$REVERT" <<EOF
#!/bin/bash
set -euo pipefail
cp -a /root/sshd_config.pre-batch8 $SSHD
rm -f $DROPIN
chmod $dirmode $SSHD_DIR
sshd -t
systemctl reload ssh.service
EOF
chmod 0700 "$REVERT"

chmod 0600 "$SSHD"
chmod 0700 "$SSHD_DIR"
write_dropin
if ! sshd -t; then
  bash "$REVERT" || true
  echo STOP-sshd-t
  exit 1
fi
if ! sshd_ok; then
  bash "$REVERT" || true
  echo STOP-sshd-T
  exit 1
fi

printf '%s\n' "$lan" > "$COUNTFILE"
systemd-run --on-active=300s --unit=johnny-cis-batch8-revert "$REVERT"
systemctl reload ssh.service

if ! listen_v4_22; then
  systemctl stop johnny-cis-batch8-revert.timer || true
  bash "$REVERT" || true
  echo STOP-ssh-after-reload
  exit 1
fi
set +e
lan2=$(lan_ssh_count)
lan2_rc=$?
set -e
if [ "$lan2_rc" -ne 0 ] || [ "$lan2" -lt 2 ] || ! sshd_ok; then
  systemctl stop johnny-cis-batch8-revert.timer || true
  bash "$REVERT" || true
  echo STOP-ssh-after-reload
  exit 1
fi
echo "TIMER-ARMED 300"
echo "Open a new SSH session from 192.168.50.0/24 and leave this one up."
echo "Within 300 seconds run: sudo bash ~/cis-audit/batch-8.sh 2"
echo OK-batch-8-pending
exit 0
fi

if [ "$paste" = 2 ]; then
# RUNS ON: JOHNNY (SSH)
# PASTE 2
# RUNS IN: SSH
set -euo pipefail
# Rollback: docs/cis-fix/batch-8.md ## Rollback.
# Disarms the revert timer after a new LAN session is present.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

MACS='hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256'
COUNTFILE=/run/johnny-batch8-ssh-count

if ! systemctl is-active --quiet johnny-cis-batch8-revert.timer; then
  echo STOP-timer-not-armed
  exit 1
fi
if [ ! -f "$COUNTFILE" ]; then
  echo STOP-no-count
  exit 1
fi
prev=$(cat "$COUNTFILE")
set +e
now=$(ss -H -tn sport = :22 | awk '$1=="ESTAB"{print $5}' | sed 's/:[0-9]*$//' | awk '
  $0 == "" { next }
  $0 == "192.168.50.152" { next }
  $0 ~ /^192\.168\.50\./ { n++; next }
  { print "STOP-ssh-peer " $0 > "/dev/stderr"; bad = 1 }
  END { if (bad) exit 2; print n+0 }
')
now_rc=$?
set -e
if [ "$now_rc" -ne 0 ]; then
  exit 1
fi
if ! ss -H -lnt sport = :22 | awk 'BEGIN { found = 0 } $4 == "0.0.0.0:22" { found = 1 } END { exit (found ? 0 : 1) }'; then
  echo STOP-no-v4-ssh
  exit 1
fi
sshd -T | awk -v macs="$MACS" '
  $1=="allowusers" && $2=="aj" { a=1 }
  $1=="banner" && $2=="/etc/issue.net" { b=1 }
  $1=="clientaliveinterval" && $2=="15" { c=1 }
  $1=="clientalivecountmax" && $2=="3" { d=1 }
  $1=="disableforwarding" && $2=="yes" { e=1 }
  $1=="logingracetime" && $2=="60" { f=1 }
  $1=="macs" && $2==macs { g=1 }
  $1=="maxauthtries" && $2=="4" { h=1 }
  $1=="maxstartups" && $2=="10:30:60" { i=1 }
  $1=="permitrootlogin" && $2=="no" { j=1 }
  END { exit (a&&b&&c&&d&&e&&f&&g&&h&&i&&j ? 0 : 1) }
' || { echo STOP-sshd-T; exit 1; }
if [ "$now" -le "$prev" ]; then
  echo "STOP-no-new-session prev=$prev now=$now"
  exit 1
fi
systemctl stop johnny-cis-batch8-revert.timer
echo "LAN-SSH $now"
echo OK-batch-8
exit 0
fi

# RUNS ON: JOHNNY (KVM)
# PASTE 3
# RUNS IN: KVM
set -euo pipefail
# Rollback: docs/cis-fix/batch-8.md ## Rollback.
# Use only if PASTE 1 left no IPv4 SSH. Restores sshd only.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

systemctl stop johnny-cis-batch8-revert.timer 2>/dev/null || true
systemctl stop johnny-cis-batch8-revert.service 2>/dev/null || true
if [ ! -f /root/batch8-sshd-revert.sh ]; then
  echo STOP-no-revert
  exit 1
fi
bash /root/batch8-sshd-revert.sh
if ! ss -H -lnt sport = :22 | awk 'BEGIN { found = 0 } $4 == "0.0.0.0:22" { found = 1 } END { exit (found ? 0 : 1) }'; then
  echo STOP-no-v4-ssh
  exit 1
fi
echo OK-paste-3
exit 0
