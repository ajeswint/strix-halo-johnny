---
name: cis-audit
description: Audit Johnny against the CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0, Level 1 – Server (Level 2 later), one section at a time, read-only, and record verdicts in docs/cis-26.04-l1-results.csv. Use when continuing the CIS baseline (handoff step 10), auditing a CIS section or rule, or re-checking a rule after a fix. Governance skill. Audit only; never remediates.
---

# CIS audit (Governance)

Audit only, no change on Johnny. Fixes belong to Platform's `cis-remediation`, behind the fix gate.

## Standard
- **CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0, Level 1 – Server** (274 recommendations). Level 2 – Server (+76) is a second pass once the log volume exists. Chosen by AJ, 2026-10-30 (handoff step 10, method c).
- Exact release only. Never use another release's content (e.g. 24.04 SCAP content, USG profiles for other releases) or work around a version gate.
- Before stating that a benchmark, profile or tool covers 26.04, fetch the standards body's own page, not a search summary.
- Move to Canonical `usg audit` (CIS + DISA STIG) once USG ships a 26.04 profile. Check https://ubuntu.com/about/release-cycle and https://documentation.ubuntu.com/security/compliance/usg/.

## License
- The benchmark PDF and every script built from it are CIS-licensed: local only, gitignored.
  - PDF: `docs/CIS_Ubuntu_Linux_26.04_LTS_Benchmark_v1.0.0.pdf` (sha256 `4acce51f65a3f5597c6083e78ee334733fb814bc733c10b566764295885a4af8`)
  - Scripts: `docs/cis-local/cis-<section>-audit.sh`
- Never paste benchmark text or CIS script bodies into a tracked file, a commit or a report. The results CSV carries rule id, title, verdict and observed evidence only.

## Where things stand
Source of truth: `docs/os-handoff.md` step 10 and `docs/cis-26.04-l1-results.csv`. As of 2026-10-30, section 1 is done (78 L1: 34 pass, 25 fail, 19 N/A). L1 left by section: 2 (44), 3 (37), 4 (4), 5 (70), 6 (17), 7 (24).

## Method, per section
1. **Extract.** `pdftotext -layout` the section from the local PDF. List its recommendations whose Profile Applicability includes Level 1 – Server; skip L2-only ones.
2. **Build the script** `docs/cis-local/cis-<section>-audit.sh`:
   - Header comment: benchmark and version, section, "L1 only", "PDF line wraps rejoined".
   - Use CIS's own audit commands, line wraps rejoined. Where CIS gives one script body for many parameters, wrap it once as a function and call it per parameter.
   - Before each rule: `echo "== <id> (expect <what CIS says passes>)"`. End with `echo "== end"`.
   - Non-root commands only.
3. **Run read-only from rock-box**, after showing AJ the command: `ssh aj@192.168.50.152 'bash -s' < docs/cis-local/cis-<section>-audit.sh`
4. **Root-only checks.** Give AJ an exact one-liner that saves output on Johnny under `~/cis-audit/` (e.g. `> ~/cis-audit/<section>-root.txt`). AJ runs it; read the file back over SSH. Never run sudo; never handle passwords.
5. **Judge** each rule against CIS's stated expected output:
   - `PASS` / `FAIL`
   - `N/A`, with the reason (e.g. "not a separate mount; separate partition is L2")
   - `PASS (manual)` / `FAIL (manual)` for Manual-assessment rules, with the reasoning
6. **Record** one row per rule in `docs/cis-26.04-l1-results.csv`: `id,title,level,result,evidence,date`. Evidence is the observed fact (file, value, command output) on one line, quoted if it contains commas.
7. **Report to the Brain** (it writes the handoff and session log):
   - one session-log row per audit block: command, counts, failing ids
   - section totals, and failures grouped by fix type (e.g. module blocklist, mount options, sysctl) so Platform can batch fixes

## Rules
- Read-only. Anything that would change Johnny is out of scope; hand it to Platform as a Handoff.
- Fix gate (record it, don't cross it): no remediation until a working console exists (HDMI dummy in + AMT KVM video verified, or a monitor at the closet); keep a second SSH session open while testing each change.
- Mark assumptions. If CIS audit text is ambiguous, say so in the evidence and use the `(manual)` verdict.
