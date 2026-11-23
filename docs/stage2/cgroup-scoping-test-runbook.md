# Stage 2: Rock Box BPF LSM Cgroup-Scoping Feasibility Test Runbook

Rev 2, 2026-11-22 America/Chicago. Status: **S2-0A & S2-0B PASSED (`docs/sessions/2026-11-22-stage2-probes-s2-0.md`); PASTE S2-1 DRAFTED — NOT YET REVIEWED, NOT RUN.** BPF object compiled unprivileged on Rock Box (`stage2/cgtest/build/j_s2_cgtest.bpf.o`, gitignored); never loaded, attached, or pinned. Johnny (`192.168.50.152`) untouched.

Review state: **Paste S2-1 DRAFT — awaiting adversarial-reviewer (Claude Code Opus medium) review before AJ runs it (`AGENTS.md:13`).**

Rev 1, 2026-11-21 America/Chicago (historical): initial S2-0A/S2-0B probe runbook and Phase 2 spec (`PR #50`).

---

## 1. Purpose, Decisions, and Safety Guardrails

### Why this test exists
- AJ decided **O28 = C** on 2026-11-17 (`docs/architecture/architecture-rev2.md` §4 Stage 2, §7 O28): Stage 2's Rock Box Linux endpoint agent runs **observe-only** (log, do not deny), **except one enforcing test cgroup**.
- **Prerequisite (UNVERIFIED):** whether BPF LSM on Rock Box (`7.3.0-10-generic`) can reliably scope an enforcement denial (`-EPERM`) to a single test cgroup while remaining observe-only everywhere else is **UNVERIFIED**. A Fast Path feasibility test (**Paste S2-1**) must confirm it before any enforcement work begins.

### What is already verified on Rock Box
- **2026-11-17 §3 check** (`docs/findings/stage2/2026-11-17-rockbox-fs-check.md`):
  - Kernel: `7.3.0-10-generic`.
  - Filesystem: `/` and `/home` are one ext4 partition (`/dev/nvme0n1p2`, `rw,relatime`), no reflink.
  - Active LSM list (`/sys/kernel/security/lsm`): `lockdown,capability,landlock,yama,apparmor,bpf,ima,evm`.
  - Kernel config: `CONFIG_BPF_LSM=y`, `CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor,bpf"`. No kernel command-line change or reboot is needed to enable BPF LSM.
- **Rock Box `/etc/os-release`:** `Ubuntu 26.10` (`PRETTY_NAME="Ubuntu 26.10"`).
- **2026-11-17 lockdown check** (`docs/findings/stage2/2026-11-17-rockbox-lockdown.md`):
  - `/sys/kernel/security/lockdown`: `[none] integrity confidentiality`. Lockdown is `none`.
- **2026-11-22 Pastes S2-0A & S2-0B** (`docs/sessions/2026-11-22-stage2-probes-s2-0.md`):
  - S2-0A (`STAGE2-PROBE-RO-DONE`): `/sys/kernel/btf/vmlinux` readable (`7,263,944` bytes), `/sys/fs/cgroup` is unified `cgroup2` (`root_inode=1`), `CONFIG_BPF_SYSCALL=y`, `CONFIG_BPF_LSM=y`, `CONFIG_CGROUPS=y`, `CONFIG_CGROUP_BPF=y`, `CONFIG_DEBUG_INFO_BTF=y`, `kernel.unprivileged_bpf_disabled=2`, `bpftool v7.8.0`. Post-probe, AJ installed `clang` + `llvm` (`CLANG-DONE`: `clang 22.1.8`, `llvm-strip`); `libbpf1` (`1.6.3`) is installed (`libbpf-dev` is not); `minisign` remains missing (not needed for S2-1).
  - S2-0B (`STAGE2-CGROUP-PROBE-DONE`): `PROG_TYPE_LSM available`, `MAP_TYPE_CGROUP_ARRAY available`, `MAP_TYPE_CGRP_STORAGE available`, and all 8 BTF enum symbols (`BPF_PROG_TYPE_LSM`, `BPF_LSM_MAC`, `BPF_LSM_CGROUP`, `BPF_FUNC_get_current_cgroup_id`, `BPF_FUNC_get_current_ancestor_cgroup_id`, `BPF_FUNC_current_task_under_cgroup`, `BPF_MAP_TYPE_CGROUP_ARRAY`, `BPF_MAP_TYPE_CGRP_STORAGE`) are `present`. Notably, `bpftool feature probe kernel` **did** emit an `lsm` helper block and reported all three cgroup helpers as `absent` in that block (`NOTE-lsm-cgroup-id-not-listed-in-bpftool`) while listing them for `kprobe`, `tracepoint`, and `cgroup_skb`.

### What remains UNVERIFIED until Paste S2-1 runs
1. Actual kernel verifier acceptance on `7.3.0-10-generic` for **Mechanism 1** (`SEC("lsm/bprm_check_security")` + `bpf_current_task_under_cgroup`) and **Mechanism 2** (`SEC("lsm_cgroup/bprm_check_security")`).
2. Runtime isolation across Cases A–D (observe outside `/johnny-stage2-test`, deny inside `/johnny-stage2-test` and `/johnny-stage2-test/nested-child`, clean detach with zero residuals).

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

## 4. Phase 2: Minimal Cgroup-Scoping Feasibility Test (Paste S2-1 — DRAFT, Not Yet Run)

Per AJ's 2026-11-22 3:18 PM CT decision (`docs/sessions/2026-11-22-stage2-probes-s2-0.md`), S2-1 is implemented under `stage2/cgtest/` and attempts **both** kernel verifier loads before selecting the active mechanism for Cases A–D. **Nothing in this draft has been loaded, attached, or run with `sudo`.**

### 4.1 Two Kernel Mechanisms — Probe Both, Prefer M1, Fall Back to M2

| Mechanism | Attach Type | How scoping works | Return Convention & Observe+Deny in O28 C | Tradeoffs / Caveats |
|---|---|---|---|---|
| **Mechanism 1 (`j_s2_cgtest_m1`, preferred when both load):** Global `SEC("lsm/bprm_check_security")` + subtree helper | `BPF_LSM_MAC` | Calls `bpf_current_task_under_cgroup(&j_s2_cgtest_cg, 0)` (populated with `/sys/fs/cgroup/johnny-stage2-test` directory fd) plus leaf `bpf_get_current_cgroup_id()` for telemetry. | **Single program:** returns `0` (allow) and increments `observed_outside` outside the test cgroup; returns `-EPERM` (`-1`) and increments `denied_inside` inside the test cgroup subtree. | Must use subtree matching (leaf `bpf_get_current_cgroup_id()` alone misses child cgroups). `bpftool feature probe` listed cgroup helpers `absent` for `lsm`, so verifier acceptance is **UNVERIFIED** until S2-1 runs. |
| **Mechanism 2 (`j_s2_cgtest_m2`, automatic fallback if M1 rejected):** Cgroup-attached `SEC("lsm_cgroup/bprm_check_security")` | `BPF_LSM_CGROUP` | Kernel attaches `j_s2_cgtest_m2` directly to `/sys/fs/cgroup/johnny-stage2-test` via `bpf_program__attach_cgroup`; kernel invokes it only for tasks inside that cgroup subtree (cgroup v2 inheritance covers `nested-child`). | **Inverted return (`1` allow / `0` deny):** returns `1` on fail-open / non-sentinel, `0` (kernel returns `-EPERM`) on sentinel inside the attached subtree. Paired with `j_s2_cgtest_obs` (global `SEC("lsm/bprm_check_security")` with **no** cgroup helpers, always returns `0`) if the verifier accepts it so Case A still proves global observe-only outside the cgroup. | Strongest kernel-enforced isolation (the denying program never executes outside the test cgroup). Non-sleepable only; per-hook `BPF_LSM_CGROUP` support for `bprm_check_security` on `7.3.0-10-generic` is **UNVERIFIED** until S2-1 runs. |

**S2-1 selection rule (AJ, 2026-11-22 3:18 PM CT):**
1. Attempt loading **M1** (`j_s2_cgtest_m1`, unattached) and record `VERIFIER-M1=accepted|rejected` plus the verifier log tail (`VERIFIER-M1-LOG: ...`). Close immediately.
2. Attempt loading **M2** (`j_s2_cgtest_m2`, unattached) and record `VERIFIER-M2=accepted|rejected` plus the verifier log tail (`VERIFIER-M2-LOG: ...`). Close immediately.
3. Selection:
   - If **M1 accepted** (whether or not M2 also accepted): select `ACTIVE_MECHANISM=M1` and run Cases A–D with M1.
   - Else if **only M2 accepted**: select `ACTIVE_MECHANISM=M2`, also probe global observe-only companion `j_s2_cgtest_obs` (`VERIFIER-M2-OBS=accepted|rejected`), and run Cases A–D with M2 (inverted `1`-allow / `0`-deny) + `j_s2_cgtest_obs` if accepted.
   - Else (**neither** accepted): emit `STOP-verifier-both-rejected`, run full cleanup/rollback with residual verification, exit non-zero, and **never** emit `STAGE2-CGROUP-SCOPE-PASS`.

### 4.2 Implementation Files, Loader Choice, Map Naming (N12), and Double-Gated Target

#### Files under `stage2/cgtest/`
- `stage2/cgtest/j_s2_cgtest.bpf.c`: minimal BPF C source (`j_s2_cgtest_m1`, `j_s2_cgtest_m2`, `j_s2_cgtest_obs`). Uses CO-RE `preserve_access_index` reads on `PTR_TO_BTF_ID` (`bprm->file->f_inode->i_ino`, `i_sb->s_dev`) with explicit NULL checks at every dereference and zero dependency on `libbpf-dev` headers.
- `stage2/cgtest/build.sh`: unprivileged build script that generates `stage2/cgtest/build/vmlinux.h` from `/sys/kernel/btf/vmlinux` (gitignored, never committed), compiles `stage2/cgtest/build/j_s2_cgtest.bpf.o` with `clang -O2 -g -target bpf -Wall -Wextra -Werror`, and runs `llvm-strip -g` (preserving `.BTF` and `.BTF.ext`).
- `stage2/cgtest/loader.py`: tiny Python 3 (`python3 -I`) helper calling Rock Box's installed `libbpf.so.1` (`libbpf1 1.6.3`) via `ctypes`.
  - **Why Python + `libbpf.so.1` instead of `bpftool`-only or C/`libbpf`:**
    1. `bpftool v7.8.0` does **not** support `lsm_cgroup` in `bpftool cgroup attach`, cannot pass an open cgroup directory fd into `BPF_MAP_TYPE_CGROUP_ARRAY` via `bpftool map update`, and cannot isolate per-program verifier log buffers cleanly for M1 vs M2.
    2. `libbpf-dev` is **not** installed on Rock Box (`/usr/include/bpf/` is absent), so a compiled C loader would require installing another package or hand-declaring libbpf ABI headers.
    3. `python3` and `/usr/lib/x86_64-linux-gnu/libbpf.so.1` are already installed on Rock Box, so `loader.py` requires **zero new packages**, uses official libbpf ELF/BTF/CO-RE loading and `bpf_program__attach_lsm` / `bpf_program__attach_cgroup`, and exposes an unprivileged `self-test` subcommand that verifies symbol resolution, ABI struct packing, N12 name lengths, and libbpf userspace-only ELF parsing without issuing any `bpf()` syscall.
- `stage2/cgtest/run_s2_1.sh`: test driver enforcing preflight cleanliness, setup, verifier probe + attach, Cases A–D, and `EXIT`-trap emergency detach/cleanup.

#### BPF Map & Program Names (PR #50 N12: `j_s2_cgtest_` prefix, `<= 15` chars)
Every map and program name is prefixed `j_s2_cgtest_` and fits inside `BPF_OBJ_NAME_LEN - 1` (`15` chars) so the kernel never truncates it:
- Maps: `j_s2_cgtest_cfg` (15 chars, `BPF_MAP_TYPE_ARRAY`, 24-byte config), `j_s2_cgtest_st` (14 chars, `BPF_MAP_TYPE_ARRAY`, 8× `u64` atomic counters), `j_s2_cgtest_cg` (14 chars, `BPF_MAP_TYPE_CGROUP_ARRAY`, 1 entry for M1 only).
- Programs: `j_s2_cgtest_m1` (14 chars), `j_s2_cgtest_m2` (14 chars), `j_s2_cgtest_obs` (15 chars).

#### Blast-radius guardrails
1. **Dedicated test cgroup (raw cgroupfs only):**
   - Parent test cgroup: `/sys/fs/cgroup/johnny-stage2-test` (`sudo mkdir -p /sys/fs/cgroup/johnny-stage2-test`).
   - Nested child cgroup (Case C subtree proof): `/sys/fs/cgroup/johnny-stage2-test/nested-child`.
   - Entered **only** by short-lived throwaway subshells (`sudo sh -c 'echo $$ > "$1/cgroup.procs" && exec python3 -I ...'`). **Never** writes AJ's interactive shell PID into `cgroup.procs`.
2. **Double-gated sentinel target (Hook A = `bprm_check_security`; optional Hook B `socket_connect` deferred until Hook A passes):**
   - Root-owned private temporary directory under `/run`: `sentinel_dir=$(sudo mktemp -d /run/johnny-s2-cgtest.XXXXXX)` (`0755 root:root`), copy `/bin/true` to `"$sentinel_dir/true"` (`0755 root:root`; keeps basename `true` because `/bin/true` on Rock Box is the rust-coreutils multi-call binary keyed on `argv[0]`), verified runnable unprivileged before attach.
   - **Kernel `s_dev` encoding:** userspace `stat(2)` `st_dev` uses glibc `makedev`, whereas kernel `i_sb->s_dev` uses `MKDEV(major, minor) = (major << 20) | minor`. `loader.py` packs `(os.major(st.st_dev) << 20) | os.minor(st.st_dev)` (verified in `self-test` for both tmpfs `0:42` and NVMe `259:2`).
   - **Fail-open:** if `enabled == 0`, `sentinel_ino == 0`, or `target_cgid == 0` (or `bpf_current_task_under_cgroup` returns `< 0` in M1), the hook returns allow (`0` in M1/OBS, `1` in M2).
   - **Double-gated deny:** any binary whose `(i_ino, i_sb->s_dev)` does not match the throwaway sentinel returns allow immediately.
3. **Pins & lifetime:**
   - Pin exclusively under `/sys/fs/bpf/johnny_s2_cgtest/` (maps + links).
   - Nothing installed at boot; synchronous run with `EXIT` trap that unpins, removes test cgroups and `/run/johnny-s2-cgtest.*`, and verifies zero residuals even on failure.

### 4.3 Four-Case Proof Matrix (Required for `STAGE2-CGROUP-SCOPE-PASS`)

| Case | Where the sentinel runs (proved via `/proc/self/cgroup`) | Expected execution result | Expected BPF map counters | Failure / STOP token |
|---|---|---|---|---|
| **A — Outside test cgroup (observe-only)** | AJ's normal shell cgroup (unprivileged); prints `/proc/self/cgroup` and **asserts** it is neither `0::/johnny-stage2-test` nor under `0::/johnny-stage2-test/` | Exits `0` (allowed, **never** `-EPERM`) | **M1:** `observed_outside >= 1`, `denied_outside == 0` (defensive/unreachable check; `fmod_ret` always sees `ret=0`), `denied_inside == 0`. **M2:** `m2_seen == 0`, `denied_inside == 0`, `denied_outside == 0` (defensive/unreachable check), plus `observed_outside >= 1` (`obs_seen >= 1`) when `VERIFIER-M2-OBS=accepted` | `STOP-case-a-in-test-cgroup`, `STOP-denied-outside-cgroup` (**critical safety stop** — immediate detach + rollback), `STOP-not-observed-outside` |
| **B — Inside test cgroup (enforcing)** | Throwaway subshell after `echo $$ > /sys/fs/cgroup/johnny-stage2-test/cgroup.procs`; prints `/proc/self/cgroup` and **asserts** exact `0::/johnny-stage2-test` before `os.execv(sentinel)` | Fails with `EPERM` (`errno=1`, exit `126`) | `denied_inside >= 1` (incremented vs before Case B) | `STOP-case-b-wrong-cgroup`, `STOP-not-denied-inside-cgroup` |
| **C — Nested child cgroup (subtree escape check)** | Throwaway subshell after `echo $$ > /sys/fs/cgroup/johnny-stage2-test/nested-child/cgroup.procs`; prints `/proc/self/cgroup` and **asserts** exact `0::/johnny-stage2-test/nested-child` before `os.execv(sentinel)` | Fails with `EPERM` (`errno=1`, exit `126`) — proves child cgroups cannot bypass enforcement | `denied_inside` increments by `>= 1` again | `STOP-case-c-wrong-cgroup`, `STOP-subtree-escape` |
| **D — Detach & post-cleanup verification (N13)** | Unpins `/sys/fs/bpf/johnny_s2_cgtest`; runs sentinel outside & inside `/johnny-stage2-test` before removing test cgroups and `/run/johnny-s2-cgtest.*` | Sentinel exits `0` both outside and inside `/johnny-stage2-test` after detach; `sudo test -e /sys/fs/bpf/johnny_s2_cgtest` fails absent; `sudo bpftool prog list`, `sudo bpftool link list -f`, and `sudo bpftool map list -f` show zero `j_s2_cgtest` / `johnny_s2_cgtest` entries | Pin dir absent; test cgroups absent; sentinel dir absent; zero residual BPF progs/links/maps | `STOP-cleanup-residual` |

### 4.4 Paste S2-1: Build, Verifier Probe (M1 + M2), Four-Case Isolation Test, and Clean Detach (Requires Sudo; Review Gate Before Running)

Verifies SHA-256 of the four `stage2/cgtest/` files, compiles `j_s2_cgtest.bpf.o` unprivileged (generating gitignored `vmlinux.h` from `/sys/kernel/btf/vmlinux`), runs unprivileged `loader.py self-test`, probes both M1 and M2 against the kernel verifier, executes Cases A–D, detaches immediately, and verifies zero residuals.

***<u>Run on Rock Box</u>***

```bash
sudo -v &&
(
  set -eu
  if [ ! -f /home/aj/Projects/strix-halo-johnny/stage2/cgtest/run_s2_1.sh ]; then
    echo "STOP-missing-stage2-cgtest-files root=/home/aj/Projects/strix-halo-johnny"
    exit 1
  fi
  cd /home/aj/Projects/strix-halo-johnny
  echo "4ebb76508e1841eceedc7638bbf70fa71dec172879217587aba605ca3a0592ea  stage2/cgtest/j_s2_cgtest.bpf.c
d033c78664d49b6a6824aa2975b1ae98c84cb69f5eebd34d187017bd680173f3  stage2/cgtest/build.sh
2d30df1ba7a6f15f30dd68550346dcc64f5983ab3ea4b3435ed22783bf452728  stage2/cgtest/loader.py
6953e1e0be278cf103bc95f59f2ff7bc3540319944fd729ab102bbcf7cd70acc  stage2/cgtest/run_s2_1.sh" | sha256sum -c -
  bash stage2/cgtest/build.sh
  python3 -I stage2/cgtest/loader.py self-test --obj stage2/cgtest/build/j_s2_cgtest.bpf.o
  bash stage2/cgtest/run_s2_1.sh
)
```

### Expect (Paste S2-1)
- Four `OK` SHA-256 lines, `S2-CGTEST-BUILD-OK`, and `S2-CGTEST-LOADER-SELFTEST-OK`.
- Both verifier probe results with log tails:
  - `VERIFIER-M1=accepted|rejected` + `VERIFIER-M1-LOG: ...`
  - `VERIFIER-M2=accepted|rejected` + `VERIFIER-M2-LOG: ...`
- `ACTIVE_MECHANISM=M1` (if M1 accepted) or `ACTIVE_MECHANISM=M2` + `VERIFIER-M2-OBS=accepted|rejected` (if only M2 accepted), followed by `ATTACH-DONE ...`.
- `PASS-case-a-observe-outside`, `PASS-case-b-deny-inside`, `PASS-case-c-deny-subtree`, `PASS-case-d-clean-detach`, and final token **`STAGE2-CGROUP-SCOPE-PASS mechanism=<M1|M2>`**.
- If **neither** M1 nor M2 is accepted by the verifier, Paste S2-1 prints `STOP-verifier-both-rejected`, runs cleanup + residual checks (`CLEANUP-ON-STOP-OK`), exits non-zero, and **never** prints `STAGE2-CGROUP-SCOPE-PASS`.
- On any `STOP-*` token, send the full output back; if the run was interrupted before its `EXIT` trap completed, run the standalone **Rollback** block in §5.

### 4.5 PASS / STOP Token Contract

| Token | Phase | Meaning |
|---|---|---|
| `PASS-probe-lsm-bpf` | S2-0A | `bpf` is present in `/sys/kernel/security/lsm`. |
| `PASS-probe-btf` | S2-0A | `/sys/kernel/btf/vmlinux` exists and is non-empty. |
| `PASS-probe-cgroup2` | S2-0A | `/sys/fs/cgroup` is mounted as unified `cgroup2`. |
| `NOTE-lockdown-unreadable`, `NOTE-config-unreadable`, `NOTE-sysctl-unreadable`, `NOTE-bpftool-version-failed` | S2-0A | Non-fatal informational note when an optional diagnostic file or `bpftool version` could not be read. |
| `STAGE2-PROBE-RO-DONE` | S2-0A | Unprivileged probe completed with all S2-0A prerequisites met. |
| `PASS-probe-lsm-prog-type` | S2-0B | `bpftool feature probe kernel` reports `program_type lsm` available. |
| `PASS-probe-lsm-cgroup-id` | S2-0B | `bpftool feature probe kernel` explicitly listed `bpf_get_current_cgroup_id` under `lsm`. |
| `NOTE-lsm-cgroup-id-not-listed-in-bpftool`, `NOTE-lsm-helpers-not-probed-by-bpftool` | S2-0B | Informational note when `bpftool feature probe` omits or marks `lsm` cgroup helpers absent; S2-1 verifier check settles definitively. |
| `PASS-probe-btf-cgroup-syms` | S2-0B | Kernel BTF exports `BPF_FUNC_get_current_cgroup_id` (and prints status of ancestor/under-cgroup/`BPF_LSM_CGROUP` symbols). |
| `STAGE2-CGROUP-PROBE-DONE` | S2-0B | Privileged read-only probe completed cleanly. |
| `S2-CGTEST-BUILD-OK` | S2-1 | Unprivileged build generated `vmlinux.h` and compiled `j_s2_cgtest.bpf.o`. |
| `S2-CGTEST-LOADER-SELFTEST-OK` | S2-1 | Unprivileged `loader.py self-test` verified `libbpf.so.1`, ABI packing, N12 name limits, and ELF metadata without loading. |
| `SHELL_CGROUP` | S2-1 | Records AJ's outer shell `/proc/self/cgroup` during preflight before any test cgroup is created. |
| `SENTINEL_PRECHECK_OK` | S2-1 | Pre-attach sanity check confirmed the root-owned sentinel copy under `/run` executes cleanly unprivileged (`rc=0`). |
| `TARGET` | S2-1 | Records resolved sentinel path, `i_ino`, `st_dev`, kernel-packed `s_dev`, cgroup path, and `target_cgid`. |
| `VERIFIER-M1=accepted\|rejected` | S2-1 | Kernel verifier result for Mechanism 1 (`SEC("lsm/bprm_check_security")` + `bpf_current_task_under_cgroup`), accompanied by `VERIFIER-M1-LOG:` tail lines. |
| `VERIFIER-M2=accepted\|rejected` | S2-1 | Kernel verifier result for Mechanism 2 (`SEC("lsm_cgroup/bprm_check_security")`), accompanied by `VERIFIER-M2-LOG:` tail lines. |
| `VERIFIER-M2-OBS=accepted\|rejected` | S2-1 | Verifier result for M2's global observe-only companion (`j_s2_cgtest_obs`, no cgroup helpers), logged only when M1 is rejected and M2 is selected, accompanied by `VERIFIER-M2-OBS-LOG:` tail lines. |
| `ACTIVE_MECHANISM=M1\|M2` | S2-1 | Mechanism selected for Cases A–D (prefers `M1` if both load; falls back to `M2` with inverted `1`-allow/`0`-deny if only M2 loads). |
| `ATTACH-DONE` | S2-1 | Selected BPF program(s) loaded, config/cgroup maps populated, links attached, and pins created under `/sys/fs/bpf/johnny_s2_cgtest`. |
| `SELECTED` | S2-1 | Driver echo of the parsed `ATTACH-DONE` `mechanism=<M1\|M2>` and `obs=<na\|yes\|no>` fields before running Cases A–D. |
| `SELF_CGROUP`, `CGROUP_MISMATCH`, `EXEC_RESULT`, `STATS` / `CASE_{A,B,C}_STATS` | S2-1 | Per-case diagnostic lines from `loader.py exec-check` / `read-stats` proving `/proc/self/cgroup`, `os.execv` errno (`EPERM`), and BPF map counters. |
| `NOTE-case-a-m2-no-global-observer` | S2-1 | Informational note in Case A when `ACTIVE_MECHANISM=M2` and `VERIFIER-M2-OBS=rejected`, so Case A verifies `m2_seen == 0` without a global observer count. |
| `PASS-case-a-observe-outside` | S2-1 | Outside test cgroup (`/proc/self/cgroup` verified): allowed (`exit 0`), `denied_outside == 0` (defensive/unreachable check; `fmod_ret` always sees `ret=0`), `denied_inside == 0`, `m2_seen == 0`, and `observed_outside >= 1` (for M1 or M2+OBS). |
| `PASS-case-b-deny-inside` | S2-1 | Inside `/johnny-stage2-test` (`/proc/self/cgroup` verified): denied (`EPERM`, exit `126`), `denied_inside` incremented. |
| `PASS-case-c-deny-subtree` | S2-1 | Inside `/johnny-stage2-test/nested-child` (`/proc/self/cgroup` verified): denied (`EPERM`, exit `126`), proving subtree coverage. |
| `POST_DETACH_SENTINEL_OK` | S2-1 | Case D verified sentinel runs cleanly (`rc=0`) both outside and inside `/johnny-stage2-test` immediately after unpinning `/sys/fs/bpf/johnny_s2_cgtest`. |
| `PASS-case-d-clean-detach` | S2-1 | Detach verified, sentinel runs cleanly outside & inside test cgroup before cleanup, zero residual pins (`sudo test -e`), test cgroups, sentinel dirs, or BPF progs/links/maps (`bpftool prog list`, `link list -f`, `map list -f` — N13). |
| `CLEANUP-ON-STOP-OK` | S2-1 | `EXIT` trap emergency/abort cleanup completed after an earlier `STOP-*` and verified zero residual pins, cgroups, sentinel dirs, or BPF objects. |
| `STAGE2-CGROUP-SCOPE-PASS` | S2-1 | All four cases passed; O28 C cgroup scoping is **VERIFIED** on Rock Box (prints `mechanism=M1` or `mechanism=M2`). |
| `STOP-probe-uname`, `STOP-probe-lsm-unreadable`, `STOP-probe-no-bpf-lsm`, `STOP-probe-no-btf`, `STOP-probe-not-cgroup2`, `STOP-probe-no-bpftool`, `STOP-probe-bpftool-failed`, `STOP-probe-no-lsm-prog-type`, `STOP-probe-btf-dump-oserror`, `STOP-probe-btf-dump-failed`, `STOP-probe-btf-no-cgroup-id-helper` | S2-0A / S2-0B | Prerequisite missing or probe command failed; do not proceed to S2-1. |
| `STOP-missing-stage2-cgtest-files` | S2-1 | Paste S2-1 could not find `stage2/cgtest/run_s2_1.sh` under `/home/aj/Projects/strix-halo-johnny`. |
| `STOP-build-missing-tool`, `STOP-build-no-vmlinux-btf` | S2-1 | `build.sh` missing `bpftool`/`clang`/`llvm-strip` or unreadable `/sys/kernel/btf/vmlinux`. |
| `STOP-selftest-missing-obj`, `STOP-selftest-missing-section`, `STOP-selftest-missing-symbol`, `STOP-selftest-libbpf-open-failed`, `STOP-selftest-libbpf-missing-prog`, `STOP-selftest-libbpf-prog-meta`, `STOP-selftest-libbpf-missing-map` | S2-1 | Unprivileged `loader.py self-test` failed ELF/BTF/libbpf verification; halts before any privileged BPF call. |
| `STOP-missing-bpf-obj`, `STOP-missing-loader` | S2-1 | `run_s2_1.sh` preflight did not find compiled `stage2/cgtest/build/j_s2_cgtest.bpf.o` or `stage2/cgtest/loader.py`. |
| `STOP-preflight-residual` | S2-1 | Pre-existing test pins, cgroups, sentinel dirs, or BPF progs/links/maps found before S2-1 started; inspect or run Rollback first. |
| `STOP-sentinel-precheck-failed` | S2-1 | Throwaway sentinel copy failed unprivileged execution before attach; `EXIT` trap cleans up and halts. |
| `STOP-loader-missing-obj`, `STOP-loader-missing-cgroup`, `STOP-loader-missing-sentinel` | S2-1 | `loader.py probe-and-attach` received a missing `--obj`, `--cgroup-dir`, or `--sentinel` path. |
| `STOP-verifier-both-rejected` | S2-1 | Kernel verifier rejected **both** M1 and M2; immediate cleanup + rollback, never emits `STAGE2-CGROUP-SCOPE-PASS`. |
| `STOP-attach-failed` | S2-1 | Loading, map population, pinning, or attaching the selected mechanism failed (or was interrupted by Ctrl-C); loader cleans its own pins and `EXIT` trap verifies zero residuals. |
| `STOP-probe-and-attach-failed` | S2-1 | `loader.py probe-and-attach` exited non-zero or without `ATTACH-DONE` before emitting a more specific `STOP-*` token (e.g., Python/ctypes error). |
| `STOP-read-stats-open-failed`, `STOP-read-stats-lookup-failed` | S2-1 | `loader.py read-stats` could not open pinned `j_s2_cgtest_st` or look up a stat slot. |
| `STOP-exec-check-bad-mode` | S2-1 | `loader.py exec-check` received an invalid `--mode` value. |
| `STOP-case-a-in-test-cgroup`, `STOP-case-b-wrong-cgroup`, `STOP-case-c-wrong-cgroup` | S2-1 | `/proc/self/cgroup` assertion failed (test process was not in the expected cgroup). |
| `STOP-denied-outside-cgroup` | S2-1 | **Critical safety stop:** hook denied (`rc != 0`), `denied_inside > 0`, `m2_seen > 0`, or defensive/unreachable `denied_outside > 0` (`fmod_ret` always sees `ret=0`) outside the test cgroup; immediate detach + rollback. |
| `STOP-not-observed-outside` | S2-1 | Hook failed to observe execution outside test cgroup. |
| `STOP-not-denied-inside-cgroup` | S2-1 | Hook failed to deny sentinel inside test cgroup. |
| `STOP-subtree-escape` | S2-1 | Nested child cgroup bypassed the check. |
| `STOP-cleanup-residual` / `STOP-rollback-residual` | S2-1 / Rollback | Residual BPF program, link, **map** (`bpftool map list -f` — N13), pin dir (`sudo test -e`), test cgroup, or sentinel dir still present after cleanup (or `bpftool` verification failed, or sentinel failed post-detach). |
| `STAGE2-CGTEST-ROLLBACK-DONE` | Rollback | Clean idempotent rollback verified (zero residual pins, BPF progs/links/maps, test cgroups, or sentinel dirs). |

---

## 5. Rollback (not part of the paste sequence above)

- **For Pastes S2-0A and S2-0B:** read-only; no system state is modified, so no rollback is required.
- **For Paste S2-1:** if S2-1 is ever interrupted before its `EXIT` trap runs, this standalone idempotent rollback block removes the test pin directory (which detaches any pinned test BPF links/programs), removes the raw test cgroups and root-owned `/run/johnny-s2-cgtest.*` sentinel directory, and verifies zero residual test objects remain (including `sudo test -e /sys/fs/bpf/johnny_s2_cgtest`, `sudo bpftool prog list`, `sudo bpftool link list -f`, and `sudo bpftool map list -f`, with a bounded 3-second settle/retry loop for kernel RCU teardown of BPF progs/links/maps). If any artifact remains (for example, `rmdir` hit `EBUSY` because a process is still inside the test cgroup) or `bpftool` fails, it prints `STOP-rollback-residual ...` and exits non-zero instead of `STAGE2-CGTEST-ROLLBACK-DONE`. Rollback never kills processes.

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
import glob, os, subprocess, sys, time

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
# Start the 3 s window after the first scan so its sudo calls do not eat the budget.
deadline = None
while True:
    bad = scan()
    if not bad:
        print("STAGE2-CGTEST-ROLLBACK-DONE")
        sys.exit(0)
    if deadline is None:
        deadline = time.monotonic() + 3.0
    only_rcu = all(item.startswith("residual-prog-") or item.startswith("residual-link-") or item.startswith("residual-map-") for item in bad)
    if only_rcu and time.monotonic() < deadline:
        time.sleep(0.2)
        continue
    print("STOP-rollback-residual " + ",".join(bad))
    sys.exit(1)
PY
)
```

---

## 6. Assumptions and Sources

### Marked assumptions
- **Assumption (UNVERIFIED until S2-1 runs):** Whether kernel `7.3.0-10-generic`'s BPF verifier accepts `bpf_current_task_under_cgroup` + `bpf_get_current_cgroup_id` in `SEC("lsm/bprm_check_security")` (Mechanism 1), given that `bpftool feature probe kernel` reported all three cgroup helpers `absent` for `lsm` in S2-0B while `/sys/kernel/btf/vmlinux` exports all three helper enums.
- **Assumption (UNVERIFIED until S2-1 runs):** Whether kernel `7.3.0-10-generic`'s BPF verifier and `bpf_program__attach_cgroup` accept `SEC("lsm_cgroup/bprm_check_security")` (Mechanism 2) on `bprm_check_security` (and enforce across `nested-child` via cgroup v2 inheritance).
- **Assumption (UNVERIFIED until S2-1 runs):** Whether `j_s2_cgtest_obs` (`SEC("lsm/bprm_check_security")` without cgroup helpers) loads cleanly as M2's global observe-only companion if M1 is rejected and M2 is selected.
- **Assumption:** Unpinning `/sys/fs/bpf/johnny_s2_cgtest` detaches trampoline-attached BPF LSM links and completes kernel RCU teardown within the bounded 3-second settle window in `run_s2_1.sh` (if teardown exceeds 3 s, `STOP-cleanup-residual` triggers safely rather than passing).

### External sources
- Linux kernel docs, *LSM BPF Programs*: https://docs.kernel.org/bpf/bpf_lsm.html
- Linux kernel docs, *LSM usage* (`/sys/kernel/security/lsm`): https://docs.kernel.org/admin-guide/LSM/index.html
- Linux kernel docs, *Control Group v2*: https://docs.kernel.org/admin-guide/cgroup-v2.html
- Linux kernel docs, *BPF Type Format (BTF)*: https://docs.kernel.org/bpf/btf.html
- Linux kernel docs, *`BPF_MAP_TYPE_CGRP_STORAGE`*: https://docs.kernel.org/bpf/map_cgrp_storage.html
- Linux man-pages, *`bpf-helpers(7)`* (`bpf_get_current_cgroup_id`, `bpf_get_current_ancestor_cgroup_id`, `bpf_current_task_under_cgroup`): https://man7.org/linux/man-pages/man7/bpf-helpers.7.html
