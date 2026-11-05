# CIS L1 fix pass, Batch 8: SSH and sudo

**Status:** DRAFT rev 1 (Grok, 2026-11-04). Nothing in this batch has run on Johnny.

**Rules in scope (15):** 5.1.1, 5.1.2, 5.1.5, 5.1.6, 5.1.8, 5.1.9, 5.1.15, 5.1.17, 5.1.18, 5.1.20, 5.1.22, 1.6.5 (same `Banner` as 5.1.6), 5.2.6, 5.2.7, 5.4.2.5.

**Not in this batch:** PAM other than the one `pam_wheel` line in `/etc/pam.d/su` (5.3.x is Batch 9). `Defaults logfile` (sudo-rs; 5.2.3 already passes on the journal). Restart of `ssh.socket`. GRUB. Reboot.

## Plan

The script AJ runs is [`batch-8.sh`](batch-8.sh). Copy it from the laptop. A second SSH session from `192.168.50.0/24` is already open before PASTE 1. PASTE 1 applies the files, checks `sshd -t`, arms a 300-second revert timer, then reloads `ssh.service`. It does not disarm that timer. PASTE 2, from a **new** SSH session opened after the reload, disarms the timer. If PASTE 2 is not run in time, the timer puts the sshd files back and reloads sshd. PASTE 3 is typed at the KVM console only if IPv4 SSH is already dead.

```bash
# RUNS ON: LAPTOP
# RUNS IN: LAPTOP
scp docs/cis-fix/batch-8.sh aj@192.168.50.152:cis-audit/batch-8.sh
```

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
# PASTE 1
sudo bash ~/cis-audit/batch-8.sh
```

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
# PASTE 2
sudo bash ~/cis-audit/batch-8.sh 2
```

```bash
# RUNS ON: JOHNNY (KVM)
# RUNS IN: KVM
# PASTE 3
sudo bash ~/cis-audit/batch-8.sh 3
```

**No reboot.**

Live read, 2026-11-04, no sudo: `ssh.service` is active and `CanReload=yes`. `ss` shows TCP `0.0.0.0:22` and `[::]:22`. `systemctl show ssh.socket -p Listen` is `0.0.0.0:22` only. The Batch 7 file `/etc/systemd/system/ssh.socket.d/60-johnny-cis-ipv4.conf` is present. This batch does not restart `ssh.socket`, so the live `[::]:22` socket stays. Three established SSH sessions were `192.168.50.152:22` from `192.168.50.223`. `/etc/ssh/sshd_config` is `0644` root:root. `/etc/ssh/sshd_config.d` is `0755` root:root with only `50-cloud-init.conf` (`0600`; unreadable as `aj`). `Include` is still the early include in `sshd_config`. `/etc/issue` and `/etc/issue.net` are both `Authorized use only. Activity is monitored.` `visudo` is visudo-rs 0.2.13 (`visudo -c` and `-f` exist). `sudo` is sudo-rs. Group `sugroup` does not exist. Group `sudo` contains `aj`. `/etc/sudoers.d` has only `README`. The 2026-10-31 root audit recorded `Defaults secure_path="...:/snap/bin"` in `/etc/sudoers` (tab after `Defaults`). `/etc/environment` PATH still ends in `/snap/bin`. `/etc/login.defs` and `/etc/profile` have no `snap` string. `sshd -T` as `aj` cannot read `50-cloud-init.conf`.

Site values already chosen (AJ, 2026-10-31): `AllowUsers aj`; banner text as above, file `/etc/issue.net`; `ClientAliveInterval 15` and `ClientAliveCountMax 3` (dead-client drop after about 45 seconds, not an idle logout); `timestamp_timeout=15`; su group `sugroup` with no members (`su` off for everyone, including `aj`; use `sudo -i`).

Values set here to the CIS bound, because that handoff did not name a number: `LoginGraceTime 60` (audit wants 1–60; live default 120). `MaxAuthTries 4` (audit wants 4 or less; live 6). `MaxStartups 10:30:60` (audit fails when any field is above 10, 30, or 60; live `10:30:100`). `DisableForwarding yes`. `PermitRootLogin no`. MACs `hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256`. The 5.1.17 audit fails on the named weak list (umac-64, umac-128-etm, hmac-sha1-96, and the other names in that grep). This list omits those and also omits `hmac-sha1` and `umac-128`.

Drop-in path: `/etc/ssh/sshd_config.d/00-johnny-cis.conf`. The name sorts before `50-cloud-init.conf`. OpenSSH keeps the first value it reads. `sshd -t` runs before `systemctl reload ssh.service`. The reload is skipped when `sshd -T` already matches and the timer is not armed.

**5.2.7 versus the 5.4.2.5 audit command.** The local 5.4.2.5 check reads root's PATH with `sudo su - root -c env`. After `pam_wheel` and an empty `sugroup`, that `su` fails for everyone, including root. PASTE 1 therefore checks root's login PATH with `su - root` **before** it enables `pam_wheel`, and it stops if `/snap/bin` is still there. After PASTE 1, `su` is expected to fail. Governance's later re-audit of 5.4.2.5 cannot use that `su` line until 5.2.7 is undone. `sudo -i` still works for `aj`.

PASTE 1 is idempotent. It prints `STATE`, then:

1. Stops unless it is root, at least two established SSH peers are in `192.168.50.0/24` on local `192.168.50.152:22`, and `0.0.0.0:22` is listening. A peer of `192.168.50.152` is `NOTE-ssh-self` and is not counted. Any established SSH peer outside `192.168.50.0/24` is `STOP-ssh-peer`. Peer parsing matches Batch 7: `ss -H -tn sport = :22`, awk `$1=="ESTAB"`, field 5.
2. Stops if `/etc/issue.net` is not exactly the site banner line. It does not rewrite the banner files.
3. Stops if `sugroup` exists and has members. An empty group is required before the `pam_wheel` line is active. It does not enable `pam_wheel` with any other group.
4. Copies `/etc/environment` to `/root/environment.pre-batch8` once and removes the trailing `:/snap/bin` from the PATH assignment only. Any other `snap` token is `STOP-environment`.
5. Copies `/etc/sudoers` to `/root/sudoers.pre-batch8` once. Replaces the single recorded `secure_path` line (the `:/snap/bin` suffix only) on a temp copy, runs `visudo -c -f` on that copy, then installs it mode `0440`. Writes `/etc/sudoers.d/60-johnny-cis-timeout` with `Defaults timestamp_timeout=15`, mode `0440`, and runs `visudo -c -f` on it and `visudo -c` on the whole policy. It does not write `Defaults logfile`. A `timestamp_timeout` that is already present and is not `15` is `STOP-timestamp`.
6. Creates system group `sugroup` if missing. Re-checks that it has no members. Copies `/etc/pam.d/su` to `/root/pam-su.pre-batch8` once and appends `auth required pam_wheel.so use_uid group=sugroup` if that active line is absent. Any other active `pam_wheel` line is `STOP-pam-wheel`. This is the only PAM edit.
7. Confirms `su - root` PATH has no `/snap/bin` and every element is a directory. Then the `pam_wheel` line is what makes later `su` fail.
8. If `/run/systemd/transient/johnny-cis-batch8-revert.timer` is active, `STOP-timer-armed`.
9. If the sshd drop-in, modes, and `sshd -T` already match, it prints `SKIP-sshd-reload` and `OK-batch-8`. It does not arm a timer and does not reload.
10. Otherwise it copies `/etc/ssh/sshd_config` to `/root/sshd_config.pre-batch8` once, writes `/root/batch8-sshd-revert.sh` to restore that copy, remove `00-johnny-cis.conf`, restore the directory mode, run `sshd -t`, and `systemctl reload ssh.service`. It sets `sshd_config` to `0600` and `sshd_config.d` to `0700`, writes the drop-in, and runs `sshd -t`. A failed check runs the revert script immediately and exits `STOP-sshd-t`. It records the LAN session count in `/run/johnny-batch8-ssh-count`, arms `systemd-run --on-active=300s --unit=johnny-cis-batch8-revert`, then reloads `ssh.service`. It re-checks `0.0.0.0:22`, at least two LAN sessions, and `sshd -T`. On that failure it runs the revert script, stops the timer, and exits `STOP-ssh-after-reload`. It leaves the timer armed on success and prints `OK-batch-8-pending`.

PASTE 2 stops if the timer is not active, if `sshd -T` drifted, if `0.0.0.0:22` is down, or if the LAN session count is not greater than the count stored before the reload. That greater count is the new-session test: open a new SSH session and leave the previous ones up, then run PASTE 2 within 300 seconds of the reload. It then stops the timer and prints `OK-batch-8`.

`OK-batch-8` means the sshd reload was kept. The ssh.socket drop-in from Batch 7 is still not applied to the live socket. No reboot is required. Governance re-audits after AJ sends the output. Verdicts stay in the CSV until that re-audit. The same commit that records the run mirrors the changed `/etc` files under `etc/` in this repo.

## Rollback

Not part of the paste. If the timer is still armed, stopping it without PASTE 2 leaves the new sshd config in place. If SSH still works and the new config should be undone:

```bash
sudo systemctl stop johnny-cis-batch8-revert.timer
sudo systemctl stop johnny-cis-batch8-revert.service
sudo bash /root/batch8-sshd-revert.sh
sudo cp -a /root/environment.pre-batch8 /etc/environment
sudo cp -a /root/sudoers.pre-batch8 /etc/sudoers
sudo rm -f /etc/sudoers.d/60-johnny-cis-timeout
sudo visudo -c
sudo cp -a /root/pam-su.pre-batch8 /etc/pam.d/su
sudo groupdel sugroup
```

`groupdel` fails if `sugroup` is missing or no longer empty; that is fine only after you confirm the `pam_wheel` line is gone. Do not restart `ssh.socket`. `0.0.0.0:22` must still be listening before the session is closed.

If IPv4 SSH is already dead, use PASTE 3 at the KVM console. PASTE 3 runs only the sshd revert. It does not undo sudo, `/etc/environment`, or `pam_wheel`.

## Results

Log: `tools/relay/logs/batch-8-20261104-194448-results.txt` (2026-11-04). PASTE 1 and PASTE 2 both completed. PASTE 3 was not used.

Pre-state matched the plan: `0.0.0.0:22` and `[::]:22` listening, two established SSH sessions from `192.168.50.223`, `sshd_config` `0644` root:root, `sshd_config.d` `0755` root:root with only `50-cloud-init.conf` (`0600`). The script printed `LAN-SSH 2`.

PASTE 1 wrote the files and kept the checks: backups `/root/environment.pre-batch8`, `/root/sudoers.pre-batch8`, `/root/pam-su.pre-batch8`, `/root/sshd_config.pre-batch8`; `WROTE-environment`, `WROTE-secure-path`, `WROTE-timestamp`, `WROTE-group`, `WROTE-pam-wheel`. Each `visudo` check printed `parsed OK`, including `/etc/sudoers`. Root PATH after the environment edit was `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games` (no `/snap/bin`). The revert timer armed at 300 seconds (`TIMER-ARMED 300`) and the script exited `OK-batch-8-pending`.

PASTE 2, from the new session, printed `LAN-SSH 3` then `OK-batch-8`. That is the keep: the timer was disarmed and the sshd reload stayed. No `STOP-*` lines.

`git diff docs/cis-26.04-l1-results.csv` is empty. The 15 in-scope rules stay at their pre-batch verdicts until Governance re-audits. The same commit that records the run still has to mirror the changed `/etc` files under `etc/`.
