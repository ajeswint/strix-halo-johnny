#!/bin/bash
# CIS L1 Batch 9. The deliverable AJ runs from SSH:
#   sudo bash ~/cis-audit/batch-9.sh
#   sudo bash ~/cis-audit/batch-9.sh 2
# PASTE 3 is KVM recovery and does not run unless AJ passes 3:
#   sudo bash ~/cis-audit/batch-9.sh 3
# NO REBOOT.
# Rollback: docs/cis-fix/batch-9.md ## Rollback.

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

TAR=/root/batch9-pam-security.tar
REVERT=/root/batch9-revert.sh
CHAGE_BEFORE=/root/batch9-chage.before
PEERS=/run/johnny-batch9-ssh-peers
UNIT=johnny-cis-batch9-revert
PROFILES=/usr/share/pam-configs
PWQ_DIR=/etc/security/pwquality.conf.d
PWQ=$PWQ_DIR/60-johnny-cis.conf
SHELL_DROP=/etc/profile.d/60-johnny-cis-shell.sh
FAILLOCK=/etc/security/faillock.conf
PWHIST=/etc/security/pwhistory.conf
LOGIN=/etc/login.defs

backup_tar_once() {
  if [ -e "$TAR" ]; then
    echo "BACKUP-KEPT $TAR"
    return 0
  fi
  if ! tar -C / -czf "$TAR" etc/pam.d etc/security etc/login.defs etc/default/useradd; then
    echo STOP-backup
    exit 1
  fi
  echo "BACKUP $TAR"
}

write_revert() {
  cat > "$REVERT" << 'EOF'
#!/bin/bash
# Rollback helper for CIS batch 9. Restores the pre-change tar of
# /etc/pam.d and /etc/security (plus login.defs and useradd defaults),
# drops the profiles this batch added, and clears aj's faillock.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
TAR=/root/batch9-pam-security.tar
CHAGE_BEFORE=/root/batch9-chage.before
if [ ! -f "$TAR" ]; then
  echo STOP-no-tar
  exit 1
fi
tar -C / -xzf "$TAR"
# Stock common-* is back on disk. Clear faillock before anything else so a
# later non-zero exit cannot leave aj locked.
faillock --user aj --reset || true
# The tar no longer matches pam-auth-update's recorded md5sums. --force is
# required or it exits "locally modified" under set -e and skips the rest.
# A failure here is non-fatal: the extracted common-* is already the stock stack.
if [ -f /usr/share/pam-configs/unix ]; then
  pam-auth-update --force --disable johnny-unix pwquality faillock-preauth faillock-authfail faillock-authsucc pwhistory --enable unix \
    || echo WARN-pam-auth-update
fi
rm -f /usr/share/pam-configs/johnny-unix \
  /usr/share/pam-configs/faillock-preauth \
  /usr/share/pam-configs/faillock-authfail \
  /usr/share/pam-configs/faillock-authsucc \
  /usr/share/pam-configs/pwhistory \
  /etc/security/pwquality.conf.d/60-johnny-cis.conf \
  /etc/profile.d/60-johnny-cis-shell.sh
rmdir /etc/security/pwquality.conf.d 2>/dev/null || true
if [ -f "$CHAGE_BEFORE" ]; then
  # passwd -S: name status date min max warn inactive
  max=$(awk '{print $5}' "$CHAGE_BEFORE")
  inact=$(awk '{print $7}' "$CHAGE_BEFORE")
  chage -M "$max" -I "$inact" aj
fi
auth=/etc/pam.d/common-auth
if grep -q 'pam_faillock' "$auth" || ! grep -E 'pam_unix\.so.*nullok' "$auth" >/dev/null; then
  echo STOP-common-auth-restore
  exit 1
fi
echo REVERTED-batch-9
EOF
  chmod 700 "$REVERT"
}

active_eq() {
  file=$1
  key=$2
  want=$3
  got=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" || true)
  if [ -z "$got" ]; then
    # A file with no trailing newline would glue this onto the last line.
    if [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ]; then
      printf '\n' >> "$file"
    fi
    printf '%s = %s\n' "$key" "$want" >> "$file"
    echo "SET $file $key"
    return 0
  fi
  if [ "$(printf '%s\n' "$got" | wc -l)" -ne 1 ]; then
    echo "STOP-dup $file $key"
    if [ "${CHANGED:-0}" = 1 ]; then
      bash "$REVERT"
      systemctl stop "${UNIT}.timer" 2>/dev/null || true
    fi
    exit 1
  fi
  val=$(printf '%s\n' "$got" | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//")
  if [ "$val" != "$want" ]; then
    echo "STOP-value $file $key $val"
    if [ "${CHANGED:-0}" = 1 ]; then
      bash "$REVERT"
      systemctl stop "${UNIT}.timer" 2>/dev/null || true
    fi
    exit 1
  fi
  echo "KEEP $file $key"
}

active_bare() {
  file=$1
  key=$2
  if grep -E "^[[:space:]]*${key}[[:space:]]*$" "$file" >/dev/null; then
    echo "KEEP $file $key"
    return 0
  fi
  if grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" >/dev/null; then
    echo "STOP-value $file $key"
    if [ "${CHANGED:-0}" = 1 ]; then
      bash "$REVERT"
      systemctl stop "${UNIT}.timer" 2>/dev/null || true
    fi
    exit 1
  fi
  if [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ]; then
    printf '\n' >> "$file"
  fi
  printf '%s\n' "$key" >> "$file"
  echo "SET $file $key"
}

refuse_active() {
  file=$1
  key=$2
  if grep -E "^[[:space:]]*${key}([[:space:]]|=|$)" "$file" >/dev/null; then
    echo "STOP-active $file $key"
    if [ "${CHANGED:-0}" = 1 ]; then
      bash "$REVERT"
      systemctl stop "${UNIT}.timer" 2>/dev/null || true
    fi
    exit 1
  fi
}

lan_peers() {
  ss -H -tn sport = :22 | awk '$1=="ESTAB" {print $5}'
}

check_peers() {
  n=0
  while IFS= read -r peer; do
    [ -z "$peer" ] && continue
    case "$peer" in
      192.168.50.*) n=$((n + 1)) ;;
      *)
        echo "STOP-ssh-peer $peer"
        exit 1
        ;;
    esac
  done << EOF
$(lan_peers)
EOF
  if [ "$n" -lt 2 ]; then
    echo STOP-ssh-count
    exit 1
  fi
  echo "SSH-LAN $n"
}

timer_active() {
  [ -e "/run/systemd/transient/${UNIT}.timer" ] && systemctl is-active --quiet "${UNIT}.timer"
}

write_profiles() {
  cat > "$PROFILES/johnny-unix" << 'EOF'
Name: Unix authentication without nullok
Default: no
Priority: 256
Auth-Type: Primary
Auth:
	[success=end default=ignore]	pam_unix.so try_first_pass
Auth-Initial:
	[success=end default=ignore]	pam_unix.so
Account-Type: Primary
Account:
	[success=end new_authtok_reqd=done default=ignore]	pam_unix.so
Account-Initial:
	[success=end new_authtok_reqd=done default=ignore]	pam_unix.so
Session-Type: Additional
Session:
	required	pam_unix.so
Session-Initial:
	required	pam_unix.so
Password-Type: Primary
Password:
	[success=end default=ignore]	pam_unix.so obscure use_authtok try_first_pass yescrypt
Password-Initial:
	[success=end default=ignore]	pam_unix.so obscure yescrypt
EOF
  cat > "$PROFILES/faillock-preauth" << 'EOF'
Name: Johnny faillock preauth
Default: no
Priority: 2048
Auth-Type: Primary
Auth:
	requisite			pam_faillock.so preauth
Auth-Initial:
	requisite			pam_faillock.so preauth
Account-Type: Primary
Account:
	required			pam_faillock.so
Account-Initial:
	required			pam_faillock.so
EOF
  cat > "$PROFILES/faillock-authfail" << 'EOF'
Name: Johnny faillock authfail
Default: no
Priority: 128
Auth-Type: Primary
Auth:
	[default=die]			pam_faillock.so authfail
Auth-Initial:
	[default=die]			pam_faillock.so authfail
EOF
  cat > "$PROFILES/faillock-authsucc" << 'EOF'
Name: Johnny faillock authsucc
Default: no
Priority: 128
Auth-Type: Additional
Auth:
	required			pam_faillock.so authsucc
Auth-Initial:
	required			pam_faillock.so authsucc
EOF
  cat > "$PROFILES/pwhistory" << 'EOF'
Name: Johnny password history
Default: no
Priority: 512
Password-Type: Primary
Password:
	requisite			pam_pwhistory.so use_authtok
Password-Initial:
	requisite			pam_pwhistory.so use_authtok
EOF
  chmod 644 "$PROFILES/johnny-unix" "$PROFILES/faillock-preauth" \
    "$PROFILES/faillock-authfail" "$PROFILES/faillock-authsucc" \
    "$PROFILES/pwhistory"
}

stack_ok() {
  auth=/etc/pam.d/common-auth
  pass=/etc/pam.d/common-password
  acct=/etc/pam.d/common-account
  if grep -E 'pam_unix\.so.*nullok|nullok' "$auth" >/dev/null; then
    echo STACK-nullok
    return 1
  fi
  if ! grep -q 'pam_faillock\.so preauth' "$auth"; then
    echo STACK-preauth
    return 1
  fi
  if ! grep -q 'pam_faillock\.so authfail' "$auth"; then
    echo STACK-authfail
    return 1
  fi
  if ! grep -q 'pam_faillock\.so authsucc' "$auth"; then
    echo STACK-authsucc
    return 1
  fi
  if ! grep -q 'pam_unix\.so' "$auth"; then
    echo STACK-unix-auth
    return 1
  fi
  if ! grep -q 'pam_faillock\.so' "$acct"; then
    echo STACK-account
    return 1
  fi
  if ! grep -q 'pam_pwquality\.so' "$pass"; then
    echo STACK-pwquality
    return 1
  fi
  if ! grep -q 'pam_pwhistory\.so use_authtok' "$pass"; then
    echo STACK-pwhistory
    return 1
  fi
  if ! grep -E 'pam_unix\.so.*use_authtok' "$pass" >/dev/null; then
    echo STACK-unix-authtok
    return 1
  fi
  # preauth before pam_unix, authfail after pam_unix
  pre=$(grep -n 'pam_faillock\.so preauth' "$auth" | head -1 | cut -d: -f1)
  ux=$(grep -n 'pam_unix\.so' "$auth" | head -1 | cut -d: -f1)
  fail=$(grep -n 'pam_faillock\.so authfail' "$auth" | head -1 | cut -d: -f1)
  if [ "$pre" -ge "$ux" ] || [ "$ux" -ge "$fail" ]; then
    echo STACK-order
    return 1
  fi
  echo STACK-OK
}

policy_files_ok() {
  grep -E '^[[:space:]]*deny[[:space:]]*=[[:space:]]*5[[:space:]]*$' "$FAILLOCK" >/dev/null || return 1
  grep -E '^[[:space:]]*unlock_time[[:space:]]*=[[:space:]]*900[[:space:]]*$' "$FAILLOCK" >/dev/null || return 1
  refuse_active "$FAILLOCK" even_deny_root
  refuse_active "$FAILLOCK" root_unlock_time
  grep -E '^[[:space:]]*remember[[:space:]]*=[[:space:]]*24[[:space:]]*$' "$PWHIST" >/dev/null || return 1
  grep -E '^[[:space:]]*enforce_for_root[[:space:]]*$' "$PWHIST" >/dev/null || return 1
  test -f "$PWQ" || return 1
  grep -E '^[[:space:]]*minlen[[:space:]]*=[[:space:]]*14[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^[[:space:]]*difok[[:space:]]*=[[:space:]]*2[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^[[:space:]]*maxrepeat[[:space:]]*=[[:space:]]*3[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^[[:space:]]*maxsequence[[:space:]]*=[[:space:]]*3[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^[[:space:]]*enforce_for_root[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^[[:space:]]*dcredit[[:space:]]*=[[:space:]]*0[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^[[:space:]]*ucredit[[:space:]]*=[[:space:]]*0[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^[[:space:]]*lcredit[[:space:]]*=[[:space:]]*0[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^[[:space:]]*ocredit[[:space:]]*=[[:space:]]*0[[:space:]]*$' "$PWQ" >/dev/null || return 1
  grep -E '^UMASK[[:space:]]+027$' "$LOGIN" >/dev/null || return 1
  grep -E '^PASS_MAX_DAYS[[:space:]]+365$' "$LOGIN" >/dev/null || return 1
  test "$(useradd -D | awk -F= '$1=="INACTIVE"{print $2}')" = "45" || return 1
  grep -q '^readonly TMOUT$' "$SHELL_DROP" || return 1
  grep -q '^umask 027$' "$SHELL_DROP" || return 1
  dpkg-query -W libpam-pwquality cracklib-runtime >/dev/null || return 1
  # passwd -S: name status date min max warn inactive. A run that died after
  # the files were written and before chage must not report OK-batch-9.
  max=$(passwd -S aj | awk '{print $5}')
  inact=$(passwd -S aj | awk '{print $7}')
  [ "$max" = 365 ] || return 1
  [ "$inact" = 45 ] || return 1
}

last_change_line() {
  chage -l aj | grep '^Last password change'
}

if [ "$paste" = 1 ]; then
# RUNS IN: SSH
# PASTE 1
# RUNS ON: JOHNNY (SSH)
set -euo pipefail
# Rollback: /root/batch9-revert.sh and docs/cis-fix/batch-9.md ## Rollback.
# The 300s timer runs that script. This paste does not disarm it.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi
check_peers
if timer_active; then
  echo STOP-timer-armed
  exit 1
fi
backup_tar_once
if [ ! -f "$CHAGE_BEFORE" ]; then
  passwd -S aj > "$CHAGE_BEFORE"
  echo "BACKUP $CHAGE_BEFORE"
else
  echo "BACKUP-KEPT $CHAGE_BEFORE"
fi
write_revert

if policy_files_ok && stack_ok >/dev/null; then
  echo STATE-already
  echo OK-batch-9
  exit 0
fi

CHANGED=1
# Unguarded failures after this point (chage, useradd, mkdir, sed, systemd-run)
# and a dropped SSH session must not leave the new stack with no timer.
trap 'trap - ERR HUP; echo ERR-REVERT; bash "$REVERT"; systemctl stop "${UNIT}.timer" 2>/dev/null || true' ERR HUP
lan_peers > "$PEERS"
echo "PEERS-SAVED $(wc -l < "$PEERS")"
before_last=$(last_change_line)

# Arm the 300s revert BEFORE apt/pam so a hung debconf cannot leave changes
# without a backstop. PASTE 2 still disarms after a new-session sudo check.
systemd-run --on-active=300s --unit="$UNIT" "$REVERT"
echo TIMER-ARMED 300

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

# Finish any half-configured packages from a prior hung install (no prompts).
if ! timeout 120 dpkg --force-confdef --force-confold --configure -a; then
  echo STOP-dpkg-configure
  bash "$REVERT"
  systemctl stop "${UNIT}.timer" 2>/dev/null || true
  exit 1
fi

need_apt=0
for pkg in libpam-pwquality cracklib-runtime; do
  st=$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)
  if [ "$st" != "install ok installed" ]; then
    need_apt=1
  fi
done
if [ "$need_apt" -eq 0 ]; then
  echo SKIP-apt-already
else
  # Never hang on interactive pam-auth-update/debconf (seen 2026-11-04 hang).
  if ! timeout 300 apt-get -y \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold \
      install libpam-pwquality cracklib-runtime; then
    echo STOP-apt
    bash "$REVERT"
    systemctl stop "${UNIT}.timer" 2>/dev/null || true
    exit 1
  fi
  echo APT-OK
fi

# Package postinst may leave common-*.pam-old; ignore, do not delete or STOP.
if ls /etc/pam.d/common-*.pam-old >/dev/null 2>&1; then
  echo NOTE-pam-old-present
fi

mkdir -p "$PWQ_DIR"
if [ ! -f "$PWQ" ]; then
  cat > "$PWQ" << 'EOF'
difok = 2
minlen = 14
dcredit = 0
ucredit = 0
lcredit = 0
ocredit = 0
maxrepeat = 3
maxsequence = 3
enforce_for_root
EOF
  chmod 644 "$PWQ"
  echo "WROTE $PWQ"
else
  echo "KEEP $PWQ"
fi
active_eq "$FAILLOCK" deny 5
active_eq "$FAILLOCK" unlock_time 900
refuse_active "$FAILLOCK" even_deny_root
refuse_active "$FAILLOCK" root_unlock_time
active_eq "$PWHIST" remember 24
active_bare "$PWHIST" enforce_for_root

if grep -E '^PASS_MAX_DAYS[[:space:]]' "$LOGIN" >/dev/null; then
  cur=$(grep -E '^PASS_MAX_DAYS[[:space:]]' "$LOGIN")
  if [ "$cur" != "PASS_MAX_DAYS	365" ] && [ "$cur" != "PASS_MAX_DAYS 365" ]; then
    if [ "$cur" != "PASS_MAX_DAYS	99999" ] && [ "$cur" != "PASS_MAX_DAYS 99999" ]; then
      echo "STOP-pass-max $cur"
      bash "$REVERT"
      systemctl stop "${UNIT}.timer" 2>/dev/null || true
      exit 1
    fi
    sed -i 's/^PASS_MAX_DAYS[[:space:]]\+99999$/PASS_MAX_DAYS\t365/' "$LOGIN"
    echo SET-PASS_MAX_DAYS
  else
    echo KEEP-PASS_MAX_DAYS
  fi
else
  echo STOP-pass-max-missing
  bash "$REVERT"
  systemctl stop "${UNIT}.timer" 2>/dev/null || true
  exit 1
fi
if grep -E '^UMASK[[:space:]]' "$LOGIN" >/dev/null; then
  if ! grep -E '^UMASK[[:space:]]+027$' "$LOGIN" >/dev/null; then
    echo STOP-umask
    bash "$REVERT"
    systemctl stop "${UNIT}.timer" 2>/dev/null || true
    exit 1
  fi
  echo KEEP-UMASK
else
  printf '\nUMASK\t\t\t027\n' >> "$LOGIN"
  echo SET-UMASK
fi

cat > "$SHELL_DROP" << 'EOF'
TMOUT=900
readonly TMOUT
export TMOUT
umask 027
EOF
chmod 644 "$SHELL_DROP"
echo "WROTE $SHELL_DROP"

write_profiles
# Explicit profiles only; --force so a prior package postinst /.pam-old does not
# block as "locally modified". DEBIAN_FRONTEND already noninteractive.
if ! pam-auth-update --force --disable unix --enable johnny-unix pwquality faillock-preauth faillock-authfail faillock-authsucc pwhistory; then
  echo STOP-pam-auth-update
  bash "$REVERT"
  systemctl stop "${UNIT}.timer" 2>/dev/null || true
  exit 1
fi
echo PAM-AUTH-UPDATE-OK

chage -M 365 aj
chage -I 45 aj
useradd -D -f 45
after_last=$(last_change_line)
if [ "$before_last" != "$after_last" ]; then
  echo "STOP-chage-last $after_last"
  bash "$REVERT"
  systemctl stop "${UNIT}.timer" 2>/dev/null || true
  exit 1
fi
echo "CHAGE-LAST-UNCHANGED $after_last"

if ! stack_ok; then
  echo STOP-validate
  bash "$REVERT"
  systemctl stop "${UNIT}.timer" 2>/dev/null || true
  exit 1
fi
if ! policy_files_ok; then
  echo STOP-validate-files
  bash "$REVERT"
  systemctl stop "${UNIT}.timer" 2>/dev/null || true
  exit 1
fi
# Runs as root, so this only refreshes root's credential cache. It does not
# prove that aj can sudo through the new stack. That proof is PASTE 2, started
# with "sudo bash" from a new SSH session.
if ! sudo -n -v; then
  echo STOP-root-sudo-n
  bash "$REVERT"
  systemctl stop "${UNIT}.timer" 2>/dev/null || true
  exit 1
fi
echo ROOT-SUDO-N-OK
faillock --user aj --reset
echo FAILLOCK-RESET-aj

# Timer was armed before apt; PASTE 2 must disarm within 300s of TIMER-ARMED.
echo OK-batch-9-pending
exit 0
fi

if [ "$paste" = 2 ]; then
# RUNS IN: SSH
# PASTE 2
# RUNS ON: JOHNNY (SSH)
set -euo pipefail
# Rollback: docs/cis-fix/batch-9.md ## Rollback. This paste disarms the timer.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi
if ! timer_active; then
  echo STOP-timer-inactive
  exit 1
fi
# Same limit as PASTE 1: this process is already root. aj's sudo is the fact
# that this paste was started with "sudo bash" and reached this line.
if ! sudo -n -v; then
  echo STOP-root-sudo-n
  exit 1
fi
echo ROOT-SUDO-N-OK
if [ ! -f "$PEERS" ]; then
  echo STOP-no-peers
  exit 1
fi
conn=""
pid=$$
while [ "$pid" -gt 1 ]; do
  if [ -r "/proc/$pid/environ" ]; then
    found=$(tr '\0' '\n' < "/proc/$pid/environ" | grep '^SSH_CONNECTION=' || true)
    if [ -n "$found" ]; then
      conn=${found#SSH_CONNECTION=}
      break
    fi
  fi
  pid=$(awk '{print $4}' "/proc/$pid/stat")
done
if [ -z "$conn" ]; then
  echo STOP-not-ssh
  exit 1
fi
# SSH_CONNECTION value: client-ip client-port server-ip server-port
set -- $conn
client_ip=$1
client_port=$2
peer="${client_ip}:${client_port}"
if grep -Fxq "$peer" "$PEERS"; then
  echo "STOP-not-new-session $peer"
  exit 1
fi
case "$client_ip" in
  192.168.50.*) ;;
  *)
    echo "STOP-ssh-peer $peer"
    exit 1
    ;;
esac
echo "NEW-SESSION $peer"
if ! stack_ok; then
  echo STOP-stack
  exit 1
fi
# If the timer already started the revert, stopping the service can kill the
# tar extract. Leave that run alone.
if systemctl is-active --quiet "${UNIT}.service"; then
  echo STOP-revert-running
  exit 1
fi
systemctl stop "${UNIT}.timer" || true
if timer_active; then
  echo STOP-timer-still-active
  exit 1
fi
echo TIMER-STOPPED
faillock --user aj --reset
echo FAILLOCK-RESET-aj
echo OK-batch-9
exit 0
fi

if [ "$paste" = 3 ]; then
# RUNS IN: KVM
# PASTE 3
# RUNS ON: JOHNNY (KVM)
set -euo pipefail
# First choice when the console can still sudo and this file is readable.
# If sudo or this script cannot run, do not use this branch. From a root
# shell (root console login or su -) the tar alone puts the stock PAM stack
# back. Type these three lines; they are also in docs/cis-fix/batch-9.md:
#   tar -C / -xzf /root/batch9-pam-security.tar
#   faillock --user aj --reset
#   systemctl stop johnny-cis-batch9-revert.timer
# Rollback is this paste. It restores pam.d + security and resets faillock for aj.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi
if systemctl is-active --quiet "${UNIT}.service"; then
  echo STOP-revert-running
  exit 1
fi
systemctl stop "${UNIT}.timer" || true
if [ ! -x "$REVERT" ]; then
  echo STOP-no-revert
  exit 1
fi
bash "$REVERT"
echo OK-batch-9-kvm
exit 0
fi
