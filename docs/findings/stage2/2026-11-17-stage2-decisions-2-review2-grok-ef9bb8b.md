APPROVE

## Detail

**APPROVE.** Review 1's B1 is fixed, and the branch still matches the ground truth. Nothing new is blocking.

HEAD is `ef9bb8b` on `claude/stage2-decisions-2`. `git diff HEAD~1..HEAD` is one line in `docs/architecture/architecture-rev2.md`. Line 324 no longer lists O27's cutover window under **AJ decides.** It keeps the open remainder (what "parity" means, and when the Python reader is retired) and points at the decided window. That window is still window A at line 339 (Stage 2 entry 1) and line 493 (§7 O27): Paste S1-6 after 2026-11-21 15:33 CT, B and C declined, the date alone does not exit Stage 1, and the accepted gap is that no cold boot has been tested under the Rust daemon.

`git diff cc7e22c..HEAD` against `docs/findings/stage2/2026-11-17-stage2-decisions-2-review1-ground-truth.txt`:

- O17 is minisign. The "private key is not a plain file on Rock Box" wording is replaced, not left beside the new text, in §7 O17, lock-in row 4, §2.1 Decision 3, and Stage 2 entry 4. The key stays on a USB stick and on Rock Box for now, with AJ's "this isnt fort knox" quote. `docs/architecture/architecture-rev2.md` has no remaining "plain file" or "PENDING" text. Rev 121's old wording stays only as history in `docs/os-handoff.md`.
- Accepted risk and the O25 note are recorded: lockdown `none`, Secure Boot on Rock Box assumed off and **UNVERIFIED**, so root on Rock Box can sign rules and can change the kernel and the agent.
- PR #46 nits: the DMT Console cite is `docs/os-handoff.md:320`, which is the current **DMT Console (rock-box)** bullet. N2 is in `docs/sessions/2026-11-17-stage2-decisions-2.md`: the interpreter plan is required before enforcing; only BPF LSM cgroup scoping is **UNVERIFIED**. `docs/sessions/2026-11-17-stage2-decisions.md` is unchanged.
- Handoff is rev 122. The session CSV's last row is `PR-OPEN`. HEAD is not contained in `origin/claude/practical-ritchie-4c6vvf` (`cc7e22c`, PR #46).
- Key handling matches the cutover doc at lines 65–72: AJ creates the key pair, agents create none, minisign's default password prompt (not `-W`), public key may be committed, private key never, rotation open.
- Paste S1-6 in `docs/tool-install/stage1-rust-daemon-cutover.md` is marked **UNREVIEWED — DRAFT**. `sudo` is only `sha256sum -c`, `systemctl is-active`, `module1-slice2b-boot.sh status`, and `journalctl`. `status` takes no lock and does not write. `ctl_rows` prints one `name total` line, and `do_status` prints `CTL name total`, so `grep -qx` is the right check. A local stand-in of that gate passes when the three drop counters are unchanged (including when `seen` increases) and stops on `rate_limited`, `rb_full`, `discarded`, or a longer value that only starts with `18217138`. A `BASELINE CTL ...` line does not satisfy the exact match. Rollback is `docs/tool-install/stage1-rust-daemon-cutover.md:275-303`, and both cites in the architecture doc point there.
- `crates/johnny-daemon/tests/parity.rs` adds only the `STAGE1-EXIT-CHECK-DONE` token. No release source changed.

Tests, from this worktree: `cargo test --locked --offline` in `crates/` passed 42 tests (21 `johnny-daemon` unit, 7 parity, 14 `johnny-record-v1`), including `cutover_runbook_audit`. `bash docs/tool-install/module1-slice2b-self-test.sh` ended `SELF-TEST-OK` (`RUNBOOK-OK blocks=22`). The repo was not modified.

Verdict file: `/tmp/johnny-seats/stage2-decisions2-review2/review.done`.

## Relay

APPROVE. B1 is fixed at `docs/architecture/architecture-rev2.md:324` (window A stays at :339 and :493). Ground truth holds: O17 minisign text replaced in the four places, old session note untouched, DMT cite is `docs/os-handoff.md:320`, rollback cite is `docs/tool-install/stage1-rust-daemon-cutover.md:275-303`, Paste S1-6 is read-only and fail-closed on a changed drop counter, parity.rs is test-only. `cargo test --locked --offline` 42 passed. Self-test `SELF-TEST-OK`. PR still open. No new findings.

## Outline

- Verdict: APPROVE
- B1 fix (`HEAD~1..HEAD`)
  - `docs/architecture/architecture-rev2.md:324` keeps only the O27 remainder
  - Window A still at :339 and :493
- Ground truth (`cc7e22c..HEAD`)
  - O17 minisign, key on USB and Rock Box, accepted risk, O25 note
  - Four "plain file" sites replaced; no current PENDING in the architecture doc
  - N1 DMT cite `:320`; N2 in the new session note; old session note unchanged
  - Handoff rev 122; CSV final row `PR-OPEN`; branch not merged
  - Key handling cites cutover doc `:65-72`
  - Paste S1-6 read-only; exact `CTL` lines; fail-closed if a drop counter changes
  - Rollback range `:275-303`
  - `parity.rs` token only
- Tests
  - `cargo test --locked --offline`: 42 passed
  - Self-test: `SELF-TEST-OK`
- Artifact: `/tmp/johnny-seats/stage2-decisions2-review2/review.done`
