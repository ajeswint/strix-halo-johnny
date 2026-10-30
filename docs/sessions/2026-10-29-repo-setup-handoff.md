# Handoff: repo setup (2026-10-29)

> **Historical.** Current state: `docs/os-handoff.md` rev 4. Johnny is now `ssh aj@192.168.50.152`.

From the aj-rock-box home-folder Claude Code session to Claude Code in Cursor.

Repo: ajeswint/strix-halo-johnny (private), cloned at ~/Projects/strix-halo-johnny, branch main tracking origin over SSH (git@github.com:ajeswint/strix-halo-johnny.git). Pushes work with the ~/.ssh/id_ed25519 key. No gh CLI on this machine; AJ creates GitHub repos on the web.

Commits so far:
- 4eef916 initial: README.md (project, hardware, sequence, design decisions), docs/os-handoff.md (OS handoff rev 3, copied from ~/Documents/claude/), docs/sessions/Johnny_OS_Session_Log_2026-10-28.csv, an empty etc/ (will mirror Johnny's live config files), .gitignore (no pcaps, keys or .env).
- 78526c2: agent rules are in AGENTS.md (also read by Cursor's agent). CLAUDE.md is just "@AGENTS.md".

Read AGENTS.md, README.md, then docs/os-handoff.md. The project is "Johnny", never "Sentinel".

Johnny box: ssh aj@192.168.50.151 (key auth). Claude runs read-only checks over SSH; AJ runs anything that needs sudo. On rock-box, root steps go through `! pkexec ...` (sudo needs a password Claude doesn't have).

Where things stand (handoff rev 3): OS installed; boot, firmware and TPM are done. The closet-move gate is open on one item: the BIOS admin password.

Next, in order:
1. BIOS admin password (put it in the password manager first), then an unattended reboot, then confirm PCR 7 still equals the baseline.
2. Package decisions: snapd, ModemManager, unattended-upgrades, remote console.
3. Pinned tool install, with versions recorded for the SBOM.

At session end: bump the handoff rev in docs/os-handoff.md, add that session's CSV under docs/sessions/, commit and push.

Not done yet: etc/ has no copies of Johnny's live config files. They need sudo to read (netplan is mode 600), so AJ has to run that step.
