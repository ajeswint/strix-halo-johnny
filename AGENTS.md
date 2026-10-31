# Working rules for agents in this repo

- Read `README.md`, then `docs/os-handoff.md` (current state). The project is "Johnny"; never call it "Sentinel".
- Terse. One step at a time. Show commands before running them.
- AJ runs anything needing sudo or credentials. Claude runs read-only checks on Johnny over `ssh aj@192.168.50.152` (DHCP on `eno3`, reserved on the router); `aj` has no passwordless sudo. Never echo or store passwords.
- Mark assumptions. Search before stating Ubuntu 26.04 specifics (package names, dracut behavior, kernel) and cite the URL.
- Exact copy-paste commands only. No `<placeholders>` in command blocks.
- Files under `etc/` are copies of live files on Johnny and mirror their real paths. Update the copy in the same commit as the change.
- At session end: bump the handoff revision in `docs/os-handoff.md` and add that session's CSV to `docs/sessions/`.
- Never `pci=noaer`; never disable ACS Source Validation; no snaps.
- The on-box SLM is part of the architecture and has full function for now (AJ, 2026-10-31). Any limits are set in the later architecture pass.
- Johnny work stays here, not in strix-halo-lab. Flag before drifting into other projects.
- After presenting options, stop and wait for AJ's choice.
