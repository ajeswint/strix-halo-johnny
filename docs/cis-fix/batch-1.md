# CIS L1 fix pass, Batch 1: file modes (no lockout risk)

**Status:** DRAFT rev 2 (Platform, 2026-11-02). Nothing below has run on Johnny. Assurance reviewed rev 1 and approved it with changes (`docs/findings/cis-batch-1-review.md`); rev 2 makes those changes. Next: the Brain shows AJ each block.

### Change log (rev 2, Assurance findings)
| # | Change in this doc |
|---|---|
| F1 | D3 and D4 now run `sudo dpkg --verify` (read-only). As `aj`, dpkg cannot `lstat` `/etc/cron.daily/dpkg` once Group A makes the directory 0700, so the non-root command would print an extra `missing … (Permission denied)` line. |
| F2 | A3: the expected journal marker is now the `pam_unix(cron:session): session opened for user root` line at `:17:01`, plus a count of 0 for WRONG/INSECURE/ORPHAN/error. Note: a fresh read at 04:20 UTC showed cron did log `(root) CMD (cd / && run-parts --report /etc/cron.hourly)` at 04:17:01, while Assurance found none at 02:17 and 03:17. CMD lines are therefore treated as optional, not as the pass marker. |
| F3 | Added the full `root adm` variant for Open Q4: D1-adm, an extra group step in D2, D3-adm expected output and D4-adm rollback. |
| F4 | Residuals: added check GR3, weekly with sudo, read-only. It is needed because Group C removes the `92-unattended-upgrades` login notice and Group D makes the uu log unreadable to `aj`. |
| F5 | A2 text and Assumption 2: dpkg leaves an existing directory's mode alone on upgrade (Assurance read of dpkg 1.23.7 `archives.c`). The six directory overrides are defense in depth only. The `/etc/crontab` override does protect against upgrades. |
| F6 | C4 expected: `Access: (644/-rw-r--r--)` (stat prints 644, not 0644). |
| F7 | B2 expected: two lines plus rc 1. |
| F8 | New D0: logrotate warning/error baseline count before D1, compared in D3. |
| F9 | Risk line: added `sar` as `aj` and the unattended-upgrades logs as lost read access. |
| F10 | Residuals: added the GR1/GR2 recurring checks after any `apt install`. |
| Assumption 1 | Now marked confirmed from dpkg source by Assurance (C6); still not tested by a real upgrade. | AJ runs every `sudo` line in their own SSH session with a second session open (fix gate met, handoff rev 16).

**Rules (10):** 2.4.1.2–2.4.1.8 (cron files and directories), 2.4.1.9 (`/etc/cron.allow`), 1.6.6 (`/etc/update-motd.d`), 6.1.3.1 (`/var/log` file modes, fixed at the writers).

**Benchmark:** CIS Ubuntu Linux 26.04 LTS v1.0.0 (`docs/CIS_Ubuntu_Linux_26.04_LTS_Benchmark_v1.0.0.pdf`, local only). Page numbers are the printed page numbers (PDF page index = printed + 1). The repo's `.gitignore` keeps CIS text local-only (licensed), so this doc quotes only the short remediation command lines. Longer CIS scripts are summarized with a page reference.

**Risk:** no SSH, PAM, sudo, firewall, GRUB, Secure Boot or PCR 7 effect, and no reboot. Visible effects: the login message goes away (1.6.6), `aj` loses `crontab` (2.4.1.9; `aj` has no crontab today), and `aj` can no longer read about 30 log files without sudo (6.1.3.1). These include `dpkg.log` and `alternatives.log`, and the `unattended-upgrades` logs, which `aj` reads today through group adm. Running `sar` as `aj` can no longer read `/var/log/sysstat/sa*` (use `sudo sar`). The Open Q4 `root adm` option keeps the dpkg, alternatives, apt-hook and uu logs readable through adm. sysstat files stay root:root 0640 under either option.

**Order AJ runs them:** Group A, then B, C, D. Each group has its own blocks: commands, durability (where relevant), verification (read-only) and rollback.

---

## Live state read (read-only, `ssh aj@192.168.50.152`, no sudo)

Read 2026-11-03 04:01:07–04:05:21 UTC on Johnny's clock (Johnny is `Etc/UTC`; this is 2026-11-02 22:01 CST). Host `johnny`, kernel 7.0.0-42-generic. Raw output was read in the session and not saved. The findings that matter are below.

- **Compared with the audit (2026-10-30/31):** cron and motd are the same as audited. `/var/log` has grown from 19 to 30 files over 0640. The monthly rotation on 2026-11-01 added `alternatives.log.1`, `dpkg.log.1` and the `unattended-upgrades/*.gz` files, and sysstat has rolled into November (`sa01`–`sa03`, `sar01`, `sar02`). Every writer and its mode is the same as audited.
- **Package versions now:** cron / cron-daemon-common 3.0pl1-200ubuntu1, dpkg 1.23.7ubuntu1, logrotate 3.22.0-1build1, sysstat 12.7.7-0ubuntu2, ubuntu-pro-client 38ubuntu0~26.04, unattended-upgrades 2.12ubuntu9, base-files 14ubuntu6.2, landscape-common 26.02.2-0ubuntu1. `dpkg --verify` on dpkg, ubuntu-pro-client, sysstat, cron-daemon-common, base-files and landscape-common is clean: no local edits yet.
- **Existing dpkg stat overrides:** `/etc/chrony/chrony.keys`, `/usr/bin/crontab` (root crontab 2755), `/var/lib/chrony`, `/usr/lib/dbus-1.0/dbus-daemon-launch-helper`, `/var/log/chrony`. None of these clash with the paths in this batch.

---

## Group A: 2.4.1.2–2.4.1.8, cron file and directories

### Live state (2026-11-03 04:01 UTC)
| Path | Mode | Owner | Package (`dpkg -S`) | Contents |
|---|---|---|---|---|
| `/etc/crontab` | 644 | root:root | cron-daemon-common (conffile) | |
| `/etc/cron.hourly` | 755 | root:root | cron-daemon-common | `.placeholder` |
| `/etc/cron.daily` | 755 | root:root | man-db, logrotate, dpkg, cron-daemon-common, apt, apport | apport, apt-compat, dpkg, logrotate, man-db |
| `/etc/cron.weekly` | 755 | root:root | man-db, cron-daemon-common | man-db |
| `/etc/cron.monthly` | 755 | root:root | cron-daemon-common | `.placeholder` |
| `/etc/cron.yearly` | 755 | root:root | cron-daemon-common | `.placeholder` (exists, so 2.4.1.7 applies) |
| `/etc/cron.d` | 755 | root:root | e2fsprogs, cron-daemon-common | e2scrub_all |

`cron.service` is enabled and active, so the "IF cron is installed" condition holds. `systemd-cron` is not installed.

### CIS remediation (quoted)
- 2.4.1.2, p. 374: `# chown root:root /etc/crontab` / `# chmod og-rwx /etc/crontab`
- 2.4.1.3, p. 376: `# chown root:root /etc/cron.hourly/` / `# chmod og-rwx /etc/cron.hourly/`
- 2.4.1.4, p. 378: the same, for `/etc/cron.daily/`
- 2.4.1.5, p. 380: the same, for `/etc/cron.weekly/`
- 2.4.1.6, p. 382: the same, for `/etc/cron.monthly/`
- 2.4.1.7, p. 384: the same, for `/etc/cron.yearly/` (the audit note says a missing directory also passes)
- 2.4.1.8, p. 386: the same, for `/etc/cron.d/`

Result: `/etc/crontab` becomes 600 and the directories become 700. cron runs as root, so the jobs still run. The audit's expected output is `Access: (600/-rw-------)` and `(700/drwx------)` (pp. 374–386).

### A1. Commands (CIS as written)
```
sudo chown root:root /etc/crontab
sudo chmod og-rwx /etc/crontab
sudo chown root:root /etc/cron.hourly/
sudo chmod og-rwx /etc/cron.hourly/
sudo chown root:root /etc/cron.daily/
sudo chmod og-rwx /etc/cron.daily/
sudo chown root:root /etc/cron.weekly/
sudo chmod og-rwx /etc/cron.weekly/
sudo chown root:root /etc/cron.monthly/
sudo chmod og-rwx /etc/cron.monthly/
sudo chown root:root /etc/cron.yearly/
sudo chmod og-rwx /etc/cron.yearly/
sudo chown root:root /etc/cron.d/
sudo chmod og-rwx /etc/cron.d/
```

### A2. Durability (Platform recommendation; AJ decides, see Open Q1)
All seven paths belong to packages, and `/etc/crontab` is a conffile. A dpkg stat override tells dpkg to apply this owner and mode every time it installs the path. For **`/etc/crontab` this protects against upgrades**: when cron-daemon-common ships a new version of the conffile, dpkg writes it with the override mode (Assurance C6, dpkg 1.23.7 `archives.c` / `configure.c`). For the **six directories it is defense in depth only**: dpkg does nothing to a directory that already exists (`archives.c`, `TAR_FILETYPE_DIR` → `existingdir` → return before `tarobject_set_perms()`; Assurance F5), and no postinst on Johnny chmods them. The directory overrides matter only if a directory is removed and recreated. The resolute man page says an override "applies to any filesystem object that dpkg handles, including directories", and `--update` sets it immediately (https://manpages.ubuntu.com/manpages/resolute/en/man1/dpkg-statoverride.1.html, dpkg 1.23.7ubuntu1). Johnny already uses a directory override (`/var/lib/chrony`).
```
sudo dpkg-statoverride --update --add root root 0600 /etc/crontab
sudo dpkg-statoverride --update --add root root 0700 /etc/cron.hourly
sudo dpkg-statoverride --update --add root root 0700 /etc/cron.daily
sudo dpkg-statoverride --update --add root root 0700 /etc/cron.weekly
sudo dpkg-statoverride --update --add root root 0700 /etc/cron.monthly
sudo dpkg-statoverride --update --add root root 0700 /etc/cron.yearly
sudo dpkg-statoverride --update --add root root 0700 /etc/cron.d
```

### A3. Verification (read-only, no sudo)
```
stat -Lc '%n Access: (%a/%A) Uid: ( %u/ %U) Gid: ( %g/ %G)' /etc/crontab /etc/cron.hourly/ /etc/cron.daily/ /etc/cron.weekly/ /etc/cron.monthly/ /etc/cron.yearly/ /etc/cron.d/
dpkg-statoverride --list | grep cron
systemctl is-active cron
```
Expected: `/etc/crontab` shows 600 and the six directories show 700, all 0/root. After A2 the list shows seven new `root root` lines plus the existing `/usr/bin/crontab` line. cron is `active`.

After the next `:17` past the hour (the stock `/etc/crontab` hourly line), run:
```
journalctl -u cron --since "-65min" --no-pager | grep -c 'session opened for user root'
journalctl -u cron --since "-65min" --no-pager | grep -ciE 'WRONG|INSECURE|ORPHAN|error'
```
Expected: line 1 prints `1` or more (the line looks like `CRON[…]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)` at `:17:01`). Line 2 prints `0`. A `(root) CMD (cd / && run-parts --report /etc/cron.hourly)` line may also appear (it did at 04:17 UTC on 2026-11-03), but it is not the pass marker.

### A4. Rollback
```
sudo dpkg-statoverride --remove /etc/crontab
sudo dpkg-statoverride --remove /etc/cron.hourly
sudo dpkg-statoverride --remove /etc/cron.daily
sudo dpkg-statoverride --remove /etc/cron.weekly
sudo dpkg-statoverride --remove /etc/cron.monthly
sudo dpkg-statoverride --remove /etc/cron.yearly
sudo dpkg-statoverride --remove /etc/cron.d
sudo chmod 0644 /etc/crontab
sudo chmod 0755 /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.yearly /etc/cron.d
```
If A2 was skipped, the `--remove` lines only print a "no override present" warning, which does no harm.

---

## Group B: 2.4.1.9, `/etc/cron.allow`

### Live state (2026-11-03 04:01 UTC)
- `/etc/cron.allow` and `/etc/cron.deny` are both missing.
- Group `crontab` exists (gid 987). `/usr/bin/crontab` is 2755 root:crontab (setgid crontab, a dpkg stat override). `/var/spool/cron/crontabs` is 1730 root:crontab.
- `crontab -l` as `aj` returns `no crontab for aj` (rc 1). `aj` has no crontab.
- Login accounts: root (uid 0) and aj (uid 1000). `nobody` uses nologin.

### CIS remediation (summarized; p. 390)
The script creates `/etc/cron.allow` if it is missing (`touch`) and runs `chmod u-x,g-wx,o-rwx`. It runs `chown root:crontab` if a `crontab` group exists in `/etc/group`, and `chown root:root` otherwise. A second script fixes `/etc/cron.deny` only if that file exists. The script leaves the file **empty**. Audit (p. 389): the file exists with mode 640 or stricter, owner root, group root **or** crontab.

On Johnny the `crontab` group exists, so the script as written produces **root:crontab 0640**, not root:root. This is also the only working form. Description, p. 388, and cron's own `crontab(1)` on Johnny (cron 3.0pl1-200ubuntu1, `/usr/share/man/man1/crontab.1.gz`) both say the file must be "either world-readable, or readable by group crontab". If it is not, cron "will deny access to all users". root:root 0640 would lock `crontab` out for every non-root user, whatever the file lists. root is always allowed (CIS p. 391; crontab(1)). `/etc/cron.deny` is missing, so the second script does nothing.

**Minimal compliant content: an empty file.** Only root can use `crontab`. Root's crontab, `/etc/crontab` and `/etc/cron.d` keep working, because the allow list only gates the `crontab` command (CIS p. 388 Note). `aj` has no crontab today, so nothing breaks. Whether `aj` should be listed is AJ's call (Open Q2). Platform recommends leaving it empty, per the rationale on p. 389 ("only the system administrator is authorized").

### B1. Commands (the CIS script's actions on Johnny)
```
getent group crontab
sudo touch /etc/cron.allow
sudo chmod u-x,g-wx,o-rwx /etc/cron.allow
sudo chown root:crontab /etc/cron.allow
```
Line 1 is read-only. It must print `crontab:x:987:` before the rest runs. If it prints nothing, stop and tell the Brain: the script's root:root branch would apply instead.

`/etc/cron.allow` belongs to no package, so it needs no dpkg override.

### B2. Verification (read-only, no sudo)
```
stat -Lc 'Access: (%a/%A) Owner: (%U) Group: (%G)' /etc/cron.allow
[ -e "/etc/cron.deny" ] && stat -Lc 'Access: (%a/%A) Owner: (%U) Group: (%G)' /etc/cron.deny
wc -c /etc/cron.allow
crontab -l
```
Expected:
- Line 1: `Access: (640/-rw-r-----) Owner: (root) Group: (crontab)`.
- Line 2: prints nothing (no cron.deny).
- Line 3: `wc` cannot open the file as `aj` (Permission denied). That is expected at 0640 root:crontab, and it shows `aj` has no direct read. To see the content, use `sudo wc -c /etc/cron.allow`, which should print `0 /etc/cron.allow`.
- Line 4: two lines, `You (aj) are not allowed to use this program (crontab)` and `See crontab(1) for more information`, exit status 1. This proves the allow list is in force. If AJ chose to list `aj` (Open Q2), it prints `no crontab for aj` instead.

### B3. Rollback
```
sudo rm /etc/cron.allow
```

---

## Group C: 1.6.6, `/etc/update-motd.d` scripts

### Live state (2026-11-03 04:01 UTC)
- `/etc/motd`, `/run/motd` and `/usr/lib/motd` are missing. `/run/motd.d/85-fwupd` is 644 root:root (passes). `/etc/motd.d` and `/usr/lib/motd.d` are missing.
- All 13 entries in `/etc/update-motd.d/` are 755 root:root, all conffiles except the landscape link. The CIS audit uses `stat -L`, so for `50-landscape-sysinfo` (a symlink) it measures the target, `/usr/share/landscape/landscape-sysinfo.wrapper` (755 root:root, a landscape-common package file).
- How the message is built: `/etc/pam.d/sshd` and `/etc/pam.d/login` call `pam_motd.so motd=/run/motd.dynamic` and `pam_motd.so noupdate`. `sshd_config` has `PrintMotd no`. pam_motd runs only the **executable** scripts, as root, at each login, in run-parts order (update-motd(5), https://manpages.ubuntu.com/manpages/resolute/en/man5/update-motd.5.html, libpam-runtime 1.7.0-5ubuntu3.2). Clearing the execute bit therefore removes that script's output from the login message.

### What AJ loses at login (every script is disabled; CIS's remediation is `chmod u-x,go-wx`, so none stay)
| Script | Package (conffile md5 recorded) | What it shows today |
|---|---|---|
| `00-header` | base-files | `Welcome to Ubuntu 26.04.1 LTS (GNU/Linux 7.0.0-42-generic x86_64)` |
| `10-help-text` | base-files | Documentation / Management / Support links (docs.ubuntu.com, landscape.canonical.com, ubuntu.com/pro) |
| `50-landscape-sysinfo` → `/usr/share/landscape/landscape-sysinfo.wrapper` | landscape-common (link made by its postinst; debconf `landscape-common/sysinfo` = "Cache sysinfo in /etc/motd") | "System information as of …": load, disk use of `/`, memory, swap, temperature, process count, users logged in, IPv4 for eno3 |
| `50-motd-news` | base-files | Canonical news from `/var/cache/motd-news` (today: the "Canonical Workshop" ad). `/etc/default/motd-news` `ENABLED=1` |
| `85-fwupd` | fwupd | Firmware update notices from `/run/motd.d/85-fwupd` (empty today) |
| `90-updates-available` | update-notifier-common | The ESM Apps notice, `0 updates can be applied immediately.`, "Enable ESM Apps…" (from `/var/lib/update-notifier/updates-available`) |
| `91-contract-ua-esm-status` | ubuntu-pro-client | Pro contract or auto-attach status (stamp files missing today, so it shows nothing) |
| `91-release-upgrade` | ubuntu-release-upgrader-core | New-release notice, root logins only |
| `92-unattended-upgrades` | unattended-upgrades | "N updates could not be installed automatically…" when `/var/lib/unattended-upgrades/kept-back` exists |
| `95-hwe-eol` | update-notifier-common | HWE end-of-life warning (stamp missing today, so nothing) |
| `97-overlayroot` | overlayroot | overlayroot mounts (none; prints a blank line) |
| `98-fsck-at-reboot` | update-notifier-common | "*** … will be checked for errors at next reboot ***" when due |
| `98-reboot-required` | update-notifier-common | `*** System restart required ***` when `/run/reboot-required` exists (missing today) |

After the change, an SSH login shows no dynamic message. The one that matters most is **98-reboot-required**: `Automatic-Reboot "false"` is set, so AJ has to check by hand after unattended upgrades with `cat /run/reboot-required /run/reboot-required.pkgs` (read-only, no sudo). The banner text for 1.6.2–1.6.4 is Batch 5 and AJ's wording, not this batch.

### CIS remediation (quoted, p. 235)
`# chown root:root </path/to/motd/file>` / `# chmod u-x,go-wx </path/to/motd/file>`. The example uses `$(readlink -e /etc/motd)`, i.e. it resolves symlinks. For `50-landscape-sysinfo` that means the target `/usr/share/landscape/landscape-sysinfo.wrapper`. The "OR remove" option on p. 235–236 applies only to `/etc/motd`, which is already missing.

### C1. Commands (CIS as written; the wrapper path is `readlink -e /etc/update-motd.d/50-landscape-sysinfo`, written out)
```
sudo chown root:root /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news /etc/update-motd.d/85-fwupd /etc/update-motd.d/90-updates-available /etc/update-motd.d/91-contract-ua-esm-status /etc/update-motd.d/91-release-upgrade /etc/update-motd.d/92-unattended-upgrades /etc/update-motd.d/95-hwe-eol /etc/update-motd.d/97-overlayroot /etc/update-motd.d/98-fsck-at-reboot /etc/update-motd.d/98-reboot-required /usr/share/landscape/landscape-sysinfo.wrapper
sudo chmod u-x,go-wx /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news /etc/update-motd.d/85-fwupd /etc/update-motd.d/90-updates-available /etc/update-motd.d/91-contract-ua-esm-status /etc/update-motd.d/91-release-upgrade /etc/update-motd.d/92-unattended-upgrades /etc/update-motd.d/95-hwe-eol /etc/update-motd.d/97-overlayroot /etc/update-motd.d/98-fsck-at-reboot /etc/update-motd.d/98-reboot-required /usr/share/landscape/landscape-sysinfo.wrapper
```
Result: 0644 root:root on all 13 files (0755 with `u-x,go-wx` removed is 0644).

### C2. Durability (Platform recommendation; AJ decides, see Open Q1)
**Do package upgrades put the mode back? Yes.** When one of these packages installs a new version of a script or the wrapper, dpkg writes the packaged mode (0755). Conffile change detection compares content (md5), not mode, so a mode-only change raises no conffile prompt and does not protect the file. A stat override makes dpkg install the file at 0644 every time (https://manpages.ubuntu.com/manpages/resolute/en/man1/dpkg-statoverride.1.html: "any filesystem object that dpkg handles"). The landscape-common postinst re-runs `ln -sf` on the link on each configure (read on Johnny, `/var/lib/dpkg/info/landscape-common.postinst` line 92). That does not change the wrapper's mode. The override goes on the wrapper path because a dpkg override acts on the installed file, not the link.
```
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/00-header
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/10-help-text
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/50-motd-news
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/85-fwupd
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/90-updates-available
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/91-contract-ua-esm-status
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/91-release-upgrade
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/92-unattended-upgrades
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/95-hwe-eol
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/97-overlayroot
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/98-fsck-at-reboot
sudo dpkg-statoverride --update --add root root 0644 /etc/update-motd.d/98-reboot-required
sudo dpkg-statoverride --update --add root root 0644 /usr/share/landscape/landscape-sysinfo.wrapper
```

### C3. Side effect: `motd-news.service` (AJ decides, see Open Q3)
`motd-news.service` runs `ExecStart=/etc/update-motd.d/50-motd-news --force` (read on Johnny, `/usr/lib/systemd/system/motd-news.service`), driven by `motd-news.timer` about twice a day. Once that file is 0644, every run fails (exec permission denied), leaving a failed unit. No other unit or cron job calls `/etc/update-motd.d/` (grep on Johnny of `/usr/lib/systemd/system`, `/etc/systemd/system`, `/etc/cron*` and `/etc/apt/apt.conf.d`). `update-notifier-motd.timer` runs `/usr/lib/ubuntu-release-upgrader/release-upgrade-motd` and is not affected (it is rule 1.6.12, Batch 5). Option (Platform recommendation): stop the timer now, since the job it drives can no longer run. motd-news.timer is not a CIS rule in any batch, so this is AJ's call. CIS 1.6.11 (pp. 245–246) notes that motd-news calls out to motd.ubuntu.com.
```
sudo systemctl disable --now motd-news.timer
```
Rollback: `sudo systemctl enable --now motd-news.timer`

### C4. Verification (read-only, no sudo)
```
stat -Lc 'File: %n Access: (%a/%A) Uid: ( %u/ %U) Gid: ( %g/ %G)' /etc/motd /run/motd /usr/lib/motd /etc/motd.d/* /run/motd.d/* /usr/lib/motd.d/* /etc/update-motd.d/* 2>/dev/null
run-parts --lsbsysinit --test /etc/update-motd.d
dpkg-statoverride --list | grep -E 'update-motd|landscape-sysinfo'
systemctl is-enabled motd-news.timer
systemctl --failed --no-pager
```
Expected:
- Line 1: every entry `Access: (644/-rw-r--r--) Uid: ( 0/ root) Gid: ( 0/ root)` (the CIS audit command, p. 235; `%a` prints 644, not 0644).
- `run-parts --test`: prints nothing (no executable scripts left).
- After C2: 13 override lines.
- After C3: `disabled`. Without C3, `motd-news.service` turns up in `--failed` after its next run.
- A new SSH login shows no "Welcome to Ubuntu…" block.

### C5. Rollback
```
sudo dpkg-statoverride --remove /etc/update-motd.d/00-header
sudo dpkg-statoverride --remove /etc/update-motd.d/10-help-text
sudo dpkg-statoverride --remove /etc/update-motd.d/50-motd-news
sudo dpkg-statoverride --remove /etc/update-motd.d/85-fwupd
sudo dpkg-statoverride --remove /etc/update-motd.d/90-updates-available
sudo dpkg-statoverride --remove /etc/update-motd.d/91-contract-ua-esm-status
sudo dpkg-statoverride --remove /etc/update-motd.d/91-release-upgrade
sudo dpkg-statoverride --remove /etc/update-motd.d/92-unattended-upgrades
sudo dpkg-statoverride --remove /etc/update-motd.d/95-hwe-eol
sudo dpkg-statoverride --remove /etc/update-motd.d/97-overlayroot
sudo dpkg-statoverride --remove /etc/update-motd.d/98-fsck-at-reboot
sudo dpkg-statoverride --remove /etc/update-motd.d/98-reboot-required
sudo dpkg-statoverride --remove /usr/share/landscape/landscape-sysinfo.wrapper
sudo chmod 0755 /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news /etc/update-motd.d/85-fwupd /etc/update-motd.d/90-updates-available /etc/update-motd.d/91-contract-ua-esm-status /etc/update-motd.d/91-release-upgrade /etc/update-motd.d/92-unattended-upgrades /etc/update-motd.d/95-hwe-eol /etc/update-motd.d/97-overlayroot /etc/update-motd.d/98-fsck-at-reboot /etc/update-motd.d/98-reboot-required /usr/share/landscape/landscape-sysinfo.wrapper
```

---

## Group D: 6.1.3.1, `/var/log` file modes, fixed at the writers

### Live state (2026-11-03 04:01:51 UTC; non-root `find -L /var/log -type f \( -perm /0137 -o ! -user root -o ! -group root \)`)
`aj` (in group adm) could not enter `/var/log/chrony` or `/var/log/private`. The root audit (`docs/cis-local/cis-6-root-out.txt`, 2026-10-31) flagged nothing there. The root re-audit after this batch covers them.

Files that fail CIS's catch-all mask (0137, i.e. 0640 or stricter); owners and groups all pass:
| File(s) | Mode, owner | Writer | What keeps the mode after the fix |
|---|---|---|---|
| `alternatives.log`, `alternatives.log.1` | 644 root:root | `update-alternatives` (dpkg); logrotate `/etc/logrotate.d/alternatives` has `create 644 root root` | edit the `create` line to 640 (conffile, dpkg) |
| `dpkg.log`, `dpkg.log.1` | 644 root:root | dpkg; logrotate `/etc/logrotate.d/dpkg` has `create 644 root root` | edit the `create` line to 640 (conffile, dpkg) |
| `ubuntu-advantage-apt-hook.log` (0 bytes) | 644 root:root | apt hook in `/etc/apt/apt.conf.d/20apt-esm-hook.conf` appends stderr with `2>>` (the shell creates the file only if it is missing); logrotate `/etc/logrotate.d/ubuntu-pro-client` has `create 0644 root root` | edit the `create` line to 0640 (conffile, ubuntu-pro-client). The pro client's own `ubuntu-advantage.log` is already created 0640 (`uaclient/log.py` line 144, `touch(mode=0o640)`) |
| `sysstat/sa01–03, sa29–31, sar01, sar02, sar29–31` | 644 root:root | `sa1`/`sadc` make a new `saDD` each day, and `sa2` writes `sarDD`. Both source `/etc/sysstat/sysstat`, which sets `UMASK=0022`, then run `umask ${UMASK}` (`/usr/libexec/sysstat/sa1` lines 16–21, `sa2` lines 17–24). sysstat rotates its own files (`sysstat-rotate.timer`), so it has no logrotate file | set `UMASK=0027` in `/etc/sysstat/sysstat` (conffile, sysstat). sysstat(5) for resolute: "use 0027 to adhere to more strict security standards" (https://manpages.ubuntu.com/manpages/resolute/en/man5/sysstat.5.html, 12.7.7-0ubuntu2) |
| `unattended-upgrades/unattended-upgrades.log`, `-shutdown.log`, `-dpkg.log` and their `.1.gz` | 644 (root:root; `-dpkg` root:adm) | Python `logging.basicConfig(filename=…)` creates a file only if it is missing (`/usr/bin/unattended-upgrade` lines 2097–2109; `unattended-upgrade-shutdown` line 406). The `-dpkg` log is created 0640 by `os.open` but first `open(…,'w')` at line 2542 | **no writer edit.** `/etc/logrotate.d/unattended-upgrades` has no `create` line, so the global `create` in `/etc/logrotate.conf` applies. With no attributes given, the new file copies the original's mode and owner (logrotate(8) resolute, https://manpages.ubuntu.com/manpages/resolute/en/man8/logrotate.8.html, 3.22.0-1build1). The one-time chmod therefore carries through each rotation. Residual: see below |
| `landscape/sysinfo.log` (0 bytes) | 644 root:root | `landscape-sysinfo` (run at login by `50-landscape-sysinfo`) through Python `RotatingFileHandler`, which rolls over at 500 KB and makes a new file under umask 022 (`landscape/sysinfo/deployment.py` lines 128–141). No logrotate file | once 1.6.6 (Group C) is in place, nothing runs it at login, so the one-time chmod holds. Residual: see below |
| `bootstrap.log`, `installer/casper-md5check.json`, `installer/curtin-install.log`, `installer/device-map.json`, `installer/block/discover.log`, `installer/block/probe-data.json` | 644 root:root | installer, written once (static) | the one-time chmod holds |
| `installer/media-info` | 444 root:root | installer (static) | the one-time chmod gives 440 |

Allowed by CIS's other branches, so left unchanged: `apt/eipp.log.xz`, `apt/history.log*` (644; apt branch mask 0133), `btmp*` (660), `lastlog` and `wtmp` (664; utmp branch 0113), `README` (644; 0113). Already 0640 or stricter: syslog, auth, kern, cloud-init, dmesg, apport, `apt/term.log*` and the journal files.

### CIS remediation (summarized; pp. 809–811)
1. **Immediate fix (pp. 809–811):** a script that walks `find -L /var/log -type f \( -perm /0137 -o ! -user root -o ! -group root \)` and removes extra permission bits per file class. For files like these (the catch-all `*)` branch) it runs `chmod u-x,g-wx,o-rwx` and fixes owner or group only where they fail (none do here). p. 811 says this alone does not last: "files re-created by their service or by log rotation revert to the service default mode".
2. **"Permanent fix" (p. 811):** (1) "logrotate create directive: … edit `/etc/logrotate.d/<service>` and set `create <mode> <user> <group>`". (2) "Application umask: for daemons that write logs outside the logrotate lifecycle, tighten the application's own umask". CIS's example (p. 811) edits `/usr/libexec/sysstat/sa1`. That is package code and would be overwritten on upgrade. On Ubuntu, sysstat reads its umask from the conffile `/etc/sysstat/sysstat` (see the table), so D1 sets it there instead. Same CIS fix, but it survives upgrades. CIS's `/etc/logrotate.d/sysstat` example (pp. 811–812) does not apply: Ubuntu's sysstat ships no logrotate file and rotates itself.

### D0. Baseline before D1 (read-only; F8)
```
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c '^error'
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -ciE '^error|warning'
```
Write down both numbers. D3 runs the same two lines and must print the same numbers (line 1 is expected to be `0`). Any warning that was there before the batch is not a regression.

### D1. Writers first (conffile edits; all four files are conffiles, md5 recorded by dpkg)
Default (Open Q4 = `root root`):
```
sudo sed -i 's/^\(\s*create\) 644 root root$/\1 640 root root/' /etc/logrotate.d/dpkg /etc/logrotate.d/alternatives
sudo sed -i 's/^\(\s*create\) 0644 root root$/\1 0640 root root/' /etc/logrotate.d/ubuntu-pro-client
sudo sed -i 's/^UMASK=0022$/UMASK=0027/' /etc/sysstat/sysstat
```
The patterns were checked against the live files with `cat -A`. dpkg and alternatives: line 8 `^Icreate 644 root root$`. ubuntu-pro-client: line 5 `    create 0644 root root$`. sysstat: line 44 `UMASK=0022$`. GNU `sed -i` keeps each file's mode and owner. Owner and group stay as the packages set them; only the mode changes.

**D1-adm (use instead of the block above only if Open Q4 = `root adm`):**
```
sudo sed -i 's/^\(\s*create\) 644 root root$/\1 640 root adm/' /etc/logrotate.d/dpkg /etc/logrotate.d/alternatives
sudo sed -i 's/^\(\s*create\) 0644 root root$/\1 0640 root adm/' /etc/logrotate.d/ubuntu-pro-client
sudo sed -i 's/^UMASK=0022$/UMASK=0027/' /etc/sysstat/sysstat
```
CIS allows group adm for these files (catch-all branch, pp. 808/811). sysstat stays root:root 0640 under both options, because sa1/sa2 run as root and the umask sets only the mode.

### D2. One-time fix of existing files (the CIS script's action on the current failing set)
Read-only preview first, so AJ sees what the globs match (the globs expand as root inside `sh -c`):
```
sudo sh -c 'ls -l /var/log/alternatives.log* /var/log/dpkg.log* /var/log/bootstrap.log /var/log/ubuntu-advantage-apt-hook.log /var/log/landscape/sysinfo.log /var/log/sysstat/sa* /var/log/unattended-upgrades/*.log* /var/log/installer/media-info /var/log/installer/casper-md5check.json /var/log/installer/curtin-install.log /var/log/installer/device-map.json /var/log/installer/block/discover.log /var/log/installer/block/probe-data.json'
```
Then (both options):
```
sudo sh -c 'chmod u-x,g-wx,o-rwx /var/log/alternatives.log* /var/log/dpkg.log* /var/log/bootstrap.log /var/log/ubuntu-advantage-apt-hook.log /var/log/landscape/sysinfo.log /var/log/sysstat/sa* /var/log/unattended-upgrades/*.log* /var/log/installer/media-info /var/log/installer/casper-md5check.json /var/log/installer/curtin-install.log /var/log/installer/device-map.json /var/log/installer/block/discover.log /var/log/installer/block/probe-data.json'
```
**D2-adm, only if Open Q4 = `root adm`, run after the chmod.** This sets the group on the files the writers will keep. The current files then match the D1-adm `create` lines, and the uu logs pick up adm through logrotate's global `create`, which copies the group. `unattended-upgrades-dpkg.log*` is already root:adm.
```
sudo sh -c 'chgrp adm /var/log/alternatives.log* /var/log/dpkg.log* /var/log/ubuntu-advantage-apt-hook.log /var/log/unattended-upgrades/unattended-upgrades.log* /var/log/unattended-upgrades/unattended-upgrades-shutdown.log*'
```

### D3. Verification (read-only; the `sudo` lines read only)
```
grep -n 'create' /etc/logrotate.d/dpkg /etc/logrotate.d/alternatives /etc/logrotate.d/ubuntu-pro-client
grep -n '^UMASK' /etc/sysstat/sysstat
sudo dpkg --verify dpkg ubuntu-pro-client sysstat
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -c '^error'
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -ciE '^error|warning'
sudo find -L /var/log -type f -perm /0137 -printf '%m %u:%g %p\n'
```
Expected (default `root root`):
- Line 1: exactly `/etc/logrotate.d/dpkg:8:	create 640 root root`, `/etc/logrotate.d/alternatives:8:	create 640 root root`, `/etc/logrotate.d/ubuntu-pro-client:5:    create 0640 root root`.
- Line 2: `44:UMASK=0027`.
- Line 3, which runs as root (F1): exactly 4 lines in any order: `??5?????? c /etc/logrotate.d/alternatives`, `??5?????? c /etc/logrotate.d/dpkg`, `??5?????? c /etc/logrotate.d/ubuntu-pro-client`, `??5?????? c /etc/sysstat/sysstat`. Each is a conffile changed on purpose, and the list is the record that these edits are local. Run without sudo after Group A, it would also print `missing   c /etc/cron.daily/dpkg (Permission denied)`, because `aj` cannot enter the 0700 directory. That line does not mean a problem.
- Lines 4–5: `logrotate -d` changes nothing ("no changes are made to the logs and the logrotate state file is not updated", logrotate(8)). Line 4 prints `0`. Line 5 prints the same number as in D0.
- Line 6: only the CIS-allowed files (`/var/log/README`, `apt/eipp.log.xz`, `apt/history.log*`, `btmp*`, `lastlog`, `wtmp`). The rule verdict comes from Governance's re-audit with `sudo bash ~/cis-audit/cis-6-root.sh > ~/cis-audit/6-root-batch1.txt 2>&1` (the script is already on Johnny).

Expected if D1-adm and D2-adm were used: line 1 reads `create 640 root adm` (twice) and `create 0640 root adm`. Lines 2–6 are as above. Add this check:
```
sudo sh -c 'stat -c "%a %U:%G %n" /var/log/alternatives.log* /var/log/dpkg.log* /var/log/ubuntu-advantage-apt-hook.log /var/log/unattended-upgrades/*.log*'
```
→ every line reads `640 root:adm`.

**Proof that the fix lasts, later (read-only, no sudo):**
- After 00:10 UTC tomorrow: `ls -l /var/log/sysstat | tail -4`. The new day's `saDD` and the newest `sarDD` should be `-rw-r-----`.
- After the monthly rotation on 2026-12-01: `ls -l /var/log/dpkg.log /var/log/alternatives.log /var/log/unattended-upgrades/` should show 0640.

### D4. Rollback
Default (`root root`):
```
sudo sed -i 's/^\(\s*create\) 640 root root$/\1 644 root root/' /etc/logrotate.d/dpkg /etc/logrotate.d/alternatives
sudo sed -i 's/^\(\s*create\) 0640 root root$/\1 0644 root root/' /etc/logrotate.d/ubuntu-pro-client
sudo sed -i 's/^UMASK=0027$/UMASK=0022/' /etc/sysstat/sysstat
sudo dpkg --verify dpkg ubuntu-pro-client sysstat
sudo sh -c 'chmod 0644 /var/log/alternatives.log* /var/log/dpkg.log* /var/log/bootstrap.log /var/log/ubuntu-advantage-apt-hook.log /var/log/landscape/sysinfo.log /var/log/sysstat/sa* /var/log/unattended-upgrades/*.log* /var/log/installer/casper-md5check.json /var/log/installer/curtin-install.log /var/log/installer/device-map.json /var/log/installer/block/discover.log /var/log/installer/block/probe-data.json; chmod 0444 /var/log/installer/media-info'
```
`sudo dpkg --verify` printing nothing confirms the three packages' conffiles match the package md5s again. It runs as root (F1), so the Group A `/etc/cron.daily` mode does not add a `Permission denied` line.

**D4-adm (if D1-adm and D2-adm were used):**
```
sudo sed -i 's/^\(\s*create\) 640 root adm$/\1 644 root root/' /etc/logrotate.d/dpkg /etc/logrotate.d/alternatives
sudo sed -i 's/^\(\s*create\) 0640 root adm$/\1 0644 root root/' /etc/logrotate.d/ubuntu-pro-client
sudo sed -i 's/^UMASK=0027$/UMASK=0022/' /etc/sysstat/sysstat
sudo dpkg --verify dpkg ubuntu-pro-client sysstat
sudo sh -c 'chgrp root /var/log/alternatives.log* /var/log/dpkg.log* /var/log/ubuntu-advantage-apt-hook.log /var/log/unattended-upgrades/unattended-upgrades.log* /var/log/unattended-upgrades/unattended-upgrades-shutdown.log*'
sudo sh -c 'chmod 0644 /var/log/alternatives.log* /var/log/dpkg.log* /var/log/bootstrap.log /var/log/ubuntu-advantage-apt-hook.log /var/log/landscape/sysinfo.log /var/log/sysstat/sa* /var/log/unattended-upgrades/*.log* /var/log/installer/casper-md5check.json /var/log/installer/curtin-install.log /var/log/installer/device-map.json /var/log/installer/block/discover.log /var/log/installer/block/probe-data.json; chmod 0444 /var/log/installer/media-info'
```
This restores the state read on 2026-11-03: `unattended-upgrades-dpkg.log*` stays root:adm, and the others go back to root:root.

### Residuals (writers that can't be fully pinned without package code; AJ to accept, Open Q5)
- **unattended-upgrades:** if one of its logs is deleted, uu recreates it at 0644 (Python logging under `apt-daily-upgrade.service`'s default umask 022). Pinning that needs a `UMask=0027` drop-in on `apt-daily-upgrade.service`, and every dpkg maintainer script run by unattended upgrades would inherit it. Not recommended. Normal rotation keeps 0640 (global `create`).
- **landscape-sysinfo:** if someone runs `landscape-sysinfo` by hand often enough to pass 500 KB, `RotatingFileHandler` starts a new 0644 file. That needs a package-code change. Unlikely once Group C is in.
- **dpkg / update-alternatives:** these recreate a missing log at 0644 (umask). Logrotate always recreates the file (`create`), so this only happens if someone deletes the log.
- **Conffile prompts:** the four D1 files are now locally modified conffiles. If a later dpkg, ubuntu-pro-client or sysstat update ships a changed version of one of them, unattended-upgrades will **skip that package** and log `Package … has conffile prompt and needs to be upgraded manually` (`/usr/bin/unattended-upgrade` 2.12ubuntu9 lines 1467–1567 and 2802–2816 on Johnny; the man page says it checks "for dpkg prompts about configuration file changes", https://manpages.ubuntu.com/manpages/resolute/en/man8/unattended-upgrade.8.html). The A2/C2 overrides do not cause this, because they change modes, not content. **This would be silent (F4):** Group C removes the `92-unattended-upgrades` login notice, and D2 makes `unattended-upgrades.log` 0640 root:root, so `aj` can no longer read it (unless Q4 = adm). A skipped security update to dpkg, ubuntu-pro-client or sysstat would show nowhere unless someone checks. Hence GR3 below.

### Recurring checks (for the handoff; F4, F10)
- **GR1**, after 00:10 UTC the day after Group D, and after any `apt install` (read-only, no sudo). This catches a new 0644 writer under sysstat:
```
find /var/log/sysstat -type f -perm /0137
```
→ prints nothing.
- **GR2**, after the 2026-12-01 01:00 UTC rotation, and after any `apt install`. Line 1 covers rotated logs; line 2 catches a new `/etc/update-motd.d/NN-*` script installed at 0755, which the C2 overrides cannot cover because they only know today's paths:
```
sudo find /var/log/dpkg.log* /var/log/alternatives.log* /var/log/unattended-upgrades -type f -perm /0137
stat -Lc 'File: %n Access: (%a/%A) Uid: ( %u/ %U) Gid: ( %g/ %G)' /etc/motd /run/motd /usr/lib/motd /etc/motd.d/* /run/motd.d/* /usr/lib/motd.d/* /etc/update-motd.d/* 2>/dev/null | grep -vc 'Access: (644/-rw-r--r--) Uid: ( 0/ root) Gid: ( 0/ root)'
```
→ line 1 prints nothing; line 2 prints `0`. A new 0755 script means: run C1's `chown`/`chmod` and C2's `dpkg-statoverride --update --add root root 0644` on that exact path (the Brain writes the exact command when it happens).
- **GR3**, weekly (sudo, read-only):
```
sudo grep -h 'conffile prompt' /var/log/unattended-upgrades/unattended-upgrades.log
```
→ prints nothing. Any line names a package AJ must upgrade by hand (keep the local conffile, then rerun D3 lines 1–3).

---

## Files to mirror under `etc/` (create after AJ applies, copied from the live files; same commit as the Config changes rows)
**Content changed or new (mirror these):**
- `etc/cron.allow` (new, empty; live mode 0640 root:crontab)
- `etc/logrotate.d/dpkg`
- `etc/logrotate.d/alternatives`
- `etc/logrotate.d/ubuntu-pro-client`
- `etc/sysstat/sysstat`

**Mode only, content unchanged (Brain decides; see Open Q6):** `/etc/crontab`, `/etc/cron.{hourly,daily,weekly,monthly,yearly,d}` (directories), and the 12 regular files in `/etc/update-motd.d/`. git stores only the execute bit and cannot store empty directories, so a repo copy cannot show these modes. Platform's proposal: one Config changes row per group that records the mode, and the output of `dpkg-statoverride --list` (the overrides live in `/var/lib/dpkg/statoverride`, not `/etc`). Outside `/etc`, nothing to mirror: `/usr/share/landscape/landscape-sysinfo.wrapper` (mode) and the motd-news timer state (C3).

**Proposed Config changes rows (Brain writes them into the handoff):** cron mode + overrides | rollback A4. `/etc/cron.allow` | `rm`. motd scripts 0644 + overrides (+ motd-news.timer if C3) | C5. logrotate `create` 640 ×3 (group per Q4) | D4 or D4-adm. `/etc/sysstat/sysstat` `UMASK=0027` | D4 sed. Also add the recurring checks GR1–GR3 to the handoff.

---

## Ubuntu 26.04 (resolute) sources checked 2026-11-02
- dpkg-statoverride(1), dpkg 1.23.7ubuntu1: https://manpages.ubuntu.com/manpages/resolute/en/man1/dpkg-statoverride.1.html
- update-motd(5), libpam-runtime 1.7.0-5ubuntu3.2: https://manpages.ubuntu.com/manpages/resolute/en/man5/update-motd.5.html
- logrotate(8), 3.22.0-1build1: https://manpages.ubuntu.com/manpages/resolute/en/man8/logrotate.8.html
- sysstat(5), 12.7.7-0ubuntu2: https://manpages.ubuntu.com/manpages/resolute/en/man5/sysstat.5.html
- unattended-upgrade(8), 2.12ubuntu9: https://manpages.ubuntu.com/manpages/resolute/en/man8/unattended-upgrade.8.html
- cron 3.0pl1-200ubuntu1: https://packages.ubuntu.com/resolute/cron. The resolute `crontab(1)` page on manpages.ubuntu.com is systemd-cron's, not cron's, so the cron.allow readability rule is cited from cron's installed man page on Johnny (`/usr/share/man/man1/crontab.1.gz`, owned by `cron`) and CIS p. 388.
- sysstat 12.7.7-0ubuntu2: https://packages.ubuntu.com/resolute/sysstat
- landscape-common 26.02.2-0ubuntu1: https://packages.ubuntu.com/resolute/landscape-common

## Assumptions (marked)
1. **[Assumption, confirmed from source]** dpkg applies a stat override when it replaces a **conffile** on upgrade. The man page says "any filesystem object that dpkg handles", and Assurance C6 read dpkg 1.23.7 `archives.c`/`configure.c`: perms are set on `.dpkg-new` before the conffile step, and `rename()` keeps them. Not yet tested by a real upgrade.
2. **[Refuted by Assurance F5]** The rev 1 assumption was that dpkg might reset an existing directory's mode on upgrade. It does not: `archives.c` returns early for an existing directory. The six A2 directory overrides are defense in depth only, for the case where a directory is removed and recreated. Whether to keep them stays AJ's call (Q1).
3. **[Assumption]** D2 (an explicit `chmod u-x,g-wx,o-rwx` on the listed files) does exactly what CIS's 6.1.3.1 script does on the current failing set. Every failing file falls in the catch-all branch, and no owner or group fails. If more files appear between now and the apply, the D3 `find` and Governance's re-audit will catch them.
4. **[Assumption]** The cron daemon does not read `/etc/cron.allow` when it runs `/etc/crontab` or `/etc/cron.d` jobs; the list gates only the `crontab` command (CIS p. 388 Note). Root's jobs are unaffected either way (root is always allowed).
5. **[Assumption]** Johnny's sysstat files are named by UTC day (timezone `Etc/UTC`), so the "tomorrow" check means after 00:10 UTC.
6. **[Assumption]** No other tool on Johnny reads `/etc/crontab` or the cron directories as a non-root user. None was found.

## Open questions for AJ
1. **Durability overrides (A2, C2):** apply the dpkg stat overrides? Platform recommends yes. The `/etc/crontab` and C2 (motd scripts and landscape wrapper) overrides stop package upgrades from putting back 644/755. Without them the rule fails again silently at the next upgrade of the owning package. The six A2 directory overrides are defense in depth only (F5), so AJ may skip those six lines and keep the `/etc/crontab` one.
2. **`/etc/cron.allow` content:** leave it empty (only root can use `crontab`; Platform's recommendation), or list `aj`? `aj` has no crontab today. To list `aj` instead of leaving it empty, run this after B1: `echo aj | sudo tee /etc/cron.allow` (the mode and owner stay).
3. **motd-news.timer (C3):** stop it now (Platform's recommendation; its job can't run after C1), or leave it and accept a failed `motd-news.service` until a later pass?
4. **Log group (D1):** keep `root root` 0640 (default blocks; `aj` needs sudo to read the dpkg, alternatives and unattended-upgrades logs), or use `root adm` 0640 (also CIS-compliant; `aj` reads them through group adm, which keeps GR3 runnable without sudo)? The `root adm` choice uses D1-adm, D2-adm, the D3-adm expected output and D4-adm.
5. **Residuals (Group D):** accept the four residuals listed? None can be pinned without package code, or without a umask change on `apt-daily-upgrade.service`, which is not recommended.
6. **Mode-only files and the mirror:** record mode-only changes as Config changes rows (plus `dpkg-statoverride --list`) instead of repo copies? Platform proposes the rows.
7. **Licensing:** this doc quotes only short CIS command lines and summarizes the scripts. Confirm that this level of quoting is fine in the tracked repo, or move the quotes to `docs/cis-local/`.
