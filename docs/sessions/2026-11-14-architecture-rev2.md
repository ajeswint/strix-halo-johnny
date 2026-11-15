# 2026-11-14 America/Chicago: Architecture Rev 2 — AJ Decisions Recorded

- **Date:** 2026-11-14 America/Chicago (AJ go 10:11 PM CT)
- **Status:** **COMPLETE (DOCS ONLY). Nothing applied. Nothing ran on Johnny.**
- **Branch:** `claude/architecture-rev2` (worktree, based on `ac947ad`)
- **Revision:** handoff rev 116
- **Seats:** writer = Claude Code (`claude-fable-5-2`). Reviewer = adversarial-reviewer, not yet run on this commit.
- **Constraints kept:** no ssh, no sudo, no contact with Johnny (192.168.50.152), the switch, or any other host. `main` untouched. No script, unit, BPF source, BPF object, or sha256 value changed. No bash fence edited. No external page fetched. Johnny's week test runs to 2026-11-21 15:33 CT (21:33Z); nothing here asks AJ to touch Johnny before then.

## Work Completed

1. **`docs/architecture/architecture-rev2.md` (new, Rev 1).** Records AJ's 2026-11-14 decisions: hybrid target; code shape; why the AI exists; Linux first and Windows in Stage 4; four fixes; two adjustments; six deferred items. Maps them to the brief's Decisions 1–6, Items A–F, and §4 questions 1–8. Defines Stages 1–4 with goal, scope, entry, exit, what stays easy to change, and open items. Adds a lock-in watch and a numbered list of every open item (O1–O34), each **AJ decides.**
2. **Rock Box read-only check drafted, not run** (rev 2 §3): filesystem type, XFS reflink, BPF LSM. No sudo, no writes. Not yet reviewed.
3. **Brief banner** added at `docs/architecture/architecture-pass.md:2`. The brief's line numbers did not move.
4. **Review-3 nits** (`docs/findings/architecture-pass/2026-11-14-review3-grok-86e2c25.md`):
   - N1: `docs/findings/module1-slice2b/README.md:11` now points at the Rate Cap Removal & Week Test bullet.
   - N2: `docs/architecture/architecture-pass.md:122` now says "Decision 1 Option C" and "Decision 1 Option B".
   - N3: `docs/tool-install/module1-slice2b-boot-unit.md:58` (plain fence) now names `/root/m1s2b/backup-pre-no-ratecap/module1-slice2b-boot.sh`. Hash value unchanged. The self-test passed with this change, so the fallback rewording of the heading was not needed.
5. **"Full function for now" replaced** in `README.md:26` and `AGENTS.md:20`. `docs/agent-team.md` §7 items 2–7 each got a status line; §9 item 4 got a pointer.
6. **`docs/os-handoff.md`** bumped to rev 116 with a new top section.
7. **`docs/findings/architecture-rev2/README.md`** created for reviews.

## Checks

- `bash docs/tool-install/module1-slice2b-self-test.sh` (Rock Box, no sudo): `OUTSIDE-FENCE-DIFF-OK blocks=17`, `RUNBOOK-OK blocks=22`, `SELF-TEST-OK`.
- `git diff --name-only ac947ad..HEAD`: `.md` files only.

## Not Done / Left for AJ

- No session CSV was added. The task limited this commit to `.md` files.
- Lines that still say "full function" and were not in the edit list are listed in rev 2 §6 (`docs/agent-team.md:85`, `docs/os-handoff.md:334`, three `.claude/agents/` files). **AJ decides.**
- The four Microsoft URLs in rev 2 fix 4 are written from memory and marked "source to confirm".
- Paste W is still due only after 2026-11-21 15:33 CT (21:33Z). It is Stage 1's first entry step.
