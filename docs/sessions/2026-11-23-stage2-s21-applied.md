# 2026-11-23 America/Chicago: Stage 2 S2-1 Cgroup-Scoping Feasibility Test Applied (PASS, M1)

- **Date / Time:** 2026-11-23 ~12:52 PM CST (America/Chicago)
- **Host:** Rock Box (`aj-rock-box`, Ubuntu 26.10, kernel `7.3.0-10-generic`). Johnny (`192.168.50.152`) untouched.
- **Run worktree:** `/home/aj/Projects/strix-halo-johnny-wt-20261122-151830`
- **Commit run:** `c90ba226b44715d3c0e34456c615eac3df4cab82` (`stage2: S2-1 cgroup-scoping test (draft, not run) (#51)`)
- **Closeout branch:** `claude/stage2-s21-closeout` (from `claude/practical-ritchie-4c6vvf` @ `c90ba226b44715d3c0e34456c615eac3df4cab82`). `main` untouched. No code under `stage2/cgtest/` changed.
- **Status:** **APPLIED & PASSED** — `STAGE2-CGROUP-SCOPE-PASS mechanism=M1`. O28 C cgroup-scoped BPF LSM enforcement with outside observe-only behavior is **VERIFIED** on Rock Box (`7.3.0-10-generic`).

---

## 1. Pinned SHA-256 Checksums (All OK)

All four `stage2/cgtest/` files passed `sha256sum -c` before build and execution:

```text
4ebb76508e1841eceedc7638bbf70fa71dec172879217587aba605ca3a0592ea  stage2/cgtest/j_s2_cgtest.bpf.c
d033c78664d49b6a6824aa2975b1ae98c84cb69f5eebd34d187017bd680173f3  stage2/cgtest/build.sh
2d30df1ba7a6f15f30dd68550346dcc64f5983ab3ea4b3435ed22783bf452728  stage2/cgtest/loader.py
6953e1e0be278cf103bc95f59f2ff7bc3540319944fd729ab102bbcf7cd70acc  stage2/cgtest/run_s2_1.sh
```

---

## 2. Verbatim S2-1 Output (Rock Box, 2026-11-23 ~12:52 PM CST)

Recorded verbatim from AJ's run (`S2-CGTEST-BUILD-OK` through `STAGE2-CGROUP-SCOPE-PASS mechanism=M1`; sudo password-prompt lines omitted):

```text
S2-CGTEST-BUILD-OK obj=/home/aj/Projects/strix-halo-johnny-wt-20261122-151830/stage2/cgtest/build/j_s2_cgtest.bpf.o sha256=28248aa8b405d2a2734e57278004c3d0929b2493889a5f4b18b151ff02c20a9e
S2-CGTEST-LOADER-SELFTEST-OK
== preflight
SHELL_CGROUP 0::/user.slice/user-1000.slice/user@1000.service/app.slice/ptyxis-spawn-9d79e147-9deb-4c13-b210-af71803e4280.scope
== setup test cgroups + root-owned sentinel under /run
SENTINEL_PRECHECK_OK path=/run/johnny-s2-cgtest.nxfASM/true
== verifier probe (M1 + M2) and attach
TARGET sentinel=/run/johnny-s2-cgtest.nxfASM/true ino=43641 st_dev=0:31 kernel_sdev=0x1f cgroup_dir=/sys/fs/cgroup/johnny-stage2-test target_cgid=1368143
VERIFIER-M1=accepted
VERIFIER-M1-LOG: processed 139 insns (limit 1000000) max_states_per_insn 1 total_states 14 peak_states 14 mark_read 0
VERIFIER-M2=accepted
VERIFIER-M2-LOG: processed 61 insns (limit 1000000) max_states_per_insn 0 total_states 5 peak_states 5 mark_read 0
ACTIVE_MECHANISM=M1
ATTACH-DONE mechanism=M1 obs=na sentinel_ino=43641 sentinel_sdev=0x1f target_cgid=1368143
SELECTED mechanism=M1 obs=na
== Case A: outside test cgroup (observe-only)
SELF_CGROUP 0::/user.slice/user-1000.slice/user@1000.service/app.slice/ptyxis-spawn-9d79e147-9deb-4c13-b210-af71803e4280.scope
CASE_A_STATS observed_outside=1 denied_inside=0 denied_outside=0 cg_helper_err=0 last_cgid_out=956995 last_cgid_in=0 m2_seen=0 obs_seen=0 rc=0
PASS-case-a-observe-outside mechanism=M1 observed_outside=1 denied_outside=0
== Case B: inside /johnny-stage2-test (enforcing)
SELF_CGROUP 0::/johnny-stage2-test
EXEC_RESULT denied errno=1 name=EPERM msg=Operation not permitted
CASE_B_STATS observed_outside=1 denied_inside=1 denied_outside=0 cg_helper_err=0 last_cgid_out=956995 last_cgid_in=1368143 m2_seen=0 obs_seen=0 rc=126
PASS-case-b-deny-inside mechanism=M1 denied_inside=1
== Case C: inside /johnny-stage2-test/nested-child (subtree escape check)
SELF_CGROUP 0::/johnny-stage2-test/nested-child
EXEC_RESULT denied errno=1 name=EPERM msg=Operation not permitted
CASE_C_STATS observed_outside=1 denied_inside=2 denied_outside=0 cg_helper_err=0 last_cgid_out=956995 last_cgid_in=1368194 m2_seen=0 obs_seen=0 rc=126
PASS-case-c-deny-subtree mechanism=M1 denied_inside=2
== Case D: detach & post-cleanup verification
POST_DETACH_SENTINEL_OK
PASS-case-d-clean-detach
STAGE2-CGROUP-SCOPE-PASS mechanism=M1
```

---

## 3. Summary & Key Finding

### Result Summary
- **Verifier probes:** `VERIFIER-M1=accepted` (139 insns, `total_states 14`, `peak_states 14`) and `VERIFIER-M2=accepted` (61 insns, `total_states 5`, `peak_states 5`).
- **Selected mechanism:** `ACTIVE_MECHANISM=M1` (per AJ's 2026-11-22 rule: prefer M1 when both load).
- **Case A (observe-outside):** **PASS** — outside `/johnny-stage2-test`, sentinel exited `0`, `observed_outside=1`, `denied_outside=0`, `denied_inside=0`, `cg_helper_err=0` (`last_cgid_out=956995`).
- **Case B (deny-inside):** **PASS** — inside `/johnny-stage2-test`, sentinel exec denied with `EPERM` (`errno=1`, `rc=126`), `denied_inside=1`, `cg_helper_err=0` (`last_cgid_in=1368143`).
- **Case C (deny nested-child):** **PASS** — inside `/johnny-stage2-test/nested-child`, sentinel exec denied with `EPERM` (`errno=1`, `rc=126`), `denied_inside=2`, `cg_helper_err=0` (`last_cgid_in=1368194`), proving subtree coverage without escape.
- **Case D (clean detach):** **PASS** — `POST_DETACH_SENTINEL_OK`, `PASS-case-d-clean-detach`, zero residual pins, test cgroups, sentinel dirs, or BPF progs/links/maps.
- **Helper errors:** `cg_helper_err=0` across all cases.

### Key Finding (`bpftool` Probe vs. Kernel Verifier)
- In S2-0B (`docs/sessions/2026-11-22-stage2-probes-s2-0.md`), `bpftool feature probe kernel` (`bpftool v7.8.0`) emitted an `lsm` helper block that reported all three cgroup helpers (`bpf_get_current_cgroup_id`, `bpf_get_current_ancestor_cgroup_id`, `bpf_current_task_under_cgroup`) as `absent` for `BPF_PROG_TYPE_LSM`.
- Yet on `7.3.0-10-generic`, the kernel verifier accepted M1 (`VERIFIER-M1=accepted`, 139 insns) using `bpf_current_task_under_cgroup` and `bpf_get_current_cgroup_id`, and runtime execution succeeded with `cg_helper_err=0`.
- **Takeaway:** `bpftool feature probe` output is **not** authoritative for LSM cgroup helper availability; the kernel verifier against a concrete BTF LSM hook target is.

---

## 4. Open Questions for AJ

> These are open questions for AJ to decide — not architecture decisions. AJ decides architecture.

1. **Standardize on M1 given both load?** Both M1 (`SEC("lsm/bprm_check_security")` + `bpf_current_task_under_cgroup`) and M2 (`SEC("lsm_cgroup/bprm_check_security")`) were accepted by the verifier on `7.3.0-10-generic`. Should Stage 2 standardize on M1 as the single production cgroup-scoping mechanism, or is there a reason to keep M2 (or dual-path support) in scope?
2. **Case A policy if only M2 had loaded?** Although moot on Rock Box `7.3.0-10-generic` now that M1 loads, should we define and keep a Case A / global-observation policy for other Linux kernels where M1 might be rejected and only M2 loads, or treat M1 as a hard requirement on supported kernels?
3. **Hook B as an S2-2 test, or go to agent design?** Should we run Hook B (`socket_connect`, deferred from S2-1) as a dedicated S2-2 cgroup-scoping feasibility test next, or proceed directly to Stage 2 Rock Box endpoint agent design?
4. **`aya` vs `libbpf-rs`?** For the Stage 2 Rock Box endpoint agent's Rust userspace BPF loader/runtime (loading CO-RE C BPF LSM programs, populating `BPF_MAP_TYPE_CGROUP_ARRAY` / policy maps, and reading telemetry), should we use `aya` (matching Stage 1's `johnny-daemon`) or `libbpf-rs`?
