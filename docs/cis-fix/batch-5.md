# CIS L1 fix pass, Batch 5: mounts, apt, banners

**Status:** APPLIED, rev 4 (Grok, 2026-11-04). Claude on the after-login result: consistent with a pass, no findings. Verdicts are not written here. Governance re-audits the eight rules. 1.3.1.1 stays FAIL until the install block runs. AJ (2026-11-04): close the batch after that install, not with the rule deferred. `.pre-batch5` stays until that install, because its restore copies the image back.

**Run order:** Paste 1, then the install block only after Governance's vet and the SBOM rows, then Paste 2, then Paste 3, then the after-login block. A paste that does not print its `OK-` line is a stop even when it printed no `STOP-` line. Do not start the next paste.

**Rules in scope (8):** 1.1.2.1.4 `/tmp` noexec, 1.1.2.2.4 `/dev/shm` noexec, 1.2.1.11 https repositories, 1.2.1.15 `Acquire::Check-Date`, 1.3.1.1 `apparmor-utils`, 1.6.2 `/etc/issue`, 1.6.3 `/etc/issue.net`, 1.6.12 `update-notifier-motd.timer`.

**Not in this batch:** 1.6.4 is already PASS (Batch 1). 1.6.5 is Batch 8 (sshd `Banner`). 1.4.1 GRUB password stays out. No `update-initramfs` is called. A package trigger that rebuilds the image is a stop: Paste 1 restores the `.pre-batch5` copy and exits.

## Decisions (AJ, 2026-11-04, with the rev 1 review)

1. **1.6.2 and 1.6.3.** (a) One line, `Authorized use only. Activity is monitored.`
2. **1.2.1.11.** (a) Change only the scheme, on the same two hosts. `ubuntu.sources.curtin.orig` is not an apt source.
3. **1.3.1.1.** (a) Install `apparmor-utils`, **behind a Governance gate.** The install is not in Paste 1. It waits until Governance's vet is in the repo and the handoff SBOM has rows for `apparmor-utils`, `python3-apparmor`, and `python3-libapparmor`. Until that gate, 1.3.1.1 stays FAIL. The simulation (2026-11-04, no sudo) is still `0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded`, all `5.0.2-0ubuntu1~26.04.1`. `apparmor` is already that version.
4. **1.2.1.15 and 1.6.12.** Both stay in Paste 1: `Acquire::Check-Date "true"` and `systemctl disable --now update-notifier-motd.timer`.

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

`/etc/issue` is `Ubuntu 26.04.1 LTS \n \l` plus a blank line. `/etc/issue.net` is `Ubuntu 26.04.1 LTS`. Both are `base-files` conffiles. `dpkg --verify base-files` will flag those two after Paste 1. That is the intended conffile edit. `/etc/apt/sources.list.d/ubuntu.sources` is 398 bytes, ends in a newline, sha256 `077ad25a51b484eae9bebddd027b18e11d85ec7b69aa0d817e7960b631fa5c8a`. It has exactly two `URIs:` lines, both `http://` (`us.archive.ubuntu.com` and `security.ubuntu.com`). `dpkg -S` on that path prints `no path found matching pattern`. It is not a package conffile, so an upgrade will not prompt for it and will not put the http lines back. `apt-config dump` has no `Check-Date` line. `apparmor` `5.0.2-0ubuntu1~26.04.1` is installed and `apparmor.service` is active. `apparmor-utils` is not installed. `update-notifier-motd.timer` is enabled and active via `/etc/systemd/system/timers.target.wants/update-notifier-motd.timer` (package `update-notifier-common`, unit file under `/lib/systemd/system/`). `ssh.socket` is active. `ca-certificates` `20260816ubuntu0.26.04.1` and `apt` `3.2.0` are installed.

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

`noexec` stops the kernel from executing a file on that mount. `sh /tmp/x` still runs, because `sh` is on `/usr`. dpkg's maintainer-script directory was not re-read this session. **[Assumption]** those scripts run from `/var/lib/dpkg`. The install block is the first `apt-get install` after `noexec` is on, so it is the apt-under-noexec test. It stays behind Governance's vet and the SBOM rows.

A2 and A2b have not been through a boot. Paste 3 is that boot. The after-login block is the A2/A2b gate plus the TPM re-check.

## Paste 1 — recoverable steps

One block. `sudo -v` is the first line. The initrd copy and both hashes happen before the banner, the timer, and apt. There is no package install in this block. `apt-get` is given `</dev/null` so it cannot read the rest of the script. `NEEDRESTART_MODE=l` is list-only: https://manpages.ubuntu.com/manpages/resolute/man1/needrestart.1.html (`NEEDRESTART_MODE` overrides the restart mode; `l` is list only).

A second run keeps an existing `/boot/initrd.img-7.0.0-42-generic.pre-batch5` when its hash is `f0a42b98383cce09397c4fa998a518a1452ed303701a732e390e5433137618a7`. It does not overwrite `/root/issue.pre-batch5`, `/root/issue.net.pre-batch5`, or `/root/ubuntu.sources.pre-batch5` when those files already exist.

```
sudo -v
sudo bash <<'EOF'
set -euo pipefail
export LC_ALL=C
known=f0a42b98383cce09397c4fa998a518a1452ed303701a732e390e5433137618a7
src_sha=077ad25a51b484eae9bebddd027b18e11d85ec7b69aa0d817e7960b631fa5c8a
[ "$(uname -r)" = "7.0.0-42-generic" ]
[ "$(systemctl --failed --no-pager --plain | tail -1)" = "0 loaded units listed." ]
[ "$(stat -c '%s %y' /boot/initrd.img-7.0.0-42-generic)" = "42618411 2026-11-03 06:13:32.840646209 +0000" ]
[ ! -e /run/reboot-required ]
[ "$(ls /boot/vmlinuz-*)" = "/boot/vmlinuz-7.0.0-42-generic" ]
h1=$(sha256sum /boot/initrd.img-7.0.0-42-generic | awk '{print $1}')
if [ "$h1" != "$known" ]; then
  echo STOP-initrd-live
  exit 1
fi
install -d -o aj -g "$(id -gn aj)" -m 0755 /home/aj/cis-audit
if [ -e /boot/initrd.img-7.0.0-42-generic.pre-batch5 ]; then
  h2=$(sha256sum /boot/initrd.img-7.0.0-42-generic.pre-batch5 | awk '{print $1}')
  if [ "$h2" != "$known" ]; then
    echo STOP-initrd-copy
    exit 1
  fi
  echo initrd-copy-kept
else
  avail=$(df -P /boot | awk 'NR==2 {print $4}')
  [ "$avail" -gt 100000 ]
  cp -a /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch5
  h2=$(sha256sum /boot/initrd.img-7.0.0-42-generic.pre-batch5 | awk '{print $1}')
  [ "$h2" = "$known" ]
fi
sha256sum /boot/initrd.img-7.0.0-42-generic > /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
sha256sum /boot/initrd.img-7.0.0-42-generic.pre-batch5 > /home/aj/cis-audit/initrd-copy-sha256-pre-batch5.txt
chown aj:"$(id -gn aj)" /home/aj/cis-audit/initrd-sha256-pre-batch5.txt /home/aj/cis-audit/initrd-copy-sha256-pre-batch5.txt
lsinitrd -m /boot/initrd.img-7.0.0-42-generic | sed -n '/^dracut modules:/,/^=====/p' > /home/aj/cis-audit/initrd-mods-pre-batch5.txt
grep -qx crypt /home/aj/cis-audit/initrd-mods-pre-batch5.txt
grep -qx systemd-cryptsetup /home/aj/cis-audit/initrd-mods-pre-batch5.txt
grep -qx tpm2-tss /home/aj/cis-audit/initrd-mods-pre-batch5.txt
chown aj:"$(id -gn aj)" /home/aj/cis-audit/initrd-mods-pre-batch5.txt
if [ -e /root/issue.pre-batch5 ]; then
  echo keep /root/issue.pre-batch5
else
  cp -a /etc/issue /root/issue.pre-batch5
fi
if [ -e /root/issue.net.pre-batch5 ]; then
  echo keep /root/issue.net.pre-batch5
else
  cp -a /etc/issue.net /root/issue.net.pre-batch5
fi
printf '%s\n' 'Authorized use only. Activity is monitored.' > /etc/issue
printf '%s\n' 'Authorized use only. Activity is monitored.' > /etc/issue.net
chown root:root /etc/issue /etc/issue.net
chmod 0644 /etc/issue /etc/issue.net
if grep -q Ubuntu /etc/issue /etc/issue.net; then
  cp -a /root/issue.pre-batch5 /etc/issue
  cp -a /root/issue.net.pre-batch5 /etc/issue.net
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
  *) rm -f /etc/apt/apt.conf.d/60-johnny-cis-check-date.conf; echo STOP-check-date; exit 1 ;;
esac
systemctl disable --now update-notifier-motd.timer
en=$(systemctl is-enabled update-notifier-motd.timer || true)
ac=$(systemctl is-active update-notifier-motd.timer || true)
[ "$en" = disabled ]
[ "$ac" = inactive ]
src=/etc/apt/sources.list.d/ubuntu.sources
bak=/root/ubuntu.sources.pre-batch5
http_n=$(grep -cE '^URIs: http://' "$src" || true)
https_n=$(grep -cE '^URIs: https://' "$src" || true)
if [ -e "$bak" ] && [ "$https_n" = 2 ] && [ "$http_n" = 0 ]; then
  bak_h=$(sha256sum "$bak" | awk '{print $1}')
  if [ "$bak_h" != "$src_sha" ]; then
    echo STOP-sources-backup
    exit 1
  fi
  echo sources-already-https
else
  if [ "$(sha256sum "$src" | awk '{print $1}')" != "$src_sha" ] || [ "$http_n" != 2 ] || [ "$https_n" != 0 ]; then
    echo STOP-sources-pre
    exit 1
  fi
  if [ -e "$bak" ]; then
    bak_h=$(sha256sum "$bak" | awk '{print $1}')
    if [ "$bak_h" != "$src_sha" ]; then
      echo STOP-sources-backup
      exit 1
    fi
    echo keep "$bak"
  else
    cp -a "$src" "$bak"
  fi
  sed -i 's|^URIs: http://|URIs: https://|' "$src"
  http_n=$(grep -cE '^URIs: http://' "$src" || true)
  https_n=$(grep -cE '^URIs: https://' "$src" || true)
  uri_n=$(grep -cE '^URIs: ' "$src" || true)
  if [ "$http_n" != 0 ] || [ "$https_n" != 2 ] || [ "$uri_n" != 2 ] \
    || ! grep -qx 'URIs: https://us.archive.ubuntu.com/ubuntu/' "$src" \
    || ! grep -qx 'URIs: https://security.ubuntu.com/ubuntu/' "$src"; then
    cp -a "$bak" "$src"
    echo STOP-sources-result
    exit 1
  fi
fi
if ! NEEDRESTART_MODE=l apt-get update </dev/null; then
  cp -a "$bak" "$src"
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

Expected: the live initrd hash and the copy hash are both `f0a42b98383cce09397c4fa998a518a1452ed303701a732e390e5433137618a7`. A second run prints `initrd-copy-kept` and does not copy again. The three dracut module names are present. `apt-config` prints a line containing `true`. The timer is `disabled` and `inactive`. After `sed`, the file has two `URIs:` lines and no `http://` URI line: `https://us.archive.ubuntu.com/ubuntu/` and `https://security.ubuntu.com/ubuntu/`. `apt-get update` exits 0. `ssh.socket` stays `active`. The last line is `OK-paste-1`.

`dpkg --verify base-files` will flag `/etc/issue` and `/etc/issue.net`. `dpkg -S /etc/apt/sources.list.d/ubuntu.sources` still finds no package. That file is not a conffile residual. resolute `sources.list(5)` documents the `https` scheme: https://manpages.ubuntu.com/manpages/resolute/man5/sources.list.5.html . `Acquire::Check-Date` defaults to true: https://manpages.ubuntu.com/manpages/resolute/man5/apt.conf.5.html . HTTPS for both InRelease files was fetched from this session, not from Johnny. Johnny's `apt-get update` is the proof on the host.

### After a STOP

The script exits before `OK-paste-1`. Do not start Paste 2. Do not reboot. Leave every `.pre-batch5` file in place.

| Line | What is true | What to do |
|---|---|---|
| `STOP-initrd-live` | The live initrd hash is not the Batch 4 hash. No copy was made by this run. | Stop. Tell the Brain the live hash. If `.pre-batch5` is already the known hash, the recovery copy under Recovery is the way back. |
| `STOP-initrd-copy` | `.pre-batch5` exists and its hash is not the known hash. The script did not overwrite it. | Stop. Tell the Brain both hashes. Do not delete the copy. |
| `STOP-banner` | The script put the issue backups back. | Read `/etc/issue` and `/etc/issue.net`. Tell the Brain. |
| `STOP-check-date` | The script removed `60-johnny-cis-check-date.conf`. The banner and the timer change from this run stay. | Tell the Brain the `apt-config` line. |
| `STOP-sources-pre` | `ubuntu.sources` is not the recorded file (hash `077ad25a…`, two `^URIs: http://` lines, no `https` URI). Nothing was edited. | Stop. Tell the Brain. |
| `STOP-sources-backup` | `/root/ubuntu.sources.pre-batch5` exists and is not that recorded hash. The live file was not edited by this run. | Stop. Do not delete the backup. Tell the Brain. |
| `STOP-sources-result` | `sed` did not leave exactly the two https URI lines. The script copied the backup back. | Tell the Brain. A later run can try again. |
| `STOP-apt-update` | `apt-get update` failed. The script copied the backup back, so the URI lines are `http://` again. The banner, the Check-Date file, and the timer change stay. | Read the apt output. Tell the Brain. A later run of Paste 1 is safe: the initrd copy and the three `/root` backups are kept, and `sed` runs again. |
| `STOP-initrd-restored` | Something rebuilt the live initrd. The script copied `.pre-batch5` back and `sha256sum -c` printed `OK`. | Stop. Tell the Brain what apt printed. Do not reboot. |

### Install block

AJ accepted R-AAU-1, option A (2026-11-04). One block. `sudo -v` is the first line. The three packages are pinned. The simulation must be `0 upgraded, 3 newly installed, 0 to remove`. A larger "not upgraded" count is the other pending packages and is not a stop. `NEEDRESTART_MODE=l` lists restart requests and does not restart anything (https://manpages.ubuntu.com/manpages/resolute/man1/needrestart.1.html). If the live initrd hash changes, the script copies `.pre-batch5` back and exits. Do not run `aa-disable`, `aa-complain`, or `aa-teardown`.

```
sudo -v
sudo bash <<'EOF'
set -euo pipefail
export LC_ALL=C
sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
pol=$(apt-cache policy apparmor-utils python3-apparmor python3-libapparmor | awk '/^  Candidate:/{print $2}' | sort -u)
[ "$pol" = "5.0.2-0ubuntu1~26.04.1" ]
show=$(apt-cache show apparmor-utils=5.0.2-0ubuntu1~26.04.1 python3-apparmor=5.0.2-0ubuntu1~26.04.1 python3-libapparmor=5.0.2-0ubuntu1~26.04.1 | grep '^SHA256:')
printf '%s\n' "$show" | grep -qx 'SHA256: 6d251b6ffefb54ccee50518bae414b5dd8abf0a55faf9687b550b153886e5d4c'
printf '%s\n' "$show" | grep -qx 'SHA256: df67e000dcec6a8888c89dc0bdf15ad5e2d33b73601265a2a69579816ba6cdff'
printf '%s\n' "$show" | grep -qx 'SHA256: fabb4c780038884b4b616a9568d90ed3113683c15f22fe9c44edf5540a844bda'
install -d -o aj -g "$(id -gn aj)" -m 0755 /home/aj/cis-audit
aa-status > /home/aj/cis-audit/aa-status-before-apparmor-utils.txt || echo "aa-status-before-exit:$?"
sha256sum /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch5 > /home/aj/cis-audit/initrd-before-apparmor-utils.txt
head -4 /home/aj/cis-audit/aa-status-before-apparmor-utils.txt
sim=$(NEEDRESTART_MODE=l apt-get -s install --no-install-recommends apparmor-utils=5.0.2-0ubuntu1~26.04.1 python3-apparmor=5.0.2-0ubuntu1~26.04.1 python3-libapparmor=5.0.2-0ubuntu1~26.04.1 </dev/null)
printf '%s\n' "$sim"
printf '%s\n' "$sim" | grep -q '^0 upgraded, 3 newly installed, 0 to remove '
ninst=$(printf '%s\n' "$sim" | grep -c '^Inst ')
[ "$ninst" = 3 ]
mark=$(wc -l < /var/log/apt/term.log)
NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apparmor-utils=5.0.2-0ubuntu1~26.04.1 python3-apparmor=5.0.2-0ubuntu1~26.04.1 python3-libapparmor=5.0.2-0ubuntu1~26.04.1 </dev/null
got=$(dpkg-query -W -f '${Version}\n' apparmor apparmor-utils python3-apparmor python3-libapparmor | sort -u)
[ "$got" = "5.0.2-0ubuntu1~26.04.1" ]
aa-status > /home/aj/cis-audit/aa-status-after-apparmor-utils.txt || echo "aa-status-after-exit:$?"
if ! diff /home/aj/cis-audit/aa-status-before-apparmor-utils.txt /home/aj/cis-audit/aa-status-after-apparmor-utils.txt; then
  echo STOP-aa-status
  exit 1
fi
echo aa-status-identical
sha256sum /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch5 > /home/aj/cis-audit/initrd-after-apparmor-utils.txt
if ! diff /home/aj/cis-audit/initrd-before-apparmor-utils.txt /home/aj/cis-audit/initrd-after-apparmor-utils.txt; then
  cp -a /boot/initrd.img-7.0.0-42-generic.pre-batch5 /boot/initrd.img-7.0.0-42-generic
  sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
  echo STOP-initrd-restored
  exit 1
fi
echo initrd-identical
if tail -n +"$((mark + 1))" /var/log/apt/term.log | grep -E 'update-initramfs|dracut' | grep -q .; then
  echo STOP-initramfs-log
  exit 1
fi
chown aj:"$(id -gn aj)" /home/aj/cis-audit/aa-status-before-apparmor-utils.txt /home/aj/cis-audit/aa-status-after-apparmor-utils.txt /home/aj/cis-audit/initrd-before-apparmor-utils.txt /home/aj/cis-audit/initrd-after-apparmor-utils.txt
[ "$(systemctl is-active ssh.socket)" = active ]
echo OK-apparmor-utils
EOF
```

`STOP-aa-status` means the profile list changed. The packages stay. Do not reboot. `STOP-initrd-restored` means the script put `.pre-batch5` back. `STOP-initramfs-log` means the apt log mentioned an initramfs rebuild. Send the output before any PASS is written.

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
[ "$(tail -c1 /etc/fstab | wc -l)" -eq 1 ]
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
systemctl show -p Options tmp.mount
tmp_opts=$(findmnt -kn -o OPTIONS /tmp)
shm_opts=$(findmnt -kn -o OPTIONS /dev/shm)
printf '%s\n' "$tmp_opts" "$shm_opts"
for flag in nosuid nodev noexec; do
  case ",$tmp_opts," in
    *,"$flag",*) ;;
    *) echo "STOP-tmp-$flag"; false ;;
  esac
  case ",$shm_opts," in
    *,"$flag",*) ;;
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

Expected: `sha256sum -c` prints `OK` at the start and again at the end. `findmnt --verify` still contains `0 parse errors, 0 errors`. The existing `/swap.img` warning may remain. The fstab already ends in a newline (`tail -c1 | wc -l` is 1; checked on Johnny 2026-11-04), so the appended `/dev/shm` line does not glue to `/swap.img`. Each of `nosuid`, `nodev`, and `noexec` is matched as its own comma-separated field. Both test binaries are refused. The last line is `OK-paste-2`. A `STOP-mount-restore` line means the backup is back in place and the reboot paste is not next.

`findmnt --verify` as non-root this session was `0 parse errors, 0 errors, 5 warnings` (permission denied on filesystem type, plus the swap-file warning). Root may print fewer warnings. An error count other than 0 restores. `systemctl show -p Options tmp.mount` is printed after the remount. It is not a pass/fail line.

| Line | What to do |
|---|---|
| `STOP-shm-line-exists` | `/dev/shm` is already in fstab. Nothing was written. Tell the Brain. |
| `STOP-mount-restore` | A step after the backup failed. The script put `/root/fstab.pre-batch5` back and removed the drop-in. Tell the Brain the line printed just before it. |
| No `OK-paste-2` and no `STOP-` line | A check before the edits failed: the initrd hash, the drop-in directory already existing, the fstab hash, or the trailing newline. The live fstab was not changed. |

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
sha256sum -c /home/aj/cis-audit/initrd-copy-sha256-pre-batch5.txt
sha256sum -c /home/aj/cis-audit/fstab-sha256-pre-batch5.txt
[ ! -e /run/reboot-required ]
st=$(systemctl is-active apt-daily-upgrade.service || true)
[ "$st" = inactive ]
if pgrep -a -x unattended-upgrade || pgrep -a -x apt-get || pgrep -a -x apt; then
  echo STOP-upgrade
  exit 1
fi
grep -qx 'tmpfs /dev/shm tmpfs rw,nosuid,nodev,noexec,inode64,usrquota 0 0' /etc/fstab
grep -qx 'Options=mode=1777,strictatime,nosuid,nodev,noexec,size=50%%,nr_inodes=1m,x-systemd.graceful-option=usrquota' /etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf
[ "$(stat -c '%a %U:%G' /etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf)" = "644 root:root" ]
tmp_opts=$(findmnt -kn -o OPTIONS /tmp)
shm_opts=$(findmnt -kn -o OPTIONS /dev/shm)
for flag in nosuid nodev noexec; do
  case ",$tmp_opts," in
    *,"$flag",*) ;;
    *) echo "STOP-tmp-$flag"; exit 1 ;;
  esac
  case ",$shm_opts," in
    *,"$flag",*) ;;
    *) echo "STOP-shm-$flag"; exit 1 ;;
  esac
done
echo OK-to-reboot
systemctl reboot
EOF
```

`unattended-upgrades.service` may stay active. Its process is the shutdown helper, and the name check above does not treat that helper as an upgrade. `sha256sum -c` on `fstab-sha256-pre-batch5.txt` checks `/root/fstab.pre-batch5`, the copy taken before the edit, so the live fstab can already contain the `/dev/shm` line. Before the reboot the script also requires that live line, the drop-in `Options=` line, and mode `644 root:root` on the drop-in. The three mount flags are matched as comma-separated fields, same as Paste 2.

`sha256sum -c` of `initrd-copy-sha256-pre-batch5.txt` checks `/boot/initrd.img-7.0.0-42-generic.pre-batch5` before the reboot. Both initrd checks must print `OK`.

The KVM watch is the TPM check. A passphrase prompt is a stop, as written under Recovery.

| Line | What to do |
|---|---|
| `STOP-upgrade` | An upgrade is running. The script did not reboot. Wait, then run Paste 3 again. |
| `STOP-tmp-…` or `STOP-shm-…` | A required mount flag is missing. The script did not reboot. Tell the Brain. |
| No `OK-to-reboot` and no `STOP-` line | A check failed: the kernel, the initrd names, the size and mtime, either initrd `sha256sum -c`, the fstab backup, `/run/reboot-required`, `apt-daily-upgrade`, the fstab line, or the drop-in. The script did not reboot. |

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
if journalctl -q -b -u systemd-modules-load.service -p err --no-pager | grep -q .; then
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
  case ",$tmp_opts," in
    *,"$flag",*) ;;
    *) echo "STOP-tmp-$flag"; exit 1 ;;
  esac
  case ",$shm_opts," in
    *,"$flag",*) ;;
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
loaded=$(lsmod | awk '$1 ~ /^(9p|adfs|affs|befs|bfs|blocklayoutdriver|btrfs|cachefiles|ceph|cifs|cifs_md4|coda|cuse|dlm|efs|erofs|exfat|f2fs|gfs2|grace|hpfs|isofs|jfs|kafs|ksmbd|lockd|minix|msdos|netfs|nfs|nfs_acl|nfs_layout_flexfiles|nfs_layout_nfsv41_files|nfsd|nfsv2|nfsv3|nfsv4|nilfs2|ntfs3|ocfs2|ocfs2_dlm|ocfs2_dlmfs|ocfs2_nodemanager|ocfs2_stack_o2cb|ocfs2_stack_user|ocfs2_stackglue|omfs|orangefs|overlay|qnx4|qnx6|quota_tree|quota_v1|quota_v2|romfs|ubifs|udf|ufs|vboxsf|virtiofs|zonefs)$/')
if [ -n "$loaded" ]; then
  printf '%s\n' "$loaded"
  echo STOP-lsmod
  exit 1
fi
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
- `systemd-modules-load`: `Result=success`, `ExecMainStatus=0`, and no priority-err journal line. `journalctl -q` is required. Without it, an empty filter prints `-- No entries --` and `grep -q .` stops a clean boot. Checked on Johnny 2026-11-04 (`systemd` 259.9-0ubuntu0.1): the plain command printed those 17 bytes and exited 0; `journalctl -q` printed nothing and exited 0. resolute `journalctl(1)` describes `-q` as suppressing informational messages: https://manpages.ubuntu.com/manpages/resolute/man1/journalctl.1.html . The man page's examples are `-- Journal begins at ...` and `-- Reboot --`. **[Assumption]** `-- No entries --` is in that class on 26.04. The Johnny check above is the evidence for this host. `is-failed` printing `active` is the success state from before the reboot and is not a failure.
- The 59 filesystem names and `overlay` each print `0`. `ksmbd` prints `1`. A `0` on `ksmbd` means the check is blind. The awk requires 60 zeros and one `1`. `lsmod` prints none of those names and none of `ksmbd`. A loaded name prints `STOP-lsmod`.
- `diff` prints nothing. `crypt`, `systemd-cryptsetup`, and `tpm2-tss` are in the live module list.
- `sha256sum -c` prints `/boot/initrd.img-7.0.0-42-generic: OK`.
- `/tmp` and `/dev/shm` still have `nosuid`, `nodev`, and `noexec` as their own comma-separated fields. The full option string may differ from the live remount, because the next boot applies the unit and the fstab line. The three flags are the pass.
- Cryptsetup `Result=success` and `ExecMainStatus=0`. `systemd-ask-password-console.service` is `inactive`. Those unit reads do not show whether a person typed the passphrase. The KVM watch is the TPM re-check.
- Last line `OK-boot-gate`.

The `.pre-batch5` copy stays until the install block has run. That block's restore copies it back if a package trigger rebuilds the image. `~/cis-audit/*-pre-batch4.txt` and `/root/apport.default.pre-batch4` stay.

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
NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get remove -y apparmor-utils python3-apparmor python3-libapparmor </dev/null
NEEDRESTART_MODE=l apt-get update </dev/null
if ! sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt; then
  cp -a /boot/initrd.img-7.0.0-42-generic.pre-batch5 /boot/initrd.img-7.0.0-42-generic
  sha256sum -c /home/aj/cis-audit/initrd-sha256-pre-batch5.txt
  echo STOP-initrd-restored
  exit 1
fi
EOF
```

`apparmor` stays. `apt-get remove` can activate a trigger. The same restore covers that. Do not delete `/boot/initrd.img-7.0.0-42-generic.pre-batch5` until the install block has run.

## Recorded output

Each output line is prefixed with `# ` so it is not a shell command. Times are 2026-11-04 UTC.

**Paste 1.** This Grok session has no Paste 1 stdout. The post-boot reads are the record of what that paste left behind: both issue files are `Authorized use only. Activity is monitored.`, `Acquire::Check-Date "true";`, the motd timer is `disabled` and `inactive`, and `ubuntu.sources` has the two https URI lines and sha256 `cabf1ceb160f86f80bfdd51c828445a76f4f094e40bf81f341ab3937d11e36a8`.

**Paste 2.** The transcript shows the opening hash and the `findmnt --verify` warning, then `^C`. There is no `OK-paste-2` line. Paste 3 was started anyway. The warning is the one the script prints before `systemctl daemon-reload`. **Inference, not a transcript line:** the remounts and the exec checks had finished, because a later read found `noexec` on both mounts and the test files gone. The compensating evidence is Paste 3's gates, which require those `noexec` flags and the drop-in line before `systemctl reboot`, and the post-boot reads below. A later `sha256sum -c` of the live initrd printed `OK`.

```
# /boot/initrd.img-7.0.0-42-generic: OK
# 0 parse errors, 0 errors, 2 warnings
# none
#    [W] non-bind mount source /swap.img is a directory or regular file
#    [W] your fstab has been modified, but systemd still uses
#        the old version; use 'systemctl daemon-reload' to reload
```

`systemctl show -p Options tmp.mount` was not in that transcript. Read back after the reboot:

```
# Options=rw,nosuid,nodev,noexec,size=15904820k,nr_inodes=1048576,inode64,usrquota
```

`size=15904820k` is the packaged `50%%` expanded. The `/dev/shm` line from the after-login block is `rw,nosuid,nodev,noexec,inode64,usrquota`, so the fstab options, including `usrquota`, were applied. That settles the remount assumption.

**Before Paste 3.**

```
# /boot/initrd.img-7.0.0-42-generic: OK
# base-files/resolute-updates 14ubuntu6.3
# bind9-dnsutils, bind9-host, bind9-libs 1:9.20.24-1ubuntu0.5
# libmspack0t64 0.11-1.1ubuntu0.2
# libpcre2-8-0 10.46-1ubuntu0.1
# motd-news-config/resolute-updates 14ubuntu6.3
# vim, vim-tiny, vim-common, vim-runtime, xxd 2:9.1.2141-1ubuntu4.10
```

Twelve packages. None is a kernel, a modules package, dracut, or an initramfs package. They were left uninstalled.

**Paste 3.** The script's stdout was not captured, including `OK-to-reboot`. The basis for treating the gates as passed is that `systemctl reboot` is the last command in the script, and the machine did reboot: SSH came back on a new boot (uptime 2 minutes). A failed gate would have exited before that command. AJ watched the KVM on that boot: the login prompt came up with no passphrase, the console showed the authorized-use line, and no Ubuntu release name. The after-login block then ran on that same boot.

**After login** (uptime 2 minutes in the paste; 3 minutes on the read-back). `OK-boot-gate`. Own-`.ko` is 60 zeros and `1 ksmbd`. No `STOP-lsmod`. No module diff. Initrd `sha256sum -c` printed `OK`. Read-back: `7.0.0-42-generic`, `0 loaded units listed.`, modules-load `success` / `0`, cryptsetup `success` / `0`, `systemd-ask-password-console` `inactive`. `own-ko-batch5.txt` is 61 lines, 60 zeros, `ksmbd` 1. Mounts:

```
# /tmp rw,nosuid,nodev,noexec,size=15904820k,nr_inodes=1048576,inode64,usrquota
# /dev/shm rw,nosuid,nodev,noexec,inode64,usrquota
```

Both initrd files are still `42618411` bytes, mtime `2026-11-03 06:13:32.840646209 +0000`.

**base-files and sources**, read back after the boot. `dpkg --verify base-files` prints only the two intended conffile lines:

```
# ??5?????? c /etc/issue
# ??5?????? c /etc/issue.net
```

`ubuntu.sources` sha256 is `cabf1ceb160f86f80bfdd51c828445a76f4f094e40bf81f341ab3937d11e36a8`. The URI lines are `https://us.archive.ubuntu.com/ubuntu/` and `https://security.ubuntu.com/ubuntu/`. `dpkg -S` still finds no owner. The hash before the `sed` was `077ad25a51b484eae9bebddd027b18e11d85ec7b69aa0d817e7960b631fa5c8a`.

**Install (2026-11-04).** The first paste stopped before `apt-get install` because the summary check required a comma after `0 to remove`. Apt printed `0 to remove and 12 not upgraded.` The corrected check is `^0 upgraded, 3 newly installed, 0 to remove `. The rerun printed `aa-status-identical`, `initrd-identical`, and `OK-apparmor-utils`. needrestart, in list-only mode, reported the kernel and microcode up to date and no service, container, session, or VM restart. Read-back: all four packages are `5.0.2-0ubuntu1~26.04.1`. The cached `.deb` hashes match the vet: `apparmor-utils` `6d251b6ffefb54ccee50518bae414b5dd8abf0a55faf9687b550b153886e5d4c`, `python3-apparmor` `df67e000dcec6a8888c89dc0bdf15ad5e2d33b73601265a2a69579816ba6cdff`, `python3-libapparmor` `fabb4c780038884b4b616a9568d90ed3113683c15f22fe9c44edf5540a844bda`. The live initrd is still `42618411` bytes, mtime `2026-11-03 06:13:32.840646209 +0000`. `ssh.socket` is active. Failed units: `0 loaded units listed.` No PASS is written here. Governance re-audits the eight rules. `.pre-batch5` was not needed and has not been deleted.

**Conffile residual.** AJ accepts it (2026-11-04). `base-files` 14ubuntu6.3 is pending in `apt list --upgradable`, and the installed files `/etc/issue` and `/etc/issue.net` are local edits of that package's conffiles. A later manual upgrade of `base-files` can stop and ask which copy to keep. Keep the local file, the one that reads `Authorized use only. Activity is monitored.` Do not take the package copy, which puts the Ubuntu release line back. After the upgrade, `dpkg --verify base-files` should still show only those two `??5?????? c` lines, and `cat` of both files should still be the one warning sentence. `motd-news-config` 14ubuntu6.3 is on the same pending list and is not part of this residual.

## After the boot gate

Governance re-audits 1.1.2.1.4, 1.1.2.2.4, 1.2.1.11, 1.2.1.15, 1.3.1.1, 1.6.2, 1.6.3, and 1.6.12. 1.3.1.1 stays FAIL. The install block is still the apt-under-noexec test, and it waits on Governance's vet plus SBOM rows for `apparmor-utils`, `python3-apparmor`, and `python3-libapparmor`. AJ (2026-11-04): the batch closes after that install, not before it. The close review covers `5a018b0` through the last commit after the install. Mirrors under `etc/` and the handoff bump wait until this session ends. The files to mirror then: `etc/fstab`, `etc/issue`, `etc/issue.net`, `etc/apt/sources.list.d/ubuntu.sources`, `etc/apt/apt.conf.d/60-johnny-cis-check-date.conf`, `etc/systemd/system/tmp.mount.d/60-johnny-cis-noexec.conf`. The timer change is the removal of `/etc/systemd/system/timers.target.wants/update-notifier-motd.timer`.
