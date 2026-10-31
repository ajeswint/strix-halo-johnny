# Johnny handoff → new session: CIS section 5 (2026-10-31)

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 12). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (for Grok) → Outline.

## Task: CIS section 5, audit only
- **Benchmark:** CIS Ubuntu Linux 26.04 LTS 1.0.0, Level 1 – Server, **section 5: 70 L1 rules** (verify from the PDF). No change on Johnny. Section 5 covers access control (SSH server, sudo, PAM, password and account settings), so expect a large root part (e.g. `sshd -T`, shadow/PAM files).
- **Owner:** a fresh `governance` agent. Procedure: `.claude/skills/cis-audit/SKILL.md` (Governance preloads it). Large section: Governance may split it into sub-blocks (e.g. 5.1 / 5.2 / 5.3–5.4), one script and one report each.
- **Scripts:** `docs/cis-local/cis-5*-audit.sh` (non-root) and `cis-5*-root.sh` (root), built from the local PDF (gitignored, CIS-licensed; never commit CIS text). Style: `docs/cis-local/cis-4-audit.sh` / `cis-4-root.sh`.
- **Run, in this order:**
  1. The Brain reads every script line for write commands before anything touches Johnny.
  2. Brain shows AJ the command, then runs the non-root part: `ssh aj@192.168.50.152 'bash -s' < docs/cis-local/<script> | tee docs/cis-local/<out>.txt`.
  3. Root part: AJ copies the script with `! ssh aj@192.168.50.152 'mkdir -p ~/cis-audit' && scp docs/cis-local/<root script> aj@192.168.50.152:cis-audit/<root script>` (typed in the Claude session), the Brain compares sha256 local vs Johnny, then AJ runs `sudo bash ~/cis-audit/<root script> > ~/cis-audit/<out>.txt 2>&1` in AJ's SSH session on Johnny; the Brain reads it back with `tee` into `docs/cis-local/`.
  - Commands to AJ are written out in full with real file names: never abbreviate with "…" (AJ pasted an abbreviated one on 2026-10-31 and ssh treated "…" as a hostname).
- **Record:** one row per rule in `docs/cis-26.04-l1-results.csv` (`id,title,level,result,evidence,date`). The Brain checks the diff (append-only, 6 columns, counts) before committing.
- **Strict CIS** (AJ, 2026-10-31): "we play by the rules for now and we will loosen if we need later." Where CIS leaves a choice to local site policy, ask AJ; don't assume approval. Judge the system as it is now (e.g. IPv6 is enabled today even though policy is "not used").
- **Fix gate:** no remediation until a working console exists (HDMI dummy + AMT KVM video verified, or a monitor at the closet). Section 5 fixes (SSH, PAM lockout, sudo) are the lockout-risk ones.
- **Session end (Brain):** section 5 totals and failures-by-fix-type into handoff step 10; bump the handoff revision; add the session CSV to `docs/sessions/`; commit; push only on AJ's word.

## State, one screen
- **Johnny:** Ubuntu Server 26.04.1, kernel 7.0.0-42, Secure Boot + TPM-unlocked LUKS, headless in the closet. Unchanged since rev 7. chrony with Ubuntu NTS pools. SSH: key-only, password auth off (handoff Installed state); `ssh.socket` on 0.0.0.0:22 and [::]:22.
- **CIS L1 progress:** sections 1–4 done, 163/274: 71 pass, 70 fail, 22 N/A. Left: 5 (70), 6 (17), 7 (24).
- **Fix queue (Platform, behind the gate):** handoff step 10, by section and fix type. Open fix-pass questions for AJ there: SSH source, deny vs reject, `nftables` removal (recommended, AJ to confirm).
- **Team:** `docs/agent-team.md` rev 5. The Brain is the main session; 9 agents in `.claude/agents/`; skill `cis-audit`.
- **Parked** (handoff § Parked): ableton_box (192.168.50.211) role and the Security Onion pattern; its OS; the `docs/hosts/` owner. Leave them unless AJ raises them.

## Don't
- Drift: section 5 only.
- Run sudo, handle passwords, or use placeholders in commands.
