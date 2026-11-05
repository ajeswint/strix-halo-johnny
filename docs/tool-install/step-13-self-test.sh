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
# shellcheck source=docs/tool-install/step-13b-name-match.sh
source "$ROOT/docs/tool-install/step-13b-name-match.sh"

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
# Step 13b: live names carry the ice- prefix.
want_cpu=(1 2 3 4 1 2 3 4 1 2 3 4)
for n in 0 1 2 3 4 5 6 7 8 9 10 11; do
  out=$(assign_cpu "ice-eno1np0-TxRx-$n" 1 2 3 4)
  [ "$out" = "${want_cpu[$n]}" ] || fail "ice txrx$n $out"
done
out=$(assign_cpu 'ice-0000:01:00.0:ctrl-TxRx-0' 1 2 3 4)
[ "$out" = 1 ] || fail "ctrl $out"
out=$(assign_cpu 'ice-0000:01:00.0:ll_ts' 1 2 3 4)
[ "$out" = 1 ] || fail "ll_ts $out"
out=$(assign_cpu 'ice-eno1np0-TxRx-9' 2 4)
[ "$out" = 4 ] || fail "two cpus $out"
[ "$(classify_irq_name ice-eno1np0-TxRx-11)" = queue ] || fail "class queue ice"
[ "$(classify_irq_name eno1np0-rx-3)" = queue ] || fail "class queue plain"
[ "$(classify_irq_name 'ice-0000:01:00.0:misc')" = aux ] || fail "class misc"
[ "$(classify_irq_name 'ice-0000:01:00.0:ll_ts')" = aux ] || fail "class ll_ts"
[ "$(classify_irq_name 'ice-0000:01:00.0:ctrl-TxRx-0')" = aux ] || fail "class ctrl"
[ "$(classify_irq_name 'irdma-0000:01:00.0-CEQ-3')" = irdma ] || fail "class irdma"
[ "$(classify_irq_name 'irdma-0000:01:00.0-AEQCEQ-0')" = irdma ] || fail "class aeqceq"
[ "$(classify_irq_name 'ice-eno1np0-TxRx-x')" = other ] || fail "class bad idx"
[ "$(classify_irq_name 'xice-eno1np0-TxRx-1')" = other ] || fail "class bad prefix"
foreign_irq_name ice-eno1np0-TxRx-0 && fail "ice eno1 flagged foreign"
foreign_irq_name irdma-0000:01:00.0-CEQ-1 && fail "irdma flagged foreign"
foreign_irq_name ice-eno2np1-TxRx-0 || fail "ice eno2 not foreign"

bk=$(mktemp)
cat > "$bk" <<'BKEOF'
189|0|ice-eno1np0-TxRx-0
201|0-23|ice-0000:01:00.0:ctrl-TxRx-0
217|0-23|irdma-0000:01:00.0-AEQCEQ-0
229|0-23|irdma-0000:01:00.0-CEQ-12
230|0-23|irdma-0000:01:00.1-AEQCEQ-0
231||irdma-0000:01:00.0-CEQ-1
BKEOF
out=$(irdma_backup_lines "$bk")
[ "$out" = $'217|0-23|irdma-0000:01:00.0-AEQCEQ-0\n229|0-23|irdma-0000:01:00.0-CEQ-12' ] || fail "irdma backup lines: $(printf %q "$out")"
rm -f "$bk"
same_cpulist 0-23 0-23 || fail "same list"
same_cpulist 0-2 0,1,2 || fail "same list forms"
if same_cpulist 1 0-23; then
  fail "different lists same"
fi
if same_cpulist '' 1; then
  fail "empty list same"
fi
# collect_eno1_map against a fake /proc built from the live Johnny names.
fp=$(mktemp -d)
mkdir -p "$fp/irq"
{
  echo '           CPU0       CPU1'
  echo ' 187:  1  0  IR-PCI-MSIX-0000:01:00.0    0-edge      ice-0000:01:00.0:misc'
  echo ' 188:  1  0  IR-PCI-MSIX-0000:01:00.0    1-edge      ice-0000:01:00.0:ll_ts'
  for n in 0 1 2 3 4 5 6 7 8 9 10 11; do
    echo " $((189 + n)):  1  0  IR-PCI-MSIX-0000:01:00.0    $((n + 2))-edge      ice-eno1np0-TxRx-$n"
  done
  echo ' 201:  1  0  IR-PCI-MSIX-0000:01:00.0   14-edge      ice-0000:01:00.0:ctrl-TxRx-0'
  echo ' 217:  1  0  IR-PCI-MSIX-0000:01:00.0   15-edge      irdma-0000:01:00.0-AEQCEQ-0'
  echo ' 218:  1  0  IR-PCI-MSIX-0000:01:00.0   16-edge      irdma-0000:01:00.0-CEQ-1'
} > "$fp/interrupts"
for i in 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 217 218; do
  mkdir -p "$fp/irq/$i"
  echo 1 > "$fp/irq/$i/smp_affinity_list"
done
PROC_ROOT=$fp
list_msi() { printf '%s\n' 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 217 218; }
CAPTURE_CPUS=(1 2 3 4)
cm_out=$(collect_eno1_map; echo "rc=$?")
printf '%s\n' "$cm_out" | grep -qx 'rc=0' || fail "collect rc: $cm_out"
collect_eno1_map > /dev/null || fail "collect map"
[ "${#ENO1_IRQS[@]}" = 15 ] || fail "collect count ${#ENO1_IRQS[@]}"
printf '%s\n' "$cm_out" | grep -q 'NOTE-irdma-skip 217 irdma-0000:01:00.0-AEQCEQ-0' || fail "irdma skip note"
printf '%s\n' "$cm_out" | grep -q 'NOTE-irdma-skip 218 ' || fail "irdma skip note 218"
if printf '%s\n' "$cm_out" | grep -q 'NOTE-irq-fallback'; then
  fail "fallback on live names: $cm_out"
fi
if printf '%s\n' "$cm_out" | grep -q 'NOTE-irq-name'; then
  fail "irq-name on live names"
fi
for i in "${!ENO1_IRQS[@]}"; do
  case "${ENO1_NAMES[$i]}" in
    irdma-*) fail "irdma in pin map" ;;
    ice-eno1np0-TxRx-*)
      q=${ENO1_NAMES[$i]##*-}
      [ "${ENO1_CPUS[$i]}" = "${want_cpu[$q]}" ] || fail "map cpu ${ENO1_NAMES[$i]} ${ENO1_CPUS[$i]}"
      ;;
    *)
      [ "${ENO1_CPUS[$i]}" = 1 ] || fail "aux cpu ${ENO1_NAMES[$i]} ${ENO1_CPUS[$i]}"
      ;;
  esac
done
sed -i 's/ice-eno1np0-TxRx-3$/mystery-vector/' "$fp/interrupts"
cm_out=$(collect_eno1_map || true)
printf '%s\n' "$cm_out" | grep -q 'NOTE-irq-fallback 192 mystery-vector' || fail "unknown name fallback"
sed -i 's/mystery-vector/ice-eno2np1-TxRx-3/' "$fp/interrupts"
cm_out=$(collect_eno1_map || true)
printf '%s\n' "$cm_out" | grep -q 'STOP-irq-foreign 192' || fail "foreign stop"
rm -rf "$fp"
# shellcheck source=etc/johnny/irq-affinity.sh
source "$ROOT/etc/johnny/irq-affinity.sh"

S13B="$ROOT/docs/tool-install/step-13b-name-match.sh"
grep -q 'STEP13B-NAME-MATCH-DONE' "$S13B" || fail "13b done line"
grep -q 'irq-affinity-before.tsv' "$S13B" || fail "13b backup path"
if grep -En '>>?[[:space:]]*"?\$BEFORE|>>?[[:space:]]*/var/lib/johnny/irq-affinity-before' "$S13B" | grep -v '^[0-9]*:#'; then
  fail "13b writes the backup"
fi
host_out=$(bash "$S13B" || true)
printf '%s\n' "$host_out" | grep -qx STOP-host || fail "13b stop host: $host_out"
if grep -En 'apt-get|apt install|update-grub|update-initramfs|[[:space:]]reboot|ethtool -[LGKX]|ip link set|sysctl -w|pci=noaer|snap install|systemctl (stop|restart|start|mask|disable)' "$S13B" \
  | grep -v '^[0-9]*:#'; then
  fail "forbidden in 13b"
fi

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

out=$(split_snap '45||NONAME')
[ "$out" = $'45\n\nNONAME' ] || fail "empty mask field: $(printf %q "$out")"
out=$(split_snap '12|0-3|eno2np1-TxRx-0')
[ "$out" = $'12\n0-3\neno2np1-TxRx-0' ] || fail "snap fields: $(printf %q "$out")"
n=$(grep -c '/etc/johnny/irq-affinity.sh apply' "$ROOT/docs/tool-install/step-13-irq-affinity.sh")
[ "$n" = 1 ] || fail "helper apply count $n"
grep -q 'STOP-irq-held' "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "missing hold stop"
grep -q 'map_needs_write' "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "missing read-only hold"
grep -q 'NO-CHANGE' "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "missing NO-CHANGE"
if grep -q '/tmp/step13-irqbalance.unit' "$ROOT/docs/tool-install/step-13-irq-affinity.sh"; then
  fail "predictable tmp path"
fi

grep -q '^Wants=network-online.target$' "$ROOT/etc/systemd/system/johnny-capture-irq.service" || fail "unit wants"
if grep -q '^sudo -v$' "$ROOT/docs/tool-install/step-13-irq-affinity.md"; then
  fail "sudo -v still in the runbook paste"
fi

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

# The c765e01 apply script keeps the old helper hash on purpose. A re-run of
# that paste now stops with STOP-hash instead of reinstalling the old helper.
got=$(sha256sum "$ROOT/etc/johnny/irq-affinity.sh" | awk '{print $1}')
if grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh"; then
  fail "old apply script knows the new helper hash"
fi
grep -q '^HELPER_SHA256=77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e$' "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "old helper hash moved"
grep -q "$got" "$S13B" || fail "13b helper hash"
grep -q '^HELPER_OLD_SHA256=77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e$' "$S13B" || fail "13b old helper hash"
got=$(sha256sum "$ROOT/etc/systemd/system/johnny-capture-irq.service" | awk '{print $1}')
grep -q "$got" "$S13B" || fail "13b unit hash"
got=$(sha256sum "$ROOT/etc/johnny/irqbalance-policy.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "policy hash"
got=$(sha256sum "$ROOT/etc/systemd/system/johnny-capture-irq.service" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "unit hash"
got=$(sha256sum "$ROOT/docs/tool-install/step-13-revert.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "revert hash"
got=$(sha256sum "$ROOT/etc/johnny/capture-cores" | awk '{print $1}')
grep -q "$got" "$ROOT/etc/johnny/irq-affinity.sh" || fail "cores hash"
got=$(sha256sum "$ROOT/docs/tool-install/step-13-irq-affinity.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook apply hash"
got=$(sha256sum "$S13B" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook 13b hash"
got=$(sha256sum "$ROOT/etc/johnny/irq-affinity.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook helper hash"
got=$(sha256sum "$ROOT/docs/tool-install/step-13-revert.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook revert hash"

echo SELF-TEST-OK
