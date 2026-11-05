#!/bin/bash
# Local checks for the step 11 paste. Does not touch a machine's network.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
# shellcheck source=docs/tool-install/step-11-e810-capture.sh
source "$ROOT/docs/tool-install/step-11-e810-capture.sh"

fail() {
  echo "SELF-TEST-FAIL $*" >&2
  exit 1
}

out=$(pick_capture_cpus 0-7 0)
[ "$out" = $'1\n2\n3\n4' ] || fail "pick lowest four: $out"
out=$(pick_capture_cpus 0-7 0,1)
[ "$out" = $'2\n3\n4\n5' ] || fail "pick excluding ht: $out"
out=$(pick_capture_cpus 8-15 0)
[ "$out" = $'8\n9\n10\n11' ] || fail "pick e-boot: $out"
if ! cpu_lists_overlap 0-7 8-23 >/tmp/step11-overlap.out; then
  fail "0-7 vs 8-23 should be disjoint"
fi
[ ! -s /tmp/step11-overlap.out ] || fail "disjoint overlap output"
if cpu_lists_overlap 0-7 6-10 >/tmp/step11-overlap.out; then
  fail "real overlap should return nonzero"
fi
grep -qx 6 /tmp/step11-overlap.out || fail "missing overlap 6"
grep -qx 7 /tmp/step11-overlap.out || fail "missing overlap 7"
is_shallow_c1 C1_ACPI || fail "C1_ACPI shallow"
is_shallow_c1 C1 || fail "C1 shallow"
if is_shallow_c1 C2_ACPI || is_shallow_c1 C3_ACPI || is_shallow_c1 C1E; then
  fail "deep state called shallow"
fi
is_keep_idle POLL || fail "keep POLL"
is_keep_idle C1_ACPI || fail "keep C1_ACPI"
if is_keep_idle C2_ACPI || is_keep_idle C3_ACPI; then
  fail "deep state kept"
fi
if pick_capture_cpus 0-2 0 >/tmp/step11-pick.out 2>/tmp/step11-pick.err; then
  fail "short list should stop"
fi
grep -q STOP-capture-cpu-count /tmp/step11-pick.out || fail "short list code"
if pick_capture_cpus '0-7;rm' 0 >/tmp/step11-pick.out 2>/tmp/step11-pick.err; then
  fail "bad list should stop"
fi
grep -q STOP-cpulist /tmp/step11-pick.out || fail "bad list code"

flags_capture_ok $((1 + 65536 + 256 + 128)) || fail "flags ok"
if flags_capture_ok $((1 + 65536 + 128)); then
  fail "flags missing promisc"
fi
flags_admin_up 1 || fail "admin up"
if flags_admin_up 65536; then
  fail "lower_up is not admin up"
fi
flags_admin_up 0x1003 || fail "hex admin up"
if flags_capture_ok 0x1003; then
  fail "hex without promisc"
fi
flags_capture_ok 0x1183 || fail "hex promisc noarp"
if flags_well_formed xyz; then
  fail "bad flags form"
fi
eno1_link_ok 10000 0x1003 1 up || fail "live link gate"
eno1_link_ok 10000 0x1003 1 down || fail "carrier alone"
eno1_link_ok 10000 0x1003 0 up || fail "operstate alone"
if eno1_link_ok 10000 0x1003 0 down; then
  fail "link without carrier"
fi
if eno1_link_ok 1000 0x1003 1 up; then
  fail "wrong speed"
fi

orig=$(mktemp)
python3 - "$ROOT/etc/netplan/00-installer-config.yaml" "$orig" <<'PY'
import pathlib, sys
src, dest = sys.argv[1:]
text = pathlib.Path(src).read_text()
drop = [
    "      # step 11: keep this port admin-down (SFP+8 end is out)\n",
    "      activation-mode: off\n",
]
if text.count(drop[1]) != 1:
    raise SystemExit("mirror missing activation-mode")
pathlib.Path(dest).write_text(text.replace("".join(drop), "", 1))
PY
status=$(edit_netplan "$orig")
[ "$status" = WROTE-yaml ] || fail "edit status $status"
if ! cmp -s "$orig" "$ROOT/etc/netplan/00-installer-config.yaml"; then
  diff -u "$ROOT/etc/netplan/00-installer-config.yaml" "$orig" || true
  fail "edited yaml != mirror"
fi
status=$(edit_netplan "$orig")
[ "$status" = ALREADY-yaml ] || fail "second edit $status"
if ! cmp -s "$orig" "$ROOT/etc/netplan/00-installer-config.yaml"; then
  fail "already rewrote the file"
fi

bad=$(mktemp)
sed 's/activation-mode: off/activation-mode: manual/' "$orig" > "$bad"
if edit_netplan "$bad" >/tmp/step11-yaml.out 2>/tmp/step11-yaml.err; then
  fail "manual activation should stop"
fi
grep -q STOP-activation-mode /tmp/step11-yaml.out || fail "manual code"

printf '%s\n' '{"map_ids":[7]}' | map_id_from_json | grep -qx 7 || fail "map id"
printf '%s\n' '[{"formatted":{"value":42},"value":["0x00"]}]' | map_value_from_json | grep -qx 42 || fail "formatted value"
printf '%s\n' '[{"value":["0x2a","0x00","0x00","0x00","0x00","0x00","0x00","0x00"]}]' | map_value_from_json | grep -qx 42 || fail "le value"
printf '%s\n' '[{"devname":"eno1np0","mode":"driver"}]' | xdp_modes_from_json eno1np0 | grep -qx driver || fail "mode"
printf '%s\n' '[]' | xdp_modes_from_json eno1np0 | grep -qx '' || fail "empty mode"

python3 - "$ROOT/docs/tool-install/step-11-e810-capture.sh" "$ROOT" <<'PY'
import pathlib, re, sys
script = pathlib.Path(sys.argv[1]).read_text()
root = pathlib.Path(sys.argv[2])
matches = list(re.finditer(r"^[ \t]*# EMBED (\S+) \d+\n.*?<<'EOF'\n(.*?)\nEOF\n", script, re.M | re.S))
if len(matches) != 4:
    raise SystemExit(f"expected 4 embeds, got {len(matches)}")
seen = []
for m in matches:
    rel, body = m.group(1), m.group(2) + "\n"
    seen.append(rel)
    disk = (root / rel).read_text()
    if disk != body:
        raise SystemExit(f"embed mismatch {rel}")
need = {
    "docs/tool-install/step-11-revert.sh",
    "etc/systemd/network/10-netplan-eno1np0.network.d/60-johnny-capture.conf",
    "etc/johnny/capture-tuning.sh",
    "etc/systemd/system/johnny-capture-tuning.service",
}
if set(seen) != need:
    raise SystemExit(f"embed set {seen}")
PY

got=$(sha256sum "$ROOT/docs/tool-install/xdp-pass-count.o" | awk '{print $1}')
[ "$got" = "$XDP_SHA256" ] || fail "xdp hash $got"
grep -q 'w0 = 0x2' <(llvm-objdump -d "$ROOT/docs/tool-install/xdp-pass-count.o") || fail "xdp pass"
grep -q 'call 0x1' <(llvm-objdump -d "$ROOT/docs/tool-install/xdp-pass-count.o") || fail "xdp helper"

if grep -nE 'NOPASSWD|apt-get|ipv6\.disable|pci=noaer|grub-mkpasswd' "$ROOT/docs/tool-install/step-11-e810-capture.sh"; then
  fail "forbidden text"
fi
if grep -nE 'disable_ipv6[[:space:]]*=' "$ROOT/docs/tool-install/step-11-e810-capture.sh"; then
  fail "ipv6 write"
fi

grep -q "trap '' HUP PIPE" "$ROOT/docs/tool-install/step-11-e810-capture.sh" || fail "missing HUP PIPE trap"
grep -q 'set -eEuo pipefail' "$ROOT/docs/tool-install/step-11-e810-capture.sh" || fail "missing set -E"
# shellcheck disable=SC2016
grep -F -q 'if [ "$rc" -ne 0 ]; then' "$ROOT/docs/tool-install/step-11-e810-capture.sh" || fail "cleanup ignores nonzero rc"
python3 - "$ROOT/docs/tool-install/step-11-revert.sh" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
unchanged = text.split("echo NETPLAN-UNCHANGED", 1)
if len(unchanged) != 2 or "networkctl reload" not in unchanged[0].split("echo NETPLAN-RESTORED", 1)[-1]:
    raise SystemExit("reload not in the unchanged branch")
PY

model=$(bash -c '
set -euo pipefail
failed=0
changed=1
ready=1
cleanup() {
  local rc=$?
  set +e
  if [ "$rc" -ne 0 ]; then failed=1; fi
  if [ "$failed" -eq 1 ] && [ "$ready" -eq 1 ] && [ "$changed" -eq 1 ]; then
    echo REVERTING
  fi
  exit "$rc"
}
trap cleanup EXIT
boom() { false; }
boom
' || true)
printf '%s\n' "$model" | grep -qx REVERTING || fail "function failure did not revert"

echo SELF-TEST-OK
