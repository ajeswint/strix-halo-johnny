# CIS L1 fix pass, Batch 10: bootloader password, remote logs, unused net modules

**Status:** DRAFT (Grok, 2026-11-04). Not run.

**Rules in scope:** 1.4.1 bootloader password, 6.1.2.5 remote log forwarding, 3.2.7 unneeded network protocol modules (manual).

**Live read (2026-11-04, `aj` over SSH, no sudo):** kernel `7.0.0-42-generic`. `/etc/default/grub` has `GRUB_TIMEOUT_STYLE=hidden` and `GRUB_TIMEOUT=0`. `aj` cannot read `/boot/grub/grub.cfg` (mode 600). `/etc/grub.d/10_linux` line 33 is `CLASS="--class gnu-linux --class gnu --class os"` with no `--unrestricted`. Same base CLASS in `10_linux_zfs`. `20_linux_xen` has that string plus `--class xen`. `GRUB_DISABLE_OS_PROBER=false` is commented. `dccp` has no `.ko` (`modprobe -n -v` → module not found). `sctp`, `rds`, `tipc`, `atm`, and `can` are not loaded; `modprobe -n -v` ends in `install /bin/false` for those five (`sctp` and `tipc` print `udp_tunnel` `insmod` lines first). `esp4`, `esp6`, and `rxrpc` still dry-run to `insmod` of their own `.ko`. No `set superusers` check was possible without root.

## Plan

The script AJ runs is [`batch-10.sh`](batch-10.sh). Copy it from the laptop, then create the hash file, then run PASTE 1. PASTE 1 does not reboot. A password prompt at the next boot means the unrestricted gate failed: use Rollback.

**1.4.1.** The password gates GRUB menu editing and the command line. It must not gate a normal boot. PASTE 1 writes `/etc/grub.d/01_johnny_users` (`set superusers="johnny"` plus `password_pbkdf2`) and appends `--unrestricted` to the base `CLASS=` line in `10_linux`, `10_linux_zfs`, and `20_linux_xen` so generated Linux entries boot with no prompt. It builds a candidate `grub.cfg`, runs `grub-script-check`, and requires the first `menuentry` line to contain `--unrestricted` before it replaces `/boot/grub/grub.cfg`. The revert helper is written before any `grub.d` edit. An ERR trap calls it on a `set -e` failure after that (a plain `exit 1` does not fire ERR, so those STOP branches call the helper themselves). The helper restores the tar and then deletes it, so a failed run can be rerun. If `STOP-tar-exists` prints, run the helper first. Do not delete the tar by hand. AJ types the password only in `grub-mkpasswd-pbkdf2`. The script accepts a hash file. It never contains a password or a hash.

A later `grub-common` upgrade can replace the patched `10_linux` and drop `--unrestricted` (for example an apt run without force-confold). Repeat the supervised KVM reboot test after any such upgrade. The first `menuentry` line in `/boot/grub/grub.cfg` must still contain `--unrestricted`. PASTE 1 checks that line before it installs the cfg and again when it sees an existing password config.

**6.1.2.5 — configure, TCP, after the GRUB and module steps.** AJ (2026-11-04 21:57 CT) named the collector: `ableton_box` in [`docs/hosts/ableton_box.md`](../hosts/ableton_box.md) (mDNS `ableton_box.local`, address `192.168.50.211`). No port is in that doc, so the forward uses syslog **514**. Transport is **TCP** (`omfwd`, protocol `tcp`, the `@@` form). A TCP connect shows that something accepted the session. UDP (`@`) would not, so it is not used.

Live read the same night, `aj` over SSH: `getent` returned nothing for `ableton_box` and `ableton_box.local`. `resolvectl query ableton_box.local` failed (`No appropriate name servers or networks`). `ip neigh` showed `192.168.50.211` on `eno3`, MAC `3c:7c:3f:4e:14:7d`, state `REACHABLE`. `timeout 3 bash -c 'echo >/dev/tcp/192.168.50.211/514'` failed. rsyslog is `active` and `enabled`. `imjournal.so` is installed. Effective journald is `ForwardToSyslog=yes` from `/usr/lib/systemd/journald.conf.d/syslog.conf`. `/etc/systemd/journald.conf` still has that line commented. `/etc/systemd/journald.conf.d/` has only Batch 3's `60-rotation.conf`. rsyslog loads `imuxsock` and `imklog`, not `imjournal`. No `omfwd` line exists. `systemctl cat systemd-journald` has `ExecStart` and no `ExecReload` (checked 2026-11-04).

PASTE 1 resolves `ableton_box.local`, then `ableton_box`. A hit must be `192.168.50.211` or the script stops (`STOP-resolve-mismatch`). No hit uses that documented address and records the hostname in a comment. It then opens TCP 514 on that address with a 5 second timeout. Failure prints `STOP-collector-514` and exits 1. It does not write `/etc/rsyslog.d/60-johnny-remote.conf`, does not write the journald drop-in, and does not print `BATCH10-SSH-DONE`. That is the expected result until ABLETON_BOX listens on TCP 514. The GRUB and module steps above that probe still run; a rerun after the collector is up is idempotent for those steps.

On success the script writes `action(type="omfwd" target="192.168.50.211" port="514" protocol="tcp" ...)` so the CIS advanced-format grep matches, checks `rsyslogd -N1`, and reloads rsyslog. Journal events already reach rsyslog through `imuxsock` because `ForwardToSyslog=yes` is effective. The script does not load `imjournal` (that would copy the same events twice). It adds `/etc/systemd/journald.conf.d/61-batch10-forward-syslog.conf` with `ForwardToSyslog=yes` so the setting also lives under `/etc`. `systemd-journald` has no `ExecReload`, and the drop-in matches the vendor value, so `systemctl reload systemd-journald || systemctl try-restart systemd-journald || true` is non-fatal. The gate is `systemd-analyze cat-config` showing `ForwardToSyslog=yes`. The revert helper uses the same non-fatal line so a reload failure cannot skip `rm` of the tar or `REVERTED`. No apt. CSV stays unchanged until scoring.

**3.2.7 — decision, narrow change.** The site deny list beyond the CIS four is still open (Detection has not signed off on capture or XDP needs). `esp4`, `esp6`, and `rxrpc` stay available. PASTE 1 only makes sure `dccp`, `sctp`, `rds`, and `tipc` have `blacklist` and `install /bin/false` in `/etc/modprobe.d/johnny-cis-net.conf`, and it stops if any of those four is loaded or listed for autoload. That edit runs only after the GRUB gate is confirmed (or already present). `/root/batch10-johnny-cis-net.conf.bak` is created only when it does not already exist, so a rerun cannot overwrite the original with an already-edited file. `sctp`, `rds`, and `tipc` are already in that file from Batch 4. `dccp` is not in this kernel; the lines are still added so a later kernel module cannot load. `atm` and `can` are left as Batch 4 wrote them. AJ (2026-11-04 22:18 CT): keep CIS four only. Verify accepts dependency `insmod` lines before a trimmed `install /bin/false` line (modprobe prints a trailing space); rejects only an `insmod` of the named module. A verify STOP no longer restores `NETBAK` (that had wiped the just-added dccp lines). Absent `dccp.ko` is fine. Re-run after GRUB-OK is idempotent: `ALREADY-1.4.1`, re-adds dccp if missing, then the collector probe. CSV is unchanged until scoring.

```bash
# RUNS ON: LAPTOP
# RUNS IN: LAPTOP
scp docs/cis-fix/batch-10.sh aj@192.168.50.152:cis-audit/batch-10.sh
```

On Johnny, SSH, type the password only into `grub-mkpasswd-pbkdf2`. Copy the printed `grub.pbkdf2.sha512...` line into the file. Do not put the password in the file, the repo, or this doc.

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
sudo grub-mkpasswd-pbkdf2
sudo install -m 600 /dev/null /root/batch10-grub.pbkdf2
sudoedit /root/batch10-grub.pbkdf2
```

`sudoedit` needs a working editor and a sudoers policy that allows it. If it will not open the file, paste the hash at this prompt instead (one line, then Ctrl-D). The password stays out of the file.

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
sudo tee /root/batch10-grub.pbkdf2 >/dev/null
sudo chmod 600 /root/batch10-grub.pbkdf2
sudo chown root:root /root/batch10-grub.pbkdf2
```

Either path should leave one line and mode 600 root-owned.

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
# PASTE 1
sudo bash ~/cis-audit/batch-10.sh
```

The first run today ends in `STOP-collector-514` after `GRUB-OK`. That is the expected stop while TCP 514 on `192.168.50.211` is closed. It is not a rollback trigger. GRUB and the module lines are already applied; a later rerun is idempotent for those steps. `BATCH10-SSH-DONE` prints only after the collector accepts TCP 514 and the forwarder checks pass. This script does not reboot. After `BATCH10-SSH-DONE`, a supervised reboot with KVM watching, LUKS recovery passphrase at hand, confirms the bootloader gate. Normal boot should show no GRUB password prompt (`timeout` is 0 and hidden). To confirm the gate, at KVM press Esc or Shift during firmware handoff so the menu appears, then try `e` on the default entry: that edit must ask for user `johnny` and the password. Boot the default entry without typing it. Repeat that reboot test after a `grub-common` package upgrade. The GRUB gate can also be checked at KVM after today's `GRUB-OK` / `STOP-collector-514` run; that stop does not undo GRUB.

PASTE 2 is the KVM rollback in the next section. It is not a second apply step.

## Rollback

Not part of the apply paste.

If the machine still boots (the expected case), from SSH:

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
sudo bash /root/batch10-revert.sh
```

That extracts `/root/batch10-grub-before.tar` (pre-change `/etc/grub.d` and `/boot/grub/grub.cfg`), restores `johnny-cis-net.conf` from `/root/batch10-johnny-cis-net.conf.bak` when that file exists, deletes `/etc/grub.d/01_johnny_users`, deletes `/etc/rsyslog.d/60-johnny-remote.conf` and `/etc/systemd/journald.conf.d/61-batch10-forward-syslog.conf` when the helper contains the syslog undo (a helper written before this revision does not; use the block below), reloads `rsyslog` when it is active, and runs `systemctl reload systemd-journald || systemctl try-restart systemd-journald || true` when journald is active. A journald reload failure does not skip removal of the tar or `REVERTED`. It does not ask for the GRUB password. After `REVERTED`, PASTE 1 can be run again.

Syslog and journald drop-ins only, installed root, SSH. This does not undo GRUB or the module file.

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
sudo rm -f /etc/rsyslog.d/60-johnny-remote.conf /etc/systemd/journald.conf.d/61-batch10-forward-syslog.conf
sudo systemctl reload rsyslog || sudo systemctl try-restart rsyslog
sudo systemctl reload systemd-journald || sudo systemctl try-restart systemd-journald || true
```

If GRUB asks for a password before any menu entry boots, do not type one. At the firmware boot menu (outside GRUB), boot Ubuntu installer media, choose the rescue shell, and run PASTE 2 there. Device names are from the disk row in `docs/os-handoff.md`: `/dev/nvme0n1p3` is LUKS (the existing recovery passphrase, slot 0), `/dev/nvme0n1p2` is `/boot`, and the volume group is `ubuntu-vg` / `ubuntu-lv`. `johnny-root` is only the mapper name PASTE 2 passes to `cryptsetup open` in the installer shell. The live mapper on a normal boot is `dm_crypt-0`. A wrong disk stops the script. Copy the script onto a USB stick from the laptop (`cp docs/cis-fix/batch-10.sh` onto the stick), mount that stick in the installer, and run:

```bash
# RUNS ON: JOHNNY (KVM)
# RUNS IN: KVM
# PASTE 2
sudo bash batch-10.sh 2
```

If `/root/batch10-grub-before.tar` is already visible, PASTE 2 only runs `/root/batch10-revert.sh` and does not call `cryptsetup`.

## Results

Run `tools/relay/logs/batch-10-20261104-225808-results.txt` (2026-11-04). The script confirmed the bootloader gate (`ALREADY-1.4.1`), kept `/root/batch10-johnny-cis-net.conf.bak` (`BACKUP-KEPT`), added `blacklist dccp` and `install dccp` (`MODULE-ADDED` twice, `MODULE-VERIFY-OK`), and resolved the collector by the documented fallback (`RESOLVE-FALLBACK 192.168.50.211 ableton_box`). It then stopped: `STOP-collector-514`. No TCP connection to `192.168.50.211:514`. No forwarder was written. `BATCH10-SSH-DONE` was not printed. That stop is the expected result until ABLETON_BOX listens on TCP 514; GRUB and the module lines stay applied.

`docs/cis-26.04-l1-results.csv` (date `2026-11-04` on the four touched rows):

- **1.4.1** FAIL → PASS. Evidence: `password_pbkdf2` / `set superusers` in `grub.cfg`, `--unrestricted` on the first menu entry, hash held in `/etc/grub.d/01_johnny_users` (hash not recorded).
- **3.2.3** PASS, evidence updated. Still no `dccp` module in this kernel; script added `blacklist dccp` and `install dccp`; `MODULE-VERIFY-OK`; not loaded.
- **3.2.7** FAIL (manual) → PASS (manual). AJ 2026-11-04 22:18 CT: site deny list is the CIS four (`dccp`, `sctp`, `rds`, `tipc`); `esp4`, `esp6`, and `rxrpc` stay available. Scored from that decision plus `MODULE-VERIFY-OK`.
- **6.1.2.5** stays FAIL (manual). Evidence now records `STOP-collector-514`: no TCP to `192.168.50.211:514`, no `omfwd` line, rerun after ABLETON_BOX listens.
