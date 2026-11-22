# 2026-11-22 America/Chicago: Stage 2 Probes S2-0A & S2-0B Recorded; S2-1 Feasibility Test Drafted (Not Run)

- **Date / Time:** 2026-11-22 ~3:15 PM–3:18 PM CT (America/Chicago)
- **Host probed:** Rock Box (`aj-rock-box`, Ubuntu 26.10, kernel `7.3.0-10-generic`). Johnny (`192.168.50.152`) untouched.
- **Branch:** `stage2/s2-1-cgroup-scope-test` (from `claude/practical-ritchie-4c6vvf` @ `13fcf86`). `main` untouched.
- **Status:** S2-0A and S2-0B **PASSED** (`STAGE2-PROBE-RO-DONE`, `STAGE2-CGROUP-PROBE-DONE`). `clang` + `llvm` installed by AJ (`CLANG-DONE`). Paste S2-1 **DRAFTED, NOT RUN** (awaiting adversarial-reviewer review before AJ runs it).

---

## 1. Paste S2-0A Output (Unprivileged Read-Only Probe, 2026-11-22 ~3:15 PM CT)

Verbatim output recorded from AJ's run on Rock Box:

```text
== kernel
KERNEL 7.3.0-10-generic
== active LSM list
LSM_LIST lockdown,capability,landlock,yama,apparmor,bpf,ima,evm
PASS-probe-lsm-bpf
== kernel lockdown
LOCKDOWN [none] integrity confidentiality
== BTF vmlinux
PASS-probe-btf bytes=7263944
== cgroup mount
CGROUP_MOUNT fstype=cgroup2 root_inode=1
PASS-probe-cgroup2
== kernel config
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_LSM=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_BPF=y
CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor,bpf"
CONFIG_DEBUG_INFO_BTF=y
== unprivileged_bpf_disabled
UNPRIV_BPF 2
== toolchain inventory
TOOL bpftool=/usr/sbin/bpftool
TOOL clang=MISSING
TOOL llvm-strip=MISSING
TOOL gcc=/usr/bin/gcc
TOOL systemd-run=/usr/bin/systemd-run
TOOL python3=/usr/bin/python3
TOOL minisign=MISSING
BPFTOOL_VERSION bpftool v7.8.0
STAGE2-PROBE-RO-DONE
```

**Post-S2-0A toolchain update (AJ, `CLANG-DONE`):**
- AJ installed `clang` + `llvm` (`clang 22.1.8`, `/usr/bin/clang`, `/usr/bin/llvm-strip`).
- `libbpf1` (`1:1.6.3-1ubuntu1`, `/usr/lib/x86_64-linux-gnu/libbpf.so.1`) is already present; `libbpf-dev` is not installed.
- `minisign` remains missing (not needed for S2-1; needed later for O17 rule signing).

---

## 2. Paste S2-0B Output (Privileged Read-Only `bpftool feature` + BTF Probe, 2026-11-22 ~3:15 PM CT)

Verbatim output recorded from AJ's run on Rock Box:

```text
PROG_TYPE_LSM available
MAP_TYPE_CGROUP_ARRAY available
MAP_TYPE_CGRP_STORAGE available
PASS-probe-lsm-prog-type
LSM_HELPER bpf_get_current_cgroup_id=absent
LSM_HELPER bpf_get_current_ancestor_cgroup_id=absent
LSM_HELPER bpf_current_task_under_cgroup=absent
NOTE-lsm-cgroup-id-not-listed-in-bpftool
REF_HELPERS kprobe=bpf_get_current_cgroup_id bpf_get_current_ancestor_cgroup_id bpf_current_task_under_cgroup
REF_HELPERS tracepoint=bpf_get_current_cgroup_id bpf_get_current_ancestor_cgroup_id bpf_current_task_under_cgroup
REF_HELPERS cgroup_skb=bpf_get_current_cgroup_id bpf_get_current_ancestor_cgroup_id bpf_current_task_under_cgroup
== BTF enum checks (BPF_LSM_CGROUP + cgroup helpers)
BTF_SYM BPF_PROG_TYPE_LSM=present
BTF_SYM BPF_LSM_MAC=present
BTF_SYM BPF_LSM_CGROUP=present
BTF_SYM BPF_FUNC_get_current_cgroup_id=present
BTF_SYM BPF_FUNC_get_current_ancestor_cgroup_id=present
BTF_SYM BPF_FUNC_current_task_under_cgroup=present
BTF_SYM BPF_MAP_TYPE_CGROUP_ARRAY=present
BTF_SYM BPF_MAP_TYPE_CGRP_STORAGE=present
PASS-probe-btf-cgroup-syms
STAGE2-CGROUP-PROBE-DONE
```

### Key Takeaway from S2-0B
- `bpftool feature probe kernel` (`bpftool v7.8.0`) **did** emit a helper block for `lsm`, and reported `bpf_get_current_cgroup_id`, `bpf_get_current_ancestor_cgroup_id`, and `bpf_current_task_under_cgroup` as `absent` in that block (`NOTE-lsm-cgroup-id-not-listed-in-bpftool`), while listing all three as available for `kprobe`, `tracepoint`, and `cgroup_skb`.
- All 8 BTF enum symbols (`BPF_PROG_TYPE_LSM`, `BPF_LSM_MAC`, `BPF_LSM_CGROUP`, all three cgroup helpers, `BPF_MAP_TYPE_CGROUP_ARRAY`, `BPF_MAP_TYPE_CGRP_STORAGE`) are `present` in `/sys/kernel/btf/vmlinux`.
- Because `bpftool`'s generic LSM helper probe does not definitively settle whether the `7.3.0-10-generic` verifier accepts these helpers on a concrete `bprm_check_security` BTF target, S2-1 must test the real kernel verifier directly.

---

## 3. AJ Design Decision (2026-11-22 3:18 PM CT)

AJ approved `docs/stage2/cgroup-scoping-test-runbook.md` §4 with one change:
- **Attempt BOTH loads in S2-1:**
  - **Mechanism 1 (M1):** `SEC("lsm/bprm_check_security")` + subtree cgroup helper (`bpf_current_task_under_cgroup`).
  - **Mechanism 2 (M2):** `SEC("lsm_cgroup/bprm_check_security")` attached to `/sys/fs/cgroup/johnny-stage2-test`.
- Record verifier outcomes for both (`VERIFIER-M1=accepted|rejected`, `VERIFIER-M2=accepted|rejected` plus verifier log tails).
- Run Cases A–D using whichever mechanism loaded:
  - Prefer **M1** if both load.
  - If only **M2** loads, run Cases A–D with **M2** (using M2's inverted `1`-allow / `0`-deny return convention, plus an optional global `SEC("lsm/bprm_check_security")` observe-only companion with no cgroup helpers if accepted by the verifier).
  - If **neither** loads, emit `STOP-verifier-both-rejected`, roll back cleanly, and never emit `STAGE2-CGROUP-SCOPE-PASS` / `DONE`.
- Fold in deferred PR #50 review nits:
  - **N12:** all map names prefixed `j_s2_cgtest_` and `<= 15` characters total (`j_s2_cgtest_cfg`, `j_s2_cgtest_st`, `j_s2_cgtest_cg`).
  - **N13:** add `sudo bpftool map list -f` residual check to Case D and the token table.

---

## 4. Deliverables Drafted (Not Loaded, Not Run)

- `stage2/cgtest/j_s2_cgtest.bpf.c`: BPF C source implementing `j_s2_cgtest_m1`, `j_s2_cgtest_m2`, and `j_s2_cgtest_obs` with N12-compliant map names and fail-open + double-gated sentinel checks.
- `stage2/cgtest/build.sh`: unprivileged build script generating gitignored `stage2/cgtest/build/vmlinux.h` from `/sys/kernel/btf/vmlinux` and compiling `stage2/cgtest/build/j_s2_cgtest.bpf.o`.
- `stage2/cgtest/loader.py`: minimal Python 3 `ctypes` helper bound to Rock Box's installed `libbpf.so.1` (no `libbpf-dev` needed; supports `BPF_MAP_TYPE_CGROUP_ARRAY` fd updates and `bpf_program__attach_cgroup` for `lsm_cgroup`, which `bpftool v7.8.0` does not support).
- `stage2/cgtest/run_s2_1.sh`: S2-1 driver running preflight, both verifier probes, Cases A–D, and `EXIT`-trap cleanup/residual checks.
- `docs/stage2/cgroup-scoping-test-runbook.md` (Rev 2): updated §4, token table, N12/N13, S2-0 results summary, and copy-paste **Paste S2-1** (`***<u>Run on Rock Box</u>***`).
