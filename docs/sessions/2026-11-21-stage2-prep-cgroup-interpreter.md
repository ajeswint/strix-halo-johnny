# 2026-11-21 America/Chicago: Stage 2 prep drafts — cgroup-scoping test runbook + interpreter plan questions (docs only)

- **Scope:** Docs-only DRAFT on stacked branch `stage2/prep-cgroup-interpreter` (based on PR #49 `docs/seat-pr-reviewer-opus-2026-11-21` -> `claude/practical-ritchie-4c6vvf`, not `main`).
- **Context:** Stage 1 exited (`STAGE1-EXIT-CHECK-DONE`, handoff rev 123); PR reviewer seat updated to Claude Code Opus medium (AJ 2026-11-21 9:15 PM CT, PR #49, handoff rev 124).
- **Drafts written under `docs/stage2/`:**
  1. `docs/stage2/cgroup-scoping-test-runbook.md`: Rock Box BPF LSM cgroup-scoping feasibility test runbook addressing O28 C's **UNVERIFIED** prerequisite (`docs/architecture/architecture-rev2.md` §4 Stage 2, §7 O28). Includes:
     - Paste S2-0A: unprivileged read-only probe (`uname -r`, `bpf` in `/sys/kernel/security/lsm`, `/sys/kernel/btf/vmlinux`, `cgroup2` mount, kernel config, toolchain inventory).
     - Paste S2-0B: privileged read-only `sudo bpftool feature probe kernel full` + BTF enum check (`sudo -v` first line, labeled `***<u>Run on Rock Box</u>***`, explicitly noting the `libbpf`/`bpftool` LSM helper-probe caveat).
     - Phase 2 minimal test design (double-gated sentinel target + 4-case proof matrix covering observe-outside, deny-inside, nested child cgroup subtree escape check, and clean detach) with PASS/STOP token contract.
     - Standalone idempotent Rollback section (`not part of the paste sequence above`, `sudo -v` first line, labeled `***<u>Run on Rock Box</u>***`).
     - Review state: **DRAFT — awaiting adversarial-reviewer (Claude Code Opus medium) review before AJ runs any sudo paste.**
  2. `docs/stage2/interpreter-plan-questions.md`: O21 interpreter gap framed as six architectural questions (`Q1–Q6`) with honest tradeoffs, bypass analysis, Rock Box breakage risk, and O17 minisign / Fix 1 / Fix 3 interactions. Not a finalized design; stops for AJ's choices (`AGENTS.md:22`).
- **Constraints kept:** No sudo run. No SSH to Johnny or any host. No processes killed. No Rust/C code modified. `crates/johnny-daemon/tests/parity.rs` untouched. Runbook paste fences in `docs/tool-install/stage1-rust-daemon-cutover.md` byte-identical. `main` untouched.
- **Handoff & Session Log:** `docs/os-handoff.md` rev 125 (shifted living `docs/os-handoff.md` line cites updated in `docs/architecture/architecture-rev2.md` and `docs/tool-install/stage1-rust-daemon-cutover.md`), `docs/sessions/Johnny_Stage2Prep_Session_Log_2026-11-21.csv`.
