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
# 6.1.2.5 is not configured here. No remote log host is named in the repo.
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
  for mod in sctp rds tipc atm can; do
    out=$(modprobe -n -v "$mod" 2>&1 || true)
    if ! printf '%s\n' "$out" | grep -qx 'install /bin/false'; then
      echo "STOP-modprobe $mod"
      if [ -f "$NETBAK" ]; then
        cp -a "$NETBAK" "$NET"
      fi
      exit 1
    fi
  done
  out=$(modprobe -n -v dccp 2>&1 || true)
  if printf '%s\n' "$out" | grep -q 'insmod'; then
    echo STOP-dccp-insmod
    if [ -f "$NETBAK" ]; then
      cp -a "$NETBAK" "$NET"
    fi
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
  rm -f /mnt/root/batch10-grub-before.tar
  echo KVM-REVERTED-LIVE
}

case "$paste" in
  1) paste1 ;;
  2) paste2 ;;
esac
