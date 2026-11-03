# CIS L1 fix pass, Batch 3: logging (journald rotation, logrotate) and AIDE

**Status:** DRAFT rev 4 (Platform, 2026-11-03). Group A has run on Johnny (2026-11-03 09:19–09:27 UTC). Group B's config edits have run (09:37–09:41 UTC, B0–B3). B5 is pending until the 2026-11-04 00:23 UTC logrotate timer. Group C is applied through C9 (2026-11-03 09:47–10:30 UTC). C8 and C9 run again after about 05:20 UTC on 2026-11-04. Governance's re-audits of 6.1.1.1.5 and 6.1.2.7 are still to do. Rev 4 (2026-11-03, Grok, after Claude's review of `44efe85`, approve with changes): C4 is `--add root mail 0755` (mode only; group stays `mail`). A1b sits after A2 and checks the `max 1.0G` line. Claude did not review C1–C10 beyond C4 and A1b. S1 (2026-11-03, Grok, after the rev 3 spot-check): assumption 9 now says 20 to 60 minutes. No command changed in that pass. Assurance asked for no re-review of S1. Spelling check (2026-11-03, Grok): `adeinit.still-running` matches the package script, so C3's `ls` stays. Rev 1 drafted Groups A and B (6.1.1.1.5, 6.1.2.7). Rev 2 added Group C (AIDE: 6.3.1, 6.3.2) after AJ's `sudo apt update` (~06:45 UTC) and Governance's vetting (`docs/findings/aide-vetting.md`, APPROVE WITH CONDITIONS). Assurance reviewed rev 2 and approved it with changes (`docs/findings/cis-batch-3-review.md`, F1-F12); rev 3 applies F1-F10 (F11 and F12 need no change beyond one line). **AJ's decisions (2026-11-03): accept R-AIDE-1 (option A), install resolute's 0.19.2-3 inside this batch with `--no-install-recommends` (no Postfix), use multiple hash functions, hold the timer until the database exists.** **AJ (2026-11-03), all recs:** Q1 keep `maxage 90`; Q2 run B2; Q3 accept the conffile residual; Q4 keep the recorded journal caps; Q5 run `journalctl --rotate`; Q7 statoverride `dotlockfile` to 0755, group `mail`; Q8 read `aide.log` by hand; Q9 `RandomizedDelaySec=0` when C6 is under 50 minutes, and stop before C7 at 50 or more; Q10 run C6 before C7. Group A is applied. Group B's config edits are applied (B0–B3). B5 is pending until the 2026-11-04 00:23 UTC timer. Group C's apply is done through C9. Claude reviews the group end. C8 and C9 run again after about 05:20 UTC on 2026-11-04. Grok runs the read-only SSH checks. AJ runs every `sudo` block, and each block is shown first. Stop on any error.

### Corrections from the apply
| Item | Status |
|---|---|
| `fold: fold-error-failed-to-write: Broken pipe` | Benign and recurring. Same cause as the mail WARN. The script pipes `fold \| send_mail` (line 754). With no mailer, `send_mail` returns without reading (line 147). Seen 2026-11-03 10:22:29 UTC. The unit still finished. |
| Entry count | Unreconciled, not a stop. Init `111497`. C6 total `111499`, added `1`, removed `0`. `111497 + 1 = 111498`. The added section lists only `/run/systemd/journal/streams/10:47893`. |
| C1 and C3 expected text | Applied below. `Created symlink` did print at install. The service and buildcache were not started. `0` failed units is a possible result. |
| `reset-failed` says `not loaded` | Applied below. Units that have never been started return that. Not a stop. The following `start` is the check. |
| `H` hash wording | Applied below. `H` is seven named hashes, not every compiled-in hash. |
| Assumption 9 | Applied below. Init measured 3m 13s. C6 measured 3m 8s. |

### Change log (rev 3 to rev 4, Claude's review of `44efe85`)
| # | Sev | Change in this doc |
|---|---|---|
| C4 | Medium | `--add root mail 0755`, not `root root`. `--add` sets user, group, and mode together, and `--remove` does not put the old mode back, so `chmod 2755` after a `root root` override would leave `2755 root:root`. Expected output is `755 root:mail` and `root mail 755`. |
| A1b | Low | The block is below A2. It adds `journalctl -u systemd-journald -n 6 --no-pager` and `journalctl --disk-usage` so the `max 1.0G` line is checked after the rotate. The SIGUSR2 claim is dropped. The new file's `640` mode is marked **[Assumption]**. |

### Change log (rev 2 to rev 3, Assurance findings)
| # | Sev | Change in this doc |
|---|---|---|
| F1 | Medium | The postinst starts the service and buildcache units several times (three `deb-systemd-invoke start` blocks), so the start limits can refuse repeats. C3 now expects 1 or 2 failed units (`dailyaidecheck.service`, possibly `dailyaidecheck-buildcache.service`). New C3a: `reset-failed`, then `start dailyaidecheck-buildcache.service`, then check `/var/lib/aide/10_aide_rootrules_cache` **before C5**. C6 resets both units. The claim "the postinst hides the failed first check" is replaced by the real description. |
| F2 | Medium | New "If C1 fails" branch after C1 (stop, read-only `dpkg --audit`, no rollback, no C2-C7). `dpkg --audit; echo rc=$?` is now the first line of C3 (and GS5). C10 points to that branch for a half-done install. |
| F3 | Medium | C1 no longer expects a "Created symlink" line (the postinst sends it to `/dev/null`). Added: if asked `Initialize AIDE database?`, answer **No**. C3 adds an `aideinit` process and `adeinit.still-running` check. |
| F4 | Low | B3 line 2 uses `grep -nP '^\trotate '` and expects exactly `rsyslog:8:` and `ufw:3:`. |
| F5 | Low | C5: a non-empty `aideinit.errors` is no longer an automatic stop (the Brain judges it); the return-code line is the gate; failure signs and the two re-run prompts are described; time stated as 20-60 minutes. |
| F6 | Low | C10 also removes `/var/lib/systemd/timers/stamp-dailyaidecheck.timer`; notes the `rm -r` of the drop-in directory errors if C7 never ran; says the simulation must show no `Remv` of anything else. |
| F7 | Low | C3: `stat` of the three directories works without sudo and prints `700 _aide:root` (two of them); only listing needs sudo. |
| F8 | Low | First `maxage` deletion date corrected from 2027-01-27 to **2027-02-01** (monthly rotation; whole days strictly greater than 90). |
| F9 | Low | C6 duration is a stated gate for C7 (under 50 minutes keeps 05:00; over, the Brain asks AJ). `AccuracySec` (1 minute) noted in C7 and Q9. C9 timing is the C6 duration plus 15 minutes, or 06:30 UTC at the latest. |
| F10 | Low | C9 states the 6.1.3.1 expected output and adds the `cis-5.4-root.sh` re-run for `_aide`. |
| F11 | Info | One line added to the operating notes: an `aide-common` upgrade restarts `dailyaidecheck.service`, which for a oneshot means "run a check now". |

### Change log (rev 1 to rev 2, kept for the record)
| # | Change in this doc |
|---|---|
| 1 | Header, Rules, Risk and Order lines now cover 6.3.1 and 6.3.2. |
| 2 | Group C written in full: C0 pre-check, C1 install, C2 timer hold, C3 post-install checks, C4 `dotlockfile` SGID, C5 database init, C6 first manual check, C7 05:00 UTC drop-in and enable, C8 CIS 6.3.1/6.3.2 verification, C9 regression checks, C10 rollback, SBOM rows and operating notes. |
| 3 | Maintainer scripts and triggers of all four packages re-read by Platform from the `.deb` files (sha256 matched the archive hashes on Johnny). Two points beyond Governance's note: `liblockfile1` does have a triggers file (`activate-noawait ldconfig`, harmless), and `liblockfile-bin` installs a **new setgid binary** (`/usr/bin/dotlockfile`, 2755 root:mail), which changes the 7.1.13 count (C4). |
| 4 | Governance's multi-hash condition: the stock `/etc/aide/aide.conf` already sets `Checksums = H` (all compiled-in, non-deprecated hashes), so no rule override is needed (C5). |
| 5 | The old Group C open question (Q6, run `apt update`) is answered and removed. Open questions renumbered: Q1-Q5 unchanged (Groups A/B, still unanswered), Q6 answered (R-AIDE-1), Q7-Q10 new. |

**Rules (4):** 6.1.1.1.5 journald log file rotation, 6.1.2.7 logrotate configured, 6.3.1 AIDE installed, 6.3.2 filesystem integrity regularly checked.

**Benchmark:** CIS Ubuntu Linux 26.04 LTS v1.0.0 (`docs/CIS_Ubuntu_Linux_26.04_LTS_Benchmark_v1.0.0.pdf`, local only). Page numbers are printed page numbers. CIS text is licensed, so this doc quotes only short command or setting lines and summarizes the rest.

**Risk:** none for access or boot. **No step touches the initramfs, dracut, PCR 7 or Secure Boot, SSH, PAM, sudo, GRUB or any held package, and no reboot is needed.** Groups A and B edit files and reload journald (see their text). Group C installs 4 packages; their maintainer scripts and triggers were read and contain no `update-initramfs`, dracut, GRUB or boot-path call (C3 proves it with the initrd mtime and size). Group C adds one system account (`_aide`, nologin), a heavy one-off disk read (the database init), a daily read of the filesystem at 05:00 UTC, and one residual security risk: **AIDE 0.19.2-3 has two open upstream detection-bypass advisories (R-AIDE-1, accepted by AJ).** The null-byte hash one (GHSA-6wc9-4w69-5jc5) is mitigated here by hashing with several functions. **The invalid-UTF-8 file-name one (GHSA-wq25-fm54-5q3q) stays open, with no workaround, until Ubuntu ships aide 0.19.5 for 26.04;** AIDE can silently miss a file whose name is not valid UTF-8. Governance keeps the vuln-intake watch for 0.19.5 in resolute-updates. Visible effects of Groups A/B are unchanged from rev 1 (journal capped at 1G; `maxage 90` deletes rotated logs older than 90 days at their next rotation).

**Order AJ runs them:** Group A (journald), then Group B (logrotate), then Group C (AIDE). Each block has commands, verification (read-only) and rollback. Grok runs the read-only checks over SSH. AJ runs every `sudo` block, shown first, in their own SSH session with a second session open (fix gate met, handoff rev 16). Claude reviews at the end of each group and at the C6 gate. Stop on any error.

---

## Live state read (read-only, `ssh aj@192.168.50.152`, no sudo)

Read 2026-11-03 06:40–06:45 UTC on Johnny's clock (Etc/UTC). Host `johnny`, kernel 7.0.0-42-generic, booted 06:17 UTC. Raw output was read in the session and not saved.

**Compared with the 2026-10-31 audit and Batch 1:**
- journald is unchanged since the audit: `/etc/systemd/journald.conf` is the stock all-commented file, **`/etc/systemd/journald.conf.d/` does not exist**, and the only drop-in is the vendor `/usr/lib/systemd/journald.conf.d/syslog.conf` (`ForwardToSyslog=yes`). Effective config (`systemd-analyze cat-config systemd/journald.conf`): stock plus that one line. systemd 259.9-0ubuntu0.1.
- Journal: `journalctl --disk-usage` = **133.5M** in `/var/log/journal/<machine-id>/` (5 files: `system.journal` 16M, `user-1000.journal` 8M, three archived). Oldest entry 2026-10-29 02:43 UTC, so the journal grows about 26 MB/day (133.5M over 5.2 days; a rough figure that includes boot noise). Filesystem `/` is 460G with 440G free, so the 1G cap is the binding limit, not free space. `/var/log/journal` and the machine-id directory are 2755 root:systemd-journal; `system.journal` is 640 root:systemd-journal (it also has an ACL, `+`).
- logrotate 3.22.0-1build1, `logrotate.timer` enabled (last run 2026-11-03 00:28 UTC, next **2026-11-04 00:23 UTC**). `/etc/logrotate.conf` is stock: `weekly` (line 6), `su root adm` (10), `rotate 4` (13, comment on line 12 says "keep 4 weeks worth of backlogs"), `create`, `include /etc/logrotate.d`. No `maxage` anywhere. `dpkg --verify logrotate` is clean for `logrotate.conf`.
- **Batch 1 conffile edits are in place (the `root adm` variant, D1-adm):** `/etc/logrotate.d/alternatives` and `dpkg` read `create 640 root adm`; `ubuntu-pro-client` reads `create 0640 root adm`. `dpkg --verify` shows exactly the expected `??5?????? c` lines for those three and `/etc/sysstat/sysstat`. Batch 1 log modes look as intended: `/var/log/{alternatives,dpkg}.log*` 640 root:adm, `ubuntu-advantage-apt-hook.log` 640 root:adm, `/var/log/unattended-upgrades/*` 640 root:adm, `/var/log/sysstat/*` 640 root:root.
- Per-package stanzas that **override** the global defaults (this matters, see Open Q1 and Q2): `alternatives`, `dpkg`, `apt`, `dracut-core` are `monthly rotate 12`; `ubuntu-pro-client`, `unattended-upgrades`, `cloud-init-base` are `rotate 6`; `rsyslog` (syslog, mail, kern, auth, user, cron logs) and `ufw` are `weekly rotate 4`; `apport`, `bootlog` are `daily rotate 7`; `btmp`, `wtmp` are `monthly rotate 1`. Only `chrony` has no frequency or count, so it inherits the global ones (`weekly`, and `rotate 4` today).
- Rotated files now: nothing older than 90 days except the empty `/var/log/btmp.1` (2026-08-26, 0 bytes). Johnny's earliest log content is from 2026-08-26 and every rotated content file is from 2026-10-29 or later, so `maxage 90` deletes nothing on its first run. The oldest content file, `dpkg.log.1` (mtime 2026-10-29 21:12), is 95 days old at the 2027-02-01 monthly rotation (only 64 days old at 2027-01-01) (logrotate compares the rotated file's mtime; `logrotate.c` 3.22.0 lines 2087 and 1971-1974).
- rsyslog 8.2512.0-1ubuntu4.2 is active, `$FileCreateMode 0640` (`/etc/rsyslog.conf` line 39), `imuxsock` (line 13). `systemd-journald.service` is `Type=notify-reload` with `FileDescriptorStorePreserve=yes`; `syslog.socket` listens on `/run/systemd/journal/syslog` and is a separate socket unit.
- `unattended-upgrades.log` has 0 "conffile prompt" lines today (GR3 clean).

---

## Group A: 6.1.1.1.5, journald log file rotation

### Live state
See above: no drop-in, nothing set for any of the five parameters (all `#`-commented in `journald.conf`).

### CIS remediation (pp. 774-775; quoted setting lines)
Audit (p. 774): `# grep -Prsi -- '\b(SystemMaxUse|SystemKeepFree|RuntimeMaxUse|RuntimeKeepFree|MaxFileSec)=' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/` and "ensure logs are rotated according to site policy". Remediation example, in `[Journal]`: `SystemMaxUse=1G`, `SystemKeepFree=500M`, `RuntimeMaxUse=200M`, `RuntimeKeepFree=50M`, `MaxFileSec=1month`; then `# systemctl reload-or-restart systemd-journald`. CIS notes that a later file or a later line overrides an earlier one.

**Site policy (AJ, 2026-10-31, "accept all recs"; Grok checked; handoff step 10 section 6):** the five CIS example values above, unchanged. The rule is Manual; with these set it verifies as PASS.

What the values mean (journald.conf(5), systemd 259.9-0ubuntu0.1, https://manpages.ubuntu.com/manpages/resolute/en/man5/journald.conf.5.html): journald "will respect both limits and use the smaller of the two values" for `SystemMaxUse` and `SystemKeepFree`; the `Runtime` options apply to the volatile store in `/run`; `MaxFileSec` is "the maximum time to store entries in a single journal file before rotating to the next one"; `SystemMaxFileSize` defaults to one eighth of the max-use value, capped at 128M. On Johnny: system journal capped at min(1G, free minus 500M) = 1G; runtime journal (`/run/log/journal`, now 8M, max 621.2M) capped at 200M; a new file at least monthly. Drop-in files are read in filename order and the last one wins for a single-value option (same page).

### A0. Baseline (read-only, no sudo)
```
journalctl --disk-usage
stat -c '%a %U:%G %n' /var/log/journal/*/*.journal
ls -d /etc/systemd/journald.conf.d
```
Expected: line 1 `Archived and active journals take up 133.5M…` (a bit more by the time AJ runs it); line 2 lists 640 root:systemd-journal for every file; line 3 `ls: cannot access '/etc/systemd/journald.conf.d': No such file or directory` (it does not exist yet).

Also take the mode snapshot that Group B compares against (AJ's own home, a plain text file):
```
sudo find -L /var/log -type f -perm /0137 -printf '%m %u:%g %p\n' | sort > ~/batch3-modes-before.txt; wc -l ~/batch3-modes-before.txt
```
Expected: the CIS-allowed leftovers from Batch 1 D3 line 6 (`README`, `apt/eipp.log.xz`, `apt/history.log*`, `btmp*`, `lastlog`, `wtmp`). Any other line is a Batch 1 regression: stop and tell the Brain.

### A1. Commands
```
sudo install -d -m 0755 -o root -g root /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/60-rotation.conf <<'EOF'
# Johnny: CIS 6.1.1.1.5 journald log file rotation (site policy, AJ 2026-10-31)
[Journal]
SystemMaxUse=1G
SystemKeepFree=500M
RuntimeMaxUse=200M
RuntimeKeepFree=50M
MaxFileSec=1month
EOF
sudo chown root:root /etc/systemd/journald.conf.d/60-rotation.conf
sudo chmod 0644 /etc/systemd/journald.conf.d/60-rotation.conf
sudo systemd-analyze cat-config systemd/journald.conf --no-pager
sudo systemctl reload-or-restart systemd-journald
```
The `60-` prefix sorts after the vendor file, which sets only `ForwardToSyslog`, so there is no conflict. The new directory and file belong to no package, so there is no dpkg override or conffile prompt. `systemd-analyze cat-config` prints the merged config so AJ can read it before the reload; it changes nothing. `--no-pager` is required. Without it, `systemd-analyze` opens a pager and the reload line does not run (seen on Johnny 2026-11-03 09:19 UTC; the reload then ran on its own at 09:22:46 UTC).

**What the reload does.** `systemd-journald.service` is `Type=notify-reload`, so `reload-or-restart` sends the reload signal, and per systemd-journald.service(8) journald on SIGHUP "will reload its configuration values and update the kernel log buffer and journals" (https://manpages.ubuntu.com/manpages/resolute/en/man8/systemd-journald.service.8.html). The service is not stopped. Even a full restart would keep the log sockets (`systemd-journald.socket`, `syslog.socket` are separate units) and its stored file descriptors (`FileDescriptorStorePreserve=yes`). Nothing else reads `journald.conf`.

### A2. Verification (read-only, no sudo)
```
grep -Prsi -- '\b(SystemMaxUse|SystemKeepFree|RuntimeMaxUse|RuntimeKeepFree|MaxFileSec)=' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/
stat -c '%a %U:%G %n' /etc/systemd/journald.conf.d /etc/systemd/journald.conf.d/60-rotation.conf
systemctl is-active systemd-journald rsyslog
journalctl -u systemd-journald -n 6 --no-pager
journalctl --disk-usage
stat -c '%a %U:%G %n' /var/log/journal/*/*.journal
logger -t johnny-batch3 "journald reload check"; sleep 2; grep -c 'johnny-batch3' /var/log/syslog
```
Expected:
- Line 1: 10 lines. Five are the inert commented defaults from `/etc/systemd/journald.conf` (for example `/etc/systemd/journald.conf:#SystemMaxUse=`); the CIS regex matches them too. The other five are the drop-in: `/etc/systemd/journald.conf.d/60-rotation.conf:SystemMaxUse=1G`, `…:SystemKeepFree=500M`, `…:RuntimeMaxUse=200M`, `…:RuntimeKeepFree=50M`, `…:MaxFileSec=1month`.
- Line 2: `755 root:root /etc/systemd/journald.conf.d` and `644 root:root /etc/systemd/journald.conf.d/60-rotation.conf`.
- Line 3: two lines, `active` and `active`.
- Line 4: no `Failed`, no `error`. **[Assumption]** A reload may log a line containing `max 1.0G`. If it does not, that is not a stop in A2. A1b, the next block, is where that line is checked.
- Line 5: same size as A0 (a small increase); nothing is vacuumed because 133.5M is far under 1G.
- Line 6: every journal file still `640 root:systemd-journal`. These are the files that existed before the rotate (Batch 1 6.1.3.1). The new file's mode is A1b.
- Line 7: `1` or more: the test line went through journald, the syslog forward (`ForwardToSyslog=yes`) and rsyslog into `/var/log/syslog`. This proves the reload did not break the rsyslog path (CIS 6.1.2.x depends on it).

Batch 1 check (GR1/GR2 side effects of journald): the reload touches only `/var/log/journal`. It does not write `/var/log/sysstat`, `dpkg.log*`, `alternatives.log*` or `unattended-upgrades/`, so GR1 and GR2 are unaffected. The A2 line 6 above is the journal-side equivalent.

### A1b. Rotate once (decided, Q5)
Run this block after A2. `journalctl --rotate` asks journald to archive the active journal files and open new empty ones. It does not take a vacuum size, so the command itself is not a delete (journalctl(1), systemd 259: https://manpages.ubuntu.com/manpages/resolute/en/man1/journalctl.1.html).
```
sudo journalctl --rotate
journalctl -u systemd-journald -n 6 --no-pager
journalctl --disk-usage
stat -c '%a %U:%G %n' /var/log/journal/*/*.journal
```
Expected:
- Line 1: no error. The command returns when the rotation has finished.
- Line 2: one of the six lines contains `max 1.0G` or `max 1G`. That is the system journal under `SystemMaxUse=1G`. A line containing `max 200` would be the runtime journal (`RuntimeMaxUse=200M`) and does not satisfy this check. Observed 2026-11-03 09:27:20 UTC: `System Journal (/var/log/journal/a8e4c2a812a640ff8ca95580b7867082) is 140.2M, max 1G, 883.7M free.` If a later run has neither `max 1.0G` nor `max 1G`, stop and show the six lines to the Brain. A2's grep of the drop-in is not a substitute.
- Line 3: `Archived and active journals take up …`, about the same size as A2 line 5. A small increase is fine. 133.5M is far under 1G, so nothing should be removed. A large drop means stop.
- Line 4: every file, including the new active `system.journal`, is `640 root:systemd-journal`. Observed 2026-11-03 09:27:20 UTC: 7 files, all that mode, including the new active `system.journal` and `user-1000.journal`. The 259 create path was not read.

### A3. Rollback
```
sudo rm /etc/systemd/journald.conf.d/60-rotation.conf
sudo rmdir /etc/systemd/journald.conf.d
sudo systemctl reload-or-restart systemd-journald
```
Expected after: `ls /etc/systemd/journald.conf.d` says "No such file or directory"; effective config back to stock plus `ForwardToSyslog=yes`. Journal contents are not changed by either direction (journald only vacuums when over a limit).

---

## Group B: 6.1.2.7, logrotate configured

### CIS remediation (pp. 797-798; summarized)
The rule is Manual: "Review `/etc/logrotate.conf` and `/etc/logrotate.d/*` and verify logs are rotated according to site policy"; remediation is "Edit `/etc/logrotate.conf` and `/etc/logrotate.d/*` to ensure logs are rotated according to site policy". The description names `/etc/logrotate.d/rsyslog`. Additional Information (p. 797): without `maxage`, a failed logrotate can leave rotated files undeleted; set `maxage` to more than the longest any log should live.

**Site policy (AJ, 2026-10-31; Grok checked):** `weekly`, `rotate 13`, `maxage 90` (about 90 days; Grok: `maxage 365` with `rotate 13` would never bind).

### What this means in practice (read before choosing)
logrotate(8) 3.22.0-1build1 (https://manpages.ubuntu.com/manpages/resolute/en/man8/logrotate.8.html): "Global options do not affect preceding include directives", so options placed before `include /etc/logrotate.d` become the defaults that every stanza inherits unless it sets its own. Per stanza, its own `rotate`/frequency wins. Consequences on Johnny:
1. **`weekly` is already global**; no edit needed.
2. **Global `rotate 13` only reaches `chrony`** (nothing else leaves `rotate` unset). `rsyslog` and `ufw` set `rotate 4` themselves, so syslog, auth.log, kern.log and ufw.log would still keep **4 weeks**, not 13. To make the site policy real for the logs that matter, those two stanzas must be edited too (option B2 below). logrotate allows only one stanza per log path, so a drop-in cannot override them.
3. **Global `maxage 90` reaches every stanza** (none sets its own). The man page says: "Remove rotated logs older than <count> days" and "the age is only checked if the logfile is to be rotated". So it also caps the stanzas that keep more: `alternatives`, `dpkg`, `apt`, `dracut-core` (12 monthly files = a year today) and `ubuntu-pro-client`, `unattended-upgrades`, `cloud-init-base` (6 months) all drop to about 90 days. Nothing is deleted on apply (Live state), and the first possible deletion is 2027-02-01 (the first monthly rotation after the file passes 90 whole days) (`dpkg.log.1`). The empty `/var/log/btmp.1` goes at the next btmp rotation. This is a retention cut for package history; it follows AJ's recorded value, so it is Open Q1, not a Platform decision.

### B0. Baseline before B1 (read-only; Batch 1 F8 method)
```
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c '^error'
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -ciE '^error|warning'
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c 'old logs are removed'
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c '(4 rotations)'
```
Write all four numbers down. `-d` is debug: "no changes are made to the logs and the logrotate state file is not updated" (logrotate(8)). Expected: line 1 `0`; line 3 about 17 (one per stanza; read-only as `aj` without sudo it showed 17 patterns); line 4 `3` (chrony, rsyslog, ufw). Line 2 may be above 0 from a warning that predates the batch, which is not a regression. As `aj` without sudo the error count is 14 (permission-denied globs), which is why this uses sudo.

### B1. Commands, global defaults (always; the minimum for the rule)
`/etc/logrotate.conf` is a conffile of `logrotate` (md5 `9290a646…`). Patterns checked on Johnny with `cat -A`: line 12 `# keep 4 weeks worth of backlogs$`, line 13 `rotate 4$`.
```
sudo sed -i -e 's/^rotate 4$/rotate 13\nmaxage 90/' -e 's/^# keep 4 weeks worth of backlogs$/# keep 13 weeks worth of backlogs/' /etc/logrotate.conf
```
Result: lines 12-14 read `# keep 13 weeks worth of backlogs`, `rotate 13`, `maxage 90`. GNU `sed -i` keeps mode 0644 and owner.

### B2. Commands, package stanzas (decided, Q2: run)
Without this, syslog, auth.log, kern.log and ufw.log stay at 4 weeks. `/etc/logrotate.d/rsyslog` (package `rsyslog`, md5 `3f26282a…`) and `/etc/logrotate.d/ufw` (package `ufw`, md5 `969308e0…`) are conffiles. Pattern checked with `cat -A`: `^Irotate 4$` (a tab) in both.
```
sudo sed -i 's/^\trotate 4$/\trotate 13/' /etc/logrotate.d/rsyslog /etc/logrotate.d/ufw
```
Disk cost: syslog.1 is about 21 MB and kern.log.1 about 18 MB per week uncompressed; compressed 13 weeks is well under 1 GB on a volume with 440G free. `ufw.log` does not exist yet (ufw rules are Batch 4).

### B3. Verification (read-only; `sudo` lines read only)
```
grep -nE '^(weekly|su |rotate|maxage|create)|keep' /etc/logrotate.conf
grep -nP '^\trotate ' /etc/logrotate.d/rsyslog /etc/logrotate.d/ufw
sudo dpkg --verify logrotate rsyslog ufw dpkg ubuntu-pro-client sysstat
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c '^error'
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -ciE '^error|warning'
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c 'old logs are removed after 90 days'
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c '(13 rotations)'
sudo find -L /var/log -type f -perm /0137 -printf '%m %u:%g %p\n' | sort | diff - ~/batch3-modes-before.txt && echo MODES-UNCHANGED
```
Expected (B1 + B2):
- Line 1: `6:weekly`, `10:su root adm`, `12:# keep 13 weeks worth of backlogs`, `13:rotate 13`, `14:maxage 90`, and the `create` line (now line 17).
- Line 2: exactly two lines, `/etc/logrotate.d/rsyslog:8:` and `/etc/logrotate.d/ufw:3:`, each followed by a tab and `rotate 13` (the pattern excludes the `postrotate` and `rsyslog-rotate` lines, which also contain "rotate").
- Line 3 (runs as root so the cron.daily directory mode adds no `Permission denied` line): exactly these lines, any order: `??5?????? c /etc/logrotate.conf`, `??5?????? c /etc/logrotate.d/rsyslog`, `??5?????? c /etc/logrotate.d/ufw` (B2 only), plus the four from Batch 1: `/etc/logrotate.d/alternatives`, `/etc/logrotate.d/dpkg`, `/etc/logrotate.d/ubuntu-pro-client`, `/etc/sysstat/sysstat`. Seven lines with B2, five without. Each is a conffile changed on purpose.
- Lines 4-5: same numbers as B0 (line 4 `0`).
- Line 6: equals the B0 line 3 count (every stanza now reports "old logs are removed after 90 days"; source: `logrotate.c` 3.22.0 lines 2425-2428 print " after %d days"). **[Assumption]** the exact debug wording follows that source and was not run on Johnny.
- Line 7: `3` with B2 (chrony, rsyslog, ufw), `1` without B2 (chrony only).
- Line 8: `MODES-UNCHANGED`. The rotation config edits cannot change any file mode; this proves it against the A0 snapshot.

### B4. Side effects on Batch 1 (checked)
- **Log modes (GR1/GR2).** B1 and B2 do not touch any `create` line, so the Batch 1 `create 640 root adm` / `0640 root adm` rules still decide the mode of rotated `dpkg`, `alternatives` and `ubuntu-advantage*` logs. `unattended-upgrades` has no `create` line and uses the global bare `create`, which copies the old file's mode and owner (still 640 root:adm); B1 edits only `rotate` and `maxage`, not `create`. The rsyslog logs are recreated 640 by rsyslog (`$FileCreateMode 0640`) after logrotate's `rsyslog-rotate` postrotate. Raising `rotate` from 4 to 13 renames more old files but does not change their modes. `maxage` only deletes. **No rotation is due until the first real run** (below), so nothing changes at apply time.
- **First real run.** `logrotate.timer` fires next at **2026-11-04 00:23 UTC**. Due then: `apport.log`, `bootlog` (daily) if non-empty; weekly logs (syslog family) next rotate on Sunday **2026-11-08**; monthly logs (dpkg, alternatives, apt, uu, pro-client) on **2026-12-01**. `maxage 90` would delete `btmp.1` (0 bytes) at the btmp rotation (2026-12-01).
- **Batch 1 recurring checks stay valid.** GR1 (`find /var/log/sysstat -type f -perm /0137`) is unaffected: sysstat rotates itself (`sysstat-rotate.timer`), with no logrotate file. GR2 still applies after 2026-12-01.

### B5. Proof after the first real runs (read-only, no sudo; add to the recurring checks)
After 00:30 UTC 2026-11-04:
```
journalctl -u logrotate.service --since "2026-11-04 00:00" --no-pager | tail -5
systemctl is-failed logrotate.service
```
Expected: a `Finished logrotate.service - Rotate log files.` line (the unit's description is "Rotate log files"; **[Assumption]** exact text), no `error:` lines, and `systemctl is-failed` prints `inactive` (not `failed`). It is a oneshot, so `inactive` is the healthy state.

After Sunday 2026-11-08 00:30 UTC:
```
ls -l /var/log/syslog* /var/log/auth.log* /var/log/kern.log*
```
Expected: every file `-rw-r-----` `syslog adm`, and the newest rotated copy appears as `syslog.1` (older ones `.2.gz`, `.3.gz`).

After 2026-12-01 (together with GR2): `sudo find /var/log/dpkg.log* /var/log/alternatives.log* /var/log/unattended-upgrades -type f -perm /0137` prints nothing.

### B6. Rollback
Global (B1):
```
sudo sed -i -e '/^maxage 90$/d' -e 's/^rotate 13$/rotate 4/' -e 's/^# keep 13 weeks worth of backlogs$/# keep 4 weeks worth of backlogs/' /etc/logrotate.conf
sudo dpkg --verify logrotate
```
Package stanzas (B2, only if applied):
```
sudo sed -i 's/^\trotate 13$/\trotate 4/' /etc/logrotate.d/rsyslog /etc/logrotate.d/ufw
sudo dpkg --verify rsyslog ufw
```
Each `dpkg --verify` printing nothing means the conffile matches the package md5 again. Rotated files that logrotate keeps because of `rotate 13` are never deleted by a rollback; the lower `rotate 4` removes the surplus at the next rotation of that log.

### Residual (conffile prompts; accepted, Q3)
`/etc/logrotate.conf` (and, with B2, `rsyslog` and `ufw`) are now locally modified conffiles. If a later `logrotate`, `rsyslog` or `ufw` update ships a changed version of one of them, unattended-upgrades **skips that package** and logs `Package … has conffile prompt and needs to be upgraded manually` (same mechanism as Batch 1; `/usr/bin/unattended-upgrade` 2.12ubuntu9; https://manpages.ubuntu.com/manpages/resolute/en/man8/unattended-upgrade.8.html). The skip is silent now that the login notice is gone. **GR3 covers it**, and it needs no sudo: `grep -h 'conffile prompt' /var/log/unattended-upgrades/unattended-upgrades.log` works for `aj` because the log is 640 root:adm and `aj` is in adm. A skipped `rsyslog` update is the one to watch (it is the log pipeline). The `journald.conf.d` drop-in is not a conffile and has no such risk.

---

## Group C: 6.3.1 AIDE installed, 6.3.2 integrity checked regularly

### Live state (read-only, 2026-11-03 06:45 UTC, after AJ's `apt update`)
- `aide`, `aide-common`, `liblockfile1`, `liblockfile-bin`: not installed. Candidates (all `resolute` release pocket, component main): `aide` 0.19.2-3, `aide-common` 0.19.2-3, `liblockfile1` 1.17-2build2, `liblockfile-bin` 1.17-2build2. No `-updates` or `-security` version exists for aide. `postfix`, `bsd-mailx`: not installed (`bsd-mailx` shows as `un`); no `/usr/sbin/sendmail`; no `mail`, `s-nail`.
- `apt-get -s install --no-install-recommends aide aide-common` on Johnny (06:45 UTC) gives exactly: additional packages `liblockfile-bin liblockfile1`; suggested `figlet`; recommended `bsd-mailx | mailx | s-nail` (left uninstalled); **4 newly installed, 0 upgraded, 0 to remove**; `Inst`/`Conf` for aide, liblockfile-bin, liblockfile1, aide-common. It matches Governance's section 6b line for line. Without `--no-install-recommends` it adds `postfix`, `bsd-mailx`, `libnsl2`, `ssl-cert` (8 packages): never use that form.
- Disk: `/` is XFS, 460G with 19.8G used, about 110 000 inodes used (of 241 million); `/boot` ext4 1.9G; `/boot/efi` vfat 1G; `/tmp` and `/run` are tmpfs. `/boot/initrd.img-7.0.0-42-generic`: 42 618 411 bytes, mtime 2026-11-03 06:13:32 UTC (the Batch 2 rebuild). `systemctl --failed`: none. `/etc/shells` has no `nologin` entry.
- Timers now: no `dailyaidecheck*` unit. Johnny's clock is `Etc/UTC`. Existing timers near 05:00 UTC: none; `apt-daily-upgrade.timer` fires about 06:05 UTC (randomized).
- SUID/SGID now: 13 SUID and 6 SGID (Batch 2 re-audit), none from the AIDE packages.

### Maintainer scripts and triggers (Platform re-read from the `.deb` files; the four `sha256` values match the archive hashes `apt-cache show` prints on Johnny)
| Package | Scripts and triggers | Boot or initramfs effect |
|---|---|---|
| `aide` 0.19.2-3 | none (`control`, `md5sums` only), no triggers | none |
| `liblockfile-bin` 1.17-2build2 | none, no triggers. Ships `/usr/bin/dotlockfile`, **mode 2755 root:mail** (setgid) | none |
| `liblockfile1` 1.17-2build2 | no scripts; `triggers` = `activate-noawait ldconfig` | none (ldconfig only) |
| `aide-common` 0.19.2-3 | `preinst` (`dpkg-maintscript-helper mv_conffile` for an old cron name), `postinst`, `prerm`, `postrm`, `config`, `templates`; no `triggers` | none: no `update-initramfs`, dracut, GRUB, PAM, sudo or SSH call (a grep of every script and trigger for `initramfs|grub|dracut` finds nothing; the only `update-` hit is `deb-systemd-helper update-state`) |

This confirms Governance's finding (no initramfs or boot hook), with the two additions in the change log. `aide-common` postinst on a fresh install: ucf-merges `/etc/aide/aide.conf`, `/etc/aide/aide.conf.d/*`, `/etc/aide/aide.settings.d/*`, `/etc/default/aide` and `/etc/cron.daily/dailyaidecheck`; runs `systemd-sysusers` (creates user and group `_aide`, home `/var/lib/aide`, shell `/usr/sbin/nologin`) and `systemd-tmpfiles` (`/run/aide` 0700 `_aide:root`, `/var/log/aide` 2755 `_aide:adm`, `/var/lib/aide` 0700 `_aide:root`); **enables `dailyaidecheck.timer`; then `deb-systemd-invoke start dailyaidecheck.service dailyaidecheck.timer` and `dailyaidecheck-buildcache.service`**. The `aide/aideinit` debconf question defaults to `false`, so no database is built at install. `/etc/cron.daily/dailyaidecheck` exits at once when systemd is running, so cron does not double-run the check. `/etc/default/aide` sets `COMMAND=update`, `COPYNEWDB=no`.

### CIS remediation (pp. 971-974; quoted command lines only)
- **6.3.1 (pp. 971-972):** audit `dpkg-query -s aide &>/dev/null && echo "aide is installed"` and the same for `aide-common`. Remediation `# apt install aide aide-common`, then `# aideinit` and `# mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db`. **Deviation: `--no-install-recommends`** (Governance condition 1; the audit checks only that both packages are installed, so it still passes). Vetting file cites pp. 971-972 for this rule as "972-973" (PDF index); the printed pages are 971-972.
- **6.3.2 (pp. 973-974):** audit `systemctl list-unit-files | awk '$1~/^dailyaidecheck\.(timer|service)$/{print $1 "\t" $2}'`; `dailyaidecheck.timer` must be `enabled` and `dailyaidecheck.service` `static` or `enabled`; then `systemctl is-active dailyaidecheck.timer` must print `active`. Remediation `# systemctl unmask dailyaidecheck.timer dailyaidecheck.service` and `# systemctl --now enable dailyaidecheck.timer`. The text says the check runs "every day at 5am" and may be changed to site policy: AJ's policy is **05:00 UTC daily**.

### Sequence overview (why the order matters)
1. Install (C1). The postinst enables the timer silently, then starts the check and buildcache units several times; with no database the check fails (expected, C3), and one failed unit or two is normal.
2. Hold the timer at once (C2): `disable --now` stops it from ever firing before the database exists.
3. Clear the failed units and rebuild the AIDE LVM root cache by hand (C3a), so the database is built with the cache in place.
4. Set the `dotlockfile` mode (C4, decided, Q7), so the database records 0755.
5. Build the database (C5), run one manual check (C6, decided, Q10), then add the 05:00 UTC drop-in and enable the timer (C7) if C6 took under 50 minutes (Q9). At 50 minutes or more, stop before C7. Until C7, 6.3.2 fails by design.

### C0. Pre-check (read-only, no sudo; run at apply time, not only now)
```
apt-get -s install --no-install-recommends aide aide-common
apt-cache policy aide aide-common liblockfile1 liblockfile-bin
dpkg -l postfix bsd-mailx 2>&1 | tail -3
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic
systemctl --failed --no-pager | tail -2
```
Expected:
- Line 1: the 4-package result above: `The following NEW packages will be installed:` / `  aide aide-common liblockfile-bin liblockfile1` / `0 upgraded, 4 newly installed, 0 to remove and 0 not upgraded.`, then 4 `Inst` and 4 `Conf` lines for 0.19.2-3 and 1.17-2build2. **Stop and tell the Brain if any other package appears, especially `postfix`, `bsd-mailx`, `ssl-cert`, `libnsl2`, or if "to remove" is not 0, or if a version differs** (a newer 0.19.x would change the vetting).
- Line 2: `Candidate: 0.19.2-3` and `1.17-2build2`, `Installed: (none)`.
- Line 3: no `ii` line for `postfix` (`dpkg-query: no packages found matching postfix` and a `un bsd-mailx` line are fine).
- Line 4: size `42618411`, mtime `2026-11-03 06:13:32` (write it down; C3 compares).
- Line 5: `0 loaded units listed.`

### C1. Install (AJ, sudo; second SSH session open)
```
sudo apt-get install --no-install-recommends aide aide-common
```
Expected: apt prints the same 4-package list and asks `Do you want to continue? [Y/n]`; answer `Y` only if it matches C0. It then unpacks and sets up `liblockfile-bin`, `liblockfile1`, `aide`, `aide-common`. **A `Created symlink` line for `dailyaidecheck.timer` did appear** on 2026-11-03 (the draft had said the postinst hid it). The same screen said `dailyaidecheck.service is a disabled or a static unit, not starting it` and the same for `dailyaidecheck-buildcache.service`, so the install did not start those units. **[Confirmed]** `needrestart` printed a "Scanning processes" block and restarted nothing. C3 then decides whether any unit failed.

**If asked `Initialize AIDE database?` (the `aide/aideinit` debconf question, medium priority, default No), answer No.** Yes would make the postinst start `aideinit -b` in the background: the heavy scan that C2 to C4 must come before. Johnny's debconf priority is probably `high`, which hides the question **[Assumption]**; C3 checks that no `aideinit` is running.

**If C1 fails** (apt exits non-zero, or prints `dpkg: error processing package`): **stop. Do not run C2 to C7, and do not run the C10 rollback.** Run this read-only and give the output to the Brain:
```
dpkg --audit; echo rc=$?
dpkg -l aide aide-common liblockfile1 liblockfile-bin | tail -4
```
A half-configured `aide-common` (state `iF` or `iU`, or listed by `dpkg --audit`) can be fixed with `sudo dpkg --configure -a`, but only after the Brain has read the output.

### C2. Hold the timer immediately (AJ, sudo; run straight after C1)
```
sudo systemctl disable --now dailyaidecheck.timer
systemctl is-enabled dailyaidecheck.timer
systemctl is-active dailyaidecheck.timer
```
Expected: `Removed '/etc/systemd/system/timers.target.wants/dailyaidecheck.timer'.`, then `disabled`, then `inactive`. The timer's schedule is 01:50 UTC plus up to 2 h, so there is no race before the next night; this step simply keeps it from ever firing while there is no database. The units stay in `/usr/lib/systemd/system`, so `dailyaidecheck.service` reads `static`.
**[Assumption]** `disable --now` is the normal way to hold a unit that `deb-systemd-helper` enabled, and a later package upgrade will not re-enable it (standard `dh_installsystemd` behavior: the postinst re-enables only if `was-enabled`). Not tested on Johnny; C8 and the next upgrade will show it.

### C3. Post-install checks and the expected failed first run (read-only, no sudo)
```
dpkg --audit; echo rc=$?
dpkg -l aide aide-common liblockfile1 liblockfile-bin | tail -4
dpkg -l postfix bsd-mailx 2>&1 | tail -2
getent passwd _aide; getent group _aide
stat -c '%a %U:%G %n' /var/log/aide /var/lib/aide /run/aide
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic
ls /run/reboot-required 2>&1
ps -eo pid,args | grep -c '[a]ideinit'; ls /var/log/aide/adeinit.still-running 2>&1
systemctl --failed --no-pager
journalctl -u dailyaidecheck.service -u dailyaidecheck-buildcache.service --since "-20min" --no-pager
cat /var/log/aide/aide.log
```
Expected:
- Line 1: only `rc=0`. Anything else: stop, give the output to the Brain (the C1 failure branch).
- Line 2: four `ii` rows (versions 0.19.2-3 x2 and 1.17-2build2 x2). Line 3: `dpkg-query: no packages found matching postfix` and a `un  bsd-mailx` row; no `ii`. **If `postfix` shows `ii`, stop.**
- Line 4: `_aide:x:` followed by a uid below 1000, then `:Advanced Intrusion Detection Environment:/var/lib/aide:/usr/sbin/nologin`, and a group line `_aide:x:` with its gid. Record both numbers in the handoff (they are chosen at install).
- Line 5: `stat` of a directory needs only search permission on its parent, so it works as `aj`: `2755 _aide:adm /var/log/aide`, `700 _aide:root /var/lib/aide`, `700 _aide:root /run/aide`. Only listing their contents needs sudo.
- Line 6: **identical** to C0 line 4 (`42618411`, `06:13:32`); line 7: `ls: cannot access '/run/reboot-required': No such file or directory`. This is the boot-path proof: no initrd rebuild, no reboot flag.
- Line 8: `0`, then `ls: cannot access '/var/log/aide/adeinit.still-running': No such file or directory` (no background init was started). If `1` or more, stop and tell the Brain. The marker is spelled `adeinit.still-running` (no second i) on purpose. `/usr/sbin/aideinit` in aide-common 0.19.2-3 `touch`es it at line 136 and `rm -f`s it at line 139. The logs next to it are `aideinit.log` and `aideinit.errors`. Confirmed 2026-11-03 from `aide-common_0.19.2-3_all.deb`, sha256 `3ee74fa9a633c8d7a955d89caeb68c97b06b431142313a4c63d5d7e6d2c2bcec`, http://us.archive.ubuntu.com/ubuntu/pool/main/a/aide/aide-common_0.19.2-3_all.deb . Do not rename it to `aideinit.still-running`.
- Line 9: **0, 1, or 2 failed units.** On 2026-11-03 the install printed `not starting it` and C3 found `0`. One or two (`dailyaidecheck.service`, possibly `dailyaidecheck-buildcache.service`) remains possible if a start is attempted and refused. Either result is not an incident. The postinst has three `deb-systemd-invoke start` blocks. `dailyaidecheck.service` has `StartLimitBurst=1` per 7200 s and requires the buildcache unit (`StartLimitBurst=1` per 60 s). A repeat start inside the window is refused with `start-limit-hit`.
- Journal (inferred from `/usr/share/aide/bin/dailyaidecheck` and the unit files): `Starting dailyaidecheck-buildcache.service - build cache for daily AIDE check...` and `Finished ...`; `Starting dailyaidecheck.service - daily AIDE check...`; `dailyaidecheck[<pid>]: WARN: mail or s-nail not installed, cannot send mail. See /usr/share/doc/aide-common/README.Debian.gz for more information.`; `dailyaidecheck.service: Main process exited, code=exited, status=1/FAILURE`; `dailyaidecheck.service: Failed with result 'exit-code'.`; `Failed to start dailyaidecheck.service - daily AIDE check.` Possibly also `Start request repeated too quickly` / `start-limit-hit` lines for either unit. The script calls `onexit nodb` ("database not present", logged to `/var/log/aide/aide.log`, which the last command shows in a banner box) then `exit 1`. The `WARN: mail or s-nail not installed` line is permanent and harmless: no mail tool exists on Johnny by design; it appears in the journal on every daily run.

### C3a. Clear the failures and build the AIDE root cache before the init (AJ, sudo)
`dailyaidecheck-buildcache.service` writes `/var/lib/aide/10_aide_rootrules_cache` (LVM, device-mapper and physical-volume data that the `31_aide_lvm2` rules use for exclusions). `aideinit` does not run it. If the install-time start of the buildcache unit was refused, the init would record paths that later checks (which do have the cache) report as removed: a noisy first report.
```
sudo systemctl reset-failed dailyaidecheck.service dailyaidecheck-buildcache.service
sudo systemctl start dailyaidecheck-buildcache.service
systemctl --failed --no-pager
sudo ls -l /var/lib/aide/10_aide_rootrules_cache
sudo head -3 /var/lib/aide/10_aide_rootrules_cache
```
Expected: `reset-failed` prints nothing if the units are loaded and not failed. If they were never started it prints `Unit … not loaded` for each. That is not a stop. The start returns after a second or so; `0 loaded units listed.`; the cache file exists, is non-empty and is owned by `_aide`; the first line starts with `# output from /etc/aide/aide.conf.d/10_aide_lvm_needsroot on johnny at` (this is the header the script writes). If the start is refused with `start-limit-hit`, wait 60 seconds and repeat. If the file is missing or empty, stop and tell the Brain: do not run C5. Do not start `dailyaidecheck.service` here; that is C6.

### C4. `/usr/bin/dotlockfile` (new SGID binary; decided, Q7: statoverride)
`liblockfile-bin` ships `/usr/bin/dotlockfile` as **2755 root:mail** (setgid mail; it exists so mail programs can lock `/var/mail` files). Johnny has no mail spool. That makes **7.1.13 go from 13 SUID / 6 SGID to 13 SUID / 7 SGID**, a new item to review and approve, and the strict-CIS policy earlier refused `ntfs-3g` and `fusermount3` for the same reason. aide's own script only uses `dotlockfile` to lock `/run/aide/dailyaidecheck.lock`, a directory `_aide` owns, where setgid is not needed. **[Assumption]** (from dotlockfile(1) and the script; C6 tests it) the lock works without the setgid bit. Q7 is decided: remove the setgid bit with a dpkg override, as in Batch 1, so a package upgrade does not put it back. Keep the package owner. `--add` sets user, group, and mode together, and `--update` applies that to the file at once. `--remove` leaves the file as it is (dpkg-statoverride(1), resolute: https://manpages.ubuntu.com/manpages/resolute/en/man1/dpkg-statoverride.1.html). `--add root root 0755` would change the group from `mail` to `root`, and the rollback's `chmod 2755` would then leave **2755 root:root**, still setgid. The override is mode only:
```
sudo dpkg-statoverride --update --add root mail 0755 /usr/bin/dotlockfile
stat -c '%a %U:%G %n' /usr/bin/dotlockfile
dpkg-statoverride --list | grep dotlockfile
```
Expected: `755 root:mail /usr/bin/dotlockfile` and `root mail 755 /usr/bin/dotlockfile`. Group `mail` without the setgid bit is not an SGID file, so 7.1.13 stays 13 SUID / 6 SGID. Run this before C5, so the database records 0755. Do not skip this, and do not approve the SGID bit. Rollback, if the package stays: `sudo dpkg-statoverride --remove /usr/bin/dotlockfile` and `sudo chmod 2755 /usr/bin/dotlockfile`. The chmod puts the setgid bit back. The group is still `mail`, because the override never changed it.

### C5. Initialise the database (AJ, sudo; about the heaviest read on Johnny, run it in `tmux`)
Multiple hash functions (R-AIDE-1, mitigates only GHSA-6wc9-4w69-5jc5): the packaged `/etc/aide/aide.conf` already sets `Checksums = H`, and `H`, on this build, is the seven hashes `sha256+sha512+stribog256+stribog512+sha512_256+sha3_256+sha3_512` (`aide --version` on Johnny, 2026-11-03). aide.conf(5) describes `H` as all compiled-in non-deprecated hashsums (https://aide.github.io). `md5`, `sha1`, `rmd160`, and `gost` are compiled in and are not in this `H`. Rules that carry checksums (`Full`, `StaticFile`, `VarTime`, and so on) use that group, so **no rule override and no hand edit is needed, and nothing to mirror under `etc/`** (`/etc/aide/aide.conf` stays the package's ucf-managed copy). I did not enumerate which paths carry checksums; many stock rules (`VarFile`, `VarDir`, logs) are metadata-only. The check below proves what the database holds.

Read-only, before the init:
```
aide --version
```
Expected: a list of compiled-in hashsums with several names (for example `sha256`, `sha512`, `sha3_256`, `sha3_512`, `stribog256`, `stribog512`; **[Assumption]** exact set depends on the build). If it shows only one, stop and tell the Brain.

Build (the `umask 027` makes the log files 0640 so 6.1.3.1 stays passing; `aideinit` runs `aide` as `_aide` via `capsh` and copies `aide.db.new` to `aide.db`, no prompt on a clean system):
```
tmux new -s aide
time sudo sh -c 'umask 027; aideinit'
```
(Reattach later with `tmux attach -t aide` if the SSH session drops; do not close the tmux session.) Expected on screen: `Running aide --init...`, a long pause, then `real` time. Measured 2026-11-03: the init took **3m 13s** (111497 entries, database about 27.8 MB) and C6 took **3m 8s**. The earlier 20-to-60-minute estimate was high. `gzip_dbout=yes`. Do not start another change meanwhile. Then, as CIS 6.3.1 says (on a clean system `aideinit` has already copied `aide.db.new` to `aide.db`; the `mv` is harmless, removes the leftover `.new` and leaves the file owned by `_aide`):
```
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
sudo ls -l /var/lib/aide
sudo tail -5 /var/log/aide/aideinit.log
sudo cat /var/log/aide/aideinit.errors
sudo zcat /var/lib/aide/aide.db | grep -m1 '^@@db_spec'
```
Expected (the gate is the return code):
- `aide.db` present, `aide.db.new` gone; `aideinit.log` ends with `AIDE --init return code 0`.
- The `@@db_spec` line lists the attribute names including several hash names (`sha256`, `sha512`, ...) **[Assumption]** (db_spec header format of 0.19 not verified on Johnny).
- `aideinit.errors` is usually empty. AIDE can write warnings there on a live system (a file that vanished during the walk, an unreadable entry) even when the return code is 0. **Text in it is not an automatic stop:** show it to the Brain before C7; harmless warnings are judged by the Brain.
- **A real failure looks like:** a non-zero code in `aideinit.log` (the same line is also appended to `aideinit.errors`), no `aide.db.new`, or `aideinit` asking `Overwrite existing /var/lib/aide/aide.db.new [Yn]?` or `Overwrite /var/lib/aide/aide.db [yN]?` because an earlier run left files. Stop, show the output to the Brain, and answer `Y`/`y` only when the Brain agrees. Do not run C7.

### C6. First manual check (AJ, sudo; decided, Q10; its duration gates C7)
```
sudo systemctl reset-failed dailyaidecheck.service dailyaidecheck-buildcache.service
time sudo systemctl start dailyaidecheck.service
systemctl is-active dailyaidecheck.service
journalctl -u dailyaidecheck.service --since "-90min" --no-pager | tail -8
sudo head -30 /var/log/aide/aide.log
systemctl --failed --no-pager
```
Expected: the start returns after the check ends (oneshot); `is-active` prints `inactive`; the journal ends with `Finished dailyaidecheck.service - daily AIDE check.` (preceded by the same `WARN: mail or s-nail not installed` line); `aide.log` starts with `aide run on johnny started at ...` and reports either no changes or a small list (this exercises `dotlockfile`, the `_aide` account and the capabilities); `0 loaded units listed.` A `Failed with result` line means stop. If `start` is refused with `start-limit-hit` (the unit allows one start per 7200 s), the `reset-failed` on line 1 clears it. Note `COMMAND=update`: the check writes `aide.db.new` and never replaces `aide.db` (`COPYNEWDB=no`), so the baseline stays the C5 state until AJ copies it deliberately (Open Q8).

**Gate for C7 (time):** write down the `real` time. **Under 50 minutes: keep 05:00 UTC** (C7 as written). **50 minutes or more:** stop, tell the Brain, and let AJ decide before C7. At 05:00 the scan would run into `apt-daily-upgrade` (06:00 plus up to an hour of random delay; today it fires at about 06:05 to 06:23 UTC), and AIDE would see files change mid-scan, which makes noisy reports. AJ's policy time stands unless AJ moves it.

### C7. Set 05:00 UTC and enable the timer (AJ, sudo)
```
sudo install -d -m 0755 -o root -g root /etc/systemd/system/dailyaidecheck.timer.d
sudo tee /etc/systemd/system/dailyaidecheck.timer.d/10-johnny.conf <<'EOF'
# Johnny: CIS 6.3.2 site policy, daily AIDE check at 05:00 UTC (AJ 2026-10-31)
[Timer]
OnCalendar=
OnCalendar=*-*-* 05:00:00 UTC
RandomizedDelaySec=0
EOF
sudo chown root:root /etc/systemd/system/dailyaidecheck.timer.d/10-johnny.conf
sudo chmod 0644 /etc/systemd/system/dailyaidecheck.timer.d/10-johnny.conf
sudo systemctl daemon-reload
sudo systemctl enable --now dailyaidecheck.timer
```
The empty `OnCalendar=` clears the package's `*-*-* 01:50:00`; the second line sets the new time (systemd.timer(5) and systemd.time(7), systemd 259.9-0ubuntu0.1: https://manpages.ubuntu.com/manpages/resolute/en/man5/systemd.timer.5.html , https://manpages.ubuntu.com/manpages/resolute/en/man7/systemd.time.7.html; the `UTC` suffix is the timezone form). `RandomizedDelaySec=0` replaces the package's `2h` (Open Q9: with a single host there is nothing to spread; the `AccuracySec` default of 1 minute still lets the run start anywhere from 05:00:00 to 05:01:00); `Persistent=true` stays from the package (a missed run, for example after a reboot, fires once at the next start). Expected: `Created symlink '/etc/systemd/system/timers.target.wants/dailyaidecheck.timer' → '/usr/lib/systemd/system/dailyaidecheck.timer'.` (this one is a real `systemctl enable`, so it does print). Run C7 only if the C6 gate was met (under 50 minutes). **Confirmed (2026-11-03 10:28 UTC):** `enable --now` did not start a catch-up check. `NEXT` was `Wed 2026-11-04 05:00:00 UTC` and `dailyaidecheck.service` stayed `inactive`. That confirms the F6/C8 assumption: with no stamp file, a `Persistent=true` timer did not catch up on this first enable.

### C8. Verification: timer and CIS 6.3.1 / 6.3.2 (read-only, no sudo)
```
systemctl cat dailyaidecheck.timer | tail -8
systemctl list-timers dailyaidecheck.timer --no-pager
systemctl list-unit-files | awk '$1~/^dailyaidecheck\.(timer|service)$/{print $1 "\t" $2}'
systemctl is-active dailyaidecheck.timer
dpkg-query -s aide &>/dev/null && echo "aide is installed"
dpkg-query -s aide-common &>/dev/null && echo "aide-common is installed"
ls -l /etc/systemd/system/dailyaidecheck.timer.d/
```
Expected:
- Line 1: the drop-in appears after `# /etc/systemd/system/dailyaidecheck.timer.d/10-johnny.conf` with `OnCalendar=`, `OnCalendar=*-*-* 05:00:00 UTC`, `RandomizedDelaySec=0`.
- Line 2: one row, `NEXT` = the next `05:00:00 UTC` (for example `Wed 2026-11-04 05:00:00 UTC` if applied after 05:00 on 2026-11-03), `UNIT dailyaidecheck.timer`, `ACTIVATES dailyaidecheck.service`.
- Line 3 (the CIS 6.3.2 audit, p. 973): `dailyaidecheck.service	static` and `dailyaidecheck.timer	enabled`. Line 4: `active`.
- Lines 5-6 (the CIS 6.3.1 audit, p. 971): `aide is installed` and `aide-common is installed`.
- Line 7: `-rw-r--r-- 1 root root … 10-johnny.conf`.
Governance re-audits 6.3.1 and 6.3.2; both should read PASS. The timer must stay `inactive`/`disabled` until C7 (so 6.3.2 reads FAIL between C1 and C7, by design).

### C9. Regression checks (after C7, and again after the first real run at 05:00 UTC)
Read-only. The 05:00 run happens on the next UTC morning; check after 05:00 plus the C6 duration plus 15 minutes, or at 06:30 UTC at the latest.
```
find /var/log/sysstat -type f -perm /0137
sudo find /var/log/dpkg.log* /var/log/alternatives.log* /var/log/unattended-upgrades -type f -perm /0137
stat -Lc 'File: %n Access: (%a/%A) Uid: ( %u/ %U) Gid: ( %g/ %G)' /etc/motd /run/motd /usr/lib/motd /etc/motd.d/* /run/motd.d/* /usr/lib/motd.d/* /etc/update-motd.d/* 2>/dev/null | grep -vc 'Access: (644/-rw-r--r--) Uid: ( 0/ root) Gid: ( 0/ root)'
grep -h 'conffile prompt' /var/log/unattended-upgrades/unattended-upgrades.log
cat /run/reboot-required /run/reboot-required.pkgs
sudo find -L /var/log -type f -perm /0137 -printf '%m %u:%g %p\n' | sort | diff - ~/batch3-modes-before.txt && echo MODES-UNCHANGED
sudo find /var/log/aide -type f -printf '%m %u:%g %p\n'
dpkg-query -s rsync &>/dev/null && echo "rsync is installed"
for pkg in telnet inetutils-telnet telnet-ssl; do dpkg-query -s "$pkg" 2>/dev/null | grep -q '^Status: install ok installed' && echo "$pkg is installed"; done
for pkg in ftp tnftp atftp inetutils-ftp ftp-ssl; do dpkg-query -s "$pkg" 2>/dev/null | grep -q '^Status: install ok installed' && echo "$pkg is installed"; done
sudo bash ~/cis-audit/cis-7-root.sh > ~/cis-audit/7-root-batch3.txt 2>&1
grep -E 'List of|dotlockfile' ~/cis-audit/7-root-batch3.txt
sudo bash ~/cis-audit/cis-6-root.sh > ~/cis-audit/6-root-batch3.txt 2>&1
sed -n '/^== 6.1.3.1/,$p' ~/cis-audit/6-root-batch3.txt
sudo bash ~/cis-audit/cis-5.4-root.sh > ~/cis-audit/5.4-root-batch3.txt 2>&1
diff <(grep -v '^== helper: johnny' ~/cis-audit/5.4-root.txt) <(grep -v '^== helper: johnny' ~/cis-audit/5.4-root-batch3.txt)
```
Expected:
- GR1 (line 1): nothing. GR2 (lines 2-3): nothing, then `0`. GR3 (line 4): nothing. GR4 (line 5): two `No such file or directory`. The AIDE install does not touch sysstat, dpkg or alternatives logs, `update-motd.d`, or `/run/reboot-required`.
- Line 6: `MODES-UNCHANGED` (no new file over 0640 anywhere under `/var/log`; `/var/log/aide` files are 0640).
- Line 7: every file `640 _aide:adm` (`aide.log`, dated or `.0` copies, and `aideinit.log`/`aideinit.errors`). The mode comes from `umask 027` at line 110 of `/usr/share/aide/bin/dailyaidecheck` plus the setgid `adm` directory `/var/log/aide` (2755). Seen 2026-11-03: all four files `640 _aide:adm`. `aideinit.log` may be `640 _aide:_aide` if the setgid bit did not apply, which still passes 6.1.3.1. **6.1.3.1 owner check:** the catch-all branch of CIS's script (p. 808) allows a file owner whose login shell is not in `/etc/shells`; `_aide` uses `/usr/sbin/nologin`, which Johnny's `/etc/shells` does not list, so `_aide` owners pass, and group `adm` passes. Governance's re-audit (`~/cis-audit/6-root-batch3.txt`, last command) is the verdict. **If any `aide` file is 0644, tighten it and tell the Brain**: `sudo sh -c 'chmod 640 /var/log/aide/*'`; the `umask 027` in C5 and the script's own `umask 027` should prevent it.
- Lines 8-10 (the three Batch 2 audit lines for 2.1.13, 2.2.4, 2.2.6): **no output at all** (none of rsync, telnet, ftp packages came back; the `--no-install-recommends` form keeps them out).
- 7.1.13 (lines 11-12): with the C4 override, ` - List of "13" SUID executable files:` and ` - List of "6" SGID executable files:` (unchanged), no `dotlockfile` line. Without C4: `13` and **`7`**, plus `/usr/bin/dotlockfile` in the SGID list.
- 6.1.3.1 (line 14, F10): the header line `== 6.1.3.1 access to all logfiles in /var/log (expect: nothing returned)`, then `== end`, and no file line between them. Seen 2026-11-03. Any file line between them is over 0640 or has a bad owner or group: show it to the Brain.
- 5.4 for `_aide` (lines 15-16): before the diff, `~/cis-audit/5.4-root.txt` must exist. It does: 2713 bytes, mtime 2026-10-31 23:14:28 UTC. The 2026-11-03 diff against it was one line, `helper: _aide locked(!)`. No new rule failure text. `sysusers` creates the account with a locked password and `nologin`. Governance reads the diff and re-audits.
- Also check `systemctl --failed` is empty after C6/C7 and, after the first 05:00 run, `journalctl -u dailyaidecheck.service --since today --no-pager | tail -5` ends with `Finished dailyaidecheck.service`.

### C10. Rollback
**If C1 failed and left a half-configured install, this rollback is not for that state:** follow the "If C1 fails" branch under C1 first.

Stop and remove the timer, then purge the four packages by name (not `autoremove`: the Batch 2 lesson is that a careless `autoremove` removes many packages). `purge` also removes the database and the ucf-managed config (aide-common `postrm`).
```
sudo systemctl disable --now dailyaidecheck.timer
sudo rm -r /etc/systemd/system/dailyaidecheck.timer.d
sudo systemctl daemon-reload
sudo dpkg-statoverride --remove /usr/bin/dotlockfile
apt-get -s purge aide aide-common liblockfile1 liblockfile-bin
```
`rm -r` of the drop-in directory errors with `No such file or directory` if C7 was never applied; that is harmless. Expected for the simulation: exactly these four packages to purge (`Purg` lines), no `Remv` of anything else, 0 other (nothing else depends on them: `apt-cache rdepends --installed` shows only the aide/liblockfile pairs). If it lists others, stop. Then:
```
sudo apt-get purge aide aide-common liblockfile1 liblockfile-bin
sudo userdel _aide
sudo rm -rf /var/lib/aide /var/log/aide /run/aide /etc/aide
sudo rm -f /var/lib/systemd/timers/stamp-dailyaidecheck.timer
sudo systemctl reset-failed
getent passwd _aide; getent group _aide; ls -d /etc/aide /var/lib/aide /var/log/aide /run/aide 2>&1
dpkg -l aide aide-common liblockfile1 liblockfile-bin 2>&1 | tail -4
```
Expected: `userdel` prints nothing (it also removes the matching `_aide` group; if the group remains, `sudo groupdel _aide`); `getent` prints nothing; each `ls -d` says `No such file or directory`; `dpkg -l` shows `un`/no packages (not `rc`). If `dpkg-statoverride --remove` says "no override present", that is harmless (C4 was skipped). `apt-get purge` stops the units first (`prerm`), removes `/etc/cron.daily/dailyaidecheck`, `/etc/default/aide` and the database; the `rm -rf` line only clears leftovers (`/var/log/aide`, `/var/lib/aide/*.cache`, the unowned `_aide` directories), and the `rm -f` line removes the `Persistent=true` stamp of the timer (written when it first fires; it survives a purge, and after a reinstall it could make `enable --now` fire a catch-up run at once). Rolling back after a successful run also loses the baseline; a fresh install needs C5 again. The rollback leaves 6.3.1 and 6.3.2 failing again.

### SBOM rows (versions and archive `sha256` from Governance's vetting file; re-confirmed on Johnny with `apt-cache show` at 06:45 UTC)
| Package | Version | `.deb` sha256 |
|---|---|---|
| aide | 0.19.2-3 | `4f07f5583859e6f43f1e2e975e59c67225fcdaa529ac15f56d639cb924a21bdd` |
| aide-common | 0.19.2-3 (all) | `3ee74fa9a633c8d7a955d89caeb68c97b06b431142313a4c63d5d7e6d2c2bcec` |
| liblockfile-bin | 1.17-2build2 | `0420cfd9502d22ca16bf4a2fa1374a7decd336de2d4fc56b3c0cd0c4bc701ea4` |
| liblockfile1 | 1.17-2build2 | `70e8dd7d390a2b65b62cb59e4664729cb89a1196b241dd4e6bce1cb92f5eb735` |

Also record: system account `_aide` (uid/gid from C3, nologin, home `/var/lib/aide`); open advisories GHSA-6wc9-4w69-5jc5 (mitigated by multi-hash) and GHSA-wq25-fm54-5q3q (open) against aide 0.19.2-3 (R-AIDE-1, accepted by AJ 2026-11-03); watch for aide 0.19.5 in resolute-updates.

### Operating notes (not a CIS requirement; AJ to know)
- The daily check **never fails on differences**: the script exits 0 whenever AIDE ran, and there is no mail tool, so a "changed file" report appears only in `/var/log/aide/aide.log` (readable by `aj` through group adm, no sudo) and the journal's `WARN: mail or s-nail not installed` line. The same run also logs `fold: fold-error-failed-to-write: Broken pipe`. That is benign and recurring: the script pipes the report as `fold | send_mail` (line 754), and with no mailer `send_mail` returns without reading (line 147). The unit still finishes. Someone has to read the log (Open Q8).
- Because `COPYNEWDB=no`, `aide.db` stays the baseline from C5. Package updates (unattended-upgrades at about 06:05 UTC) will show as changes every day until AJ accepts them: after reviewing a report, `sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db` makes the reviewed state the new baseline. Do this deliberately; automated copying would defeat the detective control.
- A later upgrade of `aide-common` re-runs its postinst, which restarts `dailyaidecheck.service`; for a oneshot that means "run a check now" (harmless once the database exists, but it is an extra full scan; the timer stays as C7 left it because the postinst re-enables only if `was-enabled`). Expect it in GR5's "Finished" count.
- `aide.conf` and its snippets are ucf-managed. Do not edit them by hand without adding a mirror under `etc/` and a Config changes row.

---

## Files to mirror under `etc/` (create or update after AJ applies, copied from the live files; same commit as the Config changes rows)
**New or changed content:**
- `etc/systemd/journald.conf.d/60-rotation.conf` (new; 0644 root:root)
- `etc/logrotate.conf` (new mirror; `rotate 13`, `maxage 90`)
- `etc/logrotate.d/rsyslog` (new mirror; only if Q2 = B2)
- `etc/logrotate.d/ufw` (new mirror; only if Q2 = B2)
- `etc/systemd/system/dailyaidecheck.timer.d/10-johnny.conf` (new; 0644 root:root)

Already mirrored and unchanged by this batch: `etc/logrotate.d/{dpkg,alternatives,ubuntu-pro-client}`, `etc/sysstat/sysstat`. **Not mirrored on purpose:** the package-managed AIDE config (`/etc/aide/*`, `/etc/default/aide`, `/etc/cron.daily/dailyaidecheck`) is untouched and comes from the package; the database lives in `/var/lib/aide` (outside `etc/`). The mode-only `dotlockfile` override lives in `/var/lib/dpkg/statoverride` (record `dpkg-statoverride --list`, as in Batch 1).

**Proposed Config changes rows (Brain writes them):**
- `/etc/systemd/journald.conf.d/60-rotation.conf` (CIS 6.1.1.1.5) | new drop-in, the five CIS values | A3 (`rm`, `rmdir`, reload).
- `/etc/logrotate.conf` (CIS 6.1.2.7) | `rotate 13`, `maxage 90`; modified conffile | B6.
- `/etc/logrotate.d/{rsyslog,ufw}` (CIS 6.1.2.7) | `rotate 13`; modified conffiles (if Q2 = B2) | B6.
- AIDE packages (CIS 6.3.1) | `aide`, `aide-common` 0.19.2-3, `liblockfile1`, `liblockfile-bin` 1.17-2build2, installed with `--no-install-recommends`; account `_aide`; database `/var/lib/aide/aide.db`, logs `/var/log/aide` | C10.
- `/etc/systemd/system/dailyaidecheck.timer.d/10-johnny.conf` (CIS 6.3.2) | `OnCalendar=*-*-* 05:00:00 UTC`, `RandomizedDelaySec=0` | C10.
- `/usr/bin/dotlockfile` (7.1.13, Q7) | dpkg override root:mail 0755 (was 2755 root:mail; mode only, group stays mail) | `sudo dpkg-statoverride --remove /usr/bin/dotlockfile` and `sudo chmod 2755 /usr/bin/dotlockfile` (the chmod puts the setgid bit back; the group is still mail).
- Recurring checks: add B5; extend GR3 to the `rsyslog` and `ufw` conffiles; add **GR5** (weekly, no sudo): read `/var/log/aide/aide.log` for reported changes, and confirm the timer ran with `journalctl -u dailyaidecheck.service --since "-8days" --no-pager | grep -c 'Finished dailyaidecheck.service'` → 7 or 8; plus the Governance watch for aide 0.19.5.

---

## Ubuntu 26.04 (resolute) sources checked 2026-11-03
- journald.conf(5), systemd 259.9-0ubuntu0.1: https://manpages.ubuntu.com/manpages/resolute/en/man5/journald.conf.5.html
- systemd-journald.service(8) (signals, reload): https://manpages.ubuntu.com/manpages/resolute/en/man8/systemd-journald.service.8.html
- journalctl(1) (`--rotate`, `--disk-usage`): https://manpages.ubuntu.com/manpages/resolute/en/man1/journalctl.1.html
- dpkg-statoverride(1) (`--add` sets user, group, and mode; `--remove` leaves the file unchanged): https://manpages.ubuntu.com/manpages/resolute/en/man1/dpkg-statoverride.1.html
- logrotate(8), 3.22.0-1build1: https://manpages.ubuntu.com/manpages/resolute/en/man8/logrotate.8.html
- logrotate 3.22.0 source (debug wording, maxage logic): https://github.com/logrotate/logrotate/blob/3.22.0/logrotate.c
- unattended-upgrade(8), 2.12ubuntu9: https://manpages.ubuntu.com/manpages/resolute/en/man8/unattended-upgrade.8.html
- systemd.timer(5), systemd.time(7), systemd 259.9-0ubuntu0.1: https://manpages.ubuntu.com/manpages/resolute/en/man5/systemd.timer.5.html , https://manpages.ubuntu.com/manpages/resolute/en/man7/systemd.time.7.html (cited for the `OnCalendar=` reset and the `UTC` suffix; not re-fetched in this pass)
- aide / aide-common 0.19.2-3, liblockfile 1.17-2build2: https://packages.ubuntu.com/resolute/aide , https://packages.ubuntu.com/resolute/aide-common , https://packages.ubuntu.com/resolute/liblockfile-bin ; `.deb` files from http://us.archive.ubuntu.com/ubuntu/pool/main/a/aide/ and /libl/liblockfile/ read on rock-box (scratchpad only); upstream manual https://aide.github.io ; advisories https://github.com/aide/aide/security/advisories ; Governance's vetting file `docs/findings/aide-vetting.md`.

## Assumptions (marked)
1. **Confirmed (2026-11-03 09:22:46 UTC).** `reload-or-restart` reloaded journald. The unit is `Type=notify-reload`. The process start stayed 06:17:24 and `NRestarts` stayed 1. The journal line was `Config file reloaded.`
2. **Confirmed (2026-11-03 09:27:20 UTC).** The rotate logged `System Journal (/var/log/journal/a8e4c2a812a640ff8ca95580b7867082) is 140.2M, max 1G, 883.7M free.` The token was `max 1G`.
3. **Confirmed (2026-11-03 09:41 UTC).** `logrotate -d` printed `(13 rotations)` 3 times and `old logs are removed after 90 days` 15 times. 15 equals B0's `old logs are removed` count. The `90 days` wording ran on Johnny.
4. **[Assumption]** The 26 MB/day journal growth is a rough 5-day average (boot activity, three reboots on 2026-10-29), not a steady rate.
5. **[Assumption]** `logrotate.service` text `Finished … Rotate log files.` in B5 is the standard systemd form; not read on Johnny.
6. **[Assumption]** The Assurance review will treat 6.1.1.1.5 and 6.1.2.7 (both Manual) as PASS when the grep and the config review match AJ's policy; the verdict is Governance's re-audit.
7. **[Assumption]** The install-time failed check and its journal lines (C3) are inferred from reading `dailyaidecheck` and the unit files; nothing was run. `systemd` 259 message wording may differ slightly.
8. **[Assumption]** `aide --version` lists several non-deprecated hashsums, and `@@db_spec` in the database header names them (C5). Both depend on the build and the 0.19 database format; unverified on Johnny.
9. **Confirmed (2026-11-03).** The init took 3m 13s (111497 entries). C6 took 3m 8s. The 20-to-60-minute estimate was high. C6's measured time gated C7, and it was under 50 minutes. The database is 27814873 bytes.
14. **Confirmed (2026-11-03 10:28 UTC).** With no stamp file, `enable --now` on the `Persistent=true` timer did not start a catch-up run. `NEXT` was `Wed 2026-11-04 05:00:00 UTC`. The service stayed `inactive`.
10. **[Assumption]** `dotlockfile` locks `/run/aide/dailyaidecheck.lock` without the setgid bit (C4); C6 tests it.
11. **[Assumption]** `dpkg-statoverride --update --add` and `systemctl disable --now` behave as in Batch 1 and the dh_installsystemd convention (C2, C4).
12. **[Assumption]** The 6.1.3.1 owner rule accepts `_aide` because `/usr/sbin/nologin` is not in `/etc/shells` (read on Johnny; CIS script p. 808); Governance's re-audit decides.
13. **Confirmed (2026-11-03 09:27:20 UTC).** The rotate left 7 files, each `640 root:systemd-journal`, including the new active `system.journal` and `user-1000.journal`. The 259 create path was not read. The `stat` is the evidence.

## Open questions for AJ
1. **ANSWERED (AJ, 2026-11-03): keep `maxage 90`.** It is global and cuts the longer stanzas. It shortens `dpkg`, `alternatives`, `apt`, `dracut-core` (now 12 months) and `ubuntu-pro-client`, `unattended-upgrades`, `cloud-init-base` (6 months) to about 90 days. Nothing is deleted before 2027-02-01. Keep `maxage 90` as recorded (Platform: yes, it is your policy value), or choose a larger value such as 400 so those package logs keep their year (then `maxage` rarely binds for the weekly logs, which Grok already noted)?
2. **ANSWERED (AJ, 2026-11-03): run B1 and B2.** Make `rotate 13` real for syslog/auth.log/kern.log/ufw.log. Global `rotate 13` alone leaves them at 4 weeks. Platform recommends B2 (edit the `rsyslog` and `ufw` stanzas). It adds two locally modified conffiles (Residual). Choose B1 only, or B1 + B2.
3. **ANSWERED (AJ, 2026-11-03): accept.** The conffile residual (`logrotate.conf`, plus `rsyslog` and `ufw` with B2): a future update to one of them is skipped by unattended-upgrades until AJ upgrades it by hand; GR3 catches it weekly.
4. **ANSWERED (AJ, 2026-11-03): keep the recorded caps, including `SystemMaxUse=1G`.** Journal retention is shorter than the 13-week logs. At about 26 MB/day the 1G cap holds roughly 5-6 weeks of journal; the text logs keep 13 weeks (with B2). Keep AJ's CIS-example values as recorded (Platform: yes; auth and sudo lines also live in `/var/log/auth.log`), or raise `SystemMaxUse` (for example 4G, still under 1% of the volume)? Changing it needs AJ's call and a note in the handoff.
5. **ANSWERED (AJ, 2026-11-03): include it (A1b).** `sudo journalctl --rotate` after A2, then the two `journalctl` reads, so the `max 1.0G` line is checked. The new file's mode 640 is an assumption until that `stat` (A1b). Harmless; include it or skip it?
6. **ANSWERED (AJ, 2026-11-03): R-AIDE-1 accepted, option A.** Install 0.19.2-3 now with `--no-install-recommends`, multiple hashes, track Ubuntu for 0.19.5. Recorded here; the Brain files the risk-register entry. The invalid-UTF-8 bypass stays open until the fix lands (Risk line).
7. **ANSWERED (AJ, 2026-11-03): statoverride to 0755.** `/usr/bin/dotlockfile` (C4): remove its setgid bit with a dpkg override, rather than approve it as a 7th SGID file in 7.1.13. The override keeps 7.1.13 at 13/6 and costs one `dpkg-statoverride` line. Rev 4 keeps group `mail` (`--add root mail 0755`). Approving the bit instead means 13/7 and one more reviewed binary.
8. **ANSWERED (AJ, 2026-11-03): accept both.** Reading the AIDE report by hand, and refreshing `aide.db` only by a deliberate copy. There is no mail, and the daily unit exits 0 even when AIDE finds changes, so a report sits in `/var/log/aide/aide.log` and nothing alerts. Accept a weekly manual read (GR5) until report delivery is decided (separate, later decision per Governance), and accept that `aide.db` is only refreshed by AJ's deliberate `cp` after review? Platform: yes to both.
9. **ANSWERED (AJ, 2026-11-03): `RandomizedDelaySec=0` when C6 is under 50 minutes.** Timer randomization: `RandomizedDelaySec=0` so the check starts at 05:00 UTC (it can slip up to the 1-minute `AccuracySec` default, so 05:00:00 to 05:01:00) (Platform and Assurance: fine, one host, nothing to spread), or keep the package's 2 h spread (05:00-07:00 UTC, overlapping `apt-daily-upgrade` at about 06:05)? The C6 scan time decides: under 50 minutes, 05:00 is safe; otherwise AJ chooses a new time before C7.
10. **ANSWERED (AJ, 2026-11-03): run C6 before C7.** First manual check before enabling the timer: run it (Platform: yes; it proves `dotlockfile`, `_aide` and the capabilities before the first unattended run), or go straight to C7?
