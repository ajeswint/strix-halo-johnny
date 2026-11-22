# Stage 2 Prep: Rock Box BPF LSM Cgroup-Scoping Feasibility Test Runbook (DRAFT)

Rev 1, 2026-11-21 America/Chicago. Status: **DRAFT — NOT YET REVIEWED.** Nothing executed on Rock Box or Johnny. No BPF program compiled or loaded.

Review state: **DRAFT — awaiting adversarial-reviewer (Claude Code Opus medium) review before AJ runs any sudo paste (`AGENTS.md:13`).**

---

## 1. Purpose, Decisions, and Safety Guardrails

### Why this test exists
- AJ decided **O28 = C** on 2026-11-17 (`docs/architecture/architecture-rev2.md` §4 Stage 2, §7 O28): Stage 2's Rock Box Linux endpoint agent runs **observe-only** (log, do not deny), **except one enforcing test cgroup**.
- **Prerequisite (UNVERIFIED):** whether BPF LSM on Rock Box (`7.3.0-10-generic`) can reliably scope an enforcement denial (`-EPERM`) to a single test cgroup while remaining observe-only everywhere else is **UNVERIFIED**. A Fast Path feasibility test must confirm it before any enforcement work begins.

### What is already verified on Rock Box
- **2026-11-17 §3 check** (`docs/findings/stage2/2026-11-17-rockbox-fs-check.md`):
  - Kernel: `7.3.0-10-generic` (Ubuntu 26.10).
  - Filesystem: `/` and `/home` are one ext4 partition (`/dev/nvme0n1p2`, `rw,relatime`), no reflink.
  - Active LSM list (`/sys/kernel/security/lsm`): `lockdown,capability,landlock,yama,apparmor,bpf,ima,evm`.
  - Kernel config: `CONFIG_BPF_LSM=y`, `CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor,bpf"`. No kernel command-line change or reboot is needed to enable BPF LSM.
- **2026-11-17 lockdown check** (`docs/findings/stage2/2026-11-17-rockbox-lockdown.md`):
  - `/sys/kernel/security/lockdown`: `[none] integrity confidentiality`. Lockdown is `none`.

### What remains UNVERIFIED until Paste S2-0 runs
1. Kernel BTF file `/sys/kernel/btf/vmlinux` presence and readability.
2. Unified cgroup v2 mount (`cgroup2`) at `/sys/fs/cgroup`.
3. `bpftool feature probe kernel` confirmation of `BPF_PROG_TYPE_LSM`, `BPF_MAP_TYPE_CGROUP_ARRAY`, `BPF_MAP_TYPE_CGRP_STORAGE`, and BTF symbol availability for `BPF_LSM_CGROUP` plus cgroup helpers (`bpf_get_current_cgroup_id`, `bpf_get_current_ancestor_cgroup_id`, `bpf_current_task_under_cgroup`).
4. Local build toolchain availability on Rock Box (`bpftool`, `clang`, `llvm-strip`, `gcc`, `systemd-run`, `minisign`).
5. Actual kernel verifier acceptance and runtime isolation of a cgroup-scoped BPF LSM hook (proven only by the follow-up **Paste S2-1** after Fast Path implements the minimal test program).

### Workstation safety guardrails (hard rules)
- Rock Box is AJ's active desktop workstation (hosts Chrome, Steam, `ROCK-BOX-BOT`, DMT Console, and every Johnny SSH session).
- **Never** touch Johnny (`192.168.50.152`), the router, the switch, or any network interface/VPN kill switch.
- **Never** enable any feasibility test program at boot; all test pins stay under `/sys/fs/bpf/johnny_s2_cgtest/` and are detached immediately at test end.
- **Fail-open on uninitialized config:** the test LSM program must return `0` (allow) whenever the target cgroup ID in its config map is `0` or unset.
- **Double-gated deny during feasibility test:** even *inside* the dedicated test cgroup, the minimal test denies only a dedicated throwaway sentinel target (not `bash`, `sudo`, `systemd`, or real desktop apps), so a mistake inside the test cgroup cannot wedge the shell.

---

## 2. Paste S2-0A: Unprivileged Read-Only Probe (No Sudo, No Writes)

Checks kernel version, `bpf` in `/sys/kernel/security/lsm`, lockdown state, `/sys/kernel/btf/vmlinux`, `/sys/fs/cgroup` mount type (`cgroup2`), kernel config flags, `unprivileged_bpf_disabled`, and available tools. Makes zero changes.

***<u>Run on Rock Box</u>***

```bash
(
  set -u
  echo "== kernel"
  kver=$(uname -r) || { echo "STOP-probe-uname"; exit 1; }
  echo "KERNEL $kver"
  echo "== active LSM list"
  if [ ! -r /sys/kernel/security/lsm ]; then echo "STOP-probe-lsm-unreadable"; exit 1; fi
  lsm_list=$(cat /sys/kernel/security/lsm)
  echo "LSM_LIST $lsm_list"
  case ",$lsm_list," in
    *,bpf,*) echo "PASS-probe-lsm-bpf" ;;
    *) echo "STOP-probe-no-bpf-lsm"; exit 1 ;;
  esac
  echo "== kernel lockdown"
  if [ -r /sys/kernel/security/lockdown ]; then
    echo "LOCKDOWN $(cat /sys/kernel/security/lockdown)"
  else
    echo "NOTE-lockdown-unreadable"
  fi
  echo "== BTF vmlinux"
  if [ -r /sys/kernel/btf/vmlinux ] && [ -s /sys/kernel/btf/vmlinux ]; then
    btf_bytes=$(stat -c '%s' /sys/kernel/btf/vmlinux)
    echo "PASS-probe-btf bytes=$btf_bytes"
  else
    echo "STOP-probe-no-btf"; exit 1
  fi
  echo "== cgroup mount"
  cg_fstype=$(findmnt -no FSTYPE --target /sys/fs/cgroup 2>/dev/null || echo unknown)
  cg_root_id=$(stat -c '%i' /sys/fs/cgroup 2>/dev/null || echo unknown)
  echo "CGROUP_MOUNT fstype=$cg_fstype root_inode=$cg_root_id"
  if [ "$cg_fstype" = "cgroup2" ]; then
    echo "PASS-probe-cgroup2"
  else
    echo "STOP-probe-not-cgroup2"; exit 1
  fi
  echo "== kernel config"
  cfg="/boot/config-$kver"
  if [ -r "$cfg" ]; then
    grep -E '^CONFIG_(BPF_LSM|BPF_SYSCALL|DEBUG_INFO_BTF|CGROUPS|CGROUP_BPF|LSM)=' "$cfg" || true
  else
    echo "NOTE-config-unreadable path=$cfg"
  fi
  echo "== unprivileged_bpf_disabled"
  sysctl -n kernel.unprivileged_bpf_disabled 2>/dev/null | sed 's/^/UNPRIV_BPF /' || echo "NOTE-sysctl-unreadable"
  echo "== toolchain inventory"
  for tool in bpftool clang llvm-strip gcc systemd-run python3 minisign; do
    p=$(command -v "$tool" 2>/dev/null || true)
    if [ -n "$p" ]; then
      echo "TOOL $tool=$p"
    else
      echo "TOOL $tool=MISSING"
    fi
  done
  if command -v bpftool >/dev/null 2>&1; then
    echo "BPFTOOL_VERSION $(bpftool version 2>/dev/null | sed -n '1p')"
  fi
  echo "STAGE2-PROBE-RO-DONE"
)
```

### Expect (Paste S2-0A)
- `PASS-probe-lsm-bpf`, `PASS-probe-btf bytes=<N>`, `PASS-probe-cgroup2`, toolchain inventory lines (`TOOL <name>=...`), and final token **`STAGE2-PROBE-RO-DONE`**.
- Any `STOP-probe-*` halts before `STAGE2-PROBE-RO-DONE`; send the full output back.
- Note: `TOOL clang=MISSING` or `TOOL minisign=MISSING` is informational, not a stop for the probe; it tells Platform/Fast Path what build tools are not yet installed on Rock Box.

---

## 3. Paste S2-0B: Privileged Read-Only `bpftool feature` + BTF Probe (Requires Sudo; Review Gate Before Running)

Runs `sudo bpftool feature probe kernel full` (read-only kernel capability probes; loads no persistent BPF program, attaches nothing, pins nothing) and checks BTF symbols in `/sys/kernel/btf/vmlinux` for `BPF_PROG_TYPE_LSM`, `BPF_LSM_MAC`, `BPF_LSM_CGROUP`, `BPF_MAP_TYPE_CGROUP_ARRAY`, `BPF_MAP_TYPE_CGRP_STORAGE`, and the cgroup helpers (`bpf_get_current_cgroup_id`, `bpf_get_current_ancestor_cgroup_id`, `bpf_current_task_under_cgroup`).

**Important `bpftool` caveat (documented in `libbpf` / `bpftool`):** `bpftool feature probe kernel` often omits or leaves empty the per-helper list for `BPF_PROG_TYPE_LSM` (as well as `tracing`, `struct_ops`, and `ext`) because probing a `BPF_PROG_TYPE_LSM` program requires a concrete kernel hook BTF ID (`attach_btf_id`) rather than a generic stub load. Therefore, Paste S2-0B checks `program_type lsm` and cgroup map types from `bpftool feature probe`, reports any `lsm` helpers if `bpftool` lists them (printing `NOTE-lsm-helpers-not-probed-by-bpftool` instead of false-stopping if omitted), prints reference helper availability on `kprobe`/`tracepoint`/`cgroup_skb`, and verifies the exact helper/attach-type enum entries in `/sys/kernel/btf/vmlinux`. Definitive verifier confirmation of an LSM program calling those helpers happens in **Phase 2 (Paste S2-1)**.

***<u>Run on Rock Box</u>***

```bash
sudo -v &&
(
  set -eu
  if ! command -v bpftool >/dev/null 2>&1; then
    echo "STOP-probe-no-bpftool"
    exit 1
  fi
  tmp_probe=$(mktemp /tmp/johnny-s2-bpftool-probe.XXXXXX)
  trap 'rm -f "$tmp_probe"' EXIT
  sudo bpftool feature probe kernel full >"$tmp_probe" 2>&1 || {
    echo "STOP-probe-bpftool-failed"
    cat "$tmp_probe"
    exit 1
  }
  python3 -I - "$tmp_probe" <<'PY'
import re, sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()

def has_line(pat):
    return re.search(pat, text, re.M) is not None

lsm_prog = has_line(r"eBPF program_type lsm is available")
cg_arr = has_line(r"eBPF map_type cgroup_array is available")
cgrp_st = has_line(r"eBPF map_type cgrp_storage is available")

print(f"PROG_TYPE_LSM {'available' if lsm_prog else 'MISSING'}")
print(f"MAP_TYPE_CGROUP_ARRAY {'available' if cg_arr else 'MISSING'}")
print(f"MAP_TYPE_CGRP_STORAGE {'available' if cgrp_st else 'MISSING'}")

if not lsm_prog:
    print("STOP-probe-no-lsm-prog-type")
    sys.exit(1)
print("PASS-probe-lsm-prog-type")

blocks = {}
cur = None
for ln in text.splitlines():
    m = re.match(r"^eBPF helpers supported for program type (\S+):\s*$", ln)
    if m:
        cur = m.group(1)
        blocks[cur] = []
        continue
    if cur is not None:
        if ln.startswith("\t") or ln.startswith("  "):
            blocks[cur].append(ln.strip())
        elif ln.strip() == "":
            cur = None

wanted = [
    "bpf_get_current_cgroup_id",
    "bpf_get_current_ancestor_cgroup_id",
    "bpf_current_task_under_cgroup",
]
if "lsm" in blocks and blocks["lsm"]:
    lsm_set = set(blocks["lsm"])
    for h in wanted:
        print(f"LSM_HELPER {h}={'available' if h in lsm_set else 'absent'}")
    if "bpf_get_current_cgroup_id" in lsm_set:
        print("PASS-probe-lsm-cgroup-id")
    else:
        print("NOTE-lsm-cgroup-id-not-listed-in-bpftool")
else:
    print("NOTE-lsm-helpers-not-probed-by-bpftool (libbpf skips generic helper probe for BTF-target LSM progs; S2-1 verifier check confirms)")

for ref_type in ("kprobe", "tracepoint", "cgroup_skb"):
    if ref_type in blocks and blocks[ref_type]:
        ref_set = set(blocks[ref_type])
        found = [h for h in wanted if h in ref_set]
        print(f"REF_HELPERS {ref_type}={' '.join(found) if found else 'none'}")
PY
  echo "== BTF enum checks (BPF_LSM_CGROUP + cgroup helpers)"
  python3 -I - <<'PY'
import subprocess, sys

p = subprocess.run(
    ["sudo", "bpftool", "btf", "dump", "file", "/sys/kernel/btf/vmlinux", "format", "c"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
if p.returncode != 0:
    print(f"STOP-probe-btf-dump-failed rc={p.returncode}")
    sys.exit(1)
btf = p.stdout
for sym in (
    "BPF_PROG_TYPE_LSM",
    "BPF_LSM_MAC",
    "BPF_LSM_CGROUP",
    "BPF_FUNC_get_current_cgroup_id",
    "BPF_FUNC_get_current_ancestor_cgroup_id",
    "BPF_FUNC_current_task_under_cgroup",
    "BPF_MAP_TYPE_CGROUP_ARRAY",
    "BPF_MAP_TYPE_CGRP_STORAGE",
):
    print(f"BTF_SYM {sym}={'present' if sym in btf else 'absent'}")
if "BPF_FUNC_get_current_cgroup_id" not in btf:
    print("STOP-probe-btf-no-cgroup-id-helper")
    sys.exit(1)
print("PASS-probe-btf-cgroup-syms")
PY
  echo "STAGE2-CGROUP-PROBE-DONE"
)
```

### Expect (Paste S2-0B)
- `PASS-probe-lsm-prog-type`, `MAP_TYPE_CGROUP_ARRAY available`, `MAP_TYPE_CGRP_STORAGE available`, `BTF_SYM BPF_LSM_CGROUP=present`, `BTF_SYM BPF_FUNC_get_current_cgroup_id=present`, `BTF_SYM BPF_FUNC_get_current_ancestor_cgroup_id=present`, `BTF_SYM BPF_FUNC_current_task_under_cgroup=present`, `PASS-probe-btf-cgroup-syms`, and final token **`STAGE2-CGROUP-PROBE-DONE`**.
- `NOTE-lsm-helpers-not-probed-by-bpftool` is expected on standard `bpftool` builds and is not a failure.
- Any `STOP-probe-*` halts before `STAGE2-CGROUP-PROBE-DONE`; send the full output back.

---

## 4. Phase 2: Minimal Cgroup-Scoping Feasibility Test Design (Spec — Not Yet Built)

Once AJ runs Pastes S2-0A and S2-0B and approves the design below, Fast Path drafts the tiny C BPF program and reviewed **Paste S2-1** in a follow-up implementation PR. No code is compiled or loaded in this draft.

### 4.1 Two Kernel Mechanisms to Evaluate

| Mechanism | Attach Type | How scoping works | Observe + Deny in O28 C | Tradeoffs / Caveats |
|---|---|---|---|---|
| **Mechanism 1 (Primary candidate): Global `SEC("lsm/<hook>")` + in-program cgroup check** | `BPF_LSM_MAC` | Program checks `bpf_current_task_under_cgroup(&cg_array, 0)` (or `bpf_get_current_ancestor_cgroup_id(target_level) == target_cgid`, plus leaf `bpf_get_current_cgroup_id() == target_cgid`). | **Single program:** returns `0` (allow) and increments `observed_outside` outside the test cgroup; returns `-EPERM` and increments `denied_inside` inside the test cgroup. | Must get subtree matching right (leaf `bpf_get_current_cgroup_id()` alone misses child cgroups spawned inside the test slice). Runs on every hook invocation host-wide, so the fast-path reject (outside cgroup) must be O(1) and fail-open (`return 0`) on any map/config error. |
| **Mechanism 2 (Alternative): Cgroup-attached `SEC("lsm_cgroup/<hook>")`** | `BPF_LSM_CGROUP` | Kernel attaches the enforcing LSM program directly to the test cgroup v2 directory fd; the kernel itself invokes the hook only for tasks/sockets in that cgroup subtree. | **Two programs:** global observe-only `SEC("lsm/<hook>")` always returns `0`; separate `SEC("lsm_cgroup/<hook>")` attached to the test cgroup returns `0` (deny) or `1` (allow). | Strongest kernel-enforced isolation (the denying code physically never executes outside the test cgroup). **Caveats:** inverted return value (`1` allow / `0` deny vs global `0` allow / `-EPERM` deny), non-sleepable programs only (`BPF_F_SLEEPABLE` rejected), and per-hook support for `BPF_LSM_CGROUP` must be verified on `7.3.0-10-generic` (`socket_*` hooks are standard; `bprm_check_security` support under `BPF_LSM_CGROUP` is **UNVERIFIED**). |

### 4.2 Minimal Test Program & Double-Gated Target

To keep blast radius effectively zero on Rock Box:
1. **Dedicated test cgroup:** a transient cgroup v2 subtree created solely for the test:
   - Parent test cgroup: `/sys/fs/cgroup/johnny-stage2-test.slice` (or `systemd-run --slice=johnny-stage2-test.slice ...`).
   - Nested child cgroup (for Case C subtree proof): `/sys/fs/cgroup/johnny-stage2-test.slice/nested-child`.
2. **Double-gated sentinel target (choose one hook for S2-1; default recommendation = Hook A):**
   - **Hook A (`lsm/bprm_check_security`, directly tests Stage 2 exec hook):**
     - Copy `/bin/true` to `/tmp/johnny-s2-test-sentinel` (`0755`) and record its `(st_dev, st_ino)` into a config map `s2_cfg` alongside `target_cgid` / `target_level` (and/or cgroup fd in `BPF_MAP_TYPE_CGROUP_ARRAY`).
     - In `j_s2_cgtest_bprm`:
       1. If `s2_cfg.enabled == 0` or `s2_cfg.sentinel_ino == 0` or `s2_cfg.target_cgid == 0`: **fail open (`return 0`)**.
       2. Check `bprm->file->f_inode->i_ino == s2_cfg.sentinel_ino` (and matching `s_dev`). If not the sentinel binary: **`return 0` immediately** (zero effect on any real process anywhere on Rock Box).
       3. Check cgroup membership (subtree check via `bpf_current_task_under_cgroup` or `bpf_get_current_ancestor_cgroup_id(target_level) == target_cgid`, plus record leaf `bpf_get_current_cgroup_id()` in stats).
       4. If **outside** the test cgroup: increment `stats.observed_outside`, emit/record, **`return 0` (allow)**.
       5. If **inside** the test cgroup: increment `stats.denied_inside`, **`return -EPERM` (deny)**.
   - **Hook B (`lsm/socket_connect`, optional second test for Stage 2 network gating):**
     - Same cgroup gate, double-gated on loopback destination `127.0.0.1:19999` only (never touches LAN, router, VPN, or Johnny). Denies (`-EPERM`) inside the test cgroup and observes (`return 0`) outside.
3. **Pins & lifetime:**
   - Pin exclusively under `/sys/fs/bpf/johnny_s2_cgtest/` (link + maps).
   - Never install a systemd boot unit. Run the four cases below synchronously inside one reviewed `sudo` block with an `EXIT` trap that unpins and cleans up even on failure.

### 4.3 Four-Case Proof Matrix (Required for `STAGE2-CGROUP-SCOPE-PASS`)

| Case | Where the sentinel runs | Expected execution result | Expected BPF map counters | Failure / STOP token |
|---|---|---|---|---|
| **A — Outside test cgroup (observe-only)** | AJ's normal shell cgroup (outside `johnny-stage2-test.slice`) | Exits `0` (allowed, **never** `-EPERM`) | `observed_outside >= 1`, `denied_outside == 0` | `STOP-denied-outside-cgroup` (if exit != 0 or `denied_outside > 0`), `STOP-not-observed-outside` (if `observed_outside == 0`) |
| **B — Inside test cgroup (enforcing)** | Inside `johnny-stage2-test.slice` | Fails with `EPERM` (`Operation not permitted`) | `denied_inside >= 1` | `STOP-not-denied-inside-cgroup` (if sentinel exited `0` or `denied_inside == 0`) |
| **C — Nested child cgroup (subtree escape check)** | Inside `johnny-stage2-test.slice/nested-child` | Fails with `EPERM` (proves child cgroups cannot bypass enforcement) | `denied_inside` increments by `>= 1` again | `STOP-subtree-escape` (documents that leaf-only `bpf_get_current_cgroup_id()` is insufficient and subtree matching is required) |
| **D — Detach & post-cleanup verification** | After removing `/sys/fs/bpf/johnny_s2_cgtest` and test cgroup | Sentinel exits `0` again; `bpftool prog list` and `bpftool link list` show zero `j_s2_cgtest` entries | Pin dir absent; test slice absent | `STOP-cleanup-residual` (if any prog/link/pin/slice remains) |

### 4.4 PASS / STOP Token Contract

| Token | Phase | Meaning |
|---|---|---|
| `PASS-probe-lsm-bpf` | S2-0A | `bpf` is present in `/sys/kernel/security/lsm`. |
| `PASS-probe-btf` | S2-0A | `/sys/kernel/btf/vmlinux` exists and is non-empty. |
| `PASS-probe-cgroup2` | S2-0A | `/sys/fs/cgroup` is mounted as unified `cgroup2`. |
| `STAGE2-PROBE-RO-DONE` | S2-0A | Unprivileged probe completed with all S2-0A prerequisites met. |
| `PASS-probe-lsm-prog-type` | S2-0B | `bpftool feature probe kernel` reports `program_type lsm` available. |
| `PASS-probe-btf-cgroup-syms` | S2-0B | Kernel BTF exports `BPF_FUNC_get_current_cgroup_id` (and prints status of ancestor/under-cgroup/`BPF_LSM_CGROUP` symbols). |
| `STAGE2-CGROUP-PROBE-DONE` | S2-0B | Privileged read-only probe completed cleanly. |
| `PASS-case-a-observe-outside` | S2-1 (planned) | Outside test cgroup: allowed (`exit 0`), `observed_outside >= 1`, `denied_outside == 0`. |
| `PASS-case-b-deny-inside` | S2-1 (planned) | Inside test cgroup: denied (`EPERM`), `denied_inside >= 1`. |
| `PASS-case-c-deny-subtree` | S2-1 (planned) | Nested child cgroup: denied (`EPERM`), proving subtree coverage. |
| `PASS-case-d-clean-detach` | S2-1 (planned) | Detach verified, sentinel runs cleanly again, zero residual BPF objects. |
| `STAGE2-CGROUP-SCOPE-PASS` | S2-1 (planned) | All four cases passed; O28 C cgroup scoping is **VERIFIED** on Rock Box. |
| `STOP-probe-*` | S2-0A / S2-0B | Prerequisite missing or probe command failed; do not proceed to S2-1. |
| `STOP-denied-outside-cgroup` | S2-1 (planned) | **Critical safety stop:** hook denied outside the test cgroup; immediate detach + rollback. |
| `STOP-not-observed-outside` | S2-1 (planned) | Hook failed to observe execution outside test cgroup. |
| `STOP-not-denied-inside-cgroup` | S2-1 (planned) | Hook failed to deny sentinel inside test cgroup. |
| `STOP-subtree-escape` | S2-1 (planned) | Nested child cgroup bypassed the check; switch to subtree helper or `BPF_LSM_CGROUP`. |
| `STOP-cleanup-residual` / `STOP-rollback-residual` | S2-1 / Rollback | Residual BPF program, link, pin dir, or test cgroup still present after cleanup. |
| `STAGE2-CGTEST-ROLLBACK-DONE` | Rollback | Clean idempotent rollback verified. |

---

## 5. Rollback (not part of the paste sequence above)

- **For Pastes S2-0A and S2-0B:** read-only; no system state is modified, so no rollback is required.
- **For the future Paste S2-1 feasibility test:** if S2-1 is ever interrupted before its `EXIT` trap runs, this standalone idempotent rollback block removes the test pin directory (which detaches any pinned test BPF links/programs), cleans up the test cgroup and sentinel file, and verifies zero residual test objects remain.

***<u>Run on Rock Box</u>***

```bash
sudo -v &&
(
  set -eu
  sudo rm -rf /sys/fs/bpf/johnny_s2_cgtest
  sudo systemctl stop johnny-stage2-test.slice 2>/dev/null || true
  if [ -d /sys/fs/cgroup/johnny-stage2-test.slice/nested-child ]; then
    sudo rmdir /sys/fs/cgroup/johnny-stage2-test.slice/nested-child 2>/dev/null || true
  fi
  if [ -d /sys/fs/cgroup/johnny-stage2-test.slice ]; then
    sudo rmdir /sys/fs/cgroup/johnny-stage2-test.slice 2>/dev/null || true
  fi
  rm -f /tmp/johnny-s2-test-sentinel
  python3 -I - <<'PY'
import os, subprocess, sys

bad = []
if os.path.exists("/sys/fs/bpf/johnny_s2_cgtest"):
    bad.append("pin-dir-exists")
for subcmd, needle in (("prog", "j_s2_cgtest"), ("link", "johnny_s2_cgtest")):
    p = subprocess.run(
        ["sudo", "bpftool", subcmd, "list"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if p.returncode != 0:
        bad.append(f"bpftool-{subcmd}-rc={p.returncode}")
    elif needle in p.stdout:
        bad.append(f"residual-{subcmd}-{needle}")
if bad:
    print("STOP-rollback-residual " + ",".join(bad))
    sys.exit(1)
print("STAGE2-CGTEST-ROLLBACK-DONE")
PY
)
```

---

## 6. Assumptions and Sources

### Marked assumptions
- **Assumption:** `bpftool feature probe kernel full` emits `eBPF program_type lsm is available`, `eBPF map_type cgroup_array is available`, and `eBPF map_type cgrp_storage is available` in the standard `bpftool` text format on Rock Box's installed `bpftool` version. Paste S2-0A prints `BPFTOOL_VERSION`, and if `bpftool` text phrasing differs, S2-0B prints the exact status rather than silently passing.
- **Assumption:** `clang` / `llvm-strip` and `minisign` may not yet be installed on Rock Box; S2-0A inventories them without installing anything.
- **Assumption:** Whether `BPF_LSM_CGROUP` supports `bprm_check_security` (in addition to `socket_*` hooks) on kernel `7.3.0-10-generic` is **UNVERIFIED** until tested in S2-1.

### External sources
- Linux kernel docs, *LSM BPF Programs*: https://docs.kernel.org/bpf/bpf_lsm.html
- Linux kernel docs, *LSM usage* (`/sys/kernel/security/lsm`): https://docs.kernel.org/admin-guide/LSM/index.html
- Linux kernel docs, *Control Group v2*: https://docs.kernel.org/admin-guide/cgroup-v2.html
- Linux kernel docs, *BPF Type Format (BTF)*: https://docs.kernel.org/bpf/btf.html
- Linux kernel docs, *`BPF_MAP_TYPE_CGRP_STORAGE`*: https://docs.kernel.org/bpf/map_cgrp_storage.html
- Linux man-pages, *`bpf-helpers(7)`* (`bpf_get_current_cgroup_id`, `bpf_get_current_ancestor_cgroup_id`, `bpf_current_task_under_cgroup`): https://man7.org/linux/man-pages/man7/bpf-helpers.7.html
