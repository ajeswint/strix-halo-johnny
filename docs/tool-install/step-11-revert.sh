#!/bin/bash
# Rollback for Johnny step 11. The apply script installs this at
# /root/step11-revert.sh before it changes the box. Safe to run twice.
#   sudo bash /root/step11-revert.sh
# Restores the first-run netplan backup, removes the capture drop-in,
# clears promisc and NOARP on eno1np0, and restores EPP and cpuidle.
set -euo pipefail
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
umask 022

if [ "$(id -u)" -ne 0 ]; then
  echo STOP-not-root
  exit 1
fi

rc=0

detach_xdp() {
  if command -v bpftool >/dev/null 2>&1 && [ -d /sys/class/net/eno1np0 ]; then
    bpftool net detach xdpdrv dev eno1np0 >/dev/null 2>&1 || true
    bpftool net detach xdp dev eno1np0 >/dev/null 2>&1 || true
  fi
  rm -f /sys/fs/bpf/johnny_xdp_count
  echo XDP-DETACHED
}

restore_tuning() {
  if [ -f /etc/systemd/system/johnny-capture-tuning.service ]; then
    systemctl disable --now johnny-capture-tuning.service || true
  fi
  if [ -x /etc/johnny/capture-tuning.sh ] && [ -f /var/lib/johnny/capture-tuning-before.tsv ]; then
    /etc/johnny/capture-tuning.sh revert || return 1
  fi
  rm -f /etc/systemd/system/johnny-capture-tuning.service
  rm -f /etc/johnny/capture-tuning.sh
  rm -f /etc/johnny/capture-cores
  rmdir /etc/johnny 2>/dev/null || true
  systemctl daemon-reload
  echo TUNING-REMOVED
}

restore_netplan() {
  local live=/etc/netplan/00-installer-config.yaml
  local bak=/root/00-installer-config.yaml.pre-step11
  local drop=/etc/systemd/network/10-netplan-eno1np0.network.d/60-johnny-capture.conf
  local reload_failed=0
  if [ -f "$drop" ] || [ -L "$drop" ]; then
    rm -f "$drop"
    rmdir /etc/systemd/network/10-netplan-eno1np0.network.d 2>/dev/null || true
    echo DROPIN-REMOVED
  fi
  if [ -f "$bak" ] && [ -f "$live" ] && ! cmp -s "$bak" "$live"; then
    cp -a "$bak" "$live"
    netplan generate
    netplan apply
    echo NETPLAN-RESTORED
  else
    # Drop-in file is already gone. Reload so networkd drops Promiscuous= and ARP=.
    if ! networkctl reload; then
      echo STOP-networkctl-reload
      reload_failed=1
    fi
    echo NETPLAN-UNCHANGED
  fi
  if [ -d /sys/class/net/eno1np0 ]; then
    ip link set dev eno1np0 promisc off
    ip link set dev eno1np0 arp on
    echo ENO1-FLAGS-CLEARED
  fi
  return "$reload_failed"
}

detach_xdp || rc=1
restore_tuning || rc=1
restore_netplan || rc=1
if [ "$rc" -ne 0 ]; then
  echo STOP-revert-incomplete
  exit 1
fi
echo REVERTED
