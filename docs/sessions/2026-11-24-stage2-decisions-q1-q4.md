# 2026-11-24 America/Chicago: Stage 2 Post-S2-1 Decisions (Q1–Q4) (docs only)

- **Date / Time:** 2026-11-24 ~5:17 PM CST (America/Chicago)
- **Context:** Recorded after S2-1 passed with Mechanism 1 (`STAGE2-CGROUP-SCOPE-PASS mechanism=M1`, [`docs/sessions/2026-11-23-stage2-s21-applied.md`](2026-11-23-stage2-s21-applied.md)) and after PR #52 (`stage2: S2-1 applied closeout (PASS, M1)`) merged into `claude/practical-ritchie-4c6vvf` as `cf3e075d0b8c2f946e093695e3c0cbaa4b620da4` (`cf3e075`).
- **Answers:** Open questions Q1–Q4 in [`docs/sessions/2026-11-23-stage2-s21-applied.md`](2026-11-23-stage2-s21-applied.md) §4.
- **Decision reviewer:** Claude Code Opus medium (`AGENTS.md`); Opus decision-reviewer recommendations are included below as the rationale for Q2 and Q4.
- **Branch / Scope:** `claude/stage2-decisions-q1-q4` (from `claude/practical-ritchie-4c6vvf` @ `cf3e075d0b8c2f946e093695e3c0cbaa4b620da4`). **Docs only.** No code changes. Nothing under `stage2/cgtest/` changed. `main` untouched. Johnny (`192.168.50.152`) and Rock Box live state untouched.

---

## 1. Decisions (AJ-DECIDED 2026-11-24 ~5:17 PM CST)

### Q1 — Primary Cgroup-Scoping Mechanism and Fallback Scope

**AJ decision (2026-11-24):**
- **M1** (`SEC("lsm/bprm_check_security")` + subtree cgroup helper `bpf_current_task_under_cgroup`, `j_s2_cgtest_m1`) is **primary**.
- **M2** (`SEC("lsm_cgroup/bprm_check_security")`, `j_s2_cgtest_m2`) is a fallback **ONLY** together with the global observe-only companion (`j_s2_cgtest_obs`).

---

### Q2 — M2 Observation Policy, Agent Startup Gate, and Pinned-Runner Gap

**AJ decision (2026-11-24):**
- **M2 + global observer (`j_s2_cgtest_obs`):** full labeled pass (`mechanism=M2 obs=yes`).
- **Bare M2 without observer (`obs=no`):** emit `STAGE2-CGROUP-SCOPE-PARTIAL mechanism=M2 obs=no` with a **non-zero exit**, while still requiring Case A safety checks (`exec rc=0`, `denied_inside=0`, `denied_outside=0`, `m2_seen=0`).
- **Agent startup gate:** try **M1**, then **M2 + observer**, otherwise **refuse to arm enforcement**.
- **Enforce-only tier:** not an automatic fallback. If an enforce-only tier is ever wanted, it is AJ's call as an explicit signed profile (per O17 / `docs/architecture/architecture-rev2.md`), not an automatic fallback.

**Known gap (do not edit the pinned runner):**
- The SHA-pinned `stage2/cgtest/run_s2_1.sh` (SHA-256 `6953e1e0be278cf103bc95f59f2ff7bc3540319944fd729ab102bbcf7cd70acc`, lines `253–256` and `328`) currently emits `NOTE-case-a-m2-no-global-observer` and can emit `STAGE2-CGROUP-SCOPE-PASS` on `M2` with `obs=no`.
- That path was **unexercised** on Rock Box because M1 won (`VERIFIER-M1=accepted`, `ACTIVE_MECHANISM=M1`).
- **Do not edit** the pinned `stage2/cgtest/run_s2_1.sh`. Fix this in a future runner version and in the Rust agent startup gate.

**Rationale (Opus decision-reviewer recommendation):**
- O28 C requires both cgroup-scoped enforcement inside the test cgroup and observe-only visibility outside it (`docs/architecture/architecture-rev2.md` §4 Stage 2, §7 O28). Allowing bare M2 (`obs=no`) to emit a full PASS or automatically arm enforcement would silently lose global observation outside the test cgroup and collapse O28 C into an unrequested enforce-only mode.
- Distinguishing full labeled pass (`mechanism=M2 obs=yes`) from `STAGE2-CGROUP-SCOPE-PARTIAL mechanism=M2 obs=no` with a non-zero exit—while still enforcing the Case A safety invariants (`exec rc=0`, `denied_inside=0`, `denied_outside=0`, `m2_seen=0`) so isolation safety is still verified rather than masked—prevents false confidence in test harnesses.
- Refusing to arm enforcement at agent startup when neither M1 nor M2+observer can attach prevents silent capability downgrade; any future enforce-only mode remains an explicit, AJ-signed choice.

---

### Q3 — Hook B (`socket_connect`) Sequencing

**AJ decision (2026-11-24):**
- Hook B (`socket_connect`, deferred from S2-1) gets its own **S2-2** feasibility test before Stage 2 agent design.

**Note:**
- S2-1 verified Hook A (`bprm_check_security`) only. Testing Hook B in a dedicated S2-2 pass before locking agent design confirms kernel verifier acceptance and cgroup-scoping behavior for `socket_connect` directly rather than assuming Hook A behavior carries over.

---

### Q4 — Rust Userspace BPF Loader (`aya` vs `libbpf-rs`)

**AJ decision (2026-11-24):**
- Use **`aya =0.16.0`** (already pinned from Stage 1 / O5 in `crates/johnny-daemon/Cargo.toml:9`, `default-features = false`) as the Rust userspace loader, and **keep clang-built C BPF objects** (consistent with `docs/architecture/architecture-rev2.md` §1.2: C stays in-kernel for BPF; Rust for userspace).
- **Parity gate (`S2-1R`):** gated on an `aya`-loader parity re-run of S2-1 Cases A–D on Rock Box kernel `7.3.0-10-generic` (**"S2-1R"**) before locking agent design.
- **Revisit triggers** — reconsider `aya` vs `libbpf-rs` if any of the following occurs:
  1. S2-1R parity fails non-trivially;
  2. Kernel-verified signed BPF becomes required (`libbpf` light skeletons; **UNVERIFIED**); or
  3. A needed BPF attach type is missing in `aya` `0.16.0`.

**Rationale (Opus decision-reviewer recommendation):**
- Reusing `aya =0.16.0` keeps one pure-Rust userspace loader across Stage 1 (`johnny-daemon`) and Stage 2 without adding a C `libbpf-dev` build dependency (`libbpf-dev` is not installed on Rock Box) or maintaining two separate loader stacks, while keeping clang-built C BPF objects for kernel-side probes.
- Because S2-1 loaded via Python `ctypes` + `libbpf.so.1`, `aya =0.16.0`'s ability to load and attach `BPF_PROG_TYPE_LSM` + `BPF_MAP_TYPE_CGROUP_ARRAY` / `BPF_LSM_CGROUP` cleanly on kernel `7.3.0-10-generic` is **UNVERIFIED**. Gating on an S2-1R parity re-run of Cases A–D catches any loader or attach-type gap before agent design locks, and the three explicit revisit criteria keep the exit ramp clear if parity, signed BPF light skeletons (**UNVERIFIED**), or attach-type coverage requires switching.

---

## 2. Summary Table

| Question | Decision (AJ, 2026-11-24) | Gate / Follow-up |
|---|---|---|
| **Q1** | M1 (`lsm/bprm_check_security` + subtree helper) primary; M2 (`lsm_cgroup`) fallback **only** with global observer (`j_s2_cgtest_obs`) | Enforced in future runner + Rust startup gate |
| **Q2** | M2+observer = full labeled pass (`mechanism=M2 obs=yes`); bare M2 = `STAGE2-CGROUP-SCOPE-PARTIAL mechanism=M2 obs=no` + non-zero exit (still requiring Case A safety checks); startup tries M1 → M2+observer → refuse to arm enforcement; enforce-only only via explicit AJ-signed profile | Pinned `stage2/cgtest/run_s2_1.sh` left untouched; fix in future runner version and Rust startup gate |
| **Q3** | Hook B (`socket_connect`) gets its own **S2-2** test before agent design | Run S2-2 after S2-1R |
| **Q4** | Use `aya =0.16.0` (from Stage 1 / O5) as Rust loader + keep clang-built C BPF objects | Gated on **S2-1R** (`aya` parity re-run of S2-1 Cases A–D on `7.3.0-10-generic`) before locking agent design; revisit on non-trivial parity failure, signed BPF / `libbpf` light skeletons (**UNVERIFIED**), or missing attach type in `aya 0.16` |

---

## 3. Next Steps (In Order; Each Step Waits for AJ)

1. **S2-1R (`aya` parity test):** Re-run S2-1 Cases A–D on Rock Box (`7.3.0-10-generic`) using `aya =0.16.0` loading the clang-built C BPF object, confirming full parity before proceeding. Waits for AJ go and adversarial review before any `sudo` paste.
2. **S2-2 (Hook B test):** Feasibility test for Hook B (`socket_connect`) cgroup scoping on Rock Box. Waits for AJ go and adversarial review before any `sudo` paste.
3. **Stage 2 agent design:** Proceeds only after S2-1R and S2-2 complete and AJ approves moving to design.
