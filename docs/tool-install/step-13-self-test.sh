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
# Two bad specs must not compare equal (both flatten to STOP-cpulist).
if same_cpulist 'x' 'x'; then
  fail "two bad specs same"
fi
if same_cpulist '3-1' '3-1'; then
  fail "two reversed ranges same"
fi
if same_cpulist 'x' 1 || same_cpulist 1 'x'; then
  fail "one bad spec same"
fi
if cpulist_flat 'a-b' >/dev/null; then
  fail "cpulist_flat bad spec rc"
fi
cpulist_has_cpu0 0-23 || fail "cpu0 in 0-23"
cpulist_has_cpu0 0 || fail "cpu0 alone"
cpulist_has_cpu0 'x' || fail "bad spec is not cpu0-clear"
cpulist_has_cpu0 '' || fail "empty spec is not cpu0-clear"
if cpulist_has_cpu0 1; then fail "cpu1 has cpu0"; fi
if cpulist_has_cpu0 10-12; then fail "10-12 has cpu0"; fi
if cpulist_has_cpu0 1,2,3,4; then fail "1,2,3,4 has cpu0"; fi
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
# Rollback restores this run's entry copies, never PREV.
if grep -n 'install .*\$PREV' "$S13B" | grep -v '^[0-9]*:#'; then
  fail "13b rollback installs from PREV"
fi
grep -q 'install -m 0755 -o root -g root "\$ENTRY_DIR/irq-affinity.sh"' "$S13B" || fail "13b entry rollback helper"
grep -q 'install -m 0644 -o root -g root "\$ENTRY_DIR/johnny-capture-irq.service"' "$S13B" || fail "13b entry rollback unit"
grep -q 'STOP-prev-helper' "$S13B" || fail "13b PREV hash check"
grep -q 'STOP-queue-count' "$S13B" || fail "13b queue count stop"
grep -q 'STOP-spread-sum' "$S13B" || fail "13b spread sum stop"
grep -qx '  echo ICE-CPU0-CLEAR' "$S13B" || fail "13b ice cpu0 line"
if grep -En '^[[:space:]]*echo CPU0-CLEAR' "$S13B"; then
  fail "13b unconditional CPU0-CLEAR"
fi
if grep -n 'step13b-apply\.log' "$S13B" | grep -v '^[0-9]*:#'; then
  fail "13b fixed log name"
fi
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
  docs/tool-install/step-13f-helper-nits.sh \
  etc/johnny/irq-affinity.sh \
  etc/johnny/irqbalance-policy.sh
do
  if grep -En 'apt-get|apt install|update-grub|update-initramfs|[[:space:]]reboot|ethtool -[LGKX]|ip link set|sysctl -w|pci=noaer|snap install' "$ROOT/$f" \
    | grep -v '^[0-9]*:#'; then
    fail "forbidden in $f"
  fi
done

# Historical pins (retired scripts keep the hashes they were applied with).
HELPER_13B=29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530
UNIT_CYCLE=a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a

# The c765e01 apply script keeps the old helper hash on purpose. A re-run of
# that paste now stops with STOP-hash instead of reinstalling the old helper.
got=$(sha256sum "$ROOT/etc/johnny/irq-affinity.sh" | awk '{print $1}')
if grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh"; then
  fail "old apply script knows the new helper hash"
fi
grep -q '^HELPER_SHA256=77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e$' "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "old helper hash moved"
grep -q "$HELPER_13B" "$S13B" || fail "13b helper hash"
grep -q '^HELPER_OLD_SHA256=77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e$' "$S13B" || fail "13b old helper hash"
grep -q "$UNIT_CYCLE" "$S13B" || fail "13b unit hash"
got=$(sha256sum "$ROOT/etc/johnny/irqbalance-policy.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "policy hash"
grep -q "$UNIT_CYCLE" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "unit hash"
got=$(sha256sum "$ROOT/docs/tool-install/step-13-revert.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.sh" || fail "revert hash"
got=$(sha256sum "$ROOT/etc/johnny/capture-cores" | awk '{print $1}')
grep -q "$got" "$ROOT/etc/johnny/irq-affinity.sh" || fail "cores hash"
got=$(sha256sum "$ROOT/docs/tool-install/step-13-irq-affinity.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook apply hash"
got=$(sha256sum "$S13B" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook 13b hash"
grep -q "$HELPER_13B" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook helper hash"
got=$(sha256sum "$ROOT/docs/tool-install/step-13-revert.sh" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook revert hash"

# Ordering-cycle fix: the irq unit must not order after johnny-capture-tuning.service
# (tuning has After=multi-user.target; irq is WantedBy=multi-user.target, so that edge is a cycle).
IRQU="$ROOT/etc/systemd/system/johnny-capture-irq.service"
if grep -q 'johnny-capture-tuning' "$IRQU"; then fail "irq unit mentions tuning (ordering cycle)"; fi
grep -q '^After=network-online.target irqbalance.service$' "$IRQU" || fail "irq unit After="
grep -q '^After=multi-user.target$' "$ROOT/etc/systemd/system/johnny-capture-tuning.service" || fail "tuning unit changed"
CYC="$ROOT/docs/tool-install/step-13b-unit-cycle-fix.sh"
bash -n "$CYC" || fail "cycle-fix script syntax"
grep -q 'STEP13B-IRQ-UNIT-CYCLE-FIXED' "$CYC" || fail "cycle-fix done token"
grep -q "^UNIT_NEW_SHA256=$UNIT_CYCLE\$" "$CYC" || fail "cycle-fix unit hash"
grep -q "^HELPER_SHA256=$HELPER_13B\$" "$CYC" || fail "cycle-fix helper hash"
got=$(sha256sum "$CYC" | awk '{print $1}')
grep -q "$got" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook cycle-fix hash"
grep -q "$UNIT_CYCLE" "$ROOT/docs/tool-install/step-13-irq-affinity.md" || fail "runbook cycle-fix unit hash"

# Step 13c/13d: boot-race waits. Stub sysfs and ip; no sleeping.
WAIT_STEP_SEC=0
WAIT_BOOT_TRIES=2
WAIT_NOTE_EVERY=1
SYSFS_NET=$(mktemp -d)
mkdir -p "$SYSFS_NET/eno1np0"
# Link down: flags without UP, speed unreadable (a real NIC returns EINVAL; a directory fails the same way here).
printf '0x1002\n' > "$SYSFS_NET/eno1np0/flags"
mkdir "$SYSFS_NET/eno1np0/speed"
printf 'down\n' > "$SYSFS_NET/eno1np0/operstate"
errs=$(read_trim "$SYSFS_NET/eno1np0/speed" 2>&1 >/dev/null)
[ -z "$errs" ] || fail "read_trim spams on bad sysfs: $errs"
[ -z "$(read_trim "$SYSFS_NET/eno1np0/nope")" ] || fail "read_trim missing file"
# eno3 stub: eno3_ok is overridden so the test needs no ip(8). ENO3_STATE=bad|good.
ENO3_STATE=good
eno3_ok() {
  if [ "$ENO3_STATE" = good ]; then return 0; fi
  echo STOP-eno3-addr
  return 1
}
out=$(wait_boot_ready 2>&1) && fail "eno1 wait should time out"
printf '%s\n' "$out" | grep -q '^NOTE-wait-eno1 try=0 speed= flags=0x1002 carrier= oper=down$' || fail "eno1 wait note: $out"
if printf '%s\n' "$out" | grep -q 'NOTE-wait-eno3'; then fail "eno3 note while eno3 good"; fi
if printf '%s\n' "$out" | grep -q 'Invalid input'; then fail "eno1 wait spam"; fi
# Link comes up: admin-up, noarp, promisc, 10G, carrier.
rmdir "$SYSFS_NET/eno1np0/speed"
printf '10000\n' > "$SYSFS_NET/eno1np0/speed"
printf '0x1583\n' > "$SYSFS_NET/eno1np0/flags"
printf '1\n' > "$SYSFS_NET/eno1np0/carrier"
printf 'up\n' > "$SYSFS_NET/eno1np0/operstate"
wait_boot_ready >/dev/null || fail "boot wait should pass (eno1 up, eno3 good)"
# 13d: the live failure. eno1 up, eno3 address not visible yet: must wait and time out, not pass.
ENO3_STATE=bad
out=$(wait_boot_ready 2>&1) && fail "eno3 wait should time out"
printf '%s\n' "$out" | grep -q '^NOTE-wait-eno3 try=0 why=STOP-eno3-addr$' || fail "eno3 wait note: $out"
if printf '%s\n' "$out" | grep -q 'NOTE-wait-eno1'; then fail "eno1 note while eno1 good"; fi
# eno3 shows up on the third poll (the stub passes on its 3rd call): wait must pass without timing out.
# eno3_ready runs eno3_ok in a subshell, so count polls in a file.
ENO3_POLLS_FILE=$(mktemp)
: > "$ENO3_POLLS_FILE"
eno3_ok() {
  echo x >> "$ENO3_POLLS_FILE"
  if [ "$(wc -l < "$ENO3_POLLS_FILE")" -ge 3 ]; then return 0; fi
  echo STOP-eno3-addr
  return 1
}
WAIT_BOOT_TRIES=5
wait_boot_ready >/dev/null || fail "boot wait should pass once eno3 appears"
rm -f "$ENO3_POLLS_FILE"
rm -rf "$SYSFS_NET"
# Tuning is never waited on (B1: waiting inside the irq oneshot deadlocks at boot).
H13C="$ROOT/etc/johnny/irq-affinity.sh"
if grep -q 'wait_tuning_ready\|WAIT_TUNING_TRIES\|capture_epp_all_performance' "$H13C"; then fail "tuning wait still in helper"; fi
if grep -q 'STOP-tuning' "$H13C"; then fail "STOP-tuning still in helper"; fi
grep -q 'NOTE-tuning-not-active' "$H13C" || fail "tuning NOTE missing"
grep -q 'NOTE-tuning-not-enabled' "$H13C" || fail "tuning enabled NOTE missing"
grep -q 'NOTE-tuning-epp' "$H13C" || fail "tuning epp NOTE missing"
# Boot wait is bounded and preflight calls it. 2s x 50 = 100s; unit timeout 150 covers it.
grep -q '^WAIT_BOOT_TRIES=50$' "$H13C" || fail "boot wait tries"
grep -q '^  wait_boot_ready || true$' "$H13C" || fail "preflight boot wait"
grep -q 'wait_eno1_link' "$H13C" && fail "old eno1-only wait still present"
# preflight still runs the boot wait first and the hard eno3_ok check after it (PR #15 nit 1).
PF_BODY=$(awk '/^preflight\(\) \{/{f=1} f{print} f&&/^}/{exit}' "$H13C")
PF_WAIT=$(printf '%s\n' "$PF_BODY" | grep -n '^  wait_boot_ready || true$' | head -1 | cut -d: -f1) || true
PF_HARD=$(printf '%s\n' "$PF_BODY" | grep -n '^  if ! eno3_ok; then$' | head -1 | cut -d: -f1) || true
[ -n "$PF_WAIT" ] || fail "preflight lacks wait_boot_ready"
[ -n "$PF_HARD" ] || fail "preflight lacks hard eno3_ok check"
[ "$PF_WAIT" -lt "$PF_HARD" ] || fail "preflight hard eno3_ok check runs before the wait"
# The hard eno3 STOPs still exist after the wait (eno3_ok prints them).
for tok in STOP-eno3-addr STOP-eno3-route STOP-eno3-down; do
  grep -q "echo $tok\$" "$H13C" || fail "hard $tok missing"
done
grep -q '^TimeoutStartSec=150$' "$IRQU" || fail "irq unit TimeoutStartSec"
if grep -E '^(After|Requires|Wants|BindsTo)=.*johnny-capture-tuning' "$IRQU"; then fail "irq unit orders on tuning"; fi
MD="$ROOT/docs/tool-install/step-13-irq-affinity.md"
# 13c script stays as the record of what Johnny already ran (its own hashes).
S13C="$ROOT/docs/tool-install/step-13c-eno1-wait.sh"
bash -n "$S13C" || fail "13c syntax"
grep -q 'STEP13B-ENO1-WAIT-FIXED' "$S13C" || fail "13c done token"
S13D="$ROOT/docs/tool-install/step-13d-eno3-wait.sh"
bash -n "$S13D" || fail "13d syntax"
grep -q 'STEP13B-ENO3-WAIT-FIXED' "$S13D" || fail "13d done token"
HELPER_13C=7c475e4a29d711ea5e104a115f0df3d01730fbf3a452eb68cdc3f8a2953fe388
HELPER_13D=807f5a5599bc3e6478a6172b3a54eb576c08f0c4609047a69b834ffec8af3804
UNIT_13C=0220ecdff1cd603726b692fbd41a19c580d98640fd70cd68efcf530afa0e04ea
# 13d script stays as the record of what Johnny ran: its helper is the 13d blob.
grep -q "^HELPER_NEW_SHA256=$HELPER_13D\$" "$S13D" || fail "13d helper hash"
grep -q "^HELPER_OLD_SHA256=$HELPER_13C\$" "$S13D" || fail "13d old helper hash"
grep -q "$HELPER_13D" "$MD" || fail "runbook 13d helper hash"
# Step 13f: the repo helper is the 13f blob.
S13F="$ROOT/docs/tool-install/step-13f-helper-nits.sh"
bash -n "$S13F" || fail "13f syntax"
grep -q 'STEP13B-HELPER-NITS-FIXED' "$S13F" || fail "13f done token"
got=$(sha256sum "$H13C" | awk '{print $1}')
[ "$got" != "$HELPER_13D" ] || fail "helper still the 13d blob (13f not applied to the repo copy)"
grep -q "^HELPER_NEW_SHA256=$got\$" "$S13F" || fail "13f helper hash"
grep -q "^HELPER_OLD_SHA256=$HELPER_13D\$" "$S13F" || fail "13f old helper hash"
grep -q "$got" "$MD" || fail "runbook 13f helper hash"
got=$(sha256sum "$IRQU" | awk '{print $1}')
grep -q "^UNIT_NEW_SHA256=$got\$" "$S13D" || fail "13d unit hash"
grep -q "^UNIT_OLD_SHA256=$UNIT_13C\$" "$S13D" || fail "13d old unit hash"
grep -q "$got" "$MD" || fail "runbook 13d unit hash"
grep -q "^UNIT_SHA256=$got\$" "$S13F" || fail "13f unit hash (unit must be unchanged)"
got=$(sha256sum "$S13D" | awk '{print $1}')
grep -q "$got" "$MD" || fail "runbook 13d script hash"
got=$(sha256sum "$S13F" | awk '{print $1}')
grep -q "$got" "$MD" || fail "runbook 13f script hash"
# 13f behavior: no stderr from affinity_is_cpu with PIPE ignored (main() ignores it).
# The old process-substitution form wrote "printf: write error: Broken pipe" here.
errs=$( (trap '' PIPE; affinity_is_cpu 0-23 1) 2>&1 ) || true
[ -z "$errs" ] || fail "affinity_is_cpu spams on a wide mismatch: $errs"
errs=$( (trap '' PIPE; affinity_is_cpu 1-4 1) 2>&1 ) || true
[ -z "$errs" ] || fail "affinity_is_cpu spams on a range mismatch: $errs"
affinity_is_cpu 0-23 1 && fail "wide range matched cpu 1"
affinity_is_cpu 1-4 1 && fail "range matched cpu 1"
affinity_is_cpu 4 4 || fail "single cpu 4"
grep -q 'done < <(expand_affinity' "$H13C" && fail "affinity_is_cpu still reads a process substitution"
# 13f lint nits stay fixed.
grep -q 'local link xdp' "$H13C" && fail "unused xdp local is back"
grep -qE 'local i irq cpu snap ' "$H13C" && fail "unused snap local is back"
grep -q "tr -d '\[:space:\]' 2>/dev/null <" "$H13C" && fail "SC2261 read_trim form is back"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$H13C" || fail "shellcheck warnings in helper"
  shellcheck -S warning "$S13F" || fail "shellcheck warnings in 13f script"
else
  echo "NOTE-shellcheck-missing (lint checks skipped)"
fi

echo SELF-TEST-OK
