# CIS L1 fix pass, Batch 9: PAM and password aging

**Status:** DRAFT rev 2 (Grok, 2026-11-04). A prior PASTE 1 hung in interactive `pam-auth-update` during `apt-get install` before the timer existed. Packages are installed. PAM is still stock `nullok`. This revision is the re-run.

**Rules in scope (24):** 5.3.1.3, 5.3.1.4, 5.3.2.2, 5.3.2.3, 5.3.2.4, 5.3.3.1.1, 5.3.3.1.2, 5.3.3.2.1, 5.3.3.2.2, 5.3.3.2.3, 5.3.3.2.4, 5.3.3.2.5, 5.3.3.2.6, 5.3.3.2.7, 5.3.3.2.8, 5.3.3.3.1, 5.3.3.3.2, 5.3.3.3.3, 5.3.3.4.1, 5.3.3.4.4, 5.4.1.1, 5.4.1.5, 5.4.3.2, 5.4.3.3.

**Not in this batch:** 1.4.1 bootloader, 6.1.2.5 rsyslog remote, 3.2.7 unneeded net modules. No reboot. Rules that already pass (5.3.1.1, 5.3.1.2, 5.3.2.1, 5.3.3.4.2, 5.3.3.4.3, 5.4.1.3, 5.4.1.4, 5.4.1.6) are not rewritten.

## Plan

The script AJ runs is [`batch-9.sh`](batch-9.sh). Copy it from the laptop. Two SSH sessions from `192.168.50.0/24` are already open before PASTE 1. PASTE 1 arms a 300-second revert timer before apt/pam, then applies the change. It does not disarm that timer. PASTE 2, from a **new** SSH session, is itself the `aj` sudo test: it is started with `sudo bash` through the new stack, and then it disarms the timer. A `sudo -n -v` inside either paste runs as root and does not prove `aj`'s sudo. If PASTE 2 is not run in time, the timer restores `/etc/pam.d` and `/etc/security` from the tar taken before the change, resets `faillock` for `aj` immediately after that extract, then runs `pam-auth-update --force` (a failure there prints `WARN-pam-auth-update` and does not stop the rest), removes the profiles and drop-ins this batch added, and puts `chage` back. The extracted `common-*` files are the stock stack even if `pam-auth-update` refuses. PASTE 3 is that same restore, typed at the KVM console. If sudo is already broken, the three-line root-shell fallback under Rollback does the tar extract, the faillock reset, and stops the timer. That tar extract alone returns a working stock PAM stack.

```bash
# RUNS ON: LAPTOP
# RUNS IN: LAPTOP
scp docs/cis-fix/batch-9.sh aj@192.168.50.152:cis-audit/batch-9.sh
```

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
# PASTE 1
sudo bash ~/cis-audit/batch-9.sh
```

If `TIMER-ARMED` is not printed, run `sudo bash /root/batch9-revert.sh`.

Open a new SSH session. Leave the earlier sessions up. Within 300 seconds of `TIMER-ARMED`:

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
# PASTE 2
sudo bash ~/cis-audit/batch-9.sh 2
```

```bash
# RUNS ON: JOHNNY (KVM)
# RUNS IN: KVM
# PASTE 3
sudo bash ~/cis-audit/batch-9.sh 3
```

**No reboot.**

**Apt/PAM noninteractive (2026-11-04 hang fix):** PASTE 1 exports `DEBIAN_FRONTEND=noninteractive` and `DEBCONF_NONINTERACTIVE_SEEN=true` before `dpkg`/`apt`/`pam-auth-update`. It arms the 300s revert timer **before** those commands. Then `timeout 120 dpkg --force-confdef --force-confold --configure -a`, then `timeout 300 apt-get -y` with `Dpkg::Options::=--force-confdef` and `--force-confold` only when a package is not `install ok installed` (`SKIP-apt-already` on this re-run). `pam-auth-update --force` names the profiles. Pre-existing `common-*.pam-old` prints `NOTE-pam-old-present` and is left in place. Any STOP after the timer is armed runs `/root/batch9-revert.sh` and `systemctl stop` on the timer.

Live read, 2026-11-04 evening, no sudo, after the hung install: `libpam-pwquality 1.4.5-5build1`, `libpwquality-common 1.4.5-5build1`, and `cracklib-runtime 2.9.6-5.2build3` are `installed`. `/usr/share/pam-configs/pwquality` is present (`Default: yes`, Priority 1024, `requisite pam_pwquality.so retry=3`) but is not in the live stack. `/etc/security/pwquality.conf` is the package conffile (all settings commented). `/etc/security/pwquality.conf.d` does not exist. Five `common-*.pam-old` files exist (mtime 2026-11-05 02:47 UTC). `common-auth` is still `pam_unix.so nullok`. `common-password` is still `pam_unix.so obscure yescrypt` only. No `johnny-cis-batch9-revert` timer unit. Earlier same-day read, still true for the rest: `/usr/share/pam-configs` also has `capability`, `mkhomedir`, `systemd`, and `unix` (no faillock or pwhistory profiles yet). `unix` is Priority 256. Its `Auth` and `Auth-Initial` lines include `nullok`. Its `Password` line (used when it is not the first password module) is `pam_unix.so obscure use_authtok try_first_pass yescrypt`. Its `Password-Initial` line has no `use_authtok`. `common-auth` is `pam_unix.so nullok` only. `common-password` is `pam_unix.so obscure yescrypt` only. `/etc/security/faillock.conf` and `pwhistory.conf` exist and have no active settings. `pam_faillock(8)` / `faillock.conf(5)` on Johnny: `even_deny_root` is enabled when the option is present, so this batch does not write `even_deny_root = off`. The stock comment stays. `root_unlock_time` stays commented. `pam_pwhistory(8)` lists `use_authtok` as a module argument. `pwhistory.conf(5)` does not list that key, so it is set on the profile line only (one place). `chage -l aj`: last change Oct 29, 2026, expires never, inactive never, max 99999. `useradd -D` is `INACTIVE=-1`. `/etc/login.defs` has `PASS_MAX_DAYS 99999`, `PASS_WARN_AGE 7`, `ENCRYPT_METHOD YESCRYPT`, `USERGROUPS_ENAB yes`, and no `UMASK` line. No `TMOUT` and no `umask` under `/etc/profile` or `/etc/profile.d`. Four established SSH sessions, all `192.168.50.152:22` from `192.168.50.223`.

The resolute package file list for `libpam-pwquality` includes `/usr/share/pam-configs/pwquality` (Priority 1024, `Default: yes`, `requisite pam_pwquality.so retry=3`) and the package depends on `libpwquality-common`, which ships `/etc/security/pwquality.conf`. That file is the package conffile. Site values go in `/etc/security/pwquality.conf.d/60-johnny-cis.conf` so the conffile is not edited. `libpam-modules` ships `pam_faillock.so` and `pam_pwhistory.so` and does not ship pam-auth-update profiles for them. This batch adds profiles under `/usr/share/pam-configs/` and enables them with `pam-auth-update`. It does not hand-edit `common-auth`, `common-account`, or `common-password`.

Site values (AJ, 2026-10-31, already inside the CIS bounds): faillock `deny = 5`, `unlock_time = 900`; pwquality `minlen = 14`, `difok = 2`, `maxrepeat = 3`, `maxsequence = 3`, `dcredit`/`ucredit`/`lcredit`/`ocredit = 0`, `enforce_for_root`; pwhistory `remember = 24` and `enforce_for_root`; `PASS_MAX_DAYS 365`; `INACTIVE 45`; `TMOUT=900`; umask `027` in `login.defs` and in `/etc/profile.d` because `USERGROUPS_ENAB yes` would turn a lone `UMASK 027` into `007`. `dictcheck` and `enforcing` stay at the module default of 1 (no `=0` line).

`TMOUT=900` is `readonly` and exported from `/etc/profile.d/60-johnny-cis-shell.sh`. After PASTE 2 keeps the change, a new login shell ends an idle SSH session at 15 minutes. Sessions already open when the file is written keep their old environment until they start a new login shell. Do not rely on a long-lived idle SSH session after this batch is kept.

Password aging is set for `aj` (`chage -M 365 -I 45`) and for new accounts (`useradd -D -f 45`, `PASS_MAX_DAYS 365` in `login.defs`). Root's locked account and any other account that later has a password are not passed to `chage`. A re-audit of 5.4.1.1 or 5.4.1.5 can still flag those accounts.

`nullok` is removed by disabling the stock `unix` profile and enabling `johnny-unix`, which is the same profile with both `nullok` tokens removed. Package upgrades of `libpam-runtime` can put `unix` back in the enabled set; the revert path enables `unix` again on purpose.

Password aging uses `login.defs`, `useradd -D -f 45`, `chage -M 365 aj`, and `chage -I 45 aj`. It does not run `chage -d`. PASTE 1 stops if the "Last password change" line from `chage -l aj` changes. Oct 29, 2026 plus 365 days is still in the future on 2026-11-04, so `aj` is not forced to change the password now.

PASTE 1 is idempotent. It prints `STATE`, then:

1. Stops unless it is root and at least two established SSH peers are in `192.168.50.0/24` on local `192.168.50.152:22`. Any established SSH peer outside that net is `STOP-ssh-peer`.
2. If `/run/systemd/transient/johnny-cis-batch9-revert.timer` is active, `STOP-timer-armed`.
3. Takes one tar, `/root/batch9-pam-security.tar`, of `/etc/pam.d`, `/etc/security`, `/etc/login.defs`, and `/etc/default/useradd`. A later run keeps that tar. Writes `/root/batch9-chage.before` from `passwd -S aj` once.
4. If the packages, profiles, `common-*` lines, conf values, aging, `TMOUT`, and umask already match, it prints `OK-batch-9` and does not arm a timer. This re-run does not match: PAM is still `nullok`.
5. Otherwise it records the current SSH peer list in `/run/johnny-batch9-ssh-peers`, then arms `systemd-run --on-active=300s --unit=johnny-cis-batch9-revert` and prints `TIMER-ARMED 300` before any `dpkg`, `apt-get`, or `pam-auth-update`. The 300 seconds start here.
6. Runs `timeout 120 dpkg --force-confdef --force-confold --configure -a`. If both packages are already `install ok installed`, prints `SKIP-apt-already` and does not call `apt-get`. Otherwise `timeout 300 apt-get -y` with `--force-confdef` and `--force-confold`, and no `apt-get update`. A timeout or non-zero exit is `STOP-dpkg-configure` or `STOP-apt`, then revert and timer stop.
7. Notes `common-*.pam-old` if present (`NOTE-pam-old-present`), writes the conf lines and the five profiles, and runs `pam-auth-update --force --disable unix --enable johnny-unix pwquality faillock-preauth faillock-authfail faillock-authsucc pwhistory`. Johnny's `pam-auth-update(8)` synopsis is `--disable profile [profile...]` and `--enable profile [profile...]` together, so several names per option is the documented form. `--force` is required because the hung postinst left `common-*` marked locally modified. If that invocation fails, PASTE 1 runs the revert, stops the timer, and exits.
8. Checks the generated stack, faillock not locking root by option, and the unchanged last-change line. It also runs `sudo -n -v` as root (`ROOT-SUDO-N-OK`). That line does not test `aj`. A failed check runs `/root/batch9-revert.sh`, stops the timer, and exits `STOP-validate`.
9. Leaves the timer armed and prints `OK-batch-9-pending`. PASTE 2 must finish inside the 300 seconds counted from `TIMER-ARMED`.

Stack the profiles are built to produce: `pam_faillock.so preauth` (requisite, before `pam_unix`), then `pam_unix` with no `nullok`, then `pam_faillock.so authfail`, then after `pam_permit` a required `pam_faillock.so authsucc`. Account: `pam_faillock` then `pam_unix`. Password: `pam_pwquality`, then `pam_pwhistory.so use_authtok`, then `pam_unix` with `use_authtok` from the non-initial `unix` line. `pam-auth-update` rewrites `success=end` so a successful `pam_unix` skips `authfail` and `pam_deny` and still reaches `authsucc`.

PASTE 2 stops if the timer is not active, if the stack drifted, or if this session's `SSH_CONNECTION` (read from the process ancestry, because `sudo` does not keep it in the environment) was already in the peer list saved at the start of PASTE 1. It then stops the timer and stops unless `timer_active` is false. It runs `faillock --user aj --reset` and prints `OK-batch-9`. Reaching this paste at all is the `aj` sudo check, because AJ starts it with `sudo bash`.

`OK-batch-9` means the new PAM stack was kept. Governance re-audits after AJ sends the output. Verdicts stay in the CSV until that re-audit. The same commit that records the run mirrors the changed `/etc` files under `etc/` in this repo.

## Rollback

Not part of the paste. If SSH and `sudo` still work and the new policy should be undone:

```bash
# RUNS ON: JOHNNY (SSH)
sudo systemctl stop johnny-cis-batch9-revert.timer
sudo systemctl stop johnny-cis-batch9-revert.service
sudo bash /root/batch9-revert.sh
```

That restore does not remove the installed `libpam-pwquality` or `cracklib-runtime` packages. It disables their PAM profile. `/etc/security/pwquality.conf` from the package may remain on disk, unused, after the tar is extracted. Do not delete `/root/batch9-pam-security.tar` until a later batch. The helper resets `faillock` for `aj` right after the extract, then runs `pam-auth-update --force`. If that command exits non-zero it prints `WARN-pam-auth-update` and still removes the added profiles and restores `chage`. It then checks that `common-auth` has no `pam_faillock` and that `pam_unix` still has `nullok`.

If `sudo` from SSH is already broken, use PASTE 3 at the KVM console. First choice, when the console can still `sudo` and `~/cis-audit/batch-9.sh` is readable:

```bash
# RUNS ON: JOHNNY (KVM)
# RUNS IN: KVM
# PASTE 3
sudo bash ~/cis-audit/batch-9.sh 3
```

If sudo, the script, or `pam-auth-update` cannot be used, log in as root at the console or run `su -`, then type this. The tar extract by itself puts the pre-change `common-*` files back, which is a working stock PAM stack (`pam_unix.so nullok`, no `pam_faillock`).

```bash
# RUNS ON: JOHNNY (KVM)
tar -C / -xzf /root/batch9-pam-security.tar
faillock --user aj --reset
systemctl stop johnny-cis-batch9-revert.timer
```

## Results

Run `batch-9-20261104-211507` finished with the timer kept off and the new stack kept. Log: `tools/relay/logs/batch-9-20261104-211507-results.txt`.

PASTE 1: `SSH-LAN 2`, backups kept (`/root/batch9-pam-security.tar`, `/root/batch9-chage.before`), `PEERS-SAVED 2`, `TIMER-ARMED 300`, `SKIP-apt-already` (packages already installed), `NOTE-pam-old-present`, wrote `60-johnny-cis.conf`, set faillock `deny` and `unlock_time`, pwhistory `remember` and `enforce_for_root`, `SET-PASS_MAX_DAYS`, `SET-UMASK`, wrote `/etc/profile.d/60-johnny-cis-shell.sh`, `PAM-AUTH-UPDATE-OK`, `CHAGE-LAST-UNCHANGED` (Oct 29, 2026), `STACK-OK`, `ROOT-SUDO-N-OK`, `FAILLOCK-RESET-aj`, `OK-batch-9-pending`.

PASTE 2 (new session `192.168.50.223:52674`): `ROOT-SUDO-N-OK`, `STACK-OK`, `TIMER-STOPPED`, `FAILLOCK-RESET-aj`, `OK-batch-9`. PASTE 3 was not used.

CSV (`git diff docs/cis-26.04-l1-results.csv`), date `2026-11-04`, evidence from this run's markers: all 24 in-scope rules moved off FAIL. Straight PASS: 5.3.1.3, 5.3.1.4, 5.3.2.2, 5.3.2.3, 5.3.2.4, 5.3.3.1.1, 5.3.3.1.2, 5.3.3.2.1, 5.3.3.2.2, 5.3.3.2.4, 5.3.3.2.5, 5.3.3.2.8, 5.3.3.3.1, 5.3.3.3.2, 5.3.3.3.3, 5.3.3.4.1, 5.3.3.4.4, 5.4.1.1, 5.4.1.5, 5.4.3.2. PASS (manual): 5.3.3.2.3, 5.3.3.2.6, 5.3.3.2.7, 5.4.3.3 (umask evidence notes it was not live-checked in the snapshot). Rules already PASS were not rewritten. `/etc` copies in this repo are not part of that diff.
