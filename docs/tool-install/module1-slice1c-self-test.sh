#!/bin/bash
# shellcheck disable=SC2015,SC2030,SC2031,SC2034,SC2317
# Local rock-box self-test for Module 1 slice 1c (boot persistence unit and
# helper for j_xdp_observe on eno1np0). Runs on rock-box WITHOUT root, touches
# no NIC, loads no BPF program, and never contacts Johnny.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
TI=$ROOT/docs/tool-install
OBJ=$TI/module1-xdp-observe.o
ATTACH=$TI/module1-slice1b-attach.sh
DETACH=$TI/module1-slice1b-detach.sh
BOOT=$TI/module1-slice1c-boot.sh
UNIT=$ROOT/etc/systemd/system/johnny-capture-xdp.service
HELPER=$ROOT/etc/johnny/irq-affinity.sh
CORES=$ROOT/etc/johnny/capture-cores
DOC=$TI/module1-slice1c-boot-unit.md
SELF=$TI/module1-slice1c-self-test.sh

WANT_OBJ_SHA=8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d
WANT_ATTACH_SHA=f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb
WANT_DETACH_SHA=f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58
WANT_BOOT_SHA=a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06
WANT_UNIT_SHA=2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0
WANT_HELPER_SHA=db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4
WANT_CORES_SHA=16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "SELF-TEST-FAIL $*" >&2
  exit 1
}

expect_eq() {
  [ "$2" = "$3" ] || fail "$1: got [$2] want [$3]"
}

has() {
  case "$2" in
    *"$3"*) ;;
    *) fail "$1: missing [$3]" ;;
  esac
}

lacks() {
  case "$2" in
    *"$3"*) fail "$1: unexpected [$3]" ;;
  esac
}

sha_of() { sha256sum "$1" | awk '{print $1}'; }
code_of() { sed -E '/^[[:space:]]*#/d' "$1"; }

# 1. Pinned sha256 checks
expect_eq "obj sha" "$(sha_of "$OBJ")" "$WANT_OBJ_SHA"
expect_eq "attach sha" "$(sha_of "$ATTACH")" "$WANT_ATTACH_SHA"
expect_eq "detach sha" "$(sha_of "$DETACH")" "$WANT_DETACH_SHA"
expect_eq "boot sha" "$(sha_of "$BOOT")" "$WANT_BOOT_SHA"
expect_eq "unit sha" "$(sha_of "$UNIT")" "$WANT_UNIT_SHA"
expect_eq "helper sha" "$(sha_of "$HELPER")" "$WANT_HELPER_SHA"
expect_eq "cores sha" "$(sha_of "$CORES")" "$WANT_CORES_SHA"

expect_eq "boot embeds OBJ_SHA256" "$(sed -n 's/^OBJ_SHA256=//p' "$BOOT")" "$WANT_OBJ_SHA"
expect_eq "boot embeds ATTACH_SHA256" "$(sed -n 's/^ATTACH_SHA256=//p' "$BOOT")" "$WANT_ATTACH_SHA"
expect_eq "boot embeds DETACH_SHA256" "$(sed -n 's/^DETACH_SHA256=//p' "$BOOT")" "$WANT_DETACH_SHA"
expect_eq "boot embeds HELPER_SHA256" "$(sed -n 's/^HELPER_SHA256=//p' "$BOOT")" "$WANT_HELPER_SHA"
expect_eq "boot embeds CORES_SHA256" "$(sed -n 's/^CORES_SHA256=//p' "$BOOT")" "$WANT_CORES_SHA"
expect_eq "boot embeds UNIT_SHA256" "$(sed -n 's/^UNIT_SHA256=//p' "$BOOT")" "$WANT_UNIT_SHA"
expect_eq "boot embeds KERNEL_WANT" "$(sed -n 's/^KERNEL_WANT=//p' "$BOOT")" "7.0.0-42-generic"
echo "PINS-OK unit=$WANT_UNIT_SHA boot=$WANT_BOOT_SHA"

# 2. Syntax and shellcheck
bash -n "$BOOT" || fail "boot.sh bash -n"
bash -n "$SELF" || fail "self-test.sh bash -n"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$BOOT" "$SELF" || fail "shellcheck"
  echo SHELLCHECK-OK
else
  echo NOTE-no-shellcheck
fi

# 3. Unit file verification + systemd-analyze verify
unit_code=$(code_of "$UNIT")
for req in \
  "After=network-online.target johnny-capture-irq.service" \
  "Wants=network-online.target johnny-capture-irq.service" \
  "ConditionPathExists=/etc/johnny/capture-cores" \
  "ConditionPathExists=/etc/johnny/irq-affinity.sh" \
  "ConditionPathExists=/root/m1s1b/module1-slice1c-boot.sh" \
  "Type=oneshot" \
  "RemainAfterExit=yes" \
  "ExecStart=/bin/bash /root/m1s1b/module1-slice1c-boot.sh start" \
  "ExecStop=/bin/bash /root/m1s1b/module1-slice1c-boot.sh stop" \
  "TimeoutStartSec=180" \
  "TimeoutStopSec=60" \
  "WantedBy=multi-user.target"; do
  has "unit directive" "$unit_code" "$req"
done
for bad in "johnny-capture-tuning.service" "Requires=" "BindsTo=" "xdpgeneric" "xdpoffload"; do
  lacks "unit forbidden directive" "$unit_code" "$bad"
done
if command -v systemd-analyze >/dev/null 2>&1; then
  sa_out=$(systemd-analyze verify "$UNIT" 2>&1 || true)
  sa_bad=$(printf '%s\n' "$sa_out" | grep -Ev 'johnny-capture-irq\.service:.*not found|/root/m1s1b/module1-slice1c-boot\.sh.*No such file|^$' || true)
  [ -z "$sa_bad" ] || fail "systemd-analyze verify errors: $sa_bad"
  echo UNIT-VERIFY-OK
else
  echo NOTE-no-systemd-analyze
fi

# 4. Static no-generic-fallback and forbidden-command checks
boot_code=$(code_of "$BOOT")
for bad in "xdpgeneric" "xdpoffload" "net attach xdp " "ip link set" "ethtool -L" "ethtool -K" \
  "sysctl -w" "apt " "apt-get" "modprobe" "pci=noaer" "NOPASSWD" \
  "systemctl start" "systemctl stop" "systemctl enable" "systemctl disable" "systemctl restart"; do
  lacks "boot.sh forbidden pattern" "$boot_code" "$bad"
done
echo STATIC-CHECKS-OK

# 5. Host gate tests on rock-box
out=$(bash "$BOOT" badarg 2>&1 && exit 1 || true)
expect_eq "badarg gate" "$out" "STOP-args"
for act in start stop verify status; do
  out=$(bash "$BOOT" "$act" 2>&1 && exit 1 || true)
  expect_eq "host gate $act" "$out" "STOP-host"
done
echo GATES-OK

# 6. Unit and E2E tests in fake environment
run_subshell_e2e() {
  local mode=$1
  (
    set +e
    # Source boot helper functions without executing main
    # shellcheck source=docs/tool-install/module1-slice1c-boot.sh
    source "$BOOT"
    start_boot_log() { :; }
    STATE_DIR=$TMP/state
    SYSFS_NET=$TMP/sys/class/net
    mkdir -p "$STATE_DIR" "$SYSFS_NET/$IFACE/statistics"
    printf '0x1183\n' > "$SYSFS_NET/$IFACE/flags"
    printf '10000\n' > "$SYSFS_NET/$IFACE/speed"
    printf '1\n' > "$SYSFS_NET/$IFACE/carrier"
    printf 'up\n' > "$SYSFS_NET/$IFACE/operstate"
    printf '1500\n' > "$SYSFS_NET/$IFACE/mtu"
    printf '1000\n' > "$SYSFS_NET/$IFACE/statistics/rx_packets"
    printf '10\n' > "$SYSFS_NET/$IFACE/statistics/rx_dropped"
    FLUSH_WAIT=0
    WAIT_STEP=0
    WAIT_BOOT_TRIES=2
    VERIFY_SECS=1

    need_tools() { :; }
    need_files() {
      echo "OK-object-hash $OBJ_SHA256"
      echo "OK-attach-hash $ATTACH_SHA256"
      echo "OK-rollback-hash $DETACH_SHA256"
      echo "OK-irq-helper-hash $HELPER_SHA256"
      echo "OK-cores-hash $CORES_SHA256"
    }
    need_unit_file() { echo "OK-unit-hash $UNIT_SHA256"; }
    root_file_ok() { echo "OK-$1-hash $3"; }
    eno3_ok() { return 0; }
    combined_now() { echo 12; }
    systemctl() {
      case "$1 $2" in
        "is-enabled suricata") echo disabled ;;
        "is-active suricata") echo inactive ;;
        "is-active johnny-capture-irq.service") echo active ;;
        "is-enabled johnny-capture-irq.service") echo enabled ;;
        "is-active johnny-capture-tuning.service") echo active ;;
        "is-enabled johnny-capture-tuning.service") echo enabled ;;
        "is-enabled johnny-capture-xdp.service") echo enabled ;;
        "is-active johnny-capture-xdp.service") echo active ;;
      esac
    }

    fake_status_attached() {
      local pkts=${1:-500} bytes=${2:-250000} xdp=${3:-"driver id=472"} ours=${4:-"1 ids=472"} pcnt=${5:-1}
      cat <<EOF
HOST johnny
KERNEL 7.0.0-42-generic
XDP-ATTACH $xdp
PROG-XDP-COUNT $pcnt
PROG-OURS $ours
PINS dir=present prog=present stats=present rxq=present
LINK eno1np0 flags=0x1183 speed=10000 carrier=1 oper=up mtu=1500
IRQ-COUNT 12
IRQ-CAPTURE ok
IRQ-BASELINE same
IRQ-SNAP ice-eno1np0-TxRx-0 irq=189 aff=1 eff=1
STAT pkts $pkts
STAT bytes $bytes
PART l3_diff=0 l4_diff=0
STAT-RXQ 0 $pkts
M1S1B-STATUS-DONE
EOF
    }

    fake_status_unattached() {
      cat <<'EOF'
HOST johnny
KERNEL 7.0.0-42-generic
XDP-ATTACH none
PROG-XDP-COUNT 0
PROG-OURS 0 ids=none
PINS dir=absent
LINK eno1np0 flags=0x1183 speed=10000 carrier=1 oper=up mtu=1500
IRQ-COUNT 12
IRQ-CAPTURE ok
IRQ-BASELINE none
IRQ-SNAP ice-eno1np0-TxRx-0 irq=189 aff=1 eff=1
M1S1B-STATUS-DONE
EOF
    }

    case "$mode" in
      ethtool-deltas)
        b=$'NIC statistics:\n     rx_packets: 100\n     rx_dropped.nic: 10\n     rx_crc_errors.nic: 0'
        a=$'NIC statistics:\n     rx_packets: 200\n     rx_dropped.nic: 14\n     rx_crc_errors.nic: 0'
        emit_ethtool_drop_deltas "$b" "$a"
        emit_ethtool_drop_deltas "$b" "$b"
        ;;
      start-cold)
        rm -f "$TMP/sc_call"
        run_detach() {
          if [ "$1" = status ]; then
            if [ ! -f "$TMP/sc_call" ]; then
              : > "$TMP/sc_call"
              fake_status_unattached
            else
              fake_status_attached
            fi
          else
            echo M1S1B-DETACH-DONE
          fi
        }
        run_attach() { echo "ATTACHED xdpdrv prog_id=472"; echo "M1S1B-ATTACH-DONE"; }
        do_start
        ;;
      start-already)
        run_detach() { fake_status_attached; }
        run_attach() { echo "SHOULD-NOT-RUN"; return 1; }
        do_start
        ;;
      start-wait-timeout)
        printf '9000\n' > "$SYSFS_NET/$IFACE/mtu"
        run_detach() { echo "SHOULD-NOT-RUN"; fake_status_unattached; }
        run_attach() { echo "SHOULD-NOT-RUN"; return 1; }
        do_start
        ;;
      start-foreign)
        run_detach() { fake_status_attached 500 250000 "driver id=999" "0 ids=none" 1; }
        do_start
        ;;
      start-rollback)
        rm -f "$TMP/sr_call"
        run_detach() {
          if [ "$1" = status ]; then
            if [ ! -f "$TMP/sr_call" ]; then
              : > "$TMP/sr_call"
              fake_status_unattached
            else
              fake_status_attached 500 250000 "generic id=472" "1 ids=472" 1
            fi
          else
            echo "DETACH-CALLED"
            echo "M1S1B-DETACH-DONE"
          fi
        }
        run_attach() { echo "M1S1B-ATTACH-DONE"; }
        do_start
        ;;
      stop-ok)
        run_detach() {
          if [ "$1" = detach ]; then echo "M1S1B-DETACH-DONE"; else fake_status_unattached; fi
        }
        HELPER=$TMP/fake-helper
        CORES=$TMP/fake-cores
        cp "$ROOT/etc/johnny/irq-affinity.sh" "$HELPER"
        chmod +x "$HELPER"
        cp "$ROOT/etc/johnny/capture-cores" "$CORES"
        do_stop
        ;;
      verify-ok)
        rm -f "$TMP/v_call" "$TMP/e_call"
        run_detach() {
          if [ ! -f "$TMP/v_call" ]; then
            : > "$TMP/v_call"
            fake_status_attached 1000 500000
          else
            printf '1500\n' > "$SYSFS_NET/$IFACE/statistics/rx_packets"
            printf '14\n' > "$SYSFS_NET/$IFACE/statistics/rx_dropped"
            fake_status_attached 1450 725000
          fi
        }
        tcpdump_verify_counts() { echo "410 0"; }
        ethtool() {
          if [ "$1" = "-l" ]; then
            printf 'Current hardware settings:\nCombined: 12\n'
          elif [ "$1" = "-S" ]; then
            if [ ! -f "$TMP/e_call" ]; then
              : > "$TMP/e_call"
              printf 'NIC statistics:\n     rx_dropped.nic: 10\n     rx_crc_errors.nic: 0\n'
            else
              printf 'NIC statistics:\n     rx_dropped.nic: 14\n     rx_crc_errors.nic: 0\n'
            fi
          fi
        }
        do_verify
        ;;
      status-ok)
        run_detach() { fake_status_attached; }
        UNIT_FILE=$TMP/nonexistent.service
        do_status
        ;;
    esac
  )
}

out=$(run_subshell_e2e ethtool-deltas)
has "ethtool delta non-zero" "$out" "ETHTOOL-DROP-DELTA rx_dropped.nic=4 (before=10 after=14)"
has "ethtool delta zero" "$out" "ETHTOOL-DROP-DELTAS none (checked=2)"
echo UNIT-TESTS-OK

out=$(run_subshell_e2e start-cold)
has "start-cold state" "$out" "STATE attached by boot helper (xdpdrv prog_id=472)"
has "start-cold token" "$out" "M1S1C-START-DONE"

out=$(run_subshell_e2e start-already)
has "start-already state" "$out" "ALREADY-ATTACHED xdpdrv prog_id=472"
has "start-already token" "$out" "M1S1C-START-DONE"
lacks "start-already no attach" "$out" "SHOULD-NOT-RUN"

out=$(run_subshell_e2e start-wait-timeout 2>&1 && exit 1 || true)
has "start-wait-timeout stop" "$out" "STOP-boot-wait-timeout tries=2 step=0s"
has "start-wait-timeout nothing-changed" "$out" "NOTHING-CHANGED"
has "start-wait-timeout stops token" "$out" "M1S1C-START-STOPS"
lacks "start-wait-timeout no status/attach" "$out" "SHOULD-NOT-RUN"
lacks "start-wait-timeout no done" "$out" "M1S1C-START-DONE"

out=$(run_subshell_e2e start-foreign 2>&1 && exit 1 || true)
has "start-foreign stop" "$out" "STOP-xdp-foreign-attached"
has "start-foreign nothing-changed" "$out" "NOTHING-CHANGED"
has "start-foreign stops token" "$out" "M1S1C-START-STOPS"

out=$(run_subshell_e2e start-rollback 2>&1 && exit 1 || true)
has "start-rollback reverting" "$out" "REVERTING-TO-CLEAN-UNATTACHED"
has "start-rollback detach" "$out" "DETACH-CALLED"
has "start-rollback stops token" "$out" "M1S1C-START-STOPS"

out=$(run_subshell_e2e stop-ok)
has "stop-ok token" "$out" "M1S1C-STOP-DONE"

out=$(run_subshell_e2e verify-ok)
has "verify-ok window" "$out" "VERIFY-WINDOW secs=1 xdp-pkts-delta=450"
has "verify-ok note drop" "$out" "NOTE-nic-rx-dropped-up delta=4"
has "verify-ok ethtool delta" "$out" "ETHTOOL-DROP-DELTA rx_dropped.nic=4 (before=10 after=14)"
has "verify-ok token" "$out" "M1S1C-VERIFY-DONE"

out=$(run_subshell_e2e status-ok)
has "status-ok unit line" "$out" "UNIT johnny-capture-xdp.service enabled=enabled active=active"
has "status-ok token" "$out" "M1S1C-STATUS-DONE"
echo "E2E-OK scenarios=8"

# 7. Runbook paste and hash audit
[ -f "$DOC" ] || fail "missing runbook $DOC"
python3 -I - "$DOC" "$WANT_OBJ_SHA" "$WANT_ATTACH_SHA" "$WANT_DETACH_SHA" "$WANT_BOOT_SHA" "$WANT_UNIT_SHA" <<'PY'
import re, sys
doc_path, obj, att, det, boot, unit = sys.argv[1:7]
text = open(doc_path).read()
lines = text.splitlines()
blocks = []
label = None
i = 0
while i < len(lines):
    s = lines[i].strip()
    if s.startswith("***<u>Run on Rock Box</u>***"):
        label = "rock"
    elif s.startswith("```bash"):
        j = i + 1
        body = []
        while j < len(lines) and not lines[j].startswith("```"):
            body.append(lines[j])
            j += 1
        blocks.append((label, "\n".join(body)))
        label = None
        i = j
    i += 1

def die(msg):
    sys.stderr.write("RUNBOOK-FAIL: " + msg + "\n")
    sys.exit(1)

if len(blocks) < 6:
    die(f"expected >=6 bash blocks, got {len(blocks)}")

def outside_single_quotes(body):
    inq = False
    for ln in body.split("\n"):
        out = []
        for ch in ln:
            if ch == "'":
                inq = not inq
            elif not inq:
                out.append(ch)
        yield "".join(out)

want = {
    "module1-xdp-observe.o": obj,
    "module1-slice1b-attach.sh": att,
    "module1-slice1b-detach.sh": det,
    "module1-slice1c-boot.sh": boot,
    "johnny-capture-xdp.service": unit,
}

for idx, (lab, body) in enumerate(blocks, 1):
    if lab != "rock":
        die(f"bash block #{idx} not preceded by ***<u>Run on Rock Box</u>***")
    if re.search(r"<[A-Za-z_][^>\n]*>", body):
        die(f"placeholder in block #{idx}: {body[:80]}")
    for s in outside_single_quotes(body):
        if re.search(r"(^|[;&|(])\s*sudo\b", s.strip()):
            die(f"sudo outside ssh -t single quotes in block #{idx}: {s}")
    if "sudo" in body:
        if "ssh -t aj@192.168.50.152" not in body:
            die(f"block #{idx} uses sudo without ssh -t aj@192.168.50.152")
        for ln in body.split("\n"):
            if "ssh -t" in ln and "sudo" in ln and not re.search(r"'sudo -v &&", ln):
                die(f"ssh -t sudo line must start with 'sudo -v &&: {ln}")
    if re.search(r"module1-slice1c-boot\.sh[ \t]+(?:status|verify|start|stop)\b[^&\n;]*\|", body) or re.search(r"\bstatus[ \t]*\|", body):
        die(f"block #{idx} pipes status/boot.sh into another command (masks exit code without pipefail)")
    if "M1S1C-COLD-BOOT-VERIFY-DONE" in body:
        if "sudo bash /root/m1s1b/module1-slice1c-boot.sh verify &&" not in body:
            die(f"block #{idx} missing unpiped verify && before M1S1C-COLD-BOOT-VERIFY-DONE")
        if "sudo bash /root/m1s1b/module1-slice1c-boot.sh status &&" not in body:
            die(f"block #{idx} missing unpiped status && before M1S1C-COLD-BOOT-VERIFY-DONE")
        if "then echo STOP-ordering-cycle-warning; false;" not in body or '"ordering cycle" ||' in body:
            die(f"block #{idx} ordering-cycle grep does not gate M1S1C-COLD-BOOT-VERIFY-DONE")
        wpos = body.find("is-active johnny-capture-xdp.service")
        if wpos < 0 or "seq 0 5 120" not in body or 'STOP-unit-not-active-after-wait' not in body:
            die(f"block #{idx} missing bounded wait for unit active")
        if wpos > body.find("module1-slice1c-boot.sh verify"):
            die(f"block #{idx} waits for unit active after verify")
    if "M1S1C-ROLLBACK-DONE" in body:
        for need in ('grep -qx "XDP-ATTACH none"', "active=inactive$", "echo STOP-rollback-not-clean; false",
                     "{ sudo systemctl reset-failed johnny-capture-xdp.service 2>/dev/null || true; } &&"):
            if need not in body:
                die(f"block #{idx} rollback token not gated: missing [{need}]")
    if "M1S1C-NITS-REINSTALL-DONE" in body:
        if body.count(boot) < 3:
            die(f"block #{idx} reinstall must check boot hash locally, on copy, and after install")
        for bad in ("systemctl restart", "systemctl start", "systemctl stop", "systemctl enable", "systemctl disable"):
            if bad in body:
                die(f"block #{idx} reinstall must not {bad}")
    for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
        name = path.rsplit("/", 1)[-1]
        if name in want and want[name] != h:
            die(f"wrong hash for {name} in block #{idx}: {h}")

bad_sample = "sudo bash /root/m1s1b/module1-slice1c-boot.sh status | grep -E '^M1S1C-' &&\necho M1S1C-COLD-BOOT-VERIFY-DONE"
if not (re.search(r"module1-slice1c-boot\.sh[ \t]+(?:status|verify|start|stop)\b[^&\n;]*\|", bad_sample) and "sudo bash /root/m1s1b/module1-slice1c-boot.sh status &&" not in bad_sample):
    die("self-check failed to reject piped status before M1S1C-COLD-BOOT-VERIFY-DONE")

joined = "\n".join(b for _, b in blocks)
if "M1S1C-COLD-BOOT-VERIFY-DONE" not in joined:
    die("missing M1S1C-COLD-BOOT-VERIFY-DONE in paste blocks")
for name, h in want.items():
    if joined.count(h) < 2:
        die(f"hash for {name} must appear in >=2 paste blocks")
for bad in ("xdpgeneric", "xdpoffload", "net attach xdp ", "pci=noaer", "NOPASSWD"):
    if bad in joined:
        die(f"forbidden text in paste block: {bad}")
print(f"RUNBOOK-OK blocks={len(blocks)}")
PY

echo SELF-TEST-OK
