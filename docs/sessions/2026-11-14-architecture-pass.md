# 2026-11-14 America/Chicago: Architecture Pass Started & Runbook Nit N2

- **Date:** 2026-11-14 America/Chicago
- **Status:** **COMPLETE (DOCS ONLY)**
- **Branch:** `claude/architecture-pass`
- **Revision:** rev 115
- **Seats:**
  - Code-writer: Antigravity agy (Gemini 3.8 Flash high)
  - Reviewer: Adversarial reviewer (Claude Code, Assurance)
- **Constraints Maintained:**
  - Branch stays `claude/architecture-pass`; never touch `main`.
  - NEVER SSH, never sudo, never contact Johnny (`192.168.50.152`) or switch (`192.168.88.1`).
  - Do not kill or touch any other `agy` or `cursor-agent` process.
  - No secrets in repo.
  - DOCS ONLY: no changes to scripts (`.sh`/`.py`), systemd units, BPF source/objects, or sha256 pins.
  - Johnny is running an uninterrupted 1-week capture test until 2026-11-21 15:33 CT; nothing touches Johnny before then.

## Work Completed

1. **Architecture Pass Decision Brief (`docs/architecture/architecture-pass.md`):**
   - Reframed as a decision brief presenting options, tradeoffs, and one recommendation per item, each explicitly marked "AJ decision pending" and "**AJ decides.**".
   - Covered Items A–F (`docs/agent-team.md` §7.2–§7.7):
     - Item A: SLM limits and autonomy (tighten-only vs. bidirectional vs. off-box).
     - Item B: Tier 1 fleet / global cloud / MLS RFC 9420 scope (point-to-point LAN mTLS/WireGuard vs. cloud TreeKEM).
     - Item C: Endpoint vs. network scope of Module 1 (pure network sensor vs. Johnny self-protection vs. distributed host EDR).
     - Item D: Copy-on-Write (CoW) filesystem architecture (drop on-box file rollback vs. XFS reflink vs. Btrfs/ZFS).
     - Item E: Automated network quarantine path (human-in-the-loop advisory vs. programmatic switch access vs. router firewall).
     - Item F: Kleene strong 3-valued logic ($K_3$) verdict model and entity transition rules.
   - Mapped capability dependencies for Modules 2 and 3 without deciding code structure.
   - Formulated 8 code-shape questions for AJ without answering them (§4).
   - Documented 9 architectural gaps vs. a commercial EDR (Webroot / CrowdStrike class) (§5).
   - Identified 5 architectural lock-in risks (§6).
   - Structured decisions for AJ in dependency order (§7).
   - Outlined staged capability build order (§8).

2. **Runbook Nit N2 Fixed (`docs/tool-install/module1-slice2b-boot-unit.md`):**
   - Bumped to Rev 5, 2026-11-14 America/Chicago outside bash fences.
   - Updated Status line to reflect applied and verified retention raise (2026-11-14 19:18Z), applied and verified rate-cap removal (2026-11-14 21:32Z), and ongoing 1-week validation test.
   - Updated Purpose list items 2 and 5 to read as historical original-slice values with pointers to applied values.
   - Historical Decisions section and all bash fences left byte-identical.
   - Ran `docs/tool-install/module1-slice2b-self-test.sh` locally: passed with `OUTSIDE-FENCE-DIFF-OK blocks=17`, `RUNBOOK-OK blocks=22`, `SELF-TEST-OK`.

3. **Handoff and Roster Updates:**
   - `docs/os-handoff.md`: Bumped title line to Rev 115; added top Rev 115 section documenting rate-cap verification (Paste A/B/C passed, 0 drops in 60 s window), week test running, and architecture pass started; updated Rev 114 status line to APPLIED AND VERIFIED on Johnny (2026-11-14 21:32Z, see rev 115).
   - `docs/agent-team.md`: Added note under §7 and §9 documenting that the architecture pass has started on 2026-11-14 with all items AJ decision pending.
   - `docs/findings/architecture-pass/README.md`: Created findings directory for review tracking.
