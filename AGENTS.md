# Working rules for agents in this repo

- Read `README.md`, then `docs/os-handoff.md` (current state). The project is "Johnny"; never call it "Sentinel".
- Team: `docs/agent-team.md` (roster, file ownership); agent files in `.claude/agents/`. The main session is the Brain. Agent reports to the Brain use that doc's §6 format.
- Reply to AJ in three parts, in this order (one-line answers excepted):
  1. **Detail**: the full write-up. Long is fine; this is the record.
  2. **Relay**: the seat that is replying writes it. The code-writer seat's Relay is for the adversarial-reviewer to read. The adversarial-reviewer's Relay is for the code-writer to read. Short, pasteable as-is.
  3. **Outline**: a nested outline of the Detail.
- Model seats (AJ, 2026-11-17 10:50 PM CT; replaces the Claude Fable writer as of 2026-11-15, and historical 2026-11-05 two Claude Code Sonnet medium instances / earlier 2026-11-03 and 2026-11-05 Grok-writer pins). Domain ownership in `docs/agent-team.md` is unchanged. The writer does not review their own work. AJ still decides and runs sudo.
  - **Writer** (**code-writer**): Antigravity `agy` with `gemini-4-argon-high` (high effort, auto mode) — drafts, commands, repo edits. **Reviewer** (**adversarial-reviewer**): Grok 4.7 high via `cursor-agent` — reviews only; does not edit the draft. Agent files: `.claude/agents/code-writer.md`, `.claude/agents/adversarial-reviewer.md`.
  - ROCK-BOX-BOT (the Grok Bot on rock-box) automates the writer↔reviewer relay. Earlier seat pins (Claude Fable writer before 2026-11-15; two Claude Code Sonnet medium instances on 2026-11-05; Grok-writer on 2026-11-03 and 2026-11-05; legacy `GROK_MODEL` values in `tools/relay/README.md` for older CIS batch scoring) remain historical only.
- CIS batches (AJ, 2026-11-04): one `sudo bash` script per batch where a failure is recoverable, with fail-fast checkpoints. Filesystem mount changes and reboots are their own pastes. Batch 5's mount steps and its reboot stay separate. Start a new code-writer session for each batch.
- Review (AJ, 2026-11-04; seat rename 2026-11-05): the adversarial-reviewer reviews the exact paste before AJ runs it, and once at batch close. Docs-only commits are not a review gate. The paste AJ runs is one fenced block. `sudo -v` is its first line when the block needs sudo. Rollback is a later block labeled not part of the paste.
- AJ runs anything needing sudo or credentials. Claude Code seats run read-only checks on Johnny over `ssh aj@192.168.50.152` (DHCP on `eno3`, reserved on the router). `aj` has no passwordless sudo. A narrow NOPASSWD entry was not adopted. Never echo or store passwords. Do not use another release's SCAP or CIS-CAT content for this pass.
- Mark assumptions. Search before stating Ubuntu 26.04 specifics (package names, dracut behavior, kernel) and cite the URL.
- Exact copy-paste commands only. No `<placeholders>` in command blocks.
- Files under `etc/` are copies of live files on Johnny and mirror their real paths. Update the copy in the same commit as the change.
- At session end only: bump the handoff revision in `docs/os-handoff.md` and add that session's CSV to `docs/sessions/`. Do not bump them on every edit. Git log is the record between session ends.
- Never `pci=noaer`; never disable ACS Source Validation; no snaps.
- The on-box SLM is part of the architecture (AJ, 2026-10-31). AJ decision 2026-11-14: the AI only tightens or suggests; loosening only via AJ-signed rules (docs/architecture/architecture-rev2.md). This replaces "full function for now" (AJ, 2026-10-31).
- Johnny work stays here, not in strix-halo-lab. Flag before drifting into other projects.
- After presenting options, stop and wait for AJ's choice.
