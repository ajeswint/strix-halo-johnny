#!/usr/bin/env bash
# Stage 2 Paste S2-1 driver: runs on Rock Box (invoked by AJ after sudo -v).
#
# Safety invariants:
# - Never modifies Johnny, router, switch, or any network/VPN state.
# - Never installs a boot unit; pins exclusively under /sys/fs/bpf/johnny_s2_cgtest.
# - Never writes AJ's interactive shell PID into cgroup.procs (uses throwaway subshells).
# - Never kills any process during cleanup or rollback.
# - EXIT trap always detaches, removes test cgroups and /run/johnny-s2-cgtest.*,
#   and verifies zero residual BPF progs/links/maps/pins/cgroups/sentinels.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOADER="$SCRIPT_DIR/loader.py"
OBJ="$SCRIPT_DIR/build/j_s2_cgtest.bpf.o"

PIN_DIR="/sys/fs/bpf/johnny_s2_cgtest"
CG_ROOT="/sys/fs/cgroup/johnny-stage2-test"
CG_CHILD="$CG_ROOT/nested-child"

SENTINEL_DIR=""
SENTINEL=""
SETUP_STARTED=0
CASE_D_DONE=0

verify_clean_residuals() {
  local stop_token="$1"
  local settle_secs="${2:-3}"
  python3 -I - "$stop_token" "$settle_secs" <<'PY'
import glob, os, subprocess, sys, time

stop_token = sys.argv[1]
settle_secs = float(sys.argv[2])
deadline = time.monotonic() + settle_secs

def scan():
    bad = []
    try:
        p_pin = subprocess.run(
            ["sudo", "test", "-e", "/sys/fs/bpf/johnny_s2_cgtest"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except OSError as exc:
        bad.append(f"pin-check-oserror={exc.errno}")
    else:
        if p_pin.returncode == 0:
            bad.append("pin-dir-exists")
        elif p_pin.returncode != 1 or p_pin.stderr.strip():
            bad.append(f"pin-check-rc={p_pin.returncode}")
    if os.path.exists("/sys/fs/cgroup/johnny-stage2-test/nested-child"):
        bad.append("cgroup-nested-exists")
    if os.path.exists("/sys/fs/cgroup/johnny-stage2-test"):
        bad.append("cgroup-root-exists")
    if glob.glob("/run/johnny-s2-cgtest.*"):
        bad.append("sentinel-dir-exists")

    checks = (
        ("prog", ["sudo", "bpftool", "prog", "list"], ("j_s2_cgtest",)),
        ("link", ["sudo", "bpftool", "link", "list", "-f"], ("johnny_s2_cgtest",)),
        ("map", ["sudo", "bpftool", "map", "list", "-f"], ("johnny_s2_cgtest", "j_s2_cgtest")),
    )
    for subcmd, cmd, needles in checks:
        try:
            p = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        except FileNotFoundError:
            bad.append(f"bpftool-{subcmd}-missing")
            continue
        except OSError as exc:
            bad.append(f"bpftool-{subcmd}-oserror={exc.errno}")
            continue
        if p.returncode != 0:
            bad.append(f"bpftool-{subcmd}-rc={p.returncode}")
        else:
            for needle in needles:
                if needle in p.stdout:
                    bad.append(f"residual-{subcmd}-{needle}")
    return bad

# Allow brief kernel RCU teardown after unpinning trampoline-attached LSM links.
while True:
    bad = scan()
    if not bad:
        sys.exit(0)
    only_rcu = all(item.startswith("residual-prog-") or item.startswith("residual-link-") or item.startswith("residual-map-") for item in bad)
    if only_rcu and time.monotonic() < deadline:
        time.sleep(0.2)
        continue
    print(f"{stop_token} " + ",".join(bad))
    sys.exit(1)
PY
}

remove_cgroup_if_exists() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    return 0
  fi
  local i=0
  while [ "$i" -lt 20 ]; do
    if sudo rmdir "$dir" 2>/dev/null; then
      return 0
    fi
    sleep 0.05
    i=$((i + 1))
  done
  sudo rmdir "$dir" || true
}

cleanup_all() {
  sudo rm -rf "$PIN_DIR" || true
  remove_cgroup_if_exists "$CG_CHILD"
  remove_cgroup_if_exists "$CG_ROOT"
  for d in /run/johnny-s2-cgtest.*; do
    if [ -e "$d" ]; then
      sudo rm -rf -- "$d" || true
    fi
  done
}

on_exit() {
  local rc=$?
  if [ "$SETUP_STARTED" -eq 1 ] && [ "$CASE_D_DONE" -eq 0 ]; then
    echo "== emergency/abort cleanup (rc=$rc)"
    cleanup_all
    if verify_clean_residuals "STOP-cleanup-residual" 3; then
      echo "CLEANUP-ON-STOP-OK"
    else
      rc=1
    fi
  fi
  exit "$rc"
}
trap on_exit EXIT

read_stat_field() {
  local stats_line="$1"
  local field="$2"
  python3 -I - "$stats_line" "$field" <<'PY'
import sys
line, field = sys.argv[1], sys.argv[2]
for tok in line.split():
    if tok.startswith(field + "="):
        print(tok.split("=", 1)[1])
        sys.exit(0)
sys.exit(1)
PY
}

echo "== preflight"
if [ ! -f "$OBJ" ]; then
  echo "STOP-missing-bpf-obj path=$OBJ"
  exit 1
fi
if [ ! -f "$LOADER" ]; then
  echo "STOP-missing-loader path=$LOADER"
  exit 1
fi

# Verify no pre-existing test artifacts before starting.
verify_clean_residuals "STOP-preflight-residual" 0

# Verify AJ's interactive shell is NOT inside the test cgroup.
shell_cg=$(cat /proc/self/cgroup)
echo "SHELL_CGROUP $shell_cg"
case "$shell_cg" in
  "0::/johnny-stage2-test"|"0::/johnny-stage2-test/"*)
    echo "STOP-case-a-in-test-cgroup cgroup=$shell_cg"
    exit 1
    ;;
esac

echo "== setup test cgroups + root-owned sentinel under /run"
SETUP_STARTED=1
sudo mkdir -p "$CG_ROOT"
sudo mkdir -p "$CG_CHILD"
SENTINEL_DIR=$(sudo mktemp -d /run/johnny-s2-cgtest.XXXXXX)
sudo chmod 0755 "$SENTINEL_DIR"
SENTINEL="$SENTINEL_DIR/true"
sudo install -o root -g root -m 0755 /bin/true "$SENTINEL"

# Pre-attach sanity check: sentinel must run cleanly unprivileged before hook attach.
if ! "$SENTINEL"; then
  echo "STOP-sentinel-precheck-failed path=$SENTINEL"
  exit 1
fi
echo "SENTINEL_PRECHECK_OK path=$SENTINEL"

echo "== verifier probe (M1 + M2) and attach"
set +e
probe_out=$(sudo python3 -I "$LOADER" probe-and-attach \
  --obj "$OBJ" \
  --pin-dir "$PIN_DIR" \
  --cgroup-dir "$CG_ROOT" \
  --sentinel "$SENTINEL" 2>&1)
probe_rc=$?
set -e
printf '%s\n' "$probe_out"
attach_line=$(printf '%s\n' "$probe_out" | grep '^ATTACH-DONE ' | tail -n 1 || true)

if [ "$probe_rc" -ne 0 ] || [ -z "$attach_line" ]; then
  if ! printf '%s\n' "$probe_out" | grep -q '^STOP-'; then
    echo "STOP-probe-and-attach-failed rc=$probe_rc"
  fi
  exit 1
fi

ACTIVE_MECH=$(read_stat_field "$attach_line" "mechanism")
M2_OBS=$(read_stat_field "$attach_line" "obs")
echo "SELECTED mechanism=$ACTIVE_MECH obs=$M2_OBS"

echo "== Case A: outside test cgroup (observe-only)"
set +e
python3 -I "$LOADER" exec-check \
  --mode outside \
  --forbidden-cgroup "0::/johnny-stage2-test" \
  --sentinel "$SENTINEL"
case_a_rc=$?
set -e

stats_a=$(sudo python3 -I "$LOADER" read-stats --pin-dir "$PIN_DIR")
echo "CASE_A_$stats_a rc=$case_a_rc"
obs_a=$(read_stat_field "$stats_a" "observed_outside")
din_a=$(read_stat_field "$stats_a" "denied_inside")
dout_a=$(read_stat_field "$stats_a" "denied_outside")
m2s_a=$(read_stat_field "$stats_a" "m2_seen")

if [ "$case_a_rc" -eq 124 ]; then
  echo "STOP-case-a-in-test-cgroup"
  exit 1
fi
if [ "$case_a_rc" -ne 0 ] || [ "$dout_a" -gt 0 ] || [ "$din_a" -gt 0 ] || [ "$m2s_a" -gt 0 ]; then
  echo "STOP-denied-outside-cgroup rc=$case_a_rc denied_inside=$din_a denied_outside=$dout_a m2_seen=$m2s_a"
  exit 1
fi
if [ "$ACTIVE_MECH" = "M1" ]; then
  if [ "$obs_a" -lt 1 ]; then
    echo "STOP-not-observed-outside mechanism=M1 observed_outside=$obs_a"
    exit 1
  fi
elif [ "$M2_OBS" = "yes" ]; then
  if [ "$obs_a" -lt 1 ]; then
    echo "STOP-not-observed-outside mechanism=M2 observed_outside=$obs_a"
    exit 1
  fi
else
  echo "NOTE-case-a-m2-no-global-observer"
fi
echo "PASS-case-a-observe-outside mechanism=$ACTIVE_MECH observed_outside=$obs_a denied_outside=$dout_a"

echo "== Case B: inside /johnny-stage2-test (enforcing)"
din_before_b="$din_a"
set +e
sudo sh -c 'echo $$ > "$1/cgroup.procs" && exec python3 -I "$2" exec-check --mode exact --expected-cgroup "0::/johnny-stage2-test" --sentinel "$3"' \
  _ "$CG_ROOT" "$LOADER" "$SENTINEL"
case_b_rc=$?
set -e

stats_b=$(sudo python3 -I "$LOADER" read-stats --pin-dir "$PIN_DIR")
echo "CASE_B_$stats_b rc=$case_b_rc"
din_b=$(read_stat_field "$stats_b" "denied_inside")

if [ "$case_b_rc" -eq 124 ]; then
  echo "STOP-case-b-wrong-cgroup"
  exit 1
fi
if [ "$case_b_rc" -ne 126 ] || [ "$din_b" -le "$din_before_b" ]; then
  echo "STOP-not-denied-inside-cgroup rc=$case_b_rc denied_before=$din_before_b denied_after=$din_b"
  exit 1
fi
echo "PASS-case-b-deny-inside mechanism=$ACTIVE_MECH denied_inside=$din_b"

echo "== Case C: inside /johnny-stage2-test/nested-child (subtree escape check)"
din_before_c="$din_b"
set +e
sudo sh -c 'echo $$ > "$1/cgroup.procs" && exec python3 -I "$2" exec-check --mode exact --expected-cgroup "0::/johnny-stage2-test/nested-child" --sentinel "$3"' \
  _ "$CG_CHILD" "$LOADER" "$SENTINEL"
case_c_rc=$?
set -e

stats_c=$(sudo python3 -I "$LOADER" read-stats --pin-dir "$PIN_DIR")
echo "CASE_C_$stats_c rc=$case_c_rc"
din_c=$(read_stat_field "$stats_c" "denied_inside")

if [ "$case_c_rc" -eq 124 ]; then
  echo "STOP-case-c-wrong-cgroup"
  exit 1
fi
if [ "$case_c_rc" -ne 126 ] || [ "$din_c" -le "$din_before_c" ]; then
  echo "STOP-subtree-escape rc=$case_c_rc denied_before=$din_before_c denied_after=$din_c"
  exit 1
fi
echo "PASS-case-c-deny-subtree mechanism=$ACTIVE_MECH denied_inside=$din_c"

echo "== Case D: detach & post-cleanup verification"
sudo rm -rf "$PIN_DIR"

# Prove sentinel runs cleanly again (both outside and inside the test cgroup)
# right after detach and BEFORE removing the test cgroup and sentinel dir.
if ! "$SENTINEL"; then
  echo "STOP-cleanup-residual sentinel-failed-outside-after-detach"
  exit 1
fi
if ! sudo sh -c 'echo $$ > "$1/cgroup.procs" && exec "$2"' _ "$CG_ROOT" "$SENTINEL"; then
  echo "STOP-cleanup-residual sentinel-failed-inside-after-detach"
  exit 1
fi
echo "POST_DETACH_SENTINEL_OK"

remove_cgroup_if_exists "$CG_CHILD"
remove_cgroup_if_exists "$CG_ROOT"
for d in /run/johnny-s2-cgtest.*; do
  if [ -e "$d" ]; then
    sudo rm -rf -- "$d"
  fi
done

verify_clean_residuals "STOP-cleanup-residual" 3
CASE_D_DONE=1
echo "PASS-case-d-clean-detach"
echo "STAGE2-CGROUP-SCOPE-PASS mechanism=$ACTIVE_MECH"
