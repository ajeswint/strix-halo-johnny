APPROVE
B1 docs/tool-install/stage1-rust-daemon-cutover.md:255-259 — TZ=America/Chicago date -d "2026-11-21 15:33:00" is 2026-11-21T21:33:00Z (1795296780). now < gate prints STOP-exit-NOT-YET and exits 1; STAGE1-EXIT-CHECK-DONE is not reached. The exact instant passes.
B2 docs/tool-install/stage1-rust-daemon-cutover.md:261-266,274-282 — btime > 2026-11-17T21:30:30Z is STOP-exit-rebooted. NRestarts=0, Result=success, and ActiveEnterTimestamp at or before cutover; else STOP-exit-daemon-restarted. boot_id and InvocationID are printed, not pinned (cutover note recorded neither). Not "changed".
N1 docs/tool-install/stage1-rust-daemon-cutover.md:308-310,312-327,329-335 — seen <= 168066737 is STOP-exit-seen-not-increased. Newest run-*.bin age > 600s is STOP-exit-runfile-stale. journalctl failure or missing "event":"reader-begin" is STOP-exit-journal-UNREADABLE. No journal line required in the last 10 minutes.
N2 docs/tool-install/stage1-rust-daemon-cutover.md:295-307 — NOTE-ctl-unreadable, status failure, missing CTL, or a non-integer is STOP-exit-ctl-UNREADABLE before any compare. *-changed only when a parsed integer differs from rate_limited 18217138, rb_full 0, or discarded 0.
Paste stays UNREVIEWED — DRAFT, read-only, ***<u>Run on Rock Box</u>*** at :246. Rollback cites docs/architecture/architecture-rev2.md:315,319 are :349-377. Session note :11-15 and the CSV record Claude's B1/B2/N1/N2 and do not say AJ declined B1. PR #47 decisions (O27 window A, O17 minisign) unchanged. parity.rs is test-only. cargo test --locked --offline: 42 passed. Self-test: SELF-TEST-OK.

**Detail**

Reviewed `git diff 1b9d113..9e80583` on `claude/stage2-decisions-2` at `9e80583` against the S1-6 ground truth, and checked `cc7e22c..9e80583` so the already-recorded PR #47 decisions still hold. No repo edits. PR #47 was not merged.

Paste S1-6 in `docs/tool-install/stage1-rust-daemon-cutover.md` is still **UNREVIEWED — DRAFT** (`:240`). The label `***<u>Run on Rock Box</u>***` is at `:246`, directly above the bash fence at `:248`. The remote script is one single-quoted `ssh -t aj@192.168.50.152` argument (`bash -n` passed). `sudo` is only `sha256sum -c`, `systemctl is-active`, `systemctl show`, `module1-slice2b-boot.sh status` (no lock; `status` is excluded from the flock at `module1-slice2b-boot.sh:1140`), `find`, `stat`, and `journalctl`. Nothing is started, stopped, installed, or written.

B1 (`:255-259`) compares `date -u +%s` to `TZ=America/Chicago date -d "2026-11-21 15:33:00" +%s`. On this host that gate is `1795296780`, the same instant as `2026-11-21T21:33:00Z`. A non-numeric clock or `now < gate` prints `STOP-exit-NOT-YET` and exits 1. `STAGE1-EXIT-CHECK-DONE` is only the last command in the `&&` chain. The embedded audit's happy path is that exact epoch; one second earlier fails and does not print the done token.

B2 uses `/proc/stat` `btime` against `2026-11-17T21:30:30Z` (`HEADER start_utc` in `docs/sessions/2026-11-17-stage1-cutover-applied.md:35`). `btime` greater than that cutover epoch prints `STOP-exit-rebooted`. `systemctl show` requires `NRestarts=0`, `Result=success`, a non-empty `InvocationID`, and `ActiveEnterTimestamp` parsed to an epoch at or before the cutover (`:274-282`), or it prints `STOP-exit-daemon-restarted`. The cutover note did not record a `boot_id` or `InvocationID`. The paste prints both live values and does not compare them to an invented pin. Neither failure token is `changed`. uutils `date` 0.12.0 parses `Tue 2026-11-17 21:30:29 UTC` and `Tue 2026-11-17 15:30:29 CST` to the correct epochs. `date` is not in Ubuntu's GNU coreutils carve-out (`cp`, `df`, `mv`, `rm`, `true`).

N1 requires `CTL seen` strictly greater than `168066737` (`:308-310`). The newest `/var/lib/johnny/m1s2b/run-*.bin` must be readable, and its mtime age must be at most 600 seconds (`:312-327`). `journalctl -u johnny-daemon.service -b` must exit 0 and contain `"event":"reader-begin"` (`:329-335`), which is the JSON the daemon emits and which Paste S1-4 already matched on Johnny. A `STOP-` line in that journal is `STOP-exit-journal-stops`. The check does not require a journal line in the last 10 minutes. File names are `run-<UTC>.bin`, so lexical `sort | tail` matches open order except a same-second `-NN` sibling, which is fail-closed rather than a false pass.

N2 parses all six `CTL name total` lines from `ctl_rows` (`module1-slice2b-boot.sh:336-351` and `:1105`) before any baseline compare (`:295-307`). `NOTE-ctl-unreadable`, a failed `status`, a missing line, or a non-integer prints `STOP-exit-ctl-UNREADABLE`. `STOP-exit-rate_limited-changed`, `STOP-exit-rb_full-changed`, and `STOP-exit-discarded-changed` run only after that parse, and only against `18217138`, `0`, and `0`. A `BASELINE ` line does not match `^CTL `.

`docs/sessions/2026-11-17-stage2-decisions-2.md:11-15` and the new CSV row record that B1/B2/N1/N2 were applied from Claude's summary. They do not say AJ declined B1. The older "B and C declined" line is the O27 window choice, not this check. `docs/sessions/2026-11-17-stage1-cutover-applied.md` and `docs/sessions/2026-11-17-stage2-decisions.md` are not in the diff.

Rollback moved with the paste. Parent `:275-303` is now `:349-377` (heading through the closing fence). Both cites in `docs/architecture/architecture-rev2.md:315` and `:319` use that range. O27 window A (`:339`, `:493`), O17 minisign, the O25 note, and the DMT Console cite at `docs/os-handoff.md:320` are unchanged. The earlier "window is decided" line at `architecture-rev2.md:324` is unchanged.

`crates/johnny-daemon/tests/parity.rs` changes are inside `cutover_runbook_audit` only. No `src/` change. `cargo test --locked --offline` in `crates/` passed 42 tests (21 `johnny-daemon` unit, 7 parity including `cutover_runbook_audit`, 14 `johnny-record-v1`). `bash docs/tool-install/module1-slice2b-self-test.sh` ended `SELF-TEST-OK`. The worktree is still clean at `9e80583`.

**Relay**

APPROVE. No paste change. S1-6 stays UNREVIEWED — DRAFT, read-only, Run on Rock Box. B1/B2/N1/N2 hold. Rollback cites `:349-377` match. parity.rs is test-only. 42 tests passed. SELF-TEST-OK. Do not merge PR #47.

**Outline**

- Verdict: APPROVE
  - Tip `9e80583`; range `1b9d113..9e80583`; PR base `cc7e22c` not merged
- Paste S1-6
  - UNREVIEWED — DRAFT, read-only, Run on Rock Box at `:246`
  - B1 `:255-259` NOT-YET before `2026-11-21 15:33 CT` / `2026-11-21T21:33:00Z`
  - B2 `:261-266` reboot, `:274-282` daemon restart; no invented `boot_id`
  - N1 `:308-335` seen past `168066737`, run file ≤ 600s, journal readable
  - N2 `:295-307` UNREADABLE before `*-changed`
- Records
  - Session note `:11-15` and CSV record Claude's summary
  - Does not say AJ declined B1
  - Historical notes untouched
  - Rollback cites `:349-377` at `architecture-rev2.md:315,319`
  - O27 window A and O17 minisign unchanged
- Tests
  - `parity.rs` test-only
  - `cargo test --locked --offline`: 42 passed
  - Self-test: `SELF-TEST-OK`
