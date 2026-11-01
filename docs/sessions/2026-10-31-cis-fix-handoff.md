# Johnny handoff → new session: CIS L1 fix pass (2026-10-31)

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 15 or later; step 10 holds every fail grouped by fix type, with the site-policy values). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (for Grok) → Outline.

## Task: fix the 115 CIS L1 fails, in batches, lowest lockout risk first
- **Source:** `docs/cis-26.04-l1-results.csv` (274 L1 rows: 136 pass, 115 fail, 23 N/A) and handoff step 10. Fails by section: 1 = 25, 2 = 11, 3 = 31, 4 = 3, 5 = 38, 6 = 6, 7 = 1. This pass **changes Johnny**, unlike the audit.
- **Expect several sessions.** One batch per step, with a re-audit after each. Don't try all 115 in one sitting.
- **Strict CIS** (AJ, 2026-10-31): "we play by the rules for now and we will loosen if we need later."

## Step 0: the fix gate (check first; no change on Johnny until it's met)
- **Gate:** a working console. Either the HDMI dummy is in and AMT KVM video is verified (handoff step 5), or a monitor and keyboard are at the closet. Rev 15 says step 5 is still open (HDMI dummy ordered). Ask AJ which applies; don't assume.
- Also, for every change: a **second SSH session open** to Johnny, and the LUKS passphrase at hand (in case a boot change drops to the passphrase prompt).
- **If the gate is not met:** do only the no-change prep below (Platform drafts files and scripts, Governance writes risk entries, Assurance writes acceptance checks). All of it stays in the repo; nothing goes to Johnny.

## Who does what (`docs/agent-team.md` §4–§6)
- **Platform** (`cis-remediation`) writes each fix: exact files, exact commands, a rollback for each, and a URL for any Ubuntu 26.04 claim. The skill exists only as a line in `docs/agent-team.md`, not yet as a file in `.claude/skills/`. Writing `.claude/skills/cis-remediation/SKILL.md` is a reasonable first job; Platform proposes it, AJ approves.
- **Assurance** reviews each batch's files and commands before anything runs (`independent-review`; nobody checks their own work) and sets the pass criteria (`acceptance-gates`).
- **Governance** writes risk-register entries for the lockout-risk batches **before** they run (handoff step 10, section 5) and re-audits each fixed rule afterwards with `cis-audit` (same scripts, same CSV method).
- **Detection** confirms capture still works on `eno1np0` after ufw, sysctl and IPv6 changes.
- **AJ** runs every sudo command in their own SSH session on Johnny. The Brain shows each command first, written out in full (no "…", no placeholders), and reads results back over SSH.

## Decisions AJ still owes (ask when the batch comes up, not all at once)
- **Section 4 (ufw):** SSH source (Brain rec 192.168.50.0/24 on `eno3`); deny vs reject (Brain rec deny); remove the `nftables` package with `ubuntu-standard` and keep the `nf_tables` kernel module (Brain + Grok rec).
- **1.6.2–1.6.4 banners:** login text for `/etc/issue`, `/etc/issue.net` and motd. The section 5 SSH banner is `Authorized use only. Activity is monitored.`; reusing it is an option, not a decision.
- **1.4.1 GRUB password:** the 26.04 method (with `--unrestricted` so the unattended boot still works) is unverified; Platform researches and cites before AJ decides.
- **1.3.1.1 `apparmor-utils`** and **6.3.1/6.3.2 `aide` + `aide-common`:** package installs. AIDE is approved once Governance vets it (license, maintainer, CVE history); `apparmor-utils` has no recorded approval. Also whether to `apt update` before installs.
- **3.2.7 module list:** Governance drafts, Detection confirms capture/XDP needs, AJ approves. Stays FAIL (manual) until then.
- **1.2.1.11 apt http mirrors:** verify HTTPS support on the mirrors first.
- **5.4.2.5 / classic sudo:** which `visudo` (sudo-rs or classic); whether classic `sudo` can be removed while sudo-rs stays (7.1.13 note).
- **CSV method for re-checks:** edit the row in place (Brain rec) or append a re-check row per rule. Decide before the first re-audit.
- Stays FAIL (manual) on purpose: **6.1.2.5** remote log host (parked ableton_box decision). Leave it unless AJ raises it.

## Suggested batch order (Platform may regroup; Assurance reviews each)
Details per rule are in handoff step 10. "Reboot" = needs a console reboot to prove it. The table covers 113 fails; the other 2 wait on decisions (3.2.7 module list, 6.1.2.5 remote log host). Batch counts: 1 = 10, 2 = 4, 3 = 4, 4 = 34, 5 = 9, 6 = 3, 7 = 9, 8 = 15, 9 = 24, 10 = 1.

| # | Batch | Rules | Lockout risk | Notes |
|---|---|---|---|---|
| 1 | File modes | 2.4.1.2–2.4.1.9, 1.6.6, 6.1.3.1 | none | cron dirs and crontab; `/etc/cron.allow` (2.4.1.9); `update-motd.d` scripts; `/var/log` files fixed at the writers (logrotate `create`), not a one-time chmod |
| 2 | Package removal | 2.1.13, 2.2.4, 2.2.6, 7.1.13 | low | `apt-mark manual` ubuntu-standard's other deps first, then remove `ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3` (plus `nftables` if AJ agrees). `apt-get -s` first, read every line; no `--autoremove` (it takes tcpdump, mtr-tiny, nano and more) |
| 3 | Logging | 6.1.1.1.5, 6.1.2.7, 6.3.1, 6.3.2 | none | journald drop-in, logrotate (weekly, rotate 13, maxage 90), AIDE install + init + daily 05:00 UTC timer |
| 4 | Kernel params and modules | 1.1.1.x, 3.2.1–3.2.6, 3.3.1.x, 1.5.4, 1.5.5, 1.5.9, 1.5.10, 1.5.7 | low, reboot | one `/etc/modprobe.d/` blocklist (keep `xfs`, `autofs4`, ufw's netfilter modules); sysctl drop-in sorting after `55-network-security.conf`; core dumps and apport; rebuild the initramfs if modprobe.d changes; prove TPM unlock on reboot |
| 5 | Mounts and apt | 1.1.2.1.4, 1.1.2.2.4, 1.2.1.11, 1.2.1.15, 1.3.1.1, 1.6.2–1.6.4, 1.6.12 | low, reboot | `noexec` on `/tmp` and `/dev/shm`; apt config; banners (AJ's text) |
| 6 | Firewall | 4.1.2, 4.1.3, 4.1.5, then 3.3.1.16/.17 | **high** | comment out `log_martians=0` in `/etc/ufw/sysctl.conf` → SSH allow rule → `ufw enable` → re-audit → Detection checks capture |
| 7 | IPv6 off | 3.1.1, 3.3.2.1–3.3.2.8 | **high**, reboot | the boot option may break `ssh.socket`'s `[::]:22` bind (untested); check `journalctl -k \| grep -c martian` afterwards |
| 8 | SSH and sudo | 5.1.x (11), 1.6.5, 5.2.6, 5.2.7, 5.4.2.5 | **high** | 1.6.5 is the same sshd `Banner` as 5.1.6; drop-in sorts before `50-cloud-init.conf`; `sshd -t` before reload; `visudo -c`; root shell already open |
| 9 | PAM and accounts | 5.3.x (20), 5.4.1.1, 5.4.1.5, 5.4.3.2, 5.4.3.3 | **high** | install libpam-pwquality + cracklib-runtime (approved); `pam-auth-update`; faillock locks key logins too for 15 min after 5 bad sudo passwords: keep a session open |
| 10 | GRUB password | 1.4.1 | **high**, reboot | only after AJ approves a cited method; prove unattended boot + TPM unlock; check PCR 7 against the baseline |

## Every change, every batch
1. Before writing a fix, Platform re-reads the live state over SSH (read-only): packages and files may have moved since the audit (2026-10-30 to 2026-11-01, plus unattended security upgrades).
2. Assurance reviews the batch. The Brain reads every command for anything outside the batch.
3. Brain shows AJ the exact commands; AJ runs them (sudo) with a second session open.
4. Governance re-audits the batch's rules with the section scripts in `docs/cis-local/`. **How re-check verdicts are recorded is open for AJ** (the `cis-audit` skill doesn't say). Brain rec: edit the existing row in place (result, evidence, date) by targeted line edits, never a CSV-library rewrite; git keeps the audit-time verdict. The Brain checks the diff (274 rows, 6 columns, no duplicate ids) and recounts the totals.
5. Every new or changed file under `/etc` gets a copy under `etc/` in the repo (same path), added to the handoff's Config changes table with its rollback, **in the same commit**.

## Session end (Brain)
Batch results and new totals into handoff step 10; Config changes table and SBOM for any package change; bump the handoff revision; add rows to a session CSV in `docs/sessions/`; banner this brief historical when the fix pass is done (or write the next batch's brief); commit; push only on AJ's word.

## State, one screen
- **Johnny:** Ubuntu Server 26.04.1, kernel 7.0.0-42, Secure Boot + TPM-unlocked LUKS (PCR 7), headless in the closet, unchanged since rev 7. SSH key-only; `sudo` is sudo-rs; `aj` is the only account with a password.
- **CIS L1 audit:** complete, 274/274: 136 pass, 115 fail, 23 N/A (rev 15). Level 2 – Server (+76) comes after the fix pass, once the log volume exists.
- **After the fix pass:** step 7 tool install (AJ: baseline before tools), then E810 capture config (step 11; see the IPv6 and rp_filter notes in step 10, section 3).
- **Parked** (handoff § Parked): ableton_box role and OS, `docs/hosts/` owner. Leave unless AJ raises them.

## Don't
- Change anything on Johnny before the gate is met, or run sudo, handle passwords, or use placeholders.
- Batch high-risk fixes together: one lockout-risk change at a time, re-audit, then the next.
- `pci=noaer`, disabling ACS Source Validation, snaps.
- Touch held packages (`shim-signed`, `secureboot-db`) or anything that changes PCR 7 without the held-package procedure (handoff § Known gaps).
