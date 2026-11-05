# CIS L1 fix pass, Batch 10: bootloader password, remote logs, unused net modules

**Status:** DRAFT (Grok, 2026-11-04). Not run.

**Rules in scope:** 1.4.1 bootloader password, 6.1.2.5 remote log forwarding, 3.2.7 unneeded network protocol modules (manual).

**Live read (2026-11-04, `aj` over SSH, no sudo):** kernel `7.0.0-42-generic`. `/etc/default/grub` has `GRUB_TIMEOUT_STYLE=hidden` and `GRUB_TIMEOUT=0`. `aj` cannot read `/boot/grub/grub.cfg` (mode 600). `/etc/grub.d/10_linux` line 33 is `CLASS="--class gnu-linux --class gnu --class os"` with no `--unrestricted`. Same base CLASS in `10_linux_zfs`. `20_linux_xen` has that string plus `--class xen`. `GRUB_DISABLE_OS_PROBER=false` is commented. `dccp` has no `.ko` (`modprobe -n -v` → module not found). `sctp`, `rds`, `tipc`, `atm`, and `can` are not loaded; `modprobe -n -v` ends in `install /bin/false` for those five (`sctp` and `tipc` print `udp_tunnel` `insmod` lines first). `esp4`, `esp6`, and `rxrpc` still dry-run to `insmod` of their own `.ko`. No `set superusers` check was possible without root.

## Plan

The script AJ runs is [`batch-10.sh`](batch-10.sh). Copy it from the laptop, then create the hash file, then run PASTE 1. PASTE 1 does not reboot. A password prompt at the next boot means the unrestricted gate failed: use Rollback.

**1.4.1.** The password gates GRUB menu editing and the command line. It must not gate a normal boot. PASTE 1 writes `/etc/grub.d/01_johnny_users` (`set superusers="johnny"` plus `password_pbkdf2`) and appends `--unrestricted` to the base `CLASS=` line in `10_linux`, `10_linux_zfs`, and `20_linux_xen` so generated Linux entries boot with no prompt. It builds a candidate `grub.cfg`, runs `grub-script-check`, and requires the first `menuentry` line to contain `--unrestricted` before it replaces `/boot/grub/grub.cfg`. The revert helper is written before any `grub.d` edit. An ERR trap calls it on a `set -e` failure after that (a plain `exit 1` does not fire ERR, so those STOP branches call the helper themselves). The helper restores the tar and then deletes it, so a failed run can be rerun. If `STOP-tar-exists` prints, run the helper first. Do not delete the tar by hand. AJ types the password only in `grub-mkpasswd-pbkdf2`. The script accepts a hash file. It never contains a password or a hash.

A later `grub-common` upgrade can replace the patched `10_linux` and drop `--unrestricted` (for example an apt run without force-confold). Repeat the supervised KVM reboot test after any such upgrade. The first `menuentry` line in `/boot/grub/grub.cfg` must still contain `--unrestricted`. PASTE 1 checks that line before it installs the cfg and again when it sees an existing password config.

**6.1.2.5 — decision, no change.** Handoff and `docs/hosts` do not name a remote log server. The ableton_box manager role is still parked. This draft does not invent a host and does not write rsyslog config. Intended score later: **N/A**, accepted exception, until AJ names a collector. CSV is unchanged in this draft. If AJ names a host, that is a new paste, not a guess in this one.

**3.2.7 — decision, narrow change.** The site deny list beyond the CIS four is still open (Detection has not signed off on capture or XDP needs). `esp4`, `esp6`, and `rxrpc` stay available. PASTE 1 only makes sure `dccp`, `sctp`, `rds`, and `tipc` have `blacklist` and `install /bin/false` in `/etc/modprobe.d/johnny-cis-net.conf`, and it stops if any of those four is loaded or listed for autoload. That edit runs only after the GRUB gate is confirmed (or already present). `/root/batch10-johnny-cis-net.conf.bak` is created only when it does not already exist, so a rerun cannot overwrite the original with an already-edited file. `sctp`, `rds`, and `tipc` are already in that file from Batch 4. `dccp` is not in this kernel; the lines are still added so a later kernel module cannot load. `atm` and `can` are left as Batch 4 wrote them. Scoring 3.2.7 stays **FAIL (manual)** until AJ approves a fuller list. CSV is unchanged.

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

Expect `GRUB-OK` and `BATCH10-SSH-DONE`. Then a supervised reboot with KVM watching, LUKS recovery passphrase at hand. This script does not reboot. Normal boot should show no GRUB password prompt (`timeout` is 0 and hidden). To confirm the gate, at KVM press Esc or Shift during firmware handoff so the menu appears, then try `e` on the default entry: that edit must ask for user `johnny` and the password. Boot the default entry without typing it. Repeat that reboot test after a `grub-common` package upgrade.

PASTE 2 is the KVM rollback in the next section. It is not a second apply step.

## Rollback

Not part of the apply paste.

If the machine still boots (the expected case), from SSH:

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
sudo bash /root/batch10-revert.sh
```

That extracts `/root/batch10-grub-before.tar` (pre-change `/etc/grub.d` and `/boot/grub/grub.cfg`), restores `johnny-cis-net.conf` from `/root/batch10-johnny-cis-net.conf.bak` when that file exists, deletes `/etc/grub.d/01_johnny_users`, and then removes the tar. It does not ask for the GRUB password. After `REVERTED`, PASTE 1 can be run again.

If GRUB asks for a password before any menu entry boots, do not type one. At the firmware boot menu (outside GRUB), boot Ubuntu installer media, choose the rescue shell, and run PASTE 2 there. Device names are from the disk row in `docs/os-handoff.md`: `/dev/nvme0n1p3` is LUKS (the existing recovery passphrase, slot 0), `/dev/nvme0n1p2` is `/boot`, and the volume group is `ubuntu-vg` / `ubuntu-lv`. `johnny-root` is only the mapper name PASTE 2 passes to `cryptsetup open` in the installer shell. The live mapper on a normal boot is `dm_crypt-0`. A wrong disk stops the script. Copy the script onto a USB stick from the laptop (`cp docs/cis-fix/batch-10.sh` onto the stick), mount that stick in the installer, and run:

```bash
# RUNS ON: JOHNNY (KVM)
# RUNS IN: KVM
# PASTE 2
sudo bash batch-10.sh 2
```

If `/root/batch10-grub-before.tar` is already visible, PASTE 2 only runs `/root/batch10-revert.sh` and does not call `cryptsetup`.
