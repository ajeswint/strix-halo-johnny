# CIS L1 fix pass, Batch 2: package removal (low lockout risk)

**Status:** APPLIED 2026-11-03 (AJ ran sudo ~06:00-06:17 UTC; Brain read-only checks over SSH). Rev 3 was reviewed by Assurance (`docs/findings/cis-batch-2-review.md`) and Governance re-audited 2.1.13, 2.2.4, 2.2.6 and 7.1.13: all PASS (151/100/23). **AJ's answers:** Q1 no `apt update`; Q2 remove `libnftables1 libntfs-3g89t64` by name (done after B4); Q3 keep `fuse3`/`nftables` configs (`rc`); Q4 accept the 43 manual marks; Q5-A console reboot (initrd rebuilt 06:13 UTC, module diff empty, boot 06:17 UTC unattended; `.pre-batch2` copy deleted). Below is the rev 3 text as reviewed.

### Change log (rev 1 to rev 2)
| Finding | Fixed in |
|---|---|
| F1 initrd rebuild | Risk line; B2a (baseline, required copy); B3 (rebuild note); B5 (module diff, mtime); B6 notes; Cleanup; Open Q5 |
| F2 B3 expected output, failure branch | B3 "Expected output" and "If B3 fails" |
| F3 ftp-ssl guard | "Why one combined removal"; B4 guard |
| F4 iptables baseline | B2a (baseline); B5 "Firewall still works"; Assumption 4 |
| F5 rollback gaps | B6 notes (11 installs if Q2 = remove, initrd rebuild, needrestart, rsync, failed-B3 pointer) |
| F6 why ufw/iptables stay | Live state "Firewall backend"; ubuntu-standard section; Assumption 3 |
| F7 exact grep lines, "already set" | B1 expected; B5 7.1.13 |
| F8 grub2-common | SBOM "Kept on purpose" |
| F9 sim header | `docs/cis-fix/batch-2-sim.txt` header; Assumption 2 |
| F10 grub-pc rc | B5 dpkg notes |
| R1 `lsinitrd -m` header lines cause false diff | B2a (save module block only); B5 (diff module block only) |
| R2 wrong module names | B2a (baseline grep); B5 (identical grep); Assumption 6 |

**Rules (4):** 2.1.13 (rsync), 2.2.4 (telnet client), 2.2.6 (ftp client), 7.1.13 (SUID/SGID review: AJ did not approve `/usr/bin/ntfs-3g` or `/usr/bin/fusermount3`). AJ also decided on 2026-11-03 to remove `nftables` in this batch and **keep** the `nf_tables` kernel module, which ufw needs.

**Removes 9 packages, nothing else:** `ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables`. Before that, 43 packages that `ubuntu-standard` holds today are marked manual, so nothing else becomes removable. Then the CIS purge lines clear the leftover config (only rsync has any left).

**Benchmark:** CIS Ubuntu Linux 26.04 LTS v1.0.0 (local PDF). Pages are printed page numbers. Only short command lines are quoted; the repo keeps CIS text local (licensed).

**Risk:** low, with one boot-path effect. **B3 regenerates `/boot/initrd.img-7.0.0-42-generic` via dracut:** fuse3's postrm runs `update-initramfs -u` and fuse3 and ntfs-3g both activate the `update-initramfs` trigger, which dracut handles (`/usr/sbin/update-initramfs` ships in dracut on 26.04: https://packages.ubuntu.com/resolute/amd64/dracut/filelist). `backup_initramfs=no`, so the old image is replaced; it is the only initrd for this kernel. PCR 7 is **unaffected** (the initrd is not measured into PCR 7). **No automatic reboot**; Johnny never auto-reboots, so the first test of the new image is the next reboot (Open Q5). No SSH, PAM, sudo, GRUB, Secure Boot or PCR 7 effect. ufw, iptables, `iptables-nft` and the `nf_tables` module all stay. Visible effects:
- The `rsync`, `telnet`, `ftp`, `nft` (nftables CLI), `ntfs-3g` and `fusermount3` commands go away.
- NTFS volumes can no longer be mounted read-write.
- FUSE mounts stop working. None are mounted today.
- `apt` reports 2 orphaned libraries as "no longer required" (Open Q2).
- The initrd for 7.0.0-42 gets a new mtime and may change size slightly (B2a, B5).

**Full simulation record:** `docs/cis-fix/batch-2-sim.txt` (349 lines, SIM1–SIM9; every line read).

---

## Live state read (read-only, `ssh aj@192.168.50.152`, no sudo)
Read 2026-11-03 05:37:06–05:50 UTC on Johnny's clock (`Etc/UTC`), kernel 7.0.0-42-generic, after Batch 1 (commit 9a5e200).

### The packages (all `ii`)
| Package | Version | Mark | Installed because | Conffiles |
|---|---|---|---|---|
| ubuntu-standard | 1.570.4 | manual | installer metapackage (not approved, AJ 2026-10-31) | none |
| ftp | 20260211-1 | auto | ubuntu-standard Depends | none |
| tnftp | 20260211-1 | auto | ftp Depends | none |
| telnet | 0.17+2.7-2ubuntu1.1 | auto | ubuntu-standard Recommends | none |
| inetutils-telnet | 2:2.7-2ubuntu1.1 | auto | telnet Depends | none |
| rsync | 3.4.1+ds1-7ubuntu0.3 | auto | ubuntu-standard Depends | `/etc/default/rsync`, `/etc/init.d/rsync` (unmodified; `dpkg --verify` clean) |
| ntfs-3g | 1:2022.10.3-5ubuntu1.1 | auto | Recommends of ubuntu-standard and udisks2 | none |
| fuse3 | 3.18.2-1 | auto | ntfs-3g Depends; open-vm-tools Recommends | `/etc/fuse.conf` (unmodified) |
| nftables | 1.1.6-1 | auto | ubuntu-standard Depends; iptables Recommends | `/etc/nftables.conf` (unmodified) |

- **Not installed:** `telnet-ssl`, `atftp`, `inetutils-ftp`, `ftp-ssl`. All four exist in the resolute archive, so the CIS purge lines resolve.
- **Reverse dependencies** (`apt-cache rdepends --installed`):
  - rsync and ftp: only ubuntu-standard.
  - telnet: only ubuntu-standard. inetutils-telnet: only telnet. tnftp: only ftp.
  - ntfs-3g: udisks2 (Recommends) and ubuntu-standard.
  - fuse3: ntfs-3g (Depends) and open-vm-tools (Recommends).
  - nftables: ubuntu-standard (Depends) and iptables (**Recommends**, not Depends).
  - Nothing installed **Depends** on nftables except ubuntu-standard.
- **Services:**
  - `rsync.service`: disabled, inactive.
  - `nftables.service`: disabled, inactive. `/etc/nftables.conf` is the stock empty `inet filter` table, so no rules are in use.
  - ufw: `ufw.service` active, `ENABLED=no` (firewall off; turning it on is Batch 6).
  - open-vm-tools: enabled but inactive (`systemd-detect-virt` = none, bare metal).
- **Firewall backend:**
  - `iptables` 1.8.11-2ubuntu3. `iptables --version` → `iptables v1.8.11 (nf_tables)`. The `iptables` alternative → `/usr/sbin/iptables-nft` (xtables-nft-multi).
  - ufw 0.36.2-9build1 Depends on `iptables`, not `nftables`.
  - **Why apt keeps ufw/iptables today (Assurance F6):** `openssh-server` 1:10.2p1-2ubuntu3.8 has `Suggests: … ufw`, and `APT::AutoRemove::SuggestsImportant` defaults to true (apt 3.2.0 `apt-pkg/depcache.cc` line 2297: https://salsa.debian.org/apt-team/apt/-/raw/3.2.0/apt-pkg/depcache.cc). iptables stays because ufw Depends on it. B1 marks both manual anyway.
  - `nf_tables` module is loaded (refcount 0, ufw off). It is the file `/usr/lib/modules/7.0.0-42-generic/kernel/net/netfilter/nf_tables.ko.zst`, owned by **linux-modules-7.0.0-42-generic**, so removing the nftables package cannot remove it.
- **SUID files from these packages:** `/usr/bin/ntfs-3g` 4755 and `/usr/bin/fusermount3` 4755, both root:root. Nothing else in `dpkg -L ntfs-3g fuse3` is SUID or SGID. No FUSE mounts (`findmnt -t fuse,fuse3,fuseblk,fuse.ntfs-3g` is empty). The 2026-11-01 root audit listed 15 SUID and 6 SGID files.
- **Metapackages installed:** ubuntu-minimal, ubuntu-server, ubuntu-standard (all 1.570.4), ubuntu-kernel-accessories. ubuntu-server does **not** depend on or recommend ubuntu-standard, so removing ubuntu-standard does not take ubuntu-server.
- **Holds:** `secureboot-db`, `shim-signed`. Untouched.
- **apt lists:** `update-success-stamp` 2026-11-03 04:57:44 UTC (apt-daily). InRelease times: security 02:58 UTC Nov 3, updates 20:08 UTC Nov 2. That was about 40 minutes old at read time. Every package in this batch shows Installed = Candidate.

### ubuntu-standard 1.570.4 (Depends + Recommends) and what each becomes
All 49 entries are installed and all are `auto` except `apparmor` (manual). Batch 2 removes 5 of them (ftp, nftables, rsync, ntfs-3g, telnet). The other **43 get marked manual (B1)**. If they are not marked, a removal leaves 29 of them, or their libraries, "no longer required", and any later `autoremove` would take them (SIM3):

`command-not-found friendly-recovery hdparm ibverbs-providers info install-info iputils-tracepath libibverbs1 libncurses6 libnftables1 libnl-route-3-200 libntfs-3g89t64 libpcap0.8t64 libplymouth5 libsensors-config libsensors5 libtraceevent1-plugin libtracefs1 libxkbcommon0 mtr-tiny nano numactl plymouth plymouth-theme-ubuntu-text python3-commandnotfound sysstat tcpdump time trace-cmd`

That list includes **sysstat** (which Batch 1 just configured), tcpdump and mtr-tiny (step 7 candidates), nano, plymouth and friendly-recovery. The careless one-liner (`purge --autoremove`, SIM2) would remove 38 packages: the 9 targets plus these 29. ufw and iptables are `auto` too. SIM2 did not list them because openssh-server Suggests ufw (see "Firewall backend"); B1 marks them manual anyway so nothing depends on that.

---

## CIS remediation (quoted; strict CIS)
- **2.1.13, pp. 310–311:**
  - Audit: `dpkg-query -s rsync &>/dev/null && echo "rsync is installed"` must print nothing.
  - Remediation: `# systemctl stop rsync.service` / `# apt purge rsync`.
  - The "OR stop and mask" branch applies only if a dependent package is required. The only dependent package is ubuntu-standard, which AJ did not approve, so that branch does not apply. **Purge is required here, not just remove:** a removed package with conffiles stays in dpkg's database as `rc`, and `dpkg-query -s` still succeeds, so the audit would still print "rsync is installed". **[Assumption, standard dpkg behavior]**: rsync is the only one of the nine whose leftover config the audit itself would catch.
- **2.2.4, p. 342:** `# apt purge telnet inetutils-telnet telnet-ssl`. The audit loops over the three names and flags only `Status: install ok installed`.
- **2.2.6, pp. 346–347:** `# apt purge ftp tnftp atftp inetutils-ftp ftp-ssl`. Same audit style, over five names.
- **7.1.13, pp. 1008–1009 (Manual):** remediation is to review the SUID/SGID list and confirm each binary is legitimate. Removing `ntfs-3g` and `fuse3` is AJ's site decision (option B, 2026-11-01), not CIS text. CIS does not say to purge, so they are removed, not purged (Brain: no purge unless CIS requires it).
- **nftables:** no CIS rule requires removing it. AJ's decision (2026-11-03). Removed, not purged (Open Q3).

**Why one combined removal, not the CIS lines one at a time:** `ftp-ssl` declares `Provides: ftp` (`apt-cache show ftp-ssl` on Johnny, 0.17.34+really0.17-3, universe). While ubuntu-standard (which Depends on ftp) is installed, `apt purge ftp tnftp` **installs ftp-ssl** to satisfy it (SIM1), and ftp-ssl is itself on the 2.2.6 list. Removing ubuntu-standard in the **same** command as ftp avoids that: 9 removed, 0 installed (SIM3, SIM6). **Correction (Assurance F3):** only the shortened `apt purge ftp tnftp` installs ftp-ssl. The full CIS line names `ftp-ssl` as a purge target, and apt never installs a package it is told to purge; run while ubuntu-standard is still installed, the CIS lines would instead **remove ubuntu-standard** as a side effect (SIM4; Assurance's run on the copy). That is harmless after B1 but unplanned. B3 then B4 stays the right order: one explicit prompt, ubuntu-standard removed by name. The CIS purge lines run after B3, when nothing needs ftp, and install nothing (SIM8a–c).

---

## B0. Pre-check (read-only, no sudo)
```
apt-get -s remove ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables
```
Expected (SIM3): 9 `Remv` lines (the 9 named packages), `0 newly installed`, and the 29-package "no longer required" list shown above. If anything else appears under `REMOVED` or `NEW`, stop and tell the Brain.

## B1. Mark ubuntu-standard's other 43 deps manual
```
sudo apt-mark manual bash-completion bind9-dnsutils busybox-static command-not-found cpio cron dmidecode dosfstools ed ethtool file friendly-recovery hdparm info iptables iputils-tracepath libpam-systemd logrotate lshw lsof man-db manpages media-types mtr-tiny nano numactl openssh-client parted pciutils plymouth plymouth-theme-ubuntu-text psmisc strace sysstat tcpdump time trace-cmd ufw update-manager-core usbutils uuid-runtime wget xz-utils
```
Expected: 43 lines `… set to manually installed.` If one was changed first (unattended-upgrades or AJ), apt prints `… was already set to manually installed.` for it; that is not a failure. These are exactly ubuntu-standard 1.570.4's Depends and Recommends, minus the 5 being removed and minus `apparmor` (already manual).

## B2. Re-check (read-only, no sudo)
```
apt-get -s remove ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables
```
Expected (SIM6, previewed against a copy of Johnny's apt state with B1 applied):
```
The following packages were automatically installed and are no longer required:
  libnftables1 libntfs-3g89t64
Use 'apt autoremove' to remove them.
The following packages will be REMOVED:
  ftp fuse3 inetutils-telnet nftables ntfs-3g rsync telnet tnftp
  ubuntu-standard
0 upgraded, 0 newly installed, 9 to remove and 0 not upgraded.
```
Followed by 9 `Remv` lines. Anything else: stop.

## B2a. Boot-path baseline and required initrd copy (before B3)
B3 replaces the only initrd for 7.0.0-42 (see Risk). Record a baseline and keep a copy first. Run in order:
```
sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic | sed -n '/^dracut modules:/,/^=====/p' > ~/cis-audit/initrd-mods-pre-batch2.txt
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic
sudo cp -a /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch2
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch2
wc -l ~/cis-audit/initrd-mods-pre-batch2.txt
grep -E '^(crypt|systemd-cryptsetup|tpm2-tss)$' ~/cis-audit/initrd-mods-pre-batch2.txt
sudo iptables -S
```
Expected:
- **lsinitrd / wc:** only the module block is saved (from `dracut modules:` to the closing `=====` line), so the `Image: …: 41M` and `Version:` header lines cannot cause a false diff later. `wc -l` must be above 2.
- **grep:** prints the crypt-related module names present today. Record them; B5 must print the identical lines. **[Assumption]** the module-list format is names one per line, as in dracut 110 (`modules.txt`); the saved file will show it.
- **First `ls`:** note the mtime (2026-10-29 05:12 UTC at Assurance's read) and size (42 620 636 bytes).
- **cp -a / second `ls`:** two lines with identical size and mtime. The copy is **required**, not optional. `/boot` had 1.8 G free at Assurance's read.
- **iptables baseline (F4):** if the ruleset is empty, exactly `-P INPUT ACCEPT`, `-P FORWARD ACCEPT`, `-P OUTPUT ACCEPT`. Save whatever prints; B5 must match it. **[Assumption]** the live ruleset is empty (ufw `ENABLED=no`; `aj` cannot read it).
- GRUB does not list the copy. Using it needs a manual GRUB edit at the AMT console (last resort only, see "If B3 fails").

## B3. Remove (rsync.service stop first, per CIS 2.1.13)
```
sudo systemctl stop rsync.service
sudo apt-get remove ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables
```
- There is no `-y`: apt shows its list and asks `Do you want to continue? [Y/n]`. Answer `Y` only if the list matches B2 exactly.
- There is no `--autoremove` and no `apt autoremove` afterwards.
- `systemctl stop` on an inactive unit returns at once.

### B3 expected output (after the removal list and the `Y`)
Beyond the 9 `Removing …` lines apt will also print (Assurance F2; exact dracut text varies, so the markers are the `Generating` line and no `failed`):
```
update-initramfs: deferring update (trigger activated)
Processing triggers for man-db (…) ...
Processing triggers for dracut (110-11ubuntu0.1) ...
update-initramfs: Generating /boot/initrd.img-7.0.0-42-generic
```
plus any dracut messages in between, and apt exits 0. The `man-db` line and the dracut version in the `Processing triggers` line are **not** stop markers; only a missing `Generating` line or a `failed` line is. The dracut version in the `Processing triggers` line is what Johnny has today and may differ if dracut is updated first. **[Assumption]** the needrestart apt hook stays silent: it runs only when something was unpacked (Assurance read `/usr/lib/needrestart/apt-pinvoke`).

### If B3 fails (apt exits non-zero, or any line says `update-initramfs: failed`)
1. **Stop.** Do not run B4. Do not reboot. Do not run B6.
2. Run the read-only `dpkg --audit; echo rc=$?` (no sudo) and give the output to the Brain.
3. Check the image: `ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic`.
4. Restore the saved copy (only after the Brain agrees, or if the image is missing or truncated):
```
sudo cp -a /boot/initrd.img-7.0.0-42-generic.pre-batch2 /boot/initrd.img-7.0.0-42-generic
```
5. Recovery of dpkg (`sudo dpkg --configure -a`) only after the Brain's review.
6. **Last resort only:** if Johnny is rebooted before the image is good, boot the copy by a manual GRUB edit at the AMT console (press `e` on the 7.0.0-42 entry, change the `initrd` line to end in `initrd.img-7.0.0-42-generic.pre-batch2`, boot with Ctrl-x). **[Assumption]** the entry has a single `initrd` line in this form; not checked on Johnny.

## B4. CIS purge lines (2.1.13, 2.2.4, 2.2.6 as written; run only after a clean B3)
```
sudo apt-get purge rsync
sudo apt-get purge telnet inetutils-telnet telnet-ssl
sudo apt-get purge ftp tnftp atftp inetutils-ftp ftp-ssl
```
`apt-get purge` is the same operation as the CIS `apt purge`; apt-get is used for its stable output. Expected (SIM8a–c):
- Line 1 purges rsync's leftover config. Answer `Y` **only if** the REMOVED list is exactly `rsync*` (`Purg rsync`, 0 newly installed).
- Lines 2–3 print `Package '…' is not installed, so not removed` for each name, then `0 upgraded, 0 newly installed, 0 to remove`.
- **Guard (F3):** anything else, in particular `ubuntu-standard` in a list, or any package to install: answer `n`, stop, tell the Brain. That would mean B3 did not complete as planned.

## B5. Verification (read-only; the `sudo` lines read only or write only a report in `~`)
CIS audit lines (pp. 310, 342, 346–347). Each must print nothing:
```
dpkg-query -s rsync &>/dev/null && echo "rsync is installed"
for pkg in telnet inetutils-telnet telnet-ssl; do dpkg-query -s "$pkg" 2>/dev/null | grep -q '^Status: install ok installed' && echo "$pkg is installed"; done
for pkg in ftp tnftp atftp inetutils-ftp ftp-ssl; do dpkg-query -s "$pkg" 2>/dev/null | grep -q '^Status: install ok installed' && echo "$pkg is installed"; done
```
Package state, SUID files, firewall backend and module:
```
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables
ls -l /usr/bin/ntfs-3g /usr/bin/fusermount3 /usr/sbin/nft
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' ufw iptables linux-modules-7.0.0-42-generic
iptables --version
modinfo -F filename nf_tables
lsmod | grep -E '^nf_tables'
apt-mark showauto ufw iptables sysstat tcpdump mtr-tiny nano plymouth friendly-recovery
apt-get -s autoremove
systemctl --failed --no-pager --plain
dpkg --audit; echo rc=$?
dpkg -l | grep '^rc'
```
Expected:
- **dpkg-query (first):** `rc  fuse3 3.18.2-1` and `rc  nftables 1.1.6-1` (removed, config kept). `dpkg-query: no packages found matching …` for the other 7 (packages without conffiles are dropped fully; rsync was purged).
- **ls:** `No such file or directory` for all three paths.
- **dpkg-query (second):** `ii` for ufw 0.36.2-9build1, iptables 1.8.11-2ubuntu3 and linux-modules-7.0.0-42-generic.
- **iptables:** `iptables v1.8.11 (nf_tables)`.
- **modinfo:** `/lib/modules/7.0.0-42-generic/kernel/net/netfilter/nf_tables.ko.zst`. modinfo resolves through the `/lib` → `/usr/lib` merge; either prefix passes. This is the real "module kept" check.
- **lsmod:** one `nf_tables` line until the next reboot. After a reboot it may be absent while ufw is off, because nothing loads it on demand until iptables or ufw runs. That is not a failure: modinfo is the check.
- **apt-mark showauto:** prints nothing (all manual).
- **apt-get -s autoremove:** offers exactly `libnftables1 libntfs-3g89t64` (SIM8d). Do **not** run it for real unless Open Q2 = remove.
- **systemctl --failed:** `0 loaded units listed.`
- **dpkg --audit:** only `rc=0` (no half-configured or trigger-pending package).
- **`dpkg -l | grep '^rc'`:** lists `fuse3` and `nftables` (Batch 2) and also `grub-pc` 2.14-2ubuntu2.1. **grub-pc was already `rc` before this batch** (`deinstall ok config-files`); no Batch 2 command touches it (F10).

Firewall still works (sudo, read-only; ufw stays off):
```
sudo ufw status
sudo iptables -S
```
Expected: `Status: inactive` (unchanged). `iptables -S` output is **identical to the B2a baseline**; if that was empty, exactly `-P INPUT ACCEPT`, `-P FORWARD ACCEPT`, `-P OUTPUT ACCEPT`. That proves the iptables-nft → nf_tables path still works without the nftables package. Confirmed from source (Assurance F4): iptables 1.8.11 lists through `nft_xt_fake_builtin_chains()` in its own cache, so listing creates no kernel table and loads no module beyond `nf_tables` and `nfnetlink`, already loaded (https://salsa.debian.org/pkg-netfilter-team/pkg-iptables/-/raw/upstream/1.8.11/iptables/nft.c).

Boot path (F1). The new initrd must carry the same dracut modules:
```
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic
sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic | sed -n '/^dracut modules:/,/^=====/p' | diff ~/cis-audit/initrd-mods-pre-batch2.txt -
sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic | sed -n '/^dracut modules:/,/^=====/p' | grep -E '^(crypt|systemd-cryptsetup|tpm2-tss)$'
```
Expected: the `ls` mtime is the B3 time (new) and the size is within a few MB of 42 620 636; the `diff` prints **nothing**; the `grep` output is **identical to the B2a grep** (not an assumed set). **[Assumption]** (Assurance) no dracut module depends on fuse3 or ntfs-3g, since their initramfs hooks are initramfs-tools hooks; Assurance could not read the current initrd (0600 root). **Any diff, a grep that differs from B2a, or dracut error: stop, do not reboot, restore the copy with the `sudo cp -a` line in "If B3 fails", and tell the Brain.**

7.1.13 re-audit (Governance; the script is already on Johnny; writes only the report file):
```
sudo bash ~/cis-audit/cis-7-root.sh > ~/cis-audit/7-root-batch2.txt 2>&1
grep -E 'List of|ntfs-3g|fusermount3' ~/cis-audit/7-root-batch2.txt
```
Expected, exactly these two lines (leading space-dash as in the report; 15 minus 2, and SGID unchanged): ` - List of "13" SUID executable files:` and ` - List of "6" SGID executable files:`. No `ntfs-3g` or `fusermount3` lines.

## Cleanup (after the boot is proven)
Run once the new initrd has booted (Open Q5-A, or the next planned reboot under Q5-B), or at AJ's word under Q5-B:
```
sudo rm /boot/initrd.img-7.0.0-42-generic.pre-batch2
ls -l /boot/initrd.img-7.0.0-42-generic.pre-batch2
```
Expected: the `ls` prints `No such file or directory`. Until then the copy stays.

## B6. Rollback (exact versions read 2026-11-03; all were Installed = Candidate)
```
sudo apt-get install ubuntu-standard=1.570.4 ftp=20260211-1 tnftp=20260211-1 telnet=0.17+2.7-2ubuntu1.1 inetutils-telnet=2:2.7-2ubuntu1.1 rsync=3.4.1+ds1-7ubuntu0.3 ntfs-3g=1:2022.10.3-5ubuntu1.1 fuse3=3.18.2-1 nftables=1.1.6-1
sudo apt-mark auto ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables
sudo apt-mark auto bash-completion bind9-dnsutils busybox-static command-not-found cpio cron dmidecode dosfstools ed ethtool file friendly-recovery hdparm info iptables iputils-tracepath libpam-systemd logrotate lshw lsof man-db manpages media-types mtr-tiny nano numactl openssh-client parted pciutils plymouth plymouth-theme-ubuntu-text psmisc strace sysstat tcpdump time trace-cmd ufw update-manager-core usbutils uuid-runtime wget xz-utils
```
- SIM9 (copy, post-batch state): 9 newly installed, 0 removed, nothing else. **If Q2 = remove:** 11 newly installed (`Inst` lines), adding `libnftables1` and `libntfs-3g89t64` (auto); verified by Assurance on the copy.
- **The rollback rebuilds the initrd again:** fuse3's postinst `configure` runs `chmod 4755 /usr/bin/fusermount3`, `modprobe fuse` and `update-initramfs -u`. Take a fresh `.pre-batch2`-style copy first if the earlier one was already deleted.
- The install unpacks packages, so the needrestart hook runs and may print or prompt.
- rsync after its purge: postinst runs `update-rc.d rsync defaults` (S01rsync returns, as before); `rsync.service` stays disabled (`deb-systemd-helper` enables nothing on a fresh install). No action needed.
- **A half-done or failed B3 is not a B6 case:** use "If B3 fails" above.
- `ubuntu-standard` stays manual, as it was. The other 8, and the 43 from B1, go back to `auto`, as they were.
- `rsync` gets its stock conffiles again; they were unmodified before. `fuse3` and `nftables` find their kept `rc` conffiles.
- The rollback downloads from the archive (`/var/cache/apt/archives` holds no .debs). If a security update supersedes one of these versions first, the `=version` pin fails for that package. Drop that package's `=version` to take the current one, and record it in the SBOM.

---

## SBOM (for the handoff's SBOM "Removed" row, after AJ applies)
Removed 2026-11-0x (date of apply): `ubuntu-standard` 1.570.4, `ftp` 20260211-1, `tnftp` 20260211-1, `telnet` 0.17+2.7-2ubuntu1.1, `inetutils-telnet` 2:2.7-2ubuntu1.1, `rsync` 3.4.1+ds1-7ubuntu0.3 (purged), `ntfs-3g` 1:2022.10.3-5ubuntu1.1, `fuse3` 3.18.2-1 (rc), `nftables` 1.1.6-1 (rc).
- Left installed but orphaned (auto): `libnftables1` 1.1.6-1, `libntfs-3g89t64` 1:2022.10.3-5ubuntu1.1 (unless Open Q2 = remove).
- Kept on purpose: `ufw` 0.36.2-9build1, `iptables` 1.8.11-2ubuntu3, `libfuse3-4` 3.18.2-1 (Depends of `grub2-common` 2.14-2ubuntu2.1, which is part of the boot chain, and of open-vm-tools; verified that B3 does not remove it; it only Suggests fuse3, an unmet Suggests that does no harm), and the kernel `nf_tables` module (linux-modules-7.0.0-42-generic).
- Mark change: the 43 B1 packages went from auto to manual.
- Side effect: `/boot/initrd.img-7.0.0-42-generic` regenerated by B3 (dracut 110-11ubuntu0.1). Fill the apply date in "2026-11-0x" at apply time.

## Files to mirror under `etc/`
None created or edited. Removing the packages deletes package files under `/etc`: `/etc/default/rsync` and `/etc/init.d/rsync` are purged, and `/etc/fuse.conf` and `/etc/nftables.conf` stay as `rc` conffiles. None of them is in the repo mirror today. The handoff's Config changes table gets one row: "Batch 2 package removal | rollback B6".

---

## Ubuntu 26.04 (resolute) sources checked 2026-11-03
- ufw 0.36.2-9build1 Depends `debconf | debconf-2.0, iptables, procps, python3, ucf`, with no nftables relation: https://packages.ubuntu.com/resolute/ufw
- iptables 1.8.11-2ubuntu3, where nftables is a **Recommends**, not a Depends: https://packages.ubuntu.com/resolute/iptables
- ubuntu-standard 1.570 (resolute). Depends include ftp, rsync, nftables; Recommends include telnet, ntfs-3g, ufw, iptables: https://packages.ubuntu.com/resolute/ubuntu-standard. Johnny has 1.570.4 from resolute-updates; its fields were read with `apt-cache show ubuntu-standard=1.570.4`.
- ftp-ssl 0.17.34+really0.17-3: https://packages.ubuntu.com/resolute/ftp-ssl. The page shows no Provides line, so the `Provides: ftp` claim rests on `apt-cache show ftp-ssl` and `apt-cache showpkg ftp` (Reverse Provides: ftp-ssl, tnftp) on Johnny, plus SIM1.
- Versions in the tables are from `dpkg-query` and `apt-cache policy` on Johnny (2026-11-03 05:37 UTC).

## Residuals (AJ to accept)
- **Unmet Recommends:** iptables Recommends nftables, udisks2 Recommends ntfs-3g, open-vm-tools Recommends fuse3. apt does not reinstall a Recommends that was removed by hand when the recommending package upgrades, and unattended-upgrades does not install new packages. **[Assumption]**: true unless a future version **adds** a new Recommends. This is apt's documented behavior, but Platform has not tested it here.
- **Something may bring them back:** a later `apt install` (step 7 tools) whose Depends or Recommends include rsync, ftp, nftables, ntfs-3g or fuse3 would reinstall them. Recurring check after any `apt install`: rerun the three CIS audit lines in B5, plus `ls -l /usr/bin/ntfs-3g /usr/bin/fusermount3`. Use `--no-install-recommends` or read `apt-get -s` first (step 7's pinned block already does this).
- **Lost tools:** no `nft` CLI, so use `iptables-nft -S` or `ufw status verbose`. No `rsync`, so use `scp` or `sftp`. No read-write NTFS. No FUSE (open-vm-tools' vmhgfs is irrelevant on bare metal).

## Assumptions (marked)
1. **[Assumption]** `dpkg-query -s` on an `rc` package succeeds, so rsync must be **purged** for 2.1.13 to pass (standard dpkg behavior; not run here).
2. **[Assumption]** Running SIM6–SIM9 against a copy of Johnny's dpkg/apt state on rock-box (apt 3.3.3; Johnny has 3.2.0; Johnny's `apt.conf.d` was not in the copy, see the sim header) predicts what apt will do on Johnny. Basis: SIM5 matched SIM3 line for line, Assurance reproduced SIM5–SIM9 independently, and nothing on Johnny changes between now and the apply except possible security updates (re-run B0 and B2 at apply time). It predicts apt's choices only, not maintainer-script effects.
3. **Resolved (F6):** apt keeps ufw because `openssh-server` Suggests it (`SuggestsImportant` defaults to true); iptables stays because ufw Depends on it. B1 marks both manual regardless.
4. **Resolved (F4):** `iptables -S` creates no kernel objects (iptables 1.8.11 source). **[Assumption]** the live ruleset is empty; B2a records the real baseline.
5. **[Assumption]** Unmet Recommends stay unmet across upgrades (see Residuals).
6. **[Assumption]** The dracut module list does not change when fuse3 and ntfs-3g go. Which crypt/TPM modules Johnny's initrd carries (`crypt`, `systemd-cryptsetup`, `tpm2-tss`) is read from the B2a baseline, not assumed; B5 must match it. Johnny's initrd is 0600 root and was not read by Assurance.

## Open questions for AJ
1. **`apt update` first?** Platform recommends **no**. The lists were about 40 minutes old at read time (refreshed daily by apt-daily), B3 and B4 only remove packages, and B0/B2 will show any drift. Only the rollback (B6) needs the archive, and it can run `apt-get update` then if needed.
2. **Orphaned libraries** `libnftables1` and `libntfs-3g89t64`: leave them (default; the brief said remove only the named packages), or remove them explicitly with `sudo apt-get remove libnftables1 libntfs-3g89t64` after B4 (SIM8d: exactly those 2)? Platform leans toward removing them: they are dead code, they would leave the SBOM tidy, and they would end the "no longer required" notice that tempts a blind `autoremove`.
3. **Leftover config** of `nftables` (`/etc/nftables.conf`, stock empty table) and `fuse3` (`/etc/fuse.conf`): keep as `rc` (default; CIS does not require purge), or `sudo apt-get purge nftables fuse3`?
4. **The 43 manual marks (B1):** accept them as Johnny's manual baseline? They stop any future `autoremove` from taking ufw, tcpdump, sysstat, nano and the rest. Rollback B6 restores `auto`.
5. **Prove the rebuilt initrd now, or later?** B3 replaces the only initrd for 7.0.0-42 (the `.pre-batch2` copy stays until cleanup). Pick one:
   - **A (Brain and Assurance recommend): console reboot right after a successful rebuild.** Gate is met (rev 16). Prerequisites: AMT KVM session open (MeshCommander or `rpc-go`, per the `oob-console` notes), LUKS recovery passphrase at hand, second SSH session closed after the check. Steps, only after B3 exited 0 and the B5 boot-path checks passed (empty diff, grep identical to B2a):
     1. In the SSH session: `sudo systemctl reboot`
     2. Watch the AMT KVM console. **Expected:** no LUKS passphrase prompt (TPM2 unlock), then the login prompt. A passphrase prompt would mean the TPM unlock failed: enter the recovery passphrase, finish booting, and tell the Brain (PCR 7 should not have moved, so find out why before anything else). A drop to the dracut emergency shell means the image is bad: tell the Brain, then at the GRUB menu use the last-resort `.pre-batch2` edit above.
     3. After login, from the laptop: `ssh aj@192.168.50.152 'uname -r; uptime -p; systemctl --failed --no-pager --plain; dpkg --audit; echo rc=$?; cat /run/reboot-required'`. **Expected:** `7.0.0-42-generic`; a short uptime; `0 loaded units listed.`; `rc=0`; `cat: /run/reboot-required: No such file or directory`.
     4. Re-run GS2/GS3 from `docs/findings/cis-batch-2-review.md` (sudo works; holds are `secureboot-db`, `shim-signed`) and `modinfo -F filename nf_tables` (the module list check; `lsmod` may show no `nf_tables` while ufw is off).
     5. Run the Cleanup block (delete the `.pre-batch2` copy). The boot is proven. 
   - **B: defer to the next planned reboot.** Governance logs the risk in the register: "initrd for 7.0.0-42 rebuilt by Batch 2 on the apply date, untested until the next reboot; an unplanned reboot (power cut, kernel update) is its first test; fallback is the `.pre-batch2` copy via a manual GRUB edit at the AMT console." Steps: after B3 and the B5 checks, do nothing more; keep the copy; at the next planned reboot follow A steps 1–4 (with AMT KVM and passphrase ready), then run the Cleanup block. AJ may also say "delete the copy" earlier, at which point run the Cleanup block. GR4 (`cat /run/reboot-required`) stays the weekly check.
