#!/bin/bash
# Local checks for the step 13 paste. Does not touch a NIC or irqbalance.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD

fail() {
  echo "SELF-TEST-FAIL $*" >&2
  exit 1
}

# shellcheck source=etc/johnny/irq-affinity.sh
source "$ROOT/etc/johnny/irq-affinity.sh"
# shellcheck source=etc/johnny/irqbalance-policy.sh
source "$ROOT/etc/johnny/irqbalance-policy.sh"
# shellcheck source=docs/tool-install/step-13-irq-affinity.sh
source "$ROOT/docs/tool-install/step-13-irq-affinity.sh"

out=$(assign_cpu eno1np0-TxRx-0 1 2 3 4)
[ "$out" = 1 ] || fail "txrx0 $out"
out=$(assign_cpu eno1np0-TxRx-4 1 2 3 4)
[ "$out" = 1 ] || fail "txrx4 $out"
out=$(assign_cpu eno1np0-TxRx-5 1 2 3 4)
[ "$out" = 2 ] || fail "txrx5 $out"
out=$(assign_cpu eno1np0-rx-3 1 2 3 4)
[ "$out" = 4 ] || fail "rx3 $out"
out=$(assign_cpu 'ice-0000:01:00.0:misc' 1 2 3 4)
[ "$out" = 1 ] || fail "misc $out"
out=$(assign_cpu eno1np0-TxRx-08 1 2 3 4)
[ "$out" = 1 ] || fail "octal $out"
if assign_cpu eno1np0-TxRx-1 >/tmp/step13-assign.out; then
  fail "no cpus should stop"
fi
grep -q STOP-no-cpus /tmp/step13-assign.out || fail "no cpus code"

affinity_is_cpu 2 2 || fail "single"
affinity_is_cpu 1-1 1 || fail "range one"
if affinity_is_cpu 0 1; then
  fail "cpu0 accepted"
fi
if affinity_is_cpu 1-2 1; then
  fail "two cpus accepted"
fi
if affinity_is_cpu 0-3 1; then
  fail "range including 0"
fi

cores=$(mktemp)
printf '1\n2\n3\n4\n' > "$cores"
out=$(read_capture_cpus "$cores")
[ "$out" = $'1\n2\n3\n4' ] || fail "cores $out"
printf '0\n1\n' > "$cores"
if read_capture_cpus "$cores" >/tmp/step13-cores.out; then
  fail "cpu0 should stop"
fi
grep -q STOP-cpu0-in-set /tmp/step13-cores.out || fail "cpu0 code"
printf '1\n1\n' > "$cores"
if read_capture_cpus "$cores" >/tmp/step13-cores.out; then
  fail "dup should stop"
fi
grep -q STOP-cores-dup /tmp/step13-cores.out || fail "dup code"
rm -f "$cores"

foreign_irq_name eno1np0-TxRx-0 && fail "eno1 flagged foreign"
foreign_irq_name 'ice-0000:01:00.0:misc' && fail "misc flagged foreign"
foreign_irq_name eno2np1-TxRx-0 || fail "eno2 not foreign"
foreign_irq_name eno3-rx-0 || fail "eno3 not foreign"

inter=$(mktemp)
cat > "$inter" <<'EOF'
           CPU0       CPU1
  12:          1          0   IR-PCI-MSIX-0000:01:00.0    0-edge      eno1np0-TxRx-0
  14:          0          1   IR-PCI-MSIX-0000:01:00.0    0-edge      ice-0000:01:00.0:misc
  15:          1          0   IR-PCI-MSIX-0000:01:00.1    0-edge      eno2np1-TxRx-0
EOF
[ "$(irq_name_from_file 12 "$inter")" = eno1np0-TxRx-0 ] || fail "irq 12 name"
[ "$(irq_name_from_file 14 "$inter")" = ice-0000:01:00.0:misc ] || fail "irq 14 name"
[ "$(irq_name_from_file 15 "$inter")" = eno2np1-TxRx-0 ] || fail "irq 15 name"
if irq_name_from_file 99 "$inter" >/dev/null; then
  fail "missing irq"
fi
rm -f "$inter"

flags_capture_ok 0x1183 || fail "hex promisc noarp"
if flags_capture_ok 0x1003; then
  fail "hex without promisc"
fi
flags_admin_up 0x1003 || fail "hex admin up"
if flags_admin_up 0; then
  fail "down flagged up"
fi
eno1_link_ok 10000 0x1183 1 up || fail "link gate"
if eno1_link_ok 1000 0x1183 1 up; then
  fail "wrong speed"
fi

sys=$(mktemp -d)
mkdir -p "$sys/bus/pci/devices/0000:01:00.0" "$sys/bus/pci/devices/0000:01:00.1" "$sys/bus/pci/devices/0000:02:00.0"
mkdir -p "$sys/class/net/eno1np0" "$sys/class/net/eno2np1" "$sys/class/net/eno3"
ln -s "$sys/bus/pci/devices/0000:01:00.0" "$sys/class/net/eno1np0/device"
ln -s "$sys/bus/pci/devices/0000:01:00.1" "$sys/class/net/eno2np1/device"
ln -s "$sys/bus/pci/devices/0000:02:00.0" "$sys/class/net/eno3/device"
policy_bans "$sys/bus/pci/devices/0000:01:00.0" "$sys" || fail "ban eno1"
policy_bans "$sys/bus/pci/devices/0000:01:00.1" "$sys" || fail "ban eno2"
if policy_bans "$sys/bus/pci/devices/0000:02:00.0" "$sys"; then
  fail "banned eno3"
fi
if policy_bans "" "$sys"; then
  fail "empty path banned"
fi
rm -rf "$sys"

fix=$(mktemp)
printf '#IRQBALANCE_ARGS=\n' > "$fix"
out=$(irqbalance_edit check "$fix")
[ "$out" = WOULD-WRITE ] || fail "plan write $out"
out=$(irqbalance_edit write "$fix")
[ "$out" = WROTE-irqbalance ] || fail "wrote $out"
grep -qx 'IRQBALANCE_ARGS=--policyscript=/etc/johnny/irqbalance-policy.sh' "$fix" || fail "args line"
out=$(irqbalance_edit check "$fix")
[ "$out" = UNCHANGED ] || fail "second plan $out"
printf 'IRQBALANCE_ARGS=--debug\n' > "$fix"
if irqbalance_edit check "$fix" >/tmp/step13-ib.out; then
  fail "foreign args should stop"
fi
printf 'IRQBALANCE_BANNED_CPULIST=1-4\n#IRQBALANCE_ARGS=\n' > "$fix"
if irqbalance_edit check "$fix" >/tmp/step13-ib.out; then
  fail "banned cpus should stop"
fi
rm -f "$fix"

unit=$(mktemp)
cat > "$unit" <<'EOF'
# /lib/systemd/system/irqbalance.service
[Service]
EnvironmentFile=-/usr/lib/irqbalance/defaults.env
EnvironmentFile=-/etc/default/irqbalance
ExecStart=/usr/sbin/irqbalance $IRQBALANCE_ARGS
EOF
last=$(unit_interest_lines "$unit" | awk 'END{print}')
[ "$last" = /etc/default/irqbalance ] || fail "env last $last"
printf 'Environment=IRQBALANCE_ARGS=--oneshot\n' >> "$unit"
unit_interest_lines "$unit" | grep -qx STOP-irqbalance-env || fail "env override"
rm -f "$unit"

host_out=$(bash "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || true)
printf '%s\n' "$host_out" | grep -qx STOP-host || fail "stop host: $host_out"
rev_out=$(bash "$ROOT/docs/tool-install/step-13-revert.sh" || true)
printf '%s\n' "$rev_out" | grep -qx STOP-not-root || fail "revert root: $rev_out"

for f in \
  docs/tool-install/step-13-irq-affinity.sh \
  docs/tool-install/step-13-revert.sh \
  etc/johnny/irq-affinity.sh \
  etc/johnny/irqbalance-policy.sh
do
  if grep -En 'apt-get|apt install|update-grub|update-initramfs|[[:space:]]reboot|ethtool -[LGKX]|ip link set|sysctl -w|pci=noaer|snap install' "$ROOT/$f" \
    | grep -v '^[0-9]*:#'; then
    fail "forbidden in $f"
  fi
done

got=$(sha256sum "$ROOT/etc/johnny/irq-affinity.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "helper hash"
got=$(sha256sum "$ROOT/etc/johnny/irqbalance-policy.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "policy hash"
got=$(sha256sum "$ROOT/etc/systemd/system/johnny-capture-irq.service" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "unit hash"
got=$(sha256sum "$ROOT/docs/tool-install/step-13-revert.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "revert hash"
got=$(sha256sum "$ROOT/etc/johnny/capture-cores" | awk '{print $1}')
grep -q "$got" "$ROOT/etc/johnny/irq-affinity.sh" || fail "cores hash"

echo SELF-TEST-OK
