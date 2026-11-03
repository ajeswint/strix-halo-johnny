# Review: CIS L1 Batch 1 draft (`docs/cis-fix/batch-1.md`)

**Reviewer:** Assurance (independent; did not write the draft). **Date:** 2026-11-02 CST (Johnny clock 2026-11-03 04:12–04:40 UTC).
**Scope:** rules 1.6.6, 2.4.1.2–2.4.1.9, 6.1.3.1 as drafted by Platform. Nothing outside Batch 1.
**Method:** read-only. `ssh aj@192.168.50.152` as `aj`, no sudo, no writes on Johnny. CIS Ubuntu Linux 26.04 LTS v1.0.0 PDF, printed pp. 235–236, 374–391, 808–812 (local). dpkg 1.23.7 source from salsa.debian.org. Ubuntu resolute man pages. CIS text is paraphrased here (licensed). Only short command lines are quoted.

## Verdict: APPROVE WITH CHANGES

The commands are exact and copy-paste, match the CIS remediation, and stay inside Batch 1. None of them can lock AJ out. None touches SSH, PAM, sudo, GRUB, the held packages (`shim-signed`, `secureboot-db`) or PCR 7, and none needs a reboot. The rollbacks restore the state read on 2026-11-03.

Two verification blocks would print output the draft does not predict, which could lead AJ to roll back a good change (F1, F2). One AJ option (Open Q4, `root adm`) has no commands (F3). F4 adds a needed check for held packages. Platform fixes F1–F4 before the Brain shows AJ the blocks. F5–F10 are text fixes and information only.

## Findings

| # | Sev | Location | Finding (root cause) | Fix requested of Platform |
|---|---|---|---|---|
| F1 | Medium | D3 line 3 and its expected output; D4 last line and the sentence under it | Once Group A is applied, `/etc/cron.daily` is 0700. `dpkg` owns the conffile `/etc/cron.daily/dpkg` (`dpkg -L dpkg`, `dpkg-query -W -f='${Conffiles}' dpkg` on Johnny). As `aj`, `dpkg --verify` cannot `lstat` it: EACCES on the parent directory. dpkg 1.23.7 `src/main/verify.c` `verify_file()` then sets `exists=VERIFY_FAIL` with errno, and `verify_output_rpm()` prints `missing   c /etc/cron.daily/dpkg (Permission denied)`. D3 therefore prints 5 lines, not 4. The D4 rollback check ("printing nothing confirms") prints 1 line even when the rollback worked. This comes from reading the source; I could not reproduce it because no file like this exists on Johnny today. | Run both checks as `sudo dpkg --verify dpkg ubuntu-pro-client sysstat` (it is read-only). Or keep them non-root and list the extra `missing … (Permission denied)` line as expected whenever Group A is in place. |
| F2 | Medium | A3 expected output ("the journal should show the hourly `CRON[...]: (root) CMD` line") | Johnny's cron logs no `CMD` lines. `cron.service` runs `/usr/sbin/cron -f -P $EXTRA_OPTS`, and `/etc/default/cron` sets nothing. `journalctl -u cron` for the last 2 h has zero `CMD` lines and shows only `pam_unix(cron:session): session opened/closed for user root` at 02:17:01 and 03:17:01. With the draft's wording, AJ would conclude that cron broke. | Change the expected line to `CRON[…]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)` at `:17:01`, plus no `WRONG`/`INSECURE`/`ORPHAN` lines (gate GA4). |
| F3 | Medium | Open Q4 and D1/D3/D4 | Q4 offers `root adm` 0640, and CIS allows it: the catch-all branch on pp. 808/811 accepts group `adm`, and accepts any group on root-owned files. But the D1 sed lines, the D3 expected lines and the D4 rollback sed lines all hard-code `root root`. If AJ picks `adm`, there is no block to paste, and the D4 rollback pattern would not match. | Add a complete `root adm` variant of D1, D3 and D4, or state that choosing `adm` sends Group D back to Platform before anything is applied. |
| F4 | Medium | Residuals, "Conffile prompts" bullet | The claim is correct (see C7). The draft misses that Group C removes `92-unattended-upgrades`, the login notice that would tell AJ about a package held back for this reason. D2 also makes `unattended-upgrades.log` 0640 root:root, so `aj` (group adm) can no longer read the log that records the hold. Together, D1 + C1 + D2 make a held security update (dpkg, ubuntu-pro-client, sysstat) silent. | Add a recurring check to the Residuals section and the handoff (gate GR3): `sudo grep -h 'conffile prompt' /var/log/unattended-upgrades/unattended-upgrades.log` should print nothing. |
| F5 | Low | A2 rationale; Assumption 2 | **Refuted.** dpkg does not reset an existing directory's mode on upgrade. dpkg 1.23.7 `src/main/archives.c`: `case TAR_FILETYPE_DIR: /* If it's already an existing directory, do nothing. */` sets `existingdir`, and `if (existingdir) return 0;` runs before `tarobject_set_perms()`. No maintainer script on Johnny chmods these directories (grep of cron, cron-daemon-common, man-db, logrotate, dpkg, base-files postinsts). The six directory overrides therefore only matter if a directory is removed and recreated. The `/etc/crontab` override does matter (F-assumption 1). | Correct the A2 text: the directory overrides are defense in depth, not upgrade protection. Whether to keep them stays AJ's call (Q1). No command change needed. |
| F6 | Low | C4 expected, line 1 | `stat -Lc '%a'` prints `644`, not `0644`. CIS p. 235's expected text also says `0644`, but the command it gives prints `Access: (644/-rw-r--r--)`. | Change the expected text to `Access: (644/-rw-r--r--) Uid: ( 0/ root) Gid: ( 0/ root)`. |
| F7 | Low | B2 expected, line 4 | `crontab` prints two lines and exits 1 (strings in `/usr/bin/crontab`, CIS p. 390). | Expected: `You (aj) are not allowed to use this program (crontab)` / `See crontab(1) for more information`, rc 1. |
| F8 | Low | D3 line 4 | The grep for `warning` has no baseline, so a warning that predates this batch would look like a regression. | Capture `sudo logrotate -d /etc/logrotate.conf 2>&1 \| grep -ciE '^error\|warning'` before D1 and compare after. |
| F9 | Low | Risk line (top) | Missing visible effect: `sar` (as `aj`) can no longer read `/var/log/sysstat/sa*` once they are 0640 root:root. Same for the unattended-upgrades logs, which `aj` reads today through group adm. | Add both to the Risk line. |
| F10 | Info | 1.6.6 and 6.1.3.1 durability | Stat overrides cover only paths that exist today. A future package that installs a new `/etc/update-motd.d/NN-*` (0755) or a new 0644 `/var/log` writer fails the rule again without notice. | Add GR1/GR2 to the recurring checks after any `apt install`. |

## Claims checked

| # | Claim | Result | Evidence |
|---|---|---|---|
| C1 | 2.4.1.9 → root:crontab 0640 | **Confirmed** | CIS p. 390: the script chowns `root:crontab` when `/etc/group` has `crontab`. Johnny: `crontab:x:987:`, `/usr/bin/crontab` 2755 root:crontab (dpkg override). `crontab(1)` on Johnny, line 168: the files must be world-readable or readable by group crontab. `/usr/sbin/cron` contains no `cron.allow` string, so only the setgid `crontab` binary reads it. |
| C2 | 6.1.3.1 writers: logrotate `create` in dpkg, alternatives, ubuntu-pro-client | **Confirmed** | `cat -A` on Johnny: dpkg/alternatives line 8 `^Icreate 644 root root$`; ubuntu-pro-client line 5 `    create 0644 root root$`. The sed patterns match. All three are conffiles (dpkg md5 recorded). CIS p. 811 "permanent fix" (1) names exactly this, and lists `/etc/logrotate.d/alternatives` as observed in practice. Note: `ubuntu-advantage-apt-hook.log` is 0 bytes and the stanza has `notifempty`, so its one-time chmod is what holds. |
| C3 | `UMASK=0027` in `/etc/sysstat/sysstat` | **Confirmed; better than CIS's example** | `sa1` line 21 and `sa2` line 24 run `umask ${UMASK}` *after* sourcing `/etc/sysstat/sysstat` (line 44 `UMASK=0022`, a conffile). CIS's p. 811 example puts `umask 0027` "near the top" of `/usr/libexec/sysstat/sa1`. On Ubuntu that line would be overridden by line 21 (0022 from the conffile), so the literal example does not work here. All three units (`sysstat-collect`, `-summary`, `-rotate`) run `sa1`/`sa2` as root. sysstat(5) resolute 12.7.7-0ubuntu2 recommends 0027. The deviation is from the CIS *example*, not the CIS requirement. |
| C4 | unattended-upgrades via the global `create` | **Confirmed** | `/etc/logrotate.conf` has bare `create`. `/etc/logrotate.d/unattended-upgrades` has no `create`. logrotate(8) resolute 3.22.0-1build1: omitted attributes take the original file's values. Live: `unattended-upgrades-dpkg.log` was recreated 2026-11-01 00:35 at 0644 root:adm, copying its predecessor. `unattended-upgrade` line 2108 (`basicConfig(filename=…)`) and line 2542 (`open(…,'w')` only if missing) create files only when missing. |
| C5 | landscape quiet after 1.6.6 | **Confirmed** | Only callers: the `/etc/update-motd.d/50-landscape-sysinfo` link, and `landscape-common.postinst` line 95 (`$WRAPPER >/dev/null 2>&1 \|\| true` on configure), which fails harmlessly at 0644. No `/etc/profile.d/50-landscape-sysinfo.sh`. The wrapper is a regular package file, so without the C2 override an upgrade restores 0755 and the postinst runs it again. C2 is needed for 1.6.6 to last. |
| C6 | dpkg-statoverride survives conffile replacement (Assumption 1) | **Confirmed from source** | dpkg 1.23.7 `archives.c`: `if (nifd->namenode->statoverride) nodestat = *…statoverride`. Then `tarobject_set_perms(ti, fnamenewvb.buf, &nodestat)` runs *before* the conffile early return (`FNNF_NEW_CONFF` → stays `.dpkg-new`). `configure.c` installs it by `rename()`, which keeps the mode. The resolute man page says "any filesystem object that dpkg handles". Not tested by an actual upgrade. |
| C7 | motd-news.service fails after 1.6.6 | **Confirmed** | `motd-news.service`: `Type=oneshot`, `ExecStart=/etc/update-motd.d/50-motd-news --force`. A non-executable file gives a systemd exec failure and leaves the unit failed. Next run 2026-11-03 07:41 UTC. If C3 is chosen, it lasts: `base-files.postinst` lines 164–174 use `deb-systemd-helper was-enabled`/`update-state`, so an upgrade does not re-enable an admin-disabled timer. |
| C8 | conffile edits make uu hold back future updates | **Confirmed (narrowly)** | `unattended-upgrade` `conffile_prompt()` (lines 1467–1556) holds back only when on-disk md5 ≠ dpkg's recorded md5 **and** the new deb's md5 ≠ recorded md5. Line 2806 logs `has conffile prompt`. Mode-only changes (A2/C2) never trigger it, because it compares md5 only. No `--force-confold` is configured (`50unattended-upgrades:48` is a comment). See F4. |
| C9 | Lockout / boot / sudo / SSH / cron / logrotate / apt / uu breakage | **None found** | pam_motd is `session optional` in `/etc/pam.d/sshd` and `/etc/pam.d/login`. No PAM, sshd or sudoers file is touched. cron runs as root, and Debian cron accepts a 0600 `/etc/crontab` and 0700 directories. `aj` has no crontab. Root is always allowed by `crontab`. Under systemd the cron.daily jobs (apt-compat, dpkg, logrotate, man-db) defer to their timers anyway. `systemctl --failed`: 0 units (baseline). `apt-mark showhold`: `secureboot-db`, `shim-signed`, untouched. Nothing installs, removes or upgrades a package, and nothing reboots. |
| C10 | Commands exact, no placeholders, inside Batch 1 | **Confirmed** | All blocks are literal paths. The `$(readlink -e …)` from CIS is written out as the wrapper path. The extras outside CIS are A2/C2 (overrides), C3 (timer) and the D1 sysstat conffile route, and each is marked as AJ's decision. `dpkg-statoverride --remove` with no override returns 2 with a warning only (dpkg `statoverride/main.c` lines 316–322), which does no harm in a paste. |
| C11 | D2 = CIS 6.1.3.1 script on the current set (Assumption 3) | **Confirmed** | The live non-root `find` (04:3x UTC) matches the draft's list exactly: 30 catch-all files at 0644/0444. Every one is root-owned, so the catch-all branch accepts its group (pp. 808/811). The CIS fix on these is `chmod u-x,g-wx,o-rwx`, the same as D2. `/var/log/chrony` and `/var/log/private` are not readable by `aj`; the root audit 2026-10-31 flagged nothing there. |
| C12 | Rollbacks restore the read state | **Confirmed** (except the F1 wording) | A4 → 644/755 root:root. B3 → file absent. C5 → 755 on 12 files + wrapper. D4 sed restores the exact original bytes (`\1` keeps the tab or spaces), so the md5 matches again. The D4 chmod list matches the 0644/0444 set read live. |

## Platform's six assumptions

| # | Status | Basis |
|---|---|---|
| 1 | **Confirmed** (source) | C6. |
| 2 | **Refuted** | F5: existing directories are left alone. |
| 3 | **Confirmed** | C11. |
| 4 | **Confirmed** | No `cron.allow` string in `/usr/sbin/cron`; only `/usr/bin/crontab` has it. CIS p. 388 Note. |
| 5 | **Confirmed** | `timedatectl show -p Timezone` → `Etc/UTC`. Live `sa02` 00:00, `sar02` 00:07 UTC. |
| 6 | **Confirmed for what was searched; left open otherwise** | No unit, profile or cron file under `/usr/lib/systemd/system`, `/etc/systemd/system`, `/etc/cron*`, `/etc/apt/apt.conf.d`, `/etc/profile.d`, `/etc/pam.d` reads the cron paths as non-root. Programs that might read them at runtime were not traced. |

## Acceptance gates for the re-audit

Run on Johnny as `aj`. Lines marked **(sudo, read-only)** are for AJ to run. Each gate applies only if its group was applied. A gate fails if the output differs from what is expected. On a failure, stop and run that group's rollback.

### Safety (run first, from a second SSH session, after each group)
- GS1, from the laptop: `ssh aj@192.168.50.152 'id -un'` → `aj`
- GS2 (AJ): `sudo -k && sudo true && echo sudo-ok` → password prompt, then `sudo-ok`
- GS3: `apt-mark showhold` → `secureboot-db` and `shim-signed`, nothing else
- GS4: `systemctl --failed --no-pager --plain` → `0 loaded units listed.` (if C3 is skipped, `motd-news.service` is the only allowed entry)
- GS5: `systemctl is-active cron unattended-upgrades apt-daily-upgrade.timer logrotate.timer sysstat-collect.timer` → `active` five times

### Group A (2.4.1.2–2.4.1.8)
- GA1: `stat -Lc 'Access: (%a/%A) Uid: ( %u/ %U) Gid: ( %g/ %G)' /etc/crontab /etc/cron.hourly/ /etc/cron.daily/ /etc/cron.weekly/ /etc/cron.monthly/ /etc/cron.yearly/ /etc/cron.d/`
  → line 1 `Access: (600/-rw-------) Uid: ( 0/ root) Gid: ( 0/ root)`, then six lines `Access: (700/drwx------) Uid: ( 0/ root) Gid: ( 0/ root)`
- GA2 (if A2): `dpkg-statoverride --list | grep -E ' /etc/cron(tab|\.(hourly|daily|weekly|monthly|yearly|d))$' | LC_ALL=C sort -k4`
  → `root root 700 /etc/cron.d`, `root root 700 /etc/cron.daily`, `root root 700 /etc/cron.hourly`, `root root 700 /etc/cron.monthly`, `root root 700 /etc/cron.weekly`, `root root 700 /etc/cron.yearly`, `root root 600 /etc/crontab` (7 lines)
- GA3: `systemctl is-active cron` → `active`
- GA4 (after the next `:17`): `journalctl -u cron --since "-65min" --no-pager | grep -c 'session opened for user root'` → `1` or more, and `journalctl -u cron --since "-65min" --no-pager | grep -ciE 'WRONG|INSECURE|ORPHAN|error'` → `0`

### Group B (2.4.1.9)
- GB1: `stat -Lc 'Access: (%a/%A) Owner: (%U) Group: (%G)' /etc/cron.allow` → `Access: (640/-rw-r-----) Owner: (root) Group: (crontab)`
- GB2: `test -e /etc/cron.deny; echo $?` → `1`
- GB3: `crontab -l; echo rc=$?` → `You (aj) are not allowed to use this program (crontab)` / `See crontab(1) for more information` / `rc=1` (if Q2 = list `aj`: `no crontab for aj` / `rc=1`)
- GB4 **(sudo, read-only)**: `sudo crontab -l -u root; echo rc=$?` → `no crontab for root` / `rc=1` (proves root is still allowed)
- GB5 **(sudo, read-only)**: `sudo wc -c /etc/cron.allow` → `0 /etc/cron.allow` (Q2 = list `aj`: `3 /etc/cron.allow`)

### Group C (1.6.6)
- GC1 (CIS audit, p. 235): `stat -Lc 'File: %n Access: (%a/%A) Uid: ( %u/ %U) Gid: ( %g/ %G)' /etc/motd /run/motd /usr/lib/motd /etc/motd.d/* /run/motd.d/* /usr/lib/motd.d/* /etc/update-motd.d/* 2>/dev/null | grep -vc 'Access: (644/-rw-r--r--) Uid: ( 0/ root) Gid: ( 0/ root)'` → `0`
- GC2: the same `stat` line piped to `wc -l` → `14` (13 if fwupd has removed `/run/motd.d/85-fwupd`)
- GC3: `run-parts --lsbsysinit --test /etc/update-motd.d; echo rc=$?` → only `rc=0`
- GC4 (if C2): `dpkg-statoverride --list | grep -cE '^root root 644 (/etc/update-motd\.d/|/usr/share/landscape/landscape-sysinfo\.wrapper$)'` → `13`
- GC5 (if C3): `systemctl is-enabled motd-news.timer` → `disabled`
- GC6 (after a fresh interactive SSH login): `stat -c %s /run/motd.dynamic` → `0`

### Group D (6.1.3.1)
- GD1: `grep -n 'create' /etc/logrotate.d/dpkg /etc/logrotate.d/alternatives /etc/logrotate.d/ubuntu-pro-client` → `/etc/logrotate.d/dpkg:8:	create 640 root root`, `/etc/logrotate.d/alternatives:8:	create 640 root root`, `/etc/logrotate.d/ubuntu-pro-client:5:    create 0640 root root` (exactly 3 lines)
- GD2: `grep -n '^UMASK' /etc/sysstat/sysstat` → `44:UMASK=0027`
- GD3 **(sudo, read-only)**: `sudo dpkg --verify dpkg ubuntu-pro-client sysstat` → exactly these 4 lines, in any order: `??5?????? c /etc/logrotate.d/alternatives`, `??5?????? c /etc/logrotate.d/dpkg`, `??5?????? c /etc/logrotate.d/ubuntu-pro-client`, `??5?????? c /etc/sysstat/sysstat`
- GD4 **(sudo, read-only)**: `sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c '^error'` → `0`
- GD5 **(sudo, read-only)**: `sudo find -L /var/log -type f -perm /0137 -printf '%m %u:%g %p\n' | LC_ALL=C sort -k3` → only CIS-allowed paths: `/var/log/README`, `/var/log/apt/eipp.log.xz`, `/var/log/apt/history.log*`, `/var/log/btmp*`, `/var/log/lastlog`, `/var/log/wtmp`
- GD6, the rule verdict **(sudo, read-only; writes only the report file in ~)**: `sudo bash ~/cis-audit/cis-6-root.sh > ~/cis-audit/6-root-batch1.txt 2>&1`, then `sed -n '/^== 6.1.3.1/,/^== end/p' ~/cis-audit/6-root-batch1.txt` → exactly 2 lines: the `== 6.1.3.1 …` header and `== end`

### Release gate (Governance re-audit; all must pass)
Governance re-runs its CIS audit for 1.6.6, 2.4.1.2–2.4.1.9 and 6.1.3.1. The verdict is PASS for all 10 rules, and no rule that passed in `docs/cis-26.04-l1-results.csv` now fails (in particular 1.6.1–1.6.5, 1.6.7–1.6.12, 2.4.1.1, 6.1.1.1.4). GS1–GS5 must pass after the last group.

### Durability (recurring)
- GR1 (after 00:10 UTC the day after D, and after any `apt install`): `find /var/log/sysstat -type f -perm /0137` → nothing
- GR2 (after 2026-12-01 01:00 UTC rotation): `find /var/log/dpkg.log* /var/log/alternatives.log* /var/log/unattended-upgrades -type f -perm /0137` → nothing. Also rerun GC1 → `0` after any `apt install`
- GR3 (weekly; F4) **(sudo, read-only)**: `sudo grep -h 'conffile prompt' /var/log/unattended-upgrades/unattended-upgrades.log` → nothing. Any line names a package AJ must upgrade by hand.

## Sources
- CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0, printed pp. 235–236 (1.6.6), 374–386 (2.4.1.2–8), 388–391 (2.4.1.9), 808–812 (6.1.3.1). Local PDF.
- dpkg 1.23.7 source: https://salsa.debian.org/dpkg-team/dpkg/-/raw/1.23.7/src/main/archives.c, https://salsa.debian.org/dpkg-team/dpkg/-/raw/1.23.7/src/main/configure.c, https://salsa.debian.org/dpkg-team/dpkg/-/raw/1.23.7/src/main/verify.c, https://salsa.debian.org/dpkg-team/dpkg/-/raw/1.23.7/src/statoverride/main.c
- dpkg-statoverride(1), dpkg 1.23.7ubuntu1: https://manpages.ubuntu.com/manpages/resolute/en/man1/dpkg-statoverride.1.html
- logrotate(8), 3.22.0-1build1: https://manpages.ubuntu.com/manpages/resolute/en/man8/logrotate.8.html
- sysstat(5), 12.7.7-0ubuntu2: https://manpages.ubuntu.com/manpages/resolute/en/man5/sysstat.5.html
- Live Johnny files read (no sudo): `/usr/bin/unattended-upgrade` (2.12ubuntu9), `/usr/libexec/sysstat/sa1`, `sa2`, `/var/lib/dpkg/info/{base-files,landscape-common,sysstat,cron,cron-daemon-common}.postinst`, `/usr/share/man/man1/crontab.1.gz`, systemd units `cron`, `motd-news`, `sysstat-*`.

## Assumptions (marked)
- **[Assumption]** F1's extra `dpkg --verify` line comes from reading the source, not from a run. No packaged file under a non-traversable directory exists on Johnny to test with.
- **[Assumption]** GB4: root has no crontab today (the `aj` view cannot confirm this). If root has one, the expected output is its contents and rc 0, which also passes.
- **[Assumption]** GD5: `/var/log/chrony` and `/var/log/private` hold no files over 0640. Based on the 2026-10-31 root audit; `aj` cannot read them.

## Addendum: rev 2 spot-check (2026-11-02 CST; Johnny 2026-11-03 04:23 UTC)

**Final verdict: APPROVE.** Rev 2 fixes F1 and F3–F10 as requested. F2 was partly my error (below); Platform's change to the A3 check is correct and stays. Remaining items are Low and do not block showing AJ the blocks.

### F2 correction (Assurance root cause was wrong)
- Live, read-only: `journalctl -t CRON --since today` shows `(root) CMD (cd / && run-parts --report /etc/cron.hourly)` at 01:17, 02:17, 03:17 and 04:17 UTC. `/var/log/syslog` has the same lines. So cron **does** log CMD every hour. My statement that "Johnny's cron logs no CMD lines" was wrong.
- Real cause: the CMD line comes from a short-lived child (for example PID 34121, while the pam_unix lines come from 34119). `journalctl -u cron` filters by unit, and journald attributes that child to `cron.service` only sometimes: 1 of 5 runs today (04:17 only). This is **[Assumption]**: a race between the process exiting and journald reading its cgroup. It is consistent with the data, but I did not prove it. The `pam_unix(cron:session): session opened for user root` line appeared under `-u cron` at every :17 from 00:17 to 04:17.
- Result: rev 2's A3 (pam_unix line as the pass marker, CMD optional) is reliable. **Gate GA4 update (optional, stronger):** add `journalctl -t CRON --since "-65min" --no-pager | grep -c 'CMD (cd / && run-parts --report /etc/cron.hourly)'` → `1` or more. This proves the hourly job itself started, not just the PAM session.

### `root adm` blocks (D1-adm … D4-adm): checked, correct
- D1-adm sed patterns match the live bytes (`^Icreate 644 root root$`, `    create 0644 root root$`). D4-adm reverses them to the original bytes, so `sudo dpkg --verify` prints nothing after the rollback.
- D2-adm glob `unattended-upgrades.log*` does not match `unattended-upgrades-dpkg.log*`, which is already root:adm. D4-adm leaves that file root:adm, as read. CIS catch-all allows group adm (pp. 808/811).
- `ubuntu-pro-client` has `su root root`. logrotate still runs with euid 0, so `create 0640 root adm` can set the group.
- Info (L-A1): the ubuntu-pro-client stanza globs `/var/log/ubuntu-advantage*.log`. Only `ubuntu-advantage-apt-hook.log` exists today. If the pro client later creates `ubuntu-advantage.log` (0640 root:root), its first rotation makes it root:adm, readable by adm. This is CIS-compliant, but AJ should know it if choosing Q4 = adm.
- The D3-adm stat check (`640 root:adm` on every line) is a correct gate for the adm option.

### Other rev 2 checks
- F1: D3/D4 now use `sudo dpkg --verify`. F6, F7 and F8 (D0 baseline) are as requested. GR1–GR3 match the gates above.
- L-A2 (Low, formatting): change-log table row "Assumption 1" (line 23) has the old Status sentence ("AJ runs every `sudo` line … rev 16") pasted into its third cell. Move that sentence back under **Status**.

### Gate updates
- GA4: keep as written; optionally add the `-t CRON` CMD check above.
- GD1/GD3 for Q4 = adm: expected `create 640 root adm` ×2 and `create 0640 root adm`; plus rev 2's D3-adm stat check → every line `640 root:adm`.
- Everything else is unchanged.
