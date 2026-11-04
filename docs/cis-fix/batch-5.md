# CIS L1 fix pass, Batch 5: mounts, apt, banners

**Status:** DRAFT rev 1 (Grok, 2026-11-04). Nothing in this file has been run. The three pastes are the recommended path. They wait on AJ's answers to Q1–Q3 and on Claude's review of the exact paste. AJ runs sudo. A second SSH session stays open for Paste 1 and Paste 2. Paste 3 needs the AMT KVM (the Johnny KVM icon on rock-box, handoff step 5) and the LUKS recovery passphrase at hand.

**Rules in scope (8):** 1.1.2.1.4 `/tmp` noexec, 1.1.2.2.4 `/dev/shm` noexec, 1.2.1.11 https repositories, 1.2.1.15 `Acquire::Check-Date`, 1.3.1.1 `apparmor-utils`, 1.6.2 `/etc/issue`, 1.6.3 `/etc/issue.net`, 1.6.12 `update-notifier-motd.timer`.

**Not in this batch:** 1.6.4 is already PASS (Batch 1). 1.6.5 is Batch 8 (sshd `Banner`). 1.4.1 GRUB password stays out. No `update-initramfs` is called. A package trigger that rebuilds the image is a stop: Paste 1 restores the `.pre-batch5` copy and exits.

## Open questions (recommendation marked)

1. **1.6.2 and 1.6.3 banner text.** (a) **Rec: one line, `Authorized use only. Activity is monitored.`** This is the section 5 SSH warning AJ already accepted. It replaces the Ubuntu release line in both files. (b) Same warning, and keep a second `\n \l` line in `/etc/issue` so the console still shows the hostname. (c) Leave both rules FAIL.
2. **1.2.1.11 https.** (a) **Rec: change only the scheme.** `http://us.archive.ubuntu.com/ubuntu/` and `http://security.ubuntu.com/ubuntu/` become `https://` on the same hosts. Suites and components stay. `ubuntu.sources.curtin.orig` is not an apt source (the name does not end in `.sources`). (b) Leave the rule FAIL.
3. **1.3.1.1 `apparmor-utils`.** (a) **Rec: install it** with `--no-install-recommends` from the current cache, before the https change. The simulation on Johnny (2026-11-04, no sudo) is `0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded`: `apparmor-utils`, `python3-apparmor`, `python3-libapparmor`, all `5.0.2-0ubuntu1~26.04.1`. `apparmor` is already that version and stays. Governance has not vetted the package. (b) Leave the rule FAIL.
4. **1.2.1.15 and 1.6.12.** **Rec: include both in Paste 1.** `Acquire::Check-Date "true"` (the compiled-in default, written down so the audit can see it) and `systemctl disable --now update-notifier-motd.timer`. Alternative for either: leave that rule FAIL and delete its lines before the paste is run.

## Live state (read-only SSH, 2026-11-04)

Kernel `7.0.0-42-generic` only (`linux-image-7.0.0-42-generic` and the `linux-image-generic` metapackage, both `7.0.0-42.42`). `systemctl --failed` prints `0 loaded units listed.` No `/run/reboot-required`. `/boot` is 2.0G with 1.8G free.

Initrd, one file, mode `0600` root:root:

```
42618411 2026-11-03 06:13:32.840646209 +0000
```

That is the Batch 2 rebuild, re-read at A2b and again this session. The last `sha256sum -c` that printed `OK` is Batch 4 D2. The recorded hash is `f0a42b98383cce09397c4fa998a518a1452ed303701a732e390e5433137618a7`. This session could not read the file (mode `0600`). Paste 1 checks the hash before it continues. `~/cis-audit/initrd-mods-pre-batch4.txt` and `initrd-sha256-pre-batch4.txt` are still on Johnny. They stay. Batch 5 writes `pre-batch5` names beside them.

`/etc/fstab` is 778 bytes, mode `0644` root:root, sha256 `065034aa079d9d208683d9b977e8b34b167ddac39ca85809d02776cfb835ce69`. Four lines: XFS `/`, ext4 `/boot`, vfat `/boot/efi`, `/swap.img`. No `/tmp` line and no `/dev/shm` line.

`/tmp` is `tmp.mount` from systemd (`/usr/lib/systemd/system/tmp.mount`, package `systemd`). No drop-in. Packaged `Options=` line, copied from `systemctl cat` this session:

```
Options=mode=1777,strictatime,nosuid,nodev,size=50%%,nr_inodes=1m,x-systemd.graceful-option=usrquota
```

`findmnt -kn /tmp` prints `rw,nosuid,nodev,nr_inodes=1048576,inode64,usrquota`. `findmnt` with two mount points on one command printed nothing this session, so every check below names one mount point.

`/dev/shm` has no unit file (`systemctl cat dev-shm.mount` prints `No files found`). `findmnt -kn /dev/shm` prints `rw,nosuid,nodev,inode64,usrquota`.

`/etc/issue` is `Ubuntu 26.04.1 LTS \n \l` plus a blank line. `/etc/issue.net` is `Ubuntu 26.04.1 LTS`. Both are `base-files` conffiles. `/etc/apt/sources.list.d/ubuntu.sources` is the deb822 file quoted under Paste 1, with `http://`. `apt-config dump` has no `Check-Date` line. `apparmor` `5.0.2-0ubuntu1~26.04.1` is installed and `apparmor.service` is active. `apparmor-utils` is not installed. `update-notifier-motd.timer` is enabled and active via `/etc/systemd/system/timers.target.wants/update-notifier-motd.timer` (package `update-notifier-common`, unit file under `/lib/systemd/system/`). `ssh.socket` is active. `ca-certificates` `20260816ubuntu0.26.04.1` and `apt` `3.2.0` are installed.

`systemd-modules-load.service`: `Result=success`, `ExecMainStatus=0`, `ActiveState=active`. `systemctl is-failed` prints `active` for this oneshot when it succeeded. That print is a pass. The non-root journal for the 2026-11-04 06:05:45 UTC boot shows `Deactivated successfully` and `Stopped`, and no `Failed` line.

`systemd-cryptsetup@dm_crypt\x2d0.service` is `active` / `exited`. No `systemd-ask-password@` instance is running. `systemd-ask-password-console.service` is inactive.

## Recovery path

The initrd copy is the boot recovery. The fstab copy is the mount recovery. They are different failures.

**Initrd.** Paste 1 copies `/boot/initrd.img-7.0.0-42-generic` to `/boot/initrd.img-7.0.0-42-generic.pre-batch5` and records both hashes before any later step. The copy is mode `0600`, same bytes as the live image. GRUB does not list the copy. If a step rebuilds the live image, Paste 1 runs:

```
cp -a /boot/initrd.img-7.0.0-42-generic.pre-batch5 /boot/initrd.img-7.0.0-42-generic
sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
```

That check must print `/boot/initrd.img-7.0.0-42-generic: OK`. The script then exits. The rebuilt image is not kept and the reboot paste is not run.

**fstab and `/tmp`, before a reboot.** Paste 2 restores itself if a later line in that paste fails. To undo a Paste 2 that succeeded, the rollback block at the bottom is the one to run. It is not part of a paste.

**After a reboot, mount failure.** A bad `/dev/shm` line or a bad `tmp.mount` drop-in fails after the real root is mounted. TPM unlock is unchanged: the initrd still has the old fstab, because this batch does not rebuild it. At the AMT KVM, from the emergency shell or from a login:

```
cp -a /root/fstab.pre-batch5 /etc/fstab
rm -f /etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf
rmdir /etc/systemd/system/tmp.mount.d
systemctl daemon-reload
mount -o remount,exec /tmp
mount -o remount,exec /dev/shm
systemctl default
```

`/root/fstab.pre-batch5` is the hashed copy. `systemctl default` is for the emergency shell. From a normal login, stop after the two remounts and check `findmnt`.

**Passphrase prompt.** Type the LUKS recovery passphrase, finish the boot, and stop. That is a TPM unlock failure. Nothing in this batch changes Secure Boot, the shim, the BIOS, or PCR 7. The next reads are the initrd hash and the fstab backup. Do not treat the after-login block as a pass.

**dracut emergency shell.** The initrd failed before the real root. At the next GRUB menu, press `e` on the 7.0.0-42 entry, change the `initrd` line so it ends in `initrd.img-7.0.0-42-generic.pre-batch5`, and boot with Ctrl-x. **[Assumption]** the entry has one `initrd` line. `grub.cfg` was not readable this session (`Permission denied`). Paste 3 refuses to reboot unless the live image still matches the `.pre-batch5` hash, so this shell means that gate was skipped or the image changed after it.

## Why the mounts are split this way

`/tmp` is already the vendor `tmp.mount`. `systemd.generator(7)` on resolute says an `/etc/fstab` line overrides a vendor unit from `/usr`: https://manpages.ubuntu.com/manpages/resolute/man7/systemd.generator.7.html . An fstab line for `/tmp` would replace the packaged size, inode cap, and `usrquota` graceful option. The drop-in replaces only `Options=` and repeats the packaged line with `noexec` added. In the unit file, `50%%` is systemd's spelling of a literal percent (the packaged file on Johnny uses that spelling). The drop-in copies it.

`/dev/shm` is an API filesystem with no unit file. systemd's API file systems note says an fstab line supplies the options: https://systemd.io/API_FILE_SYSTEMS/ . `systemd.mount(5)` points at that note for API filesystems and prefers fstab for mounts a person edits: https://manpages.ubuntu.com/manpages/resolute/man5/systemd.mount.5.html . The new line repeats today's options and adds `noexec`.

`systemd-remount-fs.service` applies fstab options to API filesystems at boot. **[Assumption]** it passes `rw,nosuid,nodev,noexec,inode64,usrquota` through to the existing tmpfs. Paste 2 remounts with that string first. A kernel rejection fails the paste and restores, with no reboot. The boot path itself is what Paste 3 proves.

dracut's only trigger is `interest-await update-initramfs`: https://git.launchpad.net/ubuntu/+source/dracut/plain/debian/dracut.triggers?h=applied/ubuntu/resolute . Editing fstab or a unit drop-in does not run it. The initrd keeps today's fstab until some later rebuild. `/tmp` and `/dev/shm` are mounted by the real root's systemd after switch-root. **[Assumption]** the initrd's own `/tmp` and `/dev/shm` are discarded at switch-root and do not keep the host options.

`noexec` stops the kernel from executing a file on that mount. `sh /tmp/x` still runs, because `sh` is on `/usr`. dpkg's maintainer-script directory was not re-read this session. **[Assumption]** those scripts run from `/var/lib/dpkg`, so the apparmor install in Paste 1 is unaffected. Paste 1 runs before Paste 2, while `/tmp` still allows execution. The first later `apt-get install` is the real apt-under-noexec test. Rollback of the mounts does not need a reboot while SSH is up.

A2 and A2b have not been through a boot. Paste 3 is that boot. The after-login block is the A2/A2b gate plus the TPM re-check.

## Paste 1 — recoverable steps

One block. `sudo -v` is the first line. The initrd copy and both hashes happen before the banner, the timer, apt, and the package install.

```
sudo -v
sudo bash <<'EOF'
set -euo pipefail
export LC_ALL=C
[ "$(uname -r)" = "7.0.0-42-generic" ]
[ "$(systemctl --failed --no-pager --plain | tail -1)" = "0 loaded units listed." ]
[ "$(stat -c '%s %y' /boot/initrd.img-7.0.0-42-generic)" = "42618411 2026-11-03 06:13:32.840646209 +0000" ]
[ ! -e /run/reboot-required ]
[ ! -e /boot/initrd.img-7.0.0-42-generic.pre-batch5 ]
[ "$(ls /boot/vmlinuz-*)" = "/boot/vmlinuz-7.0.0-42-generic" ]
avail=$(df -P /boot | awk 'NR==2 {print $4}')
[ "$avail" -gt 100000 ]
install -d -o aj -g "$(id -gn aj)" -m 0755 /home/aj/cis-audit
cp -a /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch5
h1=$(sha256sum /boot/initrd.img-7.0.0-42-generic | awk '{print $1}')
h2=$(sha256sum /boot/initrd.img-7.0.0-42-generic.pre-batch5 | awk '{print $1}')
[ "$h1" = "$h2" ]
[ "$h1" = "f0a42b98383cce09397c4fa998a518a1452ed303701a732e390e5433137618a7" ]
sha256sum /boot/initrd.img-7.0.0-42-generic > /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
sha256sum /boot/initrd.img-7.0.0-42-generic.pre-batch5 > /home/aj/cis-audit/initrd-copy-sha256-pre-batch5.txt
chown aj:"$(id -gn aj)" /home/aj/cis-audit/initrd-sha256-pre-batch5.txt /home/aj/cis-audit/initrd-copy-sha256-pre-batch5.txt
lsinitrd -m /boot/initrd.img-7.0.0-42-generic | sed -n '/^dracut modules:/,/^=====/p' > /home/aj/cis-audit/initrd-mods-pre-batch5.txt
grep -qx crypt /home/aj/cis-audit/initrd-mods-pre-batch5.txt
grep -qx systemd-cryptsetup /home/aj/cis-audit/initrd-mods-pre-batch5.txt
grep -qx tpm2-tss /home/aj/cis-audit/initrd-mods-pre-batch5.txt
chown aj:"$(id -gn aj)" /home/aj/cis-audit/initrd-mods-pre-batch5.txt
cp -a /etc/issue /root/issue.pre-batch5
cp -a /etc/issue.net /root/issue.net.pre-batch5
printf '%s\n' 'Authorized use only. Activity is monitored.' > /etc/issue
printf '%s\n' 'Authorized use only. Activity is monitored.' > /etc/issue.net
chown root:root /etc/issue /etc/issue.net
chmod 0644 /etc/issue /etc/issue.net
if grep -q Ubuntu /etc/issue /etc/issue.net; then
  echo STOP-banner
  exit 1
fi
printf '%s\n' 'Acquire::Check-Date "true";' > /etc/apt/apt.conf.d/60-johnny-cis-check-date.conf
chown root:root /etc/apt/apt.conf.d/60-johnny-cis-check-date.conf
chmod 0644 /etc/apt/apt.conf.d/60-johnny-cis-check-date.conf
out=$(apt-config dump Acquire::Check-Date)
printf '%s\n' "$out"
case "$out" in
  *true*) ;;
  *) echo STOP-check-date; exit 1 ;;
esac
systemctl disable --now update-notifier-motd.timer
en=$(systemctl is-enabled update-notifier-motd.timer || true)
ac=$(systemctl is-active update-notifier-motd.timer || true)
[ "$en" = disabled ]
[ "$ac" = inactive ]
sim=$(apt-get -s install --no-install-recommends apparmor-utils)
printf '%s\n' "$sim"
printf '%s\n' "$sim" | grep -qx '0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded.'
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apparmor-utils
got=$(dpkg-query -W -f '${Version}\n' apparmor apparmor-utils python3-apparmor python3-libapparmor | sort -u)
[ "$got" = "5.0.2-0ubuntu1~26.04.1" ]
if ! sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt; then
  cp -a /boot/initrd.img-7.0.0-42-generic.pre-batch5 /boot/initrd.img-7.0.0-42-generic
  sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
  echo STOP-initrd-restored
  exit 1
fi
cp -a /etc/apt/sources.list.d/ubuntu.sources /root/ubuntu.sources.pre-batch5
cat > /etc/apt/sources.list.d/ubuntu.sources <<'SOURCES'
Types: deb
URIs: https://us.archive.ubuntu.com/ubuntu/
Suites: resolute resolute-updates resolute-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://security.ubuntu.com/ubuntu/
Suites: resolute-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
SOURCES
chown root:root /etc/apt/sources.list.d/ubuntu.sources
chmod 0644 /etc/apt/sources.list.d/ubuntu.sources
if ! apt-get update; then
  cp -a /root/ubuntu.sources.pre-batch5 /etc/apt/sources.list.d/ubuntu.sources
  echo STOP-apt-update
  exit 1
fi
if ! sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt; then
  cp -a /boot/initrd.img-7.0.0-42-generic.pre-batch5 /boot/initrd.img-7.0.0-42-generic
  sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
  echo STOP-initrd-restored
  exit 1
fi
[ "$(systemctl --failed --no-pager --plain | tail -1)" = "0 loaded units listed." ]
[ "$(systemctl is-active ssh.socket)" = active ]
echo OK-paste-1
EOF
```

Expected: both initrd hashes equal `f0a42b98383cce09397c4fa998a518a1452ed303701a732e390e5433137618a7`, `sha256sum -c` prints `OK` twice, the three dracut module names are present, `apt-config` prints a line containing `true`, the timer is `disabled` and `inactive`, the simulation line matches, four package versions match, `apt-get update` exits 0, `ssh.socket` stays `active`, and the last line is `OK-paste-1`. `dpkg --verify base-files` will flag `/etc/issue` and `/etc/issue.net`. That is the intended conffile edit.

`needrestart` on this host is Ubuntu mode (`-m u` in `/etc/apt/apt.conf.d/99needrestart`). Its README says that from Ubuntu 24.04 the default does not show a Debconf prompt and restarts affected services. **[Assumption]** the three new packages are not mapped into a running process, so nothing restarts. A failed unit or a dead `ssh.socket` is a stop.

`apparmor-utils` has no initramfs hook in its installed file list (https://packages.ubuntu.com/resolute-updates/all/apparmor-utils/filelist). A dpkg `triggers` control member would not show in that list. **[Assumption]** none of the three packages activates `update-initramfs`. The hash check is the stop if that is wrong. Restoring the image does not remove the packages.

HTTPS was fetched from this session, not from Johnny: `https://us.archive.ubuntu.com/ubuntu/dists/resolute/InRelease` (Origin Ubuntu, Suite resolute) and `https://security.ubuntu.com/ubuntu/dists/resolute-security/InRelease` (Origin Ubuntu, Suite resolute-security, Date Tue, 03 Nov 2026). resolute `sources.list(5)` documents the `https` scheme: https://manpages.ubuntu.com/manpages/resolute/man5/sources.list.5.html . `Acquire::Check-Date` defaults to true: https://manpages.ubuntu.com/manpages/resolute/man5/apt.conf.5.html . Johnny's `apt-get update` is the proof that this host can use the new URIs. A failure restores `ubuntu.sources` and exits. The packages and the Check-Date file stay; the rollback block removes them.

## Paste 2 — mount steps

Its own paste. Run only after Paste 1 printed `OK-paste-1`. No reboot in this block. The fstab copy and its hash happen before the drop-in and before the fstab line. If a later line fails, the script puts the backup back, removes the drop-in, and remounts `exec`.

```
sudo -v
sudo bash <<'EOF'
set -euo pipefail
export LC_ALL=C
sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
[ ! -e /etc/systemd/system/tmp.mount.d ]
if grep -E '[[:space:]]/dev/shm[[:space:]]' /etc/fstab; then
  echo STOP-shm-line-exists
  exit 1
fi
h0=$(sha256sum /etc/fstab | awk '{print $1}')
[ "$h0" = "065034aa079d9d208683d9b977e8b34b167ddac39ca85809d02776cfb835ce69" ]
cp -a /etc/fstab /root/fstab.pre-batch5
h1=$(sha256sum /etc/fstab | awk '{print $1}')
h2=$(sha256sum /root/fstab.pre-batch5 | awk '{print $1}')
[ "$h1" = "$h2" ]
sha256sum /root/fstab.pre-batch5 > /home/aj/cis-audit/fstab-sha256-pre-batch5.txt
chown aj:"$(id -gn aj)" /home/aj/cis-audit/fstab-sha256-pre-batch5.txt
restore_mounts() {
  trap - ERR
  set +e
  echo STOP-mount-restore
  cp -a /root/fstab.pre-batch5 /etc/fstab
  rm -f /etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf
  rmdir /etc/systemd/system/tmp.mount.d
  systemctl daemon-reload
  mount -o remount,exec /tmp
  mount -o remount,exec /dev/shm
  findmnt -kn /tmp
  findmnt -kn /dev/shm
  exit 1
}
trap restore_mounts ERR
install -d -o root -g root -m 0755 /etc/systemd/system/tmp.mount.d
cat > /etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf <<'UNIT'
[Mount]
# Johnny: CIS 1.1.2.1.4 noexec on /tmp (Batch 5). Options= replaces the packaged line.
Options=mode=1777,strictatime,nosuid,nodev,noexec,size=50%%,nr_inodes=1m,x-systemd.graceful-option=usrquota
UNIT
chown root:root /etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf
chmod 0644 /etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf
cat >> /etc/fstab <<'FSTAB'
# Johnny: CIS 1.1.2.2.4 noexec on /dev/shm (Batch 5)
tmpfs /dev/shm tmpfs rw,nosuid,nodev,noexec,inode64,usrquota 0 0
FSTAB
verify=$(findmnt --verify 2>&1 || true)
printf '%s\n' "$verify"
case "$verify" in
  *'0 parse errors, 0 errors'*) ;;
  *) echo STOP-fstab-verify; false ;;
esac
systemctl daemon-reload
mount -o remount,noexec /tmp
mount -o remount,rw,nosuid,nodev,noexec,inode64,usrquota /dev/shm
tmp_opts=$(findmnt -kn -o OPTIONS /tmp)
shm_opts=$(findmnt -kn -o OPTIONS /dev/shm)
printf '%s\n' "$tmp_opts" "$shm_opts"
for flag in nosuid nodev noexec; do
  case "$tmp_opts" in
    *"$flag"*) ;;
    *) echo "STOP-tmp-$flag"; false ;;
  esac
  case "$shm_opts" in
    *"$flag"*) ;;
    *) echo "STOP-shm-$flag"; false ;;
  esac
done
printf '%s\n' '#!/bin/sh' 'exit 0' > /tmp/johnny-batch5-noexec
chmod 0755 /tmp/johnny-batch5-noexec
if /tmp/johnny-batch5-noexec; then
  echo STOP-tmp-exec
  false
fi
rm -f /tmp/johnny-batch5-noexec
printf '%s\n' '#!/bin/sh' 'exit 0' > /dev/shm/johnny-batch5-noexec
chmod 0755 /dev/shm/johnny-batch5-noexec
if /dev/shm/johnny-batch5-noexec; then
  echo STOP-shm-exec
  false
fi
rm -f /dev/shm/johnny-batch5-noexec
sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
trap - ERR
echo OK-paste-2
EOF
```

Expected: `sha256sum -c` prints `OK` at the start and again at the end. `findmnt --verify` still contains `0 parse errors, 0 errors`. The existing `/swap.img` warning may remain. Both `findmnt` lines contain `nosuid`, `nodev`, and `noexec`. Both test binaries are refused. The last line is `OK-paste-2`. A `STOP-mount-restore` line means the backup is back in place and the reboot paste is not next.

`findmnt --verify` as non-root this session was `0 parse errors, 0 errors, 5 warnings` (permission denied on filesystem type, plus the swap-file warning). Root may print fewer warnings. An error count other than 0 restores.

## Paste 3 — reboot

Its own paste. Run only after Paste 2 printed `OK-paste-2`. Open the KVM first. Watch from the GRUB menu through the login prompt. Expected: no passphrase prompt. The login prompt appears on its own. `systemctl reboot` is the last command inside the script, so a failed check does not fall through to a reboot.

```
sudo -v
sudo bash <<'EOF'
set -euo pipefail
export LC_ALL=C
[ "$(uname -r)" = "7.0.0-42-generic" ]
[ "$(ls /boot/vmlinuz-*)" = "/boot/vmlinuz-7.0.0-42-generic" ]
got=$(printf '%s\n' /boot/initrd.img-*)
exp='/boot/initrd.img-7.0.0-42-generic
/boot/initrd.img-7.0.0-42-generic.pre-batch5'
[ "$got" = "$exp" ]
[ "$(stat -c '%s %y' /boot/initrd.img-7.0.0-42-generic)" = "42618411 2026-11-03 06:13:32.840646209 +0000" ]
sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
sha256sum -c /home/aj/cis-audit/fstab-sha256-pre-batch5.txt
[ ! -e /run/reboot-required ]
st=$(systemctl is-active apt-daily-upgrade.service || true)
[ "$st" = inactive ]
if pgrep -a -x unattended-upgrade || pgrep -a -x apt-get || pgrep -a -x apt; then
  echo STOP-upgrade
  exit 1
fi
tmp_opts=$(findmnt -kn -o OPTIONS /tmp)
shm_opts=$(findmnt -kn -o OPTIONS /dev/shm)
for flag in nosuid nodev noexec; do
  case "$tmp_opts" in
    *"$flag"*) ;;
    *) echo "STOP-tmp-$flag"; exit 1 ;;
  esac
  case "$shm_opts" in
    *"$flag"*) ;;
    *) echo "STOP-shm-$flag"; exit 1 ;;
  esac
done
echo OK-to-reboot
systemctl reboot
EOF
```

`unattended-upgrades.service` may stay active. Its process is the shutdown helper, and the name check above does not treat that helper as an upgrade. `sha256sum -c` on `fstab-sha256-pre-batch5.txt` checks `/root/fstab.pre-batch5`, the copy taken before the edit, so the live fstab can already contain the `/dev/shm` line.

The KVM watch is the TPM check. A passphrase prompt is a stop, as written under Recovery.

## After login — reboot checks

Not part of the reboot paste. Run it from rock-box or the laptop after SSH answers. This is the A2/A2b boot gate: `systemctl --failed` empty, `systemd-modules-load` clean, the own-`.ko` check with `ksmbd` printing `1`, the module diff, and the initrd hash. It also re-reads the mounts and the cryptsetup unit.

```
sudo -v
sudo bash <<'EOF'
set -euo pipefail
export LC_ALL=C
[ "$(uname -r)" = "7.0.0-42-generic" ]
uptime -p
[ "$(systemctl --failed --no-pager --plain | tail -1)" = "0 loaded units listed." ]
[ "$(systemctl show systemd-modules-load.service -p Result --value)" = success ]
[ "$(systemctl show systemd-modules-load.service -p ExecMainStatus --value)" = 0 ]
if journalctl -b -u systemd-modules-load.service -p err --no-pager | grep -q .; then
  echo STOP-modules-load-journal
  exit 1
fi
[ "$(systemctl show 'systemd-cryptsetup@dm_crypt\x2d0.service' -p Result --value)" = success ]
[ "$(systemctl show 'systemd-cryptsetup@dm_crypt\x2d0.service' -p ExecMainStatus --value)" = 0 ]
ask=$(systemctl is-active systemd-ask-password-console.service || true)
[ "$ask" = inactive ]
tmp_opts=$(findmnt -kn -o OPTIONS /tmp)
shm_opts=$(findmnt -kn -o OPTIONS /dev/shm)
printf '%s\n' "$tmp_opts" "$shm_opts"
for flag in nosuid nodev noexec; do
  case "$tmp_opts" in
    *"$flag"*) ;;
    *) echo "STOP-tmp-$flag"; exit 1 ;;
  esac
  case "$shm_opts" in
    *"$flag"*) ;;
    *) echo "STOP-shm-$flag"; exit 1 ;;
  esac
done
{
  for m in 9p adfs affs befs bfs blocklayoutdriver btrfs cachefiles ceph cifs cifs_md4 coda cuse dlm efs erofs exfat f2fs gfs2 grace hpfs isofs jfs kafs lockd minix msdos netfs nfs nfs_acl nfs_layout_flexfiles nfs_layout_nfsv41_files nfsd nfsv2 nfsv3 nfsv4 nilfs2 ntfs3 ocfs2 ocfs2_dlm ocfs2_dlmfs ocfs2_nodemanager ocfs2_stack_o2cb ocfs2_stack_user ocfs2_stackglue omfs orangefs qnx4 qnx6 quota_tree quota_v1 quota_v2 romfs ubifs udf ufs vboxsf virtiofs zonefs overlay; do
    p=$(modinfo -n "$m")
    n=$(modprobe -n -v "$m" 2>&1 | grep -cF -- "$p" || true)
    printf '%s %s\n' "$n" "$m"
  done
  p=$(modinfo -n ksmbd)
  n=$(modprobe -n -v ksmbd 2>&1 | grep -cF -- "$p" || true)
  printf '%s %s\n' "$n" ksmbd
} | tee /home/aj/cis-audit/own-ko-batch5.txt
awk '
  NF != 2 { exit 1 }
  $2 == "ksmbd" { if ($1 != 1) exit 1; k++; next }
  { if ($1 != 0) exit 1; z++ }
  END { if (k != 1 || z != 60) exit 1 }
' /home/aj/cis-audit/own-ko-batch5.txt
live=$(lsinitrd -m /boot/initrd.img-7.0.0-42-generic | sed -n '/^dracut modules:/,/^=====/p')
printf '%s\n' "$live" | diff -u /home/aj/cis-audit/initrd-mods-pre-batch5.txt -
printf '%s\n' "$live" | grep -qx crypt
printf '%s\n' "$live" | grep -qx systemd-cryptsetup
printf '%s\n' "$live" | grep -qx tpm2-tss
sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
echo OK-boot-gate
EOF
```

Expected:

- `0 loaded units listed.`
- `systemd-modules-load`: `Result=success`, `ExecMainStatus=0`, and no priority-err journal line. `is-failed` printing `active` is the success state from before the reboot and is not a failure.
- The 59 filesystem names and `overlay` each print `0`. `ksmbd` prints `1`. A `0` on `ksmbd` means the check is blind. The awk requires 60 zeros and one `1`.
- `diff` prints nothing. `crypt`, `systemd-cryptsetup`, and `tpm2-tss` are in the live module list.
- `sha256sum -c` prints `/boot/initrd.img-7.0.0-42-generic: OK`.
- `/tmp` and `/dev/shm` still contain `nosuid`, `nodev`, and `noexec`. The full option string may differ from the live remount, because the next boot applies the unit and the fstab line. The three flags are the pass.
- Cryptsetup `Result=success` and `ExecMainStatus=0`. `systemd-ask-password-console.service` is `inactive`. Those unit reads do not show whether a person typed the passphrase. The KVM watch is the TPM re-check.
- Last line `OK-boot-gate`.

The `.pre-batch5` copy stays until that block passes and AJ says to remove it. `~/cis-audit/*-pre-batch4.txt` and `/root/apport.default.pre-batch4` stay.

## Rollback (not part of any paste)

Mounts, after a successful Paste 2, before or instead of Paste 3:

```
sudo -v
sudo bash <<'EOF'
set -euo pipefail
export LC_ALL=C
cp -a /root/fstab.pre-batch5 /etc/fstab
rm -f /etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf
rmdir /etc/systemd/system/tmp.mount.d
systemctl daemon-reload
mount -o remount,exec /tmp
mount -o remount,exec /dev/shm
findmnt -kn /tmp
findmnt -kn /dev/shm
sha256sum -c /home/aj/cis-audit/fstab-sha256-pre-batch5.txt
EOF
```

Expected: neither `findmnt` line contains `noexec`, and `sha256sum -c` prints OK for `/root/fstab.pre-batch5`.

The rest, only to undo a successful Paste 1:

```
sudo -v
sudo bash <<'EOF'
set -euo pipefail
export LC_ALL=C
cp -a /root/issue.pre-batch5 /etc/issue
cp -a /root/issue.net.pre-batch5 /etc/issue.net
rm -f /etc/apt/apt.conf.d/60-johnny-cis-check-date.conf
cp -a /root/ubuntu.sources.pre-batch5 /etc/apt/sources.list.d/ubuntu.sources
systemctl enable --now update-notifier-motd.timer
DEBIAN_FRONTEND=noninteractive apt-get remove -y apparmor-utils python3-apparmor python3-libapparmor
apt-get update
if ! sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt; then
  cp -a /boot/initrd.img-7.0.0-42-generic.pre-batch5 /boot/initrd.img-7.0.0-42-generic
  sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
  echo STOP-initrd-restored
  exit 1
fi
EOF
```

`apparmor` stays. `apt-get remove` can activate a trigger. The same restore covers that. Do not delete `/boot/initrd.img-7.0.0-42-generic.pre-batch5` in either rollback.

## After the boot gate

Governance re-audits 1.1.2.1.4, 1.1.2.2.4, 1.2.1.11, 1.2.1.15, 1.3.1.1, 1.6.2, 1.6.3, and 1.6.12 with the local scripts. Verdicts stay Governance's. Mirrors under `etc/` (same paths, same commit as the handoff rows, after the apply): `etc/fstab`, `etc/issue`, `etc/issue.net`, `etc/apt/sources.list.d/ubuntu.sources`, `etc/apt/apt.conf.d/60-johnny-cis-check-date.conf`, `etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf`. The timer change is the removal of `/etc/systemd/system/timers.target.wants/update-notifier-motd.timer`. Handoff revision and the session CSV wait until this session ends.
