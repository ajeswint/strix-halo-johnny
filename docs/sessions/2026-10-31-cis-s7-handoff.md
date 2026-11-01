# Johnny handoff → new session: CIS section 7 (2026-10-31)

> **Historical.** Section 7 done; CIS L1 pass complete, 274/274 (handoff rev 15). Current state: `docs/os-handoff.md` (latest rev); no next brief yet.

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 14). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (for Grok) → Outline.

## Task: CIS section 7, audit only (last L1 section)
- **Benchmark:** CIS Ubuntu Linux 26.04 LTS 1.0.0, Level 1 – Server, **section 7 (system maintenance): 24 L1 rules, 0 L2-only** (Brain read the PDF's Profile Applicability blocks, 2026-10-31; Governance re-verifies). No change on Johnny.
  - 7.1 system file permissions (13): 7.1.1–7.1.10 access to `/etc/passwd`, `passwd-`, `group`, `group-`, `shadow`, `shadow-`, `gshadow`, `gshadow-`, `shells`, `/etc/security/opasswd`; 7.1.11 world-writable files and dirs; 7.1.12 unowned or ungrouped files; 7.1.13 SUID/SGID review (Manual).
  - 7.2 local users and groups (11): 7.2.1 shadowed passwords; 7.2.2 no empty password fields; 7.2.3 passwd groups exist in group; 7.2.4 shadow group empty; 7.2.5–7.2.8 no duplicate UIDs, GIDs, user names, group names; 7.2.9 home dirs; 7.2.10 dot files; 7.2.11 dot directories.
- **Owner:** a fresh `governance` agent. Procedure: `.claude/skills/cis-audit/SKILL.md`. Governance may split 7.1 / 7.2.
- **Scripts:** `docs/cis-local/cis-7*-audit.sh` (non-root) and `cis-7*-root.sh` (root), built from the local PDF (gitignored, CIS-licensed; never commit CIS text). Style: `docs/cis-local/cis-6-audit.sh` / `cis-6-root.sh`. Expect more of this section in the root script than in section 6 (Governance decides; reasons to expect it): 7.1.11–7.1.13 walk the whole filesystem, and non-root `find` silently skips directories it can't enter (false pass); 7.2.2 reads `/etc/shadow`; 7.2.9–7.2.11 look inside home directories. 7.1.5–7.1.8 (`stat` of shadow files) may work as non-root.
- **Run, in this order** (same as section 6):
  1. Governance builds the scripts only (no ssh) and reports. The Brain reads every script line for write commands before anything touches Johnny. The filesystem scans must be `find`/`stat` only: no `-delete`, no `-exec` that changes anything, no `chmod`/`chown`.
  2. Brain shows AJ the command, then runs the non-root part: `ssh aj@192.168.50.152 'bash -s' < docs/cis-local/cis-7-audit.sh | tee docs/cis-local/cis-7-out.txt` (adjust the file names if Governance splits 7.1 / 7.2).
  3. Root part: AJ copies the script with `! ssh aj@192.168.50.152 'mkdir -p ~/cis-audit' && scp docs/cis-local/cis-7-root.sh aj@192.168.50.152:cis-audit/cis-7-root.sh` (typed in the Claude session), the Brain compares sha256 local vs Johnny, then AJ runs `sudo bash ~/cis-audit/cis-7-root.sh > ~/cis-audit/7-root.txt 2>&1` **in AJ's own SSH session on Johnny**; the Brain reads it back with `ssh aj@192.168.50.152 'cat ~/cis-audit/7-root.txt' | tee docs/cis-local/cis-7-root-out.txt`.
  - Commands to AJ are written out in full with real file names: never abbreviate with "…".
  4. Governance judges against the PDF and appends the rows; the Brain gives it the raw output file names and any extra read-only checks.
- **Record:** one row per rule in `docs/cis-26.04-l1-results.csv` (`id,title,level,result,evidence,date`). Append only. Don't rewrite the file with a CSV library: on 2026-10-31 a `csv.writer` rewrite re-quoted all existing rows; append lines as text. The Brain checks the diff (+24/-0, 6 columns, no duplicate ids, counts) before committing.
- **Strict CIS** (AJ, 2026-10-31): "we play by the rules for now and we will loosen if we need later." Judge the system as it is now. An empty result that is empty only because nothing is configured is not a pass where CIS requires a value (section 5: 5.3.3.2.6/.7, 5.4.3.3 FAIL (manual)); where CIS only forbids a bad value, absence passes (5.4.2.6). A missing file: follow what the PDF says for that rule (e.g. 7.1.10 if `opasswd` doesn't exist); don't assume.
- **7.1.13 (Manual) SUID/SGID review:** list what's there. Where approval is a site decision, ask AJ; don't assume approval.
- **Grok reviews** each block via AJ; keep the Relay pasteable.
- **Fix gate:** no remediation until a working console exists (HDMI dummy + AMT KVM video verified, or a monitor at the closet).
- **Session end (Brain):** section 7 totals and failures-by-fix-type into handoff step 10; mark the L1 pass complete (274/274) with the final totals; bump the handoff revision; add rows to the session CSV in `docs/sessions/`; banner this brief historical; update the skill's status line; commit; push only on AJ's word.

## Known going in (from earlier sections; verify, don't assume)
- `aj` is the only account with a password; root is locked (`L`) (section 5).
- `aj` session umask is 0002 (`USERGROUPS_ENAB yes`, no UMASK set; 5.4.3.3 FAIL (manual)), so files `aj` created may be group-writable: may matter for 7.2.10 / 7.2.11.
- `aj` groups: `aj adm cdrom sudo dip plugdev users lxd` (section 6 run). `lxd` group membership noted only; not a section 7 rule.
- `pam_pwhistory` is not configured (5.3.2.4 FAIL), so `/etc/security/opasswd` may not exist (7.1.10).
- No snaps (snapd purged). Root filesystem is one 460G XFS LV; whole-filesystem `find` scans take a while.

## State, one screen
- **Johnny:** Ubuntu Server 26.04.1, kernel 7.0.0-42, Secure Boot + TPM-unlocked LUKS, headless in the closet. Unchanged since rev 7. SSH key-only; `sudo` is sudo-rs.
- **CIS L1 progress:** sections 1–6 done, 250/274: 113 pass, 114 fail, 23 N/A. Left: 7 (24).
- **Fix queue (Platform, behind the gate):** handoff step 10, by section and fix type. Site-policy values for sections 5 and 6 are set (AJ: "accept all").
- **Team:** `docs/agent-team.md` rev 5. The Brain is the main session; 9 agents in `.claude/agents/`; skill `cis-audit`.
- **Parked** (handoff § Parked): ableton_box (192.168.50.211) role and the Security Onion pattern (also decides 6.1.2.5's remote log host); its OS; the `docs/hosts/` owner. Leave them unless AJ raises them.

## Don't
- Drift: section 7 only. Level 2 is a later pass.
- Run sudo, handle passwords, or use placeholders in commands.
