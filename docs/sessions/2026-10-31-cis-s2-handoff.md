# Johnny handoff → new session: CIS section 2 (2026-10-31)

> **Historical.** Section 2 done (handoff rev 10). Current state: `docs/os-handoff.md` (latest rev); next brief: `docs/sessions/2026-10-31-cis-s3-handoff.md`.

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 9). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (for Grok) → Outline.

## Task: CIS section 2, audit only
- **Benchmark:** CIS Ubuntu Linux 26.04 LTS 1.0.0, Level 1 – Server, **section 2: 44 L1 rules**. No change on Johnny.
- **Owner:** the `governance` agent. Procedure: `.claude/skills/cis-audit/SKILL.md` (Governance preloads it).
- **Scripts:** build `docs/cis-local/cis-2*-audit.sh` from the local PDF (gitignored, CIS-licensed; never commit CIS text).
- **Run:** Claude runs the non-root parts over `ssh aj@192.168.50.152` after showing AJ the command. AJ runs the root parts, saving output to `~/cis-audit/` on Johnny.
- **Record:** one row per rule in `docs/cis-26.04-l1-results.csv` (`id,title,level,result,evidence,date`).
- **Fix gate:** no remediation until a working console exists (HDMI dummy + AMT KVM video verified, or a monitor at the closet).
- **Session end (Brain):** write section 2 totals and failures-by-fix-type into handoff step 10; bump the handoff revision; add the session CSV to `docs/sessions/`.

## State, one screen
- **Johnny:** Ubuntu Server 26.04.1, kernel 7.0.0-42, Secure Boot + TPM-unlocked LUKS, headless in the closet. Unchanged since rev 7.
- **CIS L1 progress:** section 1 done (78: 34 pass, 25 fail, 19 N/A). Left: 2 (44), 3 (37), 4 (4), 5 (70), 6 (17), 7 (24).
- **Team:** `docs/agent-team.md` rev 5, confirmed by Grok. The Brain is the main session; 9 agents in `.claude/agents/`; first skill `cis-audit`. Agents and the skill loaded in-session on 2026-10-31.
- **SLM:** on-box, full function for now (AJ).
- **Parked** (handoff § Parked): ableton_box (192.168.50.211) role and the Security Onion pattern; its OS; the `docs/hosts/` owner. Leave them unless AJ raises them.

## Don't
- Drift: section 2 only.
- Run sudo, handle passwords, or use placeholders in commands.
