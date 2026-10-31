# Johnny handoff → new session: CIS section 3 (2026-10-31)

> **Historical.** Section 3 done (handoff rev 11). Current state: `docs/os-handoff.md` (latest rev); next brief: `docs/sessions/2026-10-31-cis-s5-handoff.md`.

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 10). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (for Grok) → Outline.

## Task: CIS section 3, audit only
- **Benchmark:** CIS Ubuntu Linux 26.04 LTS 1.0.0, Level 1 – Server, **section 3: 37 L1 rules**. No change on Johnny.
- **Owner:** the `governance` agent. Procedure: `.claude/skills/cis-audit/SKILL.md` (Governance preloads it).
- **Scripts:** build `docs/cis-local/cis-3-audit.sh` from the local PDF (gitignored, CIS-licensed; never commit CIS text). The Brain reads the script for write commands before it runs on Johnny.
- **Run:** Claude runs the non-root parts over `ssh aj@192.168.50.152` after showing AJ the command, saving output to `docs/cis-local/cis-3-out.txt`. AJ runs the root parts, saving output to `~/cis-audit/` on Johnny.
- **Record:** one row per rule in `docs/cis-26.04-l1-results.csv` (`id,title,level,result,evidence,date`).
- **Strict CIS** (AJ, 2026-10-31): "we play by the rules for now and we will loosen if we need later." Where CIS leaves a choice to local site policy, ask AJ; don't assume approval.
- **Fix gate:** no remediation until a working console exists (HDMI dummy + AMT KVM video verified, or a monitor at the closet).
- **Session end (Brain):** write section 3 totals and failures-by-fix-type into handoff step 10; bump the handoff revision; add the session CSV to `docs/sessions/`.

## State, one screen
- **Johnny:** Ubuntu Server 26.04.1, kernel 7.0.0-42, Secure Boot + TPM-unlocked LUKS, headless in the closet. Unchanged since rev 7. Time sync is chrony with Ubuntu NTS pools.
- **CIS L1 progress:** sections 1–2 done, 122/274: 64 pass, 36 fail, 22 N/A. Left: 3 (37), 4 (4), 5 (70), 6 (17), 7 (24).
- **Fix queue (Platform, behind the gate):** section 1 and 2 failures by fix type in handoff step 10. Section 2's package removal (rsync, telnet, ftp via `ubuntu-standard`) needs the deps marked manual first; a careless autoremove takes tcpdump, mtr-tiny, nano, plymouth, friendly-recovery.
- **Team:** `docs/agent-team.md` rev 5. The Brain is the main session; 9 agents in `.claude/agents/`; skill `cis-audit`.
- **SLM:** on-box, full function for now (AJ).
- **Parked** (handoff § Parked): ableton_box (192.168.50.211) role and the Security Onion pattern; its OS; the `docs/hosts/` owner. Leave them unless AJ raises them.

## Don't
- Drift: section 3 only.
- Run sudo, handle passwords, or use placeholders in commands.
