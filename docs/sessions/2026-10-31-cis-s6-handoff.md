# Johnny handoff → new session: CIS section 6 (2026-10-31)

> **Historical.** Section 6 done (handoff rev 14). Current state: `docs/os-handoff.md` (latest rev); next: section 7 (no brief yet).

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 13). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (for Grok) → Outline.

## Task: CIS section 6, audit only
- **Benchmark:** CIS Ubuntu Linux 26.04 LTS 1.0.0, Level 1 – Server, **section 6: 17 L1 rules** (handoff count; verify from the PDF). No change on Johnny. Section 6 covers logging and auditing: 6.1 system logging (journald, rsyslog, logfile access), 6.2 auditd, 6.3 integrity checking (AIDE). The auditd rules in 6.2 are L2-only in this benchmark (handoff step 10), so expect most L1 rules in 6.1 and 6.3. Some 6.1/6.3 rules may be L2 too: Governance lists the L2-only ids it skips.
- **Owner:** a fresh `governance` agent. Procedure: `.claude/skills/cis-audit/SKILL.md` (Governance preloads it). One block is likely enough; Governance may split 6.1 / 6.3.
- **Scripts:** `docs/cis-local/cis-6*-audit.sh` (non-root) and `cis-6*-root.sh` (root, only if needed, e.g. logfile modes under `/var/log` or the journal), built from the local PDF (gitignored, CIS-licensed; never commit CIS text). Style: `docs/cis-local/cis-5.1-audit.sh` / `cis-5.1-root.sh`.
- **Run, in this order:**
  1. Governance builds the scripts only (no ssh) and reports. The Brain reads every script line for write commands before anything touches Johnny.
  2. Brain shows AJ the command, then runs the non-root part: `ssh aj@192.168.50.152 'bash -s' < docs/cis-local/<script> | tee docs/cis-local/<out>.txt`.
  3. Root part: AJ copies the script with `! ssh aj@192.168.50.152 'mkdir -p ~/cis-audit' && scp docs/cis-local/<root script> aj@192.168.50.152:cis-audit/<root script>` (typed in the Claude session), the Brain compares sha256 local vs Johnny, then AJ runs `sudo bash ~/cis-audit/<root script> > ~/cis-audit/<out>.txt 2>&1` **in AJ's own SSH session on Johnny** (not the Claude chat: on 2026-10-31 a sudo line pasted into the chat ran nothing); the Brain reads it back with `tee` into `docs/cis-local/`.
  - Commands to AJ are written out in full with real file names: never abbreviate with "…".
  4. Governance judges against the PDF and appends the rows; the Brain gives it the raw output file names and any extra read-only checks.
- **Record:** one row per rule in `docs/cis-26.04-l1-results.csv` (`id,title,level,result,evidence,date`). The Brain checks the diff (append-only, 6 columns, no duplicate ids, counts) before committing.
- **Strict CIS** (AJ, 2026-10-31): "we play by the rules for now and we will loosen if we need later." Where CIS leaves a choice to local site policy (e.g. remote log host, rotation, retention), ask AJ; don't assume approval. Judge the system as it is now. An empty grep that is empty only because nothing is configured is not a pass where CIS requires a value (section 5 precedent: 5.3.3.2.6/.7, 5.4.3.3 FAIL (manual)); where CIS only forbids a bad value, absence passes (5.4.2.6).
- **Grok reviews** each block via AJ; keep the Relay pasteable.
- **Fix gate:** no remediation until a working console exists (HDMI dummy + AMT KVM video verified, or a monitor at the closet).
- **Session end (Brain):** section 6 totals and failures-by-fix-type into handoff step 10; bump the handoff revision; add rows to the session CSV in `docs/sessions/`; banner this brief historical; commit; push only on AJ's word.

## Known going in (from earlier sections; verify, don't assume)
- rsyslog appears to be running: `/var/log/auth.log` exists (owner `syslog:adm`, 0640). CIS's 5.2.3 grep found no sudo lines in it while the journal had them (not investigated; may matter for 6.1.1.1.3 / 6.1.2.x).
- No AIDE (read-only check 2026-10-30). `auditd` not installed; auditd is L2-only here.
- Possible design overlap for later, not this audit: a remote log host (6.1.2.5) ties to the parked ableton_box manager role. Record the verdict; don't design it.

## State, one screen
- **Johnny:** Ubuntu Server 26.04.1, kernel 7.0.0-42, Secure Boot + TPM-unlocked LUKS, headless in the closet. Unchanged since rev 7. SSH: key-only; `ssh.socket` on 0.0.0.0:22 and [::]:22; `sudo` is sudo-rs.
- **CIS L1 progress:** sections 1–5 done, 233/274: 103 pass, 108 fail, 22 N/A. Left: 6 (17), 7 (24).
- **Fix queue (Platform, behind the gate):** handoff step 10, by section and fix type. Section 5's fixes are all lockout-risk; its site-policy values are open for AJ (listed in step 10).
- **Team:** `docs/agent-team.md` rev 5. The Brain is the main session; 9 agents in `.claude/agents/`; skill `cis-audit`.
- **Parked** (handoff § Parked): ableton_box (192.168.50.211) role and the Security Onion pattern; its OS; the `docs/hosts/` owner. Leave them unless AJ raises them.

## Don't
- Drift: section 6 only.
- Run sudo, handle passwords, or use placeholders in commands.
