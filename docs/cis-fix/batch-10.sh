#!/bin/bash
# CIS L1 Batch 10. The deliverable AJ runs from SSH:
#   sudo bash ~/cis-audit/batch-10.sh
# PASTE 2 is KVM recovery. It does not run unless AJ passes 2:
#   sudo bash ~/cis-audit/batch-10.sh 2
# from the installed root, or from the Ubuntu installer shell after this
# script's live-media steps have mounted that root on /mnt (see batch-10.md).
# NO REBOOT in this script.
# Rollback: docs/cis-fix/batch-10.md ## Rollback.
#
# 6.1.2.5 forwards to ableton_box (docs/hosts/ableton_box.md) at 192.168.50.211
# TCP syslog port 514. The script stops before writing that forwarder if
# TCP 514 is not accepted. UDP is not used.
# 3.2.7 only re-asserts dccp, sctp, rds, and tipc. esp4, esp6, and rxrpc stay loadable.
#
# After any later grub-common upgrade, repeat the supervised KVM reboot test.
# A replaced 10_linux can drop --unrestricted and gate a normal boot on the password.

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

# PASTE 1
# RUNS IN: SSH
# Rollback: sudo bash /root/batch10-revert.sh
# or, if GRUB asks for a password before any boot, PASTE 2 from KVM.
paste1() {
  set -euo pipefail

  TAR=/root/batch10-grub-before.tar
  REVERT=/root/batch10-revert.sh
  HASH=/root/batch10-grub.pbkdf2
  USERS=/etc/grub.d/01_johnny_users
  NEWCFG=/root/batch10-grub.cfg.new
  NET=/etc/modprobe.d/johnny-cis-net.conf
  NETBAK=/root/batch10-johnny-cis-net.conf.bak

  if [ "$(id -u)" -ne 0 ]; then
    echo STOP-not-root
    exit 1
  fi
  if [ ! -f /etc/default/grub ] || [ ! -d /etc/grub.d ] || [ ! -f /boot/grub/grub.cfg ]; then
    echo STOP-grub-layout
    exit 1
  fi
  if [ ! -x /usr/sbin/grub-mkconfig ] || [ ! -x /usr/bin/grub-script-check ]; then
    echo STOP-grub-tools
    exit 1
  fi

  # Read-only 3.2.7 checks. No file is written until GRUB is confirmed below.
  for mod in dccp sctp rds tipc; do
    if lsmod | awk -v m="$mod" '$1==m { found=1 } END { exit !found }'; then
      echo "STOP-loaded $mod"
      exit 1
    fi
    if grep -RqsE "^[[:space:]]*${mod}([[:space:]]|\$)" /etc/modules /etc/modules-load.d 2>/dev/null; then
      echo "STOP-modules-load $mod"
      exit 1
    fi
  done
  if [ ! -f "$NET" ]; then
    echo STOP-no-net-conf
    exit 1
  fi

  # --- 1.4.1 ---
  if [ ! -f "$HASH" ]; then
    echo STOP-no-hash
    echo "Create $HASH first. One line, the grub.pbkdf2.sha512 string from grub-mkpasswd-pbkdf2. Mode 600, root. No password in the file."
    exit 1
  fi
  if [ "$(stat -c '%u:%a' "$HASH")" != "0:600" ]; then
    echo STOP-hash-mode
    exit 1
  fi
  mapfile -t hash_lines < "$HASH"
  if [ "${#hash_lines[@]}" -ne 1 ]; then
    echo STOP-hash-lines
    exit 1
  fi
  hash=${hash_lines[0]}
  if ! printf '%s\n' "$hash" | grep -Eq '^grub\.pbkdf2\.sha512\.[0-9]+\.[0-9A-Fa-f]+\.[0-9A-Fa-f]+$'; then
    echo STOP-hash-format
    exit 1
  fi

  grub_done=0
  if grep -q 'password_pbkdf2' /boot/grub/grub.cfg || grep -q 'set superusers' /boot/grub/grub.cfg; then
    if grep -q -- '--unrestricted' /boot/grub/grub.cfg && [ -f "$USERS" ] && grep -qF "$hash" "$USERS"; then
      first=$(grep -n '^menuentry ' /boot/grub/grub.cfg | head -1 || true)
      if [ -n "$first" ] && printf '%s\n' "$first" | grep -q -- '--unrestricted'; then
        echo ALREADY-1.4.1
        grub_done=1
      fi
    fi
    if [ "$grub_done" -ne 1 ]; then
      echo STOP-grub-password-partial
      echo "Run sudo bash /root/batch10-revert.sh (it restores the tar and then removes it), then rerun."
      exit 1
    fi
  fi

  if [ "$grub_done" -eq 0 ]; then
    if [ -e "$TAR" ]; then
      echo STOP-tar-exists
      echo "A previous run left $TAR. Run sudo bash /root/batch10-revert.sh so it restores and removes the tar, then rerun. Do not delete the tar until that restore has succeeded."
      exit 1
    fi
    tar -C / -czf "$TAR" etc/grub.d boot/grub/grub.cfg
    echo "BACKUP $TAR"

    cat > "$REVERT" << 'EOF'
#!/bin/bash
# Rollback helper for CIS batch 10. Restores /etc/grub.d and /boot/grub/grub.cfg
# from the tar taken before 1.4.1, and restores johnny-cis-net.conf if that
# backup exists. Does not need the GRUB password. Run on the installed root.
# After a successful restore it removes the tar so PASTE 1 can be rerun.
set -euo pipefail
TAR=/root/batch10-grub-before.tar
NET=/etc/modprobe.d/johnny-cis-net.conf
NETBAK=/root/batch10-johnny-cis-net.conf.bak
if [ ! -f "$TAR" ]; then
  echo STOP-no-tar
  exit 1
fi
tar -C / -xzf "$TAR"
if [ -f "$NETBAK" ]; then
  cp -a "$NETBAK" "$NET"
fi
rm -f /etc/grub.d/01_johnny_users /root/batch10-grub.cfg.new
# batch10-syslog-undo: drop-ins added for 6.1.2.5. Vendor ForwardToSyslog stays.
rm -f /etc/rsyslog.d/60-johnny-remote.conf
rm -f /etc/systemd/journald.conf.d/61-batch10-forward-syslog.conf
if systemctl is-active --quiet rsyslog; then
  systemctl reload rsyslog
fi
if systemctl is-active --quiet systemd-journald; then
  # No ExecReload on systemd-journald (checked 2026-11-04). A failing reload
  # must not skip rm of the tar or REVERTED.
  systemctl reload systemd-journald || systemctl try-restart systemd-journald || true
fi
rm -f "$TAR"
echo REVERTED
EOF
    chmod 700 "$REVERT"

    # exit 1 does not fire ERR. This trap covers set -e failures
    # (patch write, grub-mkconfig, grub-script-check, install) after $USERS.
    # Explicit STOP branches below still call bash "$REVERT" themselves.
    trap 'rc=$?; [ -x "$REVERT" ] && bash "$REVERT"; exit $rc' ERR

    cat > "$USERS" << EOF
#!/bin/sh
exec tail -n +3 \$0
set superusers="johnny"
password_pbkdf2 johnny ${hash}
EOF
    chmod 700 "$USERS"

    patch_class() {
      file=$1
      expect=$2
      n=$(grep -cF "$expect" "$file" || true)
      if [ "$n" -ne 1 ]; then
        echo "STOP-class-count $file"
        bash "$REVERT"
        exit 1
      fi
      if grep -q -- '--unrestricted' "$file"; then
        echo "CLASS-KEPT $file"
        return 0
      fi
      repl="${expect%\"} --unrestricted\""
      tmp=$(mktemp)
      awk -v old="$expect" -v new="$repl" 'BEGIN{c=0} $0==old && c==0 {print new; c=1; next} {print}' "$file" > "$tmp"
      cat "$tmp" > "$file"
      rm -f "$tmp"
      echo "CLASS-PATCHED $file"
    }
    patch_class /etc/grub.d/10_linux 'CLASS="--class gnu-linux --class gnu --class os"'
    patch_class /etc/grub.d/10_linux_zfs 'CLASS="--class gnu-linux --class gnu --class os"'
    patch_class /etc/grub.d/20_linux_xen 'CLASS="--class gnu-linux --class gnu --class os --class xen"'

    grub-mkconfig -o "$NEWCFG"
    grub-script-check "$NEWCFG"
    if ! grep -q '^set superusers="johnny"$' "$NEWCFG"; then
      echo STOP-no-superusers
      bash "$REVERT"
      exit 1
    fi
    if ! grep -q "^password_pbkdf2 johnny ${hash}$" "$NEWCFG"; then
      echo STOP-no-password-line
      bash "$REVERT"
      exit 1
    fi
    first=$(grep -n '^menuentry ' "$NEWCFG" | head -1 || true)
    if [ -z "$first" ] || ! printf '%s\n' "$first" | grep -q -- '--unrestricted'; then
      echo STOP-default-not-unrestricted
      bash "$REVERT"
      exit 1
    fi
    install -m 600 "$NEWCFG" /boot/grub/grub.cfg
    if ! grep -q -- '--unrestricted' /boot/grub/grub.cfg; then
      echo STOP-installed-cfg
      bash "$REVERT"
      exit 1
    fi
    first=$(grep -n '^menuentry ' /boot/grub/grub.cfg | head -1 || true)
    if [ -z "$first" ] || ! printf '%s\n' "$first" | grep -q -- '--unrestricted'; then
      echo STOP-installed-first-entry
      bash "$REVERT"
      exit 1
    fi
    trap - ERR
    echo GRUB-OK
    echo "Supervised reboot is recommended with KVM watching. This script does not reboot."
    echo "Repeat that test after any grub-common upgrade. The first menuentry must still contain --unrestricted."
    echo "A password prompt before the countdown is a failed gate. Run PASTE 2 or /root/batch10-revert.sh."
  fi

  # --- 3.2.7 after the GRUB gate. Backup only if this file has no backup yet. ---
  # Rollback for this file: cp -a /root/batch10-johnny-cis-net.conf.bak "$NET"
  changed=0
  for mod in dccp sctp rds tipc; do
    if ! grep -qx "blacklist ${mod}" "$NET" || ! grep -qx "install ${mod} /bin/false" "$NET"; then
      changed=1
    fi
  done
  if [ "$changed" -eq 1 ]; then
    if [ ! -f "$NETBAK" ]; then
      cp -a "$NET" "$NETBAK"
      echo "BACKUP $NETBAK"
    else
      echo "BACKUP-KEPT $NETBAK"
    fi
    for mod in dccp sctp rds tipc; do
      if ! grep -qx "blacklist ${mod}" "$NET"; then
        printf 'blacklist %s\n' "$mod" >> "$NET"
        echo "MODULE-ADDED blacklist $mod"
      fi
      if ! grep -qx "install ${mod} /bin/false" "$NET"; then
        printf 'install %s /bin/false\n' "$mod" >> "$NET"
        echo "MODULE-ADDED install $mod"
      fi
    done
  else
    echo MODULE-KEPT-all
  fi
  # modprobe -n -v may print dependency insmod lines, then "install /bin/false "
  # (trailing space). Require a trimmed line equal to install /bin/false (or the
  # last trimmed line). Dependency insmods are OK. Insmod of the named module is not.
  # Do not restore NETBAK on verify failure: the conf block is intentional; a false
  # STOP previously wiped newly added dccp lines. Soft revert undoes if needed.
  modprobe_install_false() {
    local mod=$1 out
    out=$(modprobe -n -v "$mod" 2>&1 || true)
    if printf '%s\n' "$out" | grep -Eq "insmod[[:space:]]+.*/${mod}\.ko"; then
      return 1
    fi
    if printf '%s\n' "$out" | sed 's/[[:space:]]*$//' | grep -qx 'install /bin/false'; then
      return 0
    fi
    if printf '%s\n' "$out" | sed 's/[[:space:]]*$//' | awk 'NF{last=$0} END{exit !(last=="install /bin/false")}'; then
      return 0
    fi
    return 1
  }
  for mod in sctp rds tipc atm can; do
    if ! modprobe_install_false "$mod"; then
      echo "STOP-modprobe $mod"
      echo "modprobe -n -v $mod did not deny via install /bin/false, or would insmod ${mod}.ko. Left $NET unchanged."
      exit 1
    fi
  done
  out=$(modprobe -n -v dccp 2>&1 || true)
  # Module absent from this kernel is fine. Fail only if this dry-run would insmod dccp itself.
  if printf '%s\n' "$out" | grep -Eq 'insmod[[:space:]]+.*/dccp\.ko'; then
    echo STOP-dccp-insmod
    echo "modprobe -n -v dccp would insmod dccp.ko. Left $NET unchanged."
    exit 1
  fi
  echo MODULE-VERIFY-OK

  # --- 6.1.2.5 ableton_box, TCP/514. No write until the probe succeeds. ---
  # Rollback: sudo rm -f /etc/rsyslog.d/60-johnny-remote.conf /etc/systemd/journald.conf.d/61-batch10-forward-syslog.conf
  #   then: sudo systemctl reload rsyslog; sudo systemctl reload systemd-journald || sudo systemctl try-restart systemd-journald || true
  # A helper written by this revision also removes those two files.
  LOGIP=192.168.50.211
  RSYS=/etc/rsyslog.d/60-johnny-remote.conf
  JRN=/etc/systemd/journald.conf.d/61-batch10-forward-syslog.conf
  resolved=""
  for name in ableton_box.local ableton_box; do
    got=$(getent ahostsv4 "$name" 2>/dev/null | awk 'NR==1 { print $1 }' || true)
    if [ -n "$got" ]; then
      resolved=$got
      break
    fi
  done
  if [ -n "$resolved" ] && [ "$resolved" != "$LOGIP" ]; then
    echo "STOP-resolve-mismatch $resolved"
    echo "ableton_box resolved to an address other than $LOGIP. Not forwarding."
    exit 1
  fi
  if [ -z "$resolved" ]; then
    echo "RESOLVE-FALLBACK $LOGIP ableton_box"
  else
    echo "RESOLVE-OK $resolved"
  fi
  if ! timeout 5 bash -c "echo >/dev/tcp/${LOGIP}/514"; then
    echo STOP-collector-514
    echo "No TCP connection to ${LOGIP}:514 (ableton_box). Stand up syslog on ABLETON_BOX so it listens on TCP 514, then rerun. No forwarder was written."
    exit 1
  fi
  echo "PROBE-OK ${LOGIP}:514"
  if ! grep -q '\$WorkDirectory' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
    echo STOP-no-workdirectory
    exit 1
  fi
  if [ -f "$REVERT" ] && ! grep -q 'batch10-syslog-undo' "$REVERT"; then
    echo STOP-revert-old
    echo "$REVERT has no syslog undo. Run it, then rerun PASTE 1 so the helper is rewritten."
    exit 1
  fi
  want=$(cat << EOF
# ableton_box (ableton_box.local) ${LOGIP} — docs/hosts/ableton_box.md
# TCP syslog 514 (omfwd). UDP is not used. Hostname is a comment: target is the documented address.
action(type="omfwd" target="${LOGIP}" port="514" protocol="tcp" action.resumeRetryCount="-1" action.resumeInterval="30" queue.type="LinkedList" queue.filename="batch10fwd" queue.saveOnShutdown="on")
EOF
)
  if [ -f "$RSYS" ] && [ "$(cat "$RSYS")" = "$want" ]; then
    echo RSYSLOG-KEPT
  else
    if [ -f "$RSYS" ] && [ ! -f /root/batch10-60-johnny-remote.conf.bak ]; then
      cp -a "$RSYS" /root/batch10-60-johnny-remote.conf.bak
      echo BACKUP /root/batch10-60-johnny-remote.conf.bak
    fi
    printf '%s\n' "$want" > "$RSYS"
    chmod 644 "$RSYS"
    if ! rsyslogd -N1; then
      rm -f "$RSYS"
      echo STOP-rsyslog-syntax
      exit 1
    fi
    systemctl reload rsyslog
    echo RSYSLOG-OK
  fi
  if [ ! -d /etc/systemd/journald.conf.d ]; then
    echo STOP-no-journald-dir
    exit 1
  fi
  jwant=$(cat << 'EOF'
[Journal]
ForwardToSyslog=yes
EOF
)
  if [ -f "$JRN" ] && [ "$(cat "$JRN")" = "$jwant" ]; then
    echo JOURNAL-KEPT
  else
    if [ -f "$JRN" ] && [ ! -f /root/batch10-61-batch10-forward-syslog.conf.bak ]; then
      cp -a "$JRN" /root/batch10-61-batch10-forward-syslog.conf.bak
    fi
    printf '%s\n' "$jwant" > "$JRN"
    chmod 644 "$JRN"
    # Vendor already sets ForwardToSyslog=yes. The unit has no ExecReload
    # (checked 2026-11-04). The cat-config check below is the gate.
    systemctl reload systemd-journald || systemctl try-restart systemd-journald || true
    echo JOURNAL-OK
  fi
  if ! systemd-analyze cat-config systemd/journald.conf | grep -q '^ForwardToSyslog=yes$'; then
    echo STOP-journal-forward
    exit 1
  fi

  echo BATCH10-SSH-DONE
}

# PASTE 2
# RUNS IN: KVM
# Rollback path: put the pre-change grub.cfg and grub.d back without the new password.
# On the installed system (normal boot still works): sudo bash ~/cis-audit/batch-10.sh 2
# If GRUB demands a password before boot: use the installer shell. See batch-10.md.
#
# Assumptions (docs/os-handoff.md disk row): LUKS is /dev/nvme0n1p3, /boot is
# /dev/nvme0n1p2, LVM is ubuntu-vg/ubuntu-lv. johnny-root is the name this
# paste passes to cryptsetup open. It is not the live mapper (live is dm_crypt-0).
# A wrong name stops at STOP-not-luks or STOP-not-johnny-root.
paste2() {
  set -euo pipefail
  if [ "$(id -u)" -ne 0 ]; then
    echo STOP-not-root
    exit 1
  fi
  if [ -f /root/batch10-grub-before.tar ] && [ -d /etc/grub.d ] && [ -f /root/batch10-revert.sh ]; then
    bash /root/batch10-revert.sh
    echo KVM-REVERTED-INSTALLED
    exit 0
  fi
  if [ ! -b /dev/nvme0n1p3 ] || [ ! -b /dev/nvme0n1p2 ]; then
    echo STOP-disks
    exit 1
  fi
  if ! blkid -t TYPE=crypto_LUKS -o device | grep -qx /dev/nvme0n1p3; then
    echo STOP-not-luks
    exit 1
  fi
  if [ ! -e /dev/mapper/johnny-root ]; then
    cryptsetup open /dev/nvme0n1p3 johnny-root
  fi
  if ! command -v vgchange >/dev/null 2>&1; then
    echo STOP-no-lvm
    exit 1
  fi
  vgchange -ay ubuntu-vg
  mkdir -p /mnt
  if ! mountpoint -q /mnt; then
    mount /dev/ubuntu-vg/ubuntu-lv /mnt
  fi
  if [ ! -d /mnt/etc/grub.d ]; then
    echo STOP-not-johnny-root
    exit 1
  fi
  mkdir -p /mnt/boot
  if ! mountpoint -q /mnt/boot; then
    mount /dev/nvme0n1p2 /mnt/boot
  fi
  if [ ! -f /mnt/root/batch10-grub-before.tar ]; then
    echo STOP-no-tar
    exit 1
  fi
  tar -C /mnt -xzf /mnt/root/batch10-grub-before.tar
  if [ -f /mnt/root/batch10-johnny-cis-net.conf.bak ]; then
    cp -a /mnt/root/batch10-johnny-cis-net.conf.bak /mnt/etc/modprobe.d/johnny-cis-net.conf
  fi
  rm -f /mnt/etc/grub.d/01_johnny_users /mnt/root/batch10-grub.cfg.new
  rm -f /mnt/etc/rsyslog.d/60-johnny-remote.conf
  rm -f /mnt/etc/systemd/journald.conf.d/61-batch10-forward-syslog.conf
  rm -f /mnt/root/batch10-grub-before.tar
  echo KVM-REVERTED-LIVE
}

case "$paste" in
  1) paste1 ;;
  2) paste2 ;;
esac
