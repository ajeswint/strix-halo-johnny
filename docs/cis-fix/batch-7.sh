#!/bin/bash
# CIS L1 Batch 7. The deliverable AJ runs from SSH, no argument, is PASTE 1 only:
#   sudo bash ~/cis-audit/batch-7.sh
# PASTE 2 is KVM recovery and does not run unless AJ passes 2:
#   sudo bash ~/cis-audit/batch-7.sh 2
# NO REBOOT. This script does not set ipv6.disable=1, does not edit GRUB,
# and does not rebuild the initrd. CIS 3.1.1 is met by disable_ipv6=1.
# Rollback: docs/cis-fix/batch-7.md ## Rollback.

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
# RUNS ON: JOHNNY (SSH)
# PASTE 1
# RUNS IN: SSH
set -euo pipefail
# Rollback: docs/cis-fix/batch-7.md ## Rollback.
# Immediate: sysctl -w. Persistent: 60-johnny-cis-network.conf at next boot.
# The ssh.socket drop-in is not applied to the live socket. Do not restart
# ssh.socket here. No GRUB. No ipv6.disable=1. No reboot.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

JOHNNY=/etc/sysctl.d/60-johnny-cis-network.conf
BACKUP=/root/60-johnny-cis-network.conf.pre-batch7
DROPIN_DIR=/etc/systemd/system/ssh.socket.d
DROPIN=$DROPIN_DIR/60-johnny-cis-ipv4.conf
NETPLAN=/etc/netplan/00-installer-config.yaml
KEY_ALL='net.ipv6.conf.all.disable_ipv6 = 1'
KEY_DEF='net.ipv6.conf.default.disable_ipv6 = 1'

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

ipv4_ok() {
  ip -4 -o addr show dev eno3 | grep -q 'inet 192\.168\.50\.152/24 '
}

# awk reads the whole ss list so grep -q cannot SIGPIPE the pipeline under pipefail.
listen_v4_22() {
  ss -H -lnt sport = :22 | awk 'BEGIN { found = 0 } $4 == "0.0.0.0:22" { found = 1 } END { exit (found ? 0 : 1) }'
}

echo "=== STATE ==="
ip -4 -o addr show dev eno3 || true
ip -4 route show default || true
ss -H -lntu || true
sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6
echo "=== END STATE ==="

if ! ipv4_ok; then
  echo STOP-eno3-addr
  exit 1
fi
if ! ip -4 route show default | grep -q 'dev eno3'; then
  echo STOP-default-route
  exit 1
fi
if [ ! -f "$NETPLAN" ]; then
  echo STOP-netplan-missing
  exit 1
fi
if grep -q 'dhcp6: true' "$NETPLAN"; then
  echo STOP-dhcp6
  exit 1
fi

lan_ssh=0
while read -r peer; do
  [ -n "$peer" ] || continue
  case "$peer" in
    192.168.50.152)
      echo NOTE-ssh-self
      ;;
    192.168.50.*)
      lan_ssh=1
      ;;
    *)
      echo "STOP-ssh-peer $peer"
      exit 1
      ;;
  esac
done < <(ss -H -tn sport = :22 | awk '$1=="ESTAB"{print $5}' | sed 's/:[0-9]*$//')

if [ "$lan_ssh" -ne 1 ]; then
  echo STOP-no-lan-ssh
  exit 1
fi
if ! listen_v4_22; then
  echo STOP-no-v4-ssh
  exit 1
fi

while read -r netid local; do
  [ -n "${netid:-}" ] || continue
  case "$netid $local" in
    "tcp 0.0.0.0:22"|"tcp [::]:22"|"tcp 127.0.0.54:53"|"tcp 127.0.0.53%lo:53"|"tcp 127.0.0.53:53")
      ;;
    "udp 127.0.0.54:53"|"udp 127.0.0.53%lo:53"|"udp 127.0.0.53:53"|"udp 192.168.50.152%eno3:68"|"udp 127.0.0.1:323"|"udp [::1]:323")
      ;;
    *)
      echo "STOP-listener $netid $local"
      exit 1
      ;;
  esac
done < <(ss -H -lntu | awk '{print $1, $5}')

if ! listen_v4_22; then
  echo STOP-no-v4-ssh
  exit 1
fi
if ! ss -H -lnu sport = :323 | awk 'BEGIN { found = 0 } $4 == "127.0.0.1:323" { found = 1 } END { exit (found ? 0 : 1) }'; then
  echo STOP-chrony-v4
  exit 1
fi

if [ ! -f "$JOHNNY" ]; then
  echo STOP-sysctl-missing
  exit 1
fi

if [ -f "$DROPIN" ]; then
  if ! cmp -s - "$DROPIN" <<'EOF'
[Socket]
ListenStream=
ListenStream=0.0.0.0:22
EOF
  then
    echo STOP-ssh-dropin
    exit 1
  fi
  echo SKIP-ssh-dropin
else
  install -d -m 0755 -o root -g root "$DROPIN_DIR"
  cat > "$DROPIN" <<'EOF'
[Socket]
ListenStream=
ListenStream=0.0.0.0:22
EOF
  chmod 0644 "$DROPIN"
  echo "WROTE $DROPIN"
fi
systemctl daemon-reload
echo SKIP-ssh-restart

have_all=0
have_def=0
if grep -Fxq -- "$KEY_ALL" "$JOHNNY"; then
  have_all=1
fi
if grep -Fxq -- "$KEY_DEF" "$JOHNNY"; then
  have_def=1
fi
if grep -E -q '^[[:space:]]*net\.ipv6\.conf\.(all|default)\.disable_ipv6[[:space:]]*=' "$JOHNNY"; then
  if [ "$have_all" -ne 1 ] || [ "$have_def" -ne 1 ]; then
    echo STOP-sysctl-file
    exit 1
  fi
fi

run_all=$(sysctl -n net.ipv6.conf.all.disable_ipv6)
run_def=$(sysctl -n net.ipv6.conf.default.disable_ipv6)
if [ "$have_all" -eq 1 ] && [ "$have_def" -eq 1 ] && [ "$run_all" = 1 ] && [ "$run_def" = 1 ]; then
  echo SKIP-disable-ipv6
else
  backup_once "$JOHNNY" "$BACKUP"
  if [ "$have_all" -ne 1 ] || [ "$have_def" -ne 1 ]; then
    if [ "$have_all" -eq 1 ] || [ "$have_def" -eq 1 ]; then
      echo STOP-sysctl-file
      exit 1
    fi
    printf '\n%s\n%s\n%s\n' \
      '# 3.1.1. IPv6 disabled. 3.3.2.1-3.3.2.8 are N/A while this stays 1. No ipv6.disable=1.' \
      "$KEY_ALL" \
      "$KEY_DEF" >> "$JOHNNY"
    echo APPENDED-disable-ipv6
  fi
fi

if [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6)" != 1 ] || [ "$(sysctl -n net.ipv6.conf.default.disable_ipv6)" != 1 ]; then
  sysctl -w net.ipv6.conf.default.disable_ipv6=1
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
fi

if ! ipv4_ok || ! listen_v4_22; then
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 || true
  echo STOP-ipv4-ssh
  echo "Live keys set back to 0. The two disable_ipv6 lines may still be in $JOHNNY. Run the rollback block in docs/cis-fix/batch-7.md before reboot."
  exit 1
fi

for d in /proc/sys/net/ipv6/conf/*; do
  v=$(cat "$d/disable_ipv6")
  if [ "$v" != 1 ]; then
    echo "STOP-disable-ipv6 $(basename "$d") $v"
    exit 1
  fi
done

echo "=== VERIFY ==="
sysctl --system 2>&1 | grep disable_ipv6 || true
if [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6)" != 1 ] || [ "$(sysctl -n net.ipv6.conf.default.disable_ipv6)" != 1 ]; then
  echo STOP-sysctl-override
  exit 1
fi
sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6
ip -4 -o addr show dev eno3
listen_v4_22
ss -H -lnt sport = :22
ip -6 addr show || true
echo "=== END VERIFY ==="
echo OK-batch-7
exit 0
fi

# RUNS ON: JOHNNY (KVM)
# PASTE 2
# RUNS IN: KVM
set -euo pipefail
# Rollback: docs/cis-fix/batch-7.md ## Rollback.
# Use only if PASTE 1 left no IPv4 SSH. This does not touch GRUB.

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

JOHNNY=/etc/sysctl.d/60-johnny-cis-network.conf
BACKUP=/root/60-johnny-cis-network.conf.pre-batch7
sysctl -w net.ipv6.conf.all.disable_ipv6=0
sysctl -w net.ipv6.conf.default.disable_ipv6=0
if [ ! -f "$BACKUP" ]; then
  echo STOP-no-backup
  exit 1
fi
cp -a "$BACKUP" "$JOHNNY"
if ! ss -H -lnt sport = :22 | awk 'BEGIN { found = 0 } $4 == "0.0.0.0:22" { found = 1 } END { exit (found ? 0 : 1) }'; then
  echo STOP-no-v4-ssh
  exit 1
fi
echo OK-paste-2
exit 0
