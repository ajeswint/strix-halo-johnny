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
  - Kernel: `7.3.0-10-generic`.
  - Filesystem: `/` and `/home` are one ext4 partition (`/dev/nvme0n1p2`, `rw,relatime`), no reflink.
  - Active LSM list (`/sys/kernel/security/lsm`): `lockdown,capability,landlock,yama,apparmor,bpf,ima,evm`.
  - Kernel config: `CONFIG_BPF_LSM=y`, `CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor,bpf"`. No kernel command-line change or reboot is needed to enable BPF LSM.
- **Rock Box `/etc/os-release`:** `Ubuntu 26.10` (`PRETTY_NAME="Ubuntu 26.10"`).
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
    if bpftool_out=$(bpftool version 2>/dev/null) && [ -n "$bpftool_out" ]; then
      echo "BPFTOOL_VERSION $(printf '%s\n' "$bpftool_out" | sed -n '1p')"
    else
      echo "NOTE-bpftool-version-failed"
    fi
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

Runs `sudo bpftool feature probe kernel` (read-only kernel capability probes; loads no persistent BPF program, attaches nothing, pins nothing) and checks BTF symbols in `/sys/kernel/btf/vmlinux` (read unprivileged, since `/sys/kernel/btf/vmlinux` is `0444`) for `BPF_PROG_TYPE_LSM`, `BPF_LSM_MAC`, `BPF_LSM_CGROUP`, `BPF_MAP_TYPE_CGROUP_ARRAY`, `BPF_MAP_TYPE_CGRP_STORAGE`, and the cgroup helpers (`bpf_get_current_cgroup_id`, `bpf_get_current_ancestor_cgroup_id`, `bpf_current_task_under_cgroup`).

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
  sudo bpftool feature probe kernel >"$tmp_probe" 2>&1 || {
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
        if ln.startswith("\t") or ln.startswith("  ") or ln.lstrip().startswith("- "):
            item = re.sub(r"^-\s+", "", ln.strip())
            if item:
                blocks[cur].append(item)
        else:
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

try:
    p = subprocess.run(
        ["bpftool", "btf", "dump", "file", "/sys/kernel/btf/vmlinux", "format", "c"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
except OSError as exc:
    print(f"STOP-probe-btf-dump-oserror errno={exc.errno}")
    sys.exit(1)
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

### 4.1 Two Kernel Mechanisms — Selection for S2-1

| Mechanism | Attach Type | How scoping works | Observe + Deny in O28 C | Tradeoffs / Caveats |
|---|---|---|---|---|
| **Mechanism 1 (S2-1 primary): Global `SEC("lsm/<hook>")` + in-program subtree cgroup check** | `BPF_LSM_MAC` | Program checks `bpf_current_task_under_cgroup(&cg_array, 0)` (or `bpf_get_current_ancestor_cgroup_id(target_level) == target_cgid`, plus leaf `bpf_get_current_cgroup_id()` for telemetry). | **Single program:** returns `0` (allow) and increments `observed_outside` outside the test cgroup; returns `-EPERM` and increments `denied_inside` inside the test cgroup. | Must use subtree matching (leaf `bpf_get_current_cgroup_id()` alone misses child cgroups). Runs on every hook invocation host-wide, so the fast-path reject (outside cgroup) must be O(1) and fail-open (`return 0`) on any map/config error. |
| **Mechanism 2 (Informational verifier check only in S2-1): Cgroup-attached `SEC("lsm_cgroup/<hook>")`** | `BPF_LSM_CGROUP` | Kernel attaches the enforcing LSM program directly to the test cgroup v2 directory fd; the kernel itself invokes the hook only for tasks/sockets in that cgroup subtree. | **Two programs:** global observe-only `SEC("lsm/<hook>")` always returns `0`; separate `SEC("lsm_cgroup/<hook>")` attached to the test cgroup returns `0` (deny) or `1` (allow). | Strongest kernel-enforced isolation (the denying code physically never executes outside the test cgroup). **Caveats:** inverted return value (`1` allow / `0` deny vs global `0` allow / `-EPERM` deny), non-sleepable programs only (`BPF_F_SLEEPABLE` rejected), and per-hook support for `BPF_LSM_CGROUP` on `bprm_check_security` is **UNVERIFIED** on `7.3.0-10-generic` (`socket_*` hooks are standard). |

**S2-1 choice:** S2-1 proves O28 C using **Mechanism 1** (`SEC("lsm/bprm_check_security")` + subtree helper: `bpf_current_task_under_cgroup` or `bpf_get_current_ancestor_cgroup_id`), because `BPF_LSM_CGROUP` support for `bprm_check_security` is UNVERIFIED and may be rejected by the verifier. Separately, S2-1 records whether kernel `7.3.0-10-generic`'s verifier accepts a one-shot load of Mechanism 2 (`SEC("lsm_cgroup/bprm_check_security")`, no persistent attach) as an informational `NOTE-lsm-cgroup-bprm=accepted|rejected` line without gating the O28 C proof on it.

### 4.2 Minimal Test Program & Double-Gated Target

To keep blast radius effectively zero on Rock Box:
1. **Dedicated test cgroup (single creation method — raw cgroupfs only):**
   - Use raw root-made cgroupfs directories (**not** `systemd-run` / `*.slice`, respecting systemd's single-writer rule and ensuring Case B runs directly in the parent cgroup rather than an implicit child unit scope):
     - Parent test cgroup: `/sys/fs/cgroup/johnny-stage2-test` (`sudo mkdir -p /sys/fs/cgroup/johnny-stage2-test`).
     - Nested child cgroup (for Case C subtree proof): `/sys/fs/cgroup/johnny-stage2-test/nested-child` (`sudo mkdir -p /sys/fs/cgroup/johnny-stage2-test/nested-child`).
   - Enter the test cgroups **only** from a short-lived throwaway subshell (`sudo sh -c 'echo $$ > /sys/fs/cgroup/johnny-stage2-test/cgroup.procs && cat /proc/self/cgroup && exec "$1"' _ "$sentinel"`, and identically into `.../nested-child/cgroup.procs` for Case C). **Never** write AJ's interactive shell PID into `cgroup.procs` (otherwise `rmdir` hits `EBUSY` and AJ's shell stays inside the enforcing cgroup).
2. **Double-gated sentinel target (Hook A = S2-1 default; Hook B = optional second test):**
   - **Hook A (`SEC("lsm/bprm_check_security")`, Mechanism 1, directly tests Stage 2 exec hook):**
     - Create a root-owned private temporary directory under `/run` (not world-writable `/tmp`): `sentinel_dir=$(sudo mktemp -d /run/johnny-s2-cgtest.XXXXXX)` with `chmod 0755 "$sentinel_dir"` (owned `root:root`, so no non-root user can write or replace entries while unprivileged Case A can traverse it; `/run` on Rock Box is `tmpfs` `rw,nosuid,nodev,mode=755` with no `noexec`). Copy `/bin/true` to `"$sentinel_dir/sentinel"` (`0755`, `root:root`) and verify it runs cleanly before attaching the LSM hook.
     - **Kernel `s_dev` encoding requirement:** userspace `stat(2)` `st_dev` uses glibc/Linux `makedev` encoding (`major` at bit 8, split `minor` above 255), whereas kernel `bprm->file->f_inode->i_sb->s_dev` (`dev_t` in `include/linux/kdev_t.h`) uses `MKDEV(major, minor) = (major << 20) | minor` (`MINORBITS = 20`). They match only when `major == 0` and `minor < 256` (e.g., `tmpfs`), and differ on block devices such as NVMe (`259:x`). Userspace **must** pack `sentinel_sdev = (major(st_dev) << 20) | minor(st_dev)` (e.g., Python `(os.major(st.st_dev) << 20) | os.minor(st.st_dev)`) when populating `s2_cfg`, alongside `sentinel_ino = st.st_ino` and `target_cgid` / `target_level` (and/or cgroup fd in `BPF_MAP_TYPE_CGROUP_ARRAY`).
     - In `j_s2_cgtest_bprm`:
       1. If `s2_cfg.enabled == 0` or `s2_cfg.sentinel_ino == 0` or `s2_cfg.target_cgid == 0`: **fail open (`return 0`)**.
       2. Check `bprm->file->f_inode->i_ino == s2_cfg.sentinel_ino` and `bprm->file->f_inode->i_sb->s_dev == s2_cfg.sentinel_sdev`. If not the sentinel binary: **`return 0` immediately** (zero effect on any real process anywhere on Rock Box).
       3. Check cgroup membership (subtree check via `bpf_current_task_under_cgroup` or `bpf_get_current_ancestor_cgroup_id(target_level) == target_cgid`, plus record leaf `bpf_get_current_cgroup_id()` in stats).
       4. If **outside** the test cgroup: increment `stats.observed_outside`, emit/record, **`return 0` (allow)**.
       5. If **inside** the test cgroup: increment `stats.denied_inside`, **`return -EPERM` (deny)**.
   - **Hook B (`lsm/socket_connect`, optional second test for Stage 2 network gating):**
     - Same cgroup gate, double-gated on loopback destination `127.0.0.1:19999` only (never touches LAN, router, VPN, or Johnny). Denies (`-EPERM`) inside the test cgroup and observes (`return 0`) outside.
3. **Pins & lifetime:**
   - Pin exclusively under `/sys/fs/bpf/johnny_s2_cgtest/` (link + maps).
   - Never install a systemd boot unit. Run the four cases below synchronously inside one reviewed `sudo` block with an `EXIT` trap that unpins and cleans up even on failure.

### 4.3 Four-Case Proof Matrix (Required for `STAGE2-CGROUP-SCOPE-PASS`)

| Case | Where the sentinel runs (proved via `/proc/self/cgroup`) | Expected execution result | Expected BPF map counters | Failure / STOP token |
|---|---|---|---|---|
| **A — Outside test cgroup (observe-only)** | AJ's normal shell cgroup; print `/proc/self/cgroup` for the outside run and **assert** it is neither `0::/johnny-stage2-test` nor under `0::/johnny-stage2-test/` | Exits `0` (allowed, **never** `-EPERM`) | `observed_outside >= 1`, `denied_outside == 0` | `STOP-case-a-in-test-cgroup` (if `/proc/self/cgroup` is inside test cgroup), `STOP-denied-outside-cgroup` (if exit != 0 or `denied_outside > 0`), `STOP-not-observed-outside` (if `observed_outside == 0`) |
| **B — Inside test cgroup (enforcing)** | Throwaway subshell after `echo $$ > /sys/fs/cgroup/johnny-stage2-test/cgroup.procs`; print `/proc/self/cgroup` and **assert** exact `0::/johnny-stage2-test` before `exec "$sentinel"` | Fails with `EPERM` (`Operation not permitted`) | `denied_inside >= 1` | `STOP-case-b-wrong-cgroup` (if `/proc/self/cgroup` != `0::/johnny-stage2-test`), `STOP-not-denied-inside-cgroup` (if sentinel exited `0` or `denied_inside == 0`) |
| **C — Nested child cgroup (subtree escape check)** | Throwaway subshell after `echo $$ > /sys/fs/cgroup/johnny-stage2-test/nested-child/cgroup.procs`; print `/proc/self/cgroup` and **assert** exact `0::/johnny-stage2-test/nested-child` before `exec "$sentinel"` | Fails with `EPERM` (proves child cgroups cannot bypass enforcement) | `denied_inside` increments by `>= 1` again | `STOP-case-c-wrong-cgroup` (if `/proc/self/cgroup` != `0::/johnny-stage2-test/nested-child`), `STOP-subtree-escape` (documents that leaf-only `bpf_get_current_cgroup_id()` is insufficient and subtree matching is required) |
| **D — Detach & post-cleanup verification** | After removing `/sys/fs/bpf/johnny_s2_cgtest`, `/sys/fs/cgroup/johnny-stage2-test`, and `/run/johnny-s2-cgtest.*` | Sentinel runs cleanly before final sentinel dir removal (exits `0`); `bpftool prog list` and `bpftool link list -f` show zero `j_s2_cgtest` / `johnny_s2_cgtest` entries | Pin dir absent; test cgroup absent; sentinel dir absent | `STOP-cleanup-residual` (if any prog/link/pin/cgroup/sentinel remains) |

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
| `PASS-case-a-observe-outside` | S2-1 (planned) | Outside test cgroup (`/proc/self/cgroup` verified): allowed (`exit 0`), `observed_outside >= 1`, `denied_outside == 0`. |
| `PASS-case-b-deny-inside` | S2-1 (planned) | Inside `/johnny-stage2-test` (`/proc/self/cgroup` verified): denied (`EPERM`), `denied_inside >= 1`. |
| `PASS-case-c-deny-subtree` | S2-1 (planned) | Inside `/johnny-stage2-test/nested-child` (`/proc/self/cgroup` verified): denied (`EPERM`), proving subtree coverage. |
| `PASS-case-d-clean-detach` | S2-1 (planned) | Detach verified, sentinel runs cleanly again, zero residual BPF objects, test cgroups, or sentinel dirs. |
| `STAGE2-CGROUP-SCOPE-PASS` | S2-1 (planned) | All four cases passed; O28 C cgroup scoping is **VERIFIED** on Rock Box. |
| `STOP-probe-*` | S2-0A / S2-0B | Prerequisite missing or probe command failed; do not proceed to S2-1. |
| `STOP-case-{a,b,c}-*` | S2-1 (planned) | `/proc/self/cgroup` assertion failed (test process was not in the expected cgroup). |
| `STOP-denied-outside-cgroup` | S2-1 (planned) | **Critical safety stop:** hook denied outside the test cgroup; immediate detach + rollback. |
| `STOP-not-observed-outside` | S2-1 (planned) | Hook failed to observe execution outside test cgroup. |
| `STOP-not-denied-inside-cgroup` | S2-1 (planned) | Hook failed to deny sentinel inside test cgroup. |
| `STOP-subtree-escape` | S2-1 (planned) | Nested child cgroup bypassed the check; switch to subtree helper or `BPF_LSM_CGROUP`. |
| `STOP-cleanup-residual` / `STOP-rollback-residual` | S2-1 / Rollback | Residual BPF program, link, pin dir, test cgroup, or sentinel dir still present after cleanup (or `bpftool` verification failed). |
| `STAGE2-CGTEST-ROLLBACK-DONE` | Rollback | Clean idempotent rollback verified (zero residual pins, BPF progs/links, test cgroups, or sentinel dirs). |

---

## 5. Rollback (not part of the paste sequence above)

- **For Pastes S2-0A and S2-0B:** read-only; no system state is modified, so no rollback is required.
- **For the future Paste S2-1 feasibility test:** if S2-1 is ever interrupted before its `EXIT` trap runs, this standalone idempotent rollback block removes the test pin directory (which detaches any pinned test BPF links/programs), removes the raw test cgroups and root-owned `/run/johnny-s2-cgtest.*` sentinel directory, and verifies zero residual test objects remain. If any artifact remains (for example, `rmdir` hit `EBUSY` because a process is still inside the test cgroup) or `bpftool` fails, it prints `STOP-rollback-residual ...` and exits non-zero instead of `STAGE2-CGTEST-ROLLBACK-DONE`. Rollback never kills processes.

***<u>Run on Rock Box</u>***

```bash
sudo -v &&
(
  set -eu
  sudo rm -rf /sys/fs/bpf/johnny_s2_cgtest || true
  if [ -d /sys/fs/cgroup/johnny-stage2-test/nested-child ]; then
    sudo rmdir /sys/fs/cgroup/johnny-stage2-test/nested-child || true
  fi
  if [ -d /sys/fs/cgroup/johnny-stage2-test ]; then
    sudo rmdir /sys/fs/cgroup/johnny-stage2-test || true
  fi
  for d in /run/johnny-s2-cgtest.*; do
    if [ -e "$d" ]; then
      sudo rm -rf -- "$d" || true
    fi
  done
  python3 -I - <<'PY'
import glob, os, subprocess, sys

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
- **Assumption:** `bpftool feature probe kernel` emits `eBPF program_type lsm is available`, `eBPF map_type cgroup_array is available`, and `eBPF map_type cgrp_storage is available` in the standard `bpftool` text format on Rock Box's installed `bpftool` version. Paste S2-0A prints `BPFTOOL_VERSION`, and if `bpftool` text phrasing differs, S2-0B prints the exact status rather than silently passing.
- **Assumption:** `clang` / `llvm-strip` and `minisign` may not yet be installed on Rock Box; S2-0A inventories them without installing anything.
- **Assumption:** Whether `BPF_LSM_CGROUP` supports `bprm_check_security` (in addition to `socket_*` hooks) on kernel `7.3.0-10-generic` is **UNVERIFIED** until tested in S2-1.

### External sources
- Linux kernel docs, *LSM BPF Programs*: https://docs.kernel.org/bpf/bpf_lsm.html
- Linux kernel docs, *LSM usage* (`/sys/kernel/security/lsm`): https://docs.kernel.org/admin-guide/LSM/index.html
- Linux kernel docs, *Control Group v2*: https://docs.kernel.org/admin-guide/cgroup-v2.html
- Linux kernel docs, *BPF Type Format (BTF)*: https://docs.kernel.org/bpf/btf.html
- Linux kernel docs, *`BPF_MAP_TYPE_CGRP_STORAGE`*: https://docs.kernel.org/bpf/map_cgrp_storage.html
- Linux man-pages, *`bpf-helpers(7)`* (`bpf_get_current_cgroup_id`, `bpf_get_current_ancestor_cgroup_id`, `bpf_current_task_under_cgroup`): https://man7.org/linux/man-pages/man7/bpf-helpers.7.html
