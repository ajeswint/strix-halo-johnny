# Working rules for agents in this repo

- Read `README.md`, then `docs/os-handoff.md` (current state). The project is "Johnny"; never call it "Sentinel".
- Team: `docs/agent-team.md` (roster, file ownership); agent files in `.claude/agents/`. The main session is the Brain. Agent reports to the Brain use that doc's §6 format.
- Reply to AJ in three parts, in this order (one-line answers excepted):
  1. **Detail**: the full write-up. Long is fine; this is the record.
  2. **Relay**: the seat that is replying writes it. Grok's Relay is for Claude to read. Claude's Relay is for Grok to read. Short, pasteable as-is.
  3. **Outline**: a nested outline of the Detail.
- Model seats (AJ, 2026-11-03): Grok writes the drafts, commands, and repo edits. Claude reviews and does not edit the draft. The writer does not review their own work. AJ still decides and runs sudo. Domain ownership in `docs/agent-team.md` is unchanged.
- CIS batches (AJ, 2026-11-04): one `sudo bash` script per batch where a failure is recoverable, with fail-fast checkpoints. Filesystem mount changes and reboots are their own pastes. Batch 5's mount steps and its reboot stay separate. Start a new Grok session for each batch.
- Review (AJ, 2026-11-04): Claude reviews the exact paste before AJ runs it, and once at batch close. Docs-only commits are not a review gate. The paste AJ runs is one fenced block. `sudo -v` is its first line when the block needs sudo. Rollback is a later block labeled not part of the paste.
- AJ runs anything needing sudo or credentials. Claude and Grok run read-only checks on Johnny over `ssh aj@192.168.50.152` (DHCP on `eno3`, reserved on the router). `aj` has no passwordless sudo. A narrow NOPASSWD entry was not adopted. Never echo or store passwords. Do not use another release's SCAP or CIS-CAT content for this pass.
- Mark assumptions. Search before stating Ubuntu 26.04 specifics (package names, dracut behavior, kernel) and cite the URL.
- Exact copy-paste commands only. No `<placeholders>` in command blocks.
- Files under `etc/` are copies of live files on Johnny and mirror their real paths. Update the copy in the same commit as the change.
- At session end only: bump the handoff revision in `docs/os-handoff.md` and add that session's CSV to `docs/sessions/`. Do not bump them on every edit. Git log is the record between session ends.
- Never `pci=noaer`; never disable ACS Source Validation; no snaps.
- The on-box SLM is part of the architecture and has full function for now (AJ, 2026-10-31). Any limits are set in the later architecture pass.
- Johnny work stays here, not in strix-halo-lab. Flag before drifting into other projects.
- After presenting options, stop and wait for AJ's choice.
