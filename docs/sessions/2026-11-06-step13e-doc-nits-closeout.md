# 2026-11-06 — step 13e: doc nits from PRs #14 and #15, and the 13d closeout

Seat: code-writer (Sonnet). Branch `claude/step13e-doc-nits`, PR against `claude/practical-ritchie-4c6vvf` (base tip `460503a`). rock-box edits only. Read-only SSH to Johnny; no SSH write, no sudo, no apt, no reboot, no GRUB, no netplan, no `After=` change. Helper, unit and 13d script unchanged (hashes `807f5a55…`, `6084be53…`, `80f4b5f0…`).

**Closeout facts.** AJ ran the 13d paste (`STEP13B-ENO3-WAIT-FIXED`, as AJ reported) and cold-rebooted (boot 2026-11-06 01:20:40Z). Read-only SSH at ~01:23Z: live files match the repo; `johnny-capture-irq.service` `active`, `enabled`, `Result=success`; no manual start; no ordering cycle; IRQ spread `1 2 3 4 1 2 3 4 1 2 3 4`. Failing boot (-1) and proof boot (0) timelines are in the runbook § Boot race 2.

**Nits closed.**

| Nit | Source | Where it closed |
|---|---|---|
| N1 doc `TimeoutStartSec=210` vs unit 150 | PR #14 | Already fixed on `460503a` (commit `12219bc`); re-verified: no `210` left outside hashes in runbook, handoff, 13 session CSV, unit or helper. Files table now says live = 13d, 150 |
| N2 stray double backtick before `STOP-prev-hash` | PR #14 | Already fixed on `460503a`; re-verified with an odd-backtick scan of the runbook (none) |
| N3 self-test hash not in the paste | PR #14 | Runbook 13d table now records the self-test digest; Notes explain the as-run 13c/13d pastes did not hash it and a new paste should. As-run paste blocks left unedited |
| N4 pins run before tuning | PR #14 | Runbook Notes (expected `NOTE-tuning-*`); confirmed in the proof boot journal |
| N5 / PR #15 nit 5: no rollback after post-start STOPs | PRs #14, #15 | Runbook Notes |
| PR #15 nit 1: no assertion that `preflight` still calls `eno3_ok` after the wait; "second poll" comment | PR #15 | Self-test asserts `wait_boot_ready` precedes the hard `eno3_ok` in `preflight`; comment now says third poll. Mutation tested in scratch copies |
| PR #15 nit 2: oneshot gates `multi-user.target`, up to 100s stall | PR #15 | Runbook § Boot-time effect; handoff |
| PR #15 nit 3: "[Inference]" cause wording | PR #15 | Runbook and handoff: cause supported by journal timestamps (failing boot -1), not traced inside the helper |
| PR #15 nit 4: `sudo -v` placement, `rev-parse` does not pin the tip | PR #15 | Runbook Notes |
| PR #15 nit 6: `Broken pipe` journal noise (line 33) | PR #15 | Runbook Result and handoff: seen again in the proof boot (11 lines), unit succeeded; not fixed (helper edit changes the pinned hash) |

**Not closed (not doc-only).** `read_trim` shellcheck SC2261 and unused locals `xdp`/`snap` (PR #14 first review nits), and the `Broken pipe` source. Any helper edit changes the pinned hash and needs a new review and paste. `0x1583` in the self-test stub is a harmless extra bit versus Johnny's live `0x1183` (read over SSH); left as is.

**Self-test.** `bash docs/tool-install/step-13-self-test.sh` → `SELF-TEST-OK`.

**Open.** Merge is the adversarial-reviewer's call and AJ's. Handoff rev 92; row 10 and 11 added to the step 13 session CSV.
