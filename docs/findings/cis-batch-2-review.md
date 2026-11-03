# Review: CIS L1 Batch 2 draft (`docs/cis-fix/batch-2.md`)

**Reviewer:** Assurance (independent; did not write the draft). **Date:** 2026-11-02 CST (Johnny clock 2026-11-03 05:50–06:30 UTC).
**Scope:** rules 2.1.13, 2.2.4, 2.2.6, 7.1.13 and AJ's `nftables` removal as drafted by Platform, with its record `docs/cis-fix/batch-2-sim.txt`. Nothing outside Batch 2.
**Method:** read-only. `ssh aj@192.168.50.152` as `aj`, no sudo, nothing written on Johnny. Own `apt-get -s` on Johnny. Independent re-run of SIM5–SIM9 on this laptop against a read-only copy of Johnny's apt/dpkg state (`tar` to stdout over SSH; copy in the scratchpad only). dpkg 1.23.7, apt 3.2.0 and iptables 1.8.11 source. Maintainer scripts read from `/var/lib/dpkg/info` on Johnny. CIS Ubuntu Linux 26.04 LTS v1.0.0 PDF (local); CIS text is paraphrased, and only short command lines are quoted.

## Verdict: APPROVE WITH CHANGES

The package plan is right. My own B0 on Johnny matches SIM3 line for line. The B1 list is exactly the 43 names it should be. The copy-of-state previews reproduce on a second machine. Nothing installs, the 29 packages that a careless `autoremove` would take stay, and ufw, iptables and the `nf_tables` module stay. No command touches SSH, PAM, sudo, GRUB, the held packages or PCR 7.

The draft misses one effect. **Removing `fuse3` and `ntfs-3g` rebuilds Johnny's initramfs** (F1). `fuse3`'s postrm calls `update-initramfs -u`, and both packages activate the `update-initramfs` trigger, which dracut handles. Johnny keeps no backup (`backup_initramfs=no`), and `initrd.img.old` points to the same file. So B3 replaces the only initrd for 7.0.0-42 without saying so. The next reboot, whenever it comes, is its first test. The draft's "No reboot" and "no boot effect" claims are therefore wrong, and the B3 output AJ will see is not predicted (F2). PCR 7 is not affected, because the initrd is not measured into PCR 7 (handoff, Known gaps). Platform fixes F1 and F2 before the Brain shows AJ the blocks. F3–F7 are Low text and gate fixes. F8–F10 are information only.

## Findings

| # | Sev | Location | Finding (root cause) | Fix requested of Platform |
|---|---|---|---|---|
| F1 | High | Risk line ("No reboot"; no boot effect listed); B3; B5; B6 | **B3 rebuilds `/boot/initrd.img-7.0.0-42-generic`.** On Johnny: `/var/lib/dpkg/info/fuse3.postrm` runs `update-initramfs -u` on `remove`. `fuse3.triggers` and `ntfs-3g.triggers` both have `activate-noawait update-initramfs`, and `dracut.triggers` has `interest-await update-initramfs`. `/usr/sbin/update-initramfs` belongs to dracut 110-11ubuntu0.1 ([resolute filelist](https://packages.ubuntu.com/resolute/amd64/dracut/filelist)). Under dpkg it defers to the trigger (lines 22–26), and `dracut.postinst triggered` then runs `update-initramfs -u` → `dracut --force`. `backup_initramfs=no` is the default, and `/etc/initramfs-tools/update-initramfs.conf` does not exist, so the old image is deleted on success. `/boot/initrd.img.old` → `initrd.img-7.0.0-42-generic`, the same file. The current initrd dates from 2026-10-29 05:12 UTC (42 620 636 bytes). The rebuild will also pick up any library or config drift since then. Johnny never auto-reboots, so a bad image would only show at an unplanned reboot (power cut, kernel update). The batch table's own rule ("rebuild the initramfs → prove TPM unlock on reboot", Batch 4) applies here too. Root cause: the draft read package relations and SUID bits but not the maintainer scripts or triggers. | (a) Risk line: state "B3 regenerates the initramfs for 7.0.0-42 (dracut); PCR 7 unaffected; no automatic reboot". (b) B0 adds a baseline: `sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic > ~/cis-audit/initrd-mods-pre-batch2.txt` and `ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic`. (c) Optional fallback for AJ to decide: `sudo cp -a /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch2` (`/boot` has 1.8 G free). GRUB does not list it, so using it needs a manual GRUB edit at the AMT console. Give the matching delete line. (d) B5 adds `sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic \| diff ~/cis-audit/initrd-mods-pre-batch2.txt -` → no output, plus the new mtime. Any diff: stop, do not reboot, tell the Brain. (e) Add a new Open Q for AJ: prove the boot now with a console reboot (AMT KVM ready, LUKS passphrase at hand; the gate is met, rev 16), or accept the risk until the next planned reboot and record it in the risk register. (f) B6 notes that the rollback rebuilds the initrd again (fuse3 postinst `configure` runs `update-initramfs -u`). |
| F2 | Medium | B3 expected output and failure handling | B3 says only "answer Y if the list matches B2". After the removal lines, apt will also print output that the draft does not predict: `update-initramfs: deferring update (trigger activated)` (from fuse3's postrm), `Processing triggers for dracut (110-11ubuntu0.1) ...`, `update-initramfs: Generating /boot/initrd.img-7.0.0-42-generic` plus any dracut messages, and the `man-db` trigger. If dracut fails, the script prints `update-initramfs: failed for … with N.`, dpkg leaves dracut with triggers pending, and apt exits non-zero. The draft has no branch for this. AJ would then go on to B4 or roll back blind. (The needrestart apt hook stays silent here: `apt-pinvoke` runs only if `/run/needrestart/unpacked` exists, and that file is only created when something is unpacked.) | List the expected trigger lines under B3. Add a failure branch: if apt exits non-zero or prints `update-initramfs: failed`, stop. Do not run B4, do not reboot, and do not run B6. Run the read-only `dpkg --audit` (no sudo) and give its output to the Brain. Recovery (`sudo dpkg --configure -a`) only after review. |
| F3 | Low | "Why one combined removal" paragraph; B4 last bullet ("If line 3 offers to install `ftp-ssl`, answer `n`") | The trap is real only for the shortened line `apt purge ftp tnftp` (SIM1). The CIS line as written names `ftp-ssl` as a purge target, and apt never installs a package it is told to purge. SIM4 (live, full CIS lists) and my run on the copy both show that, while ubuntu-standard is still installed, the CIS lines **remove ubuntu-standard** to satisfy its Depends. `purge rsync` → `Purg ubuntu-standard`, `Purg rsync`. `purge ftp tnftp atftp inetutils-ftp ftp-ssl` → `Purg ubuntu-standard`, `ftp`, `tnftp`. 0 installed. So the B4 guard can never fire. The real risk if B3 was skipped is that ubuntu-standard goes as a side effect. That is harmless after B1, but it is unplanned. B3 → B4 remains the right order: one explicit prompt, and ubuntu-standard removed by name. | Correct the paragraph: "only the shortened `purge ftp tnftp` installs ftp-ssl; the full CIS line would remove ubuntu-standard instead". Replace the B4 guard with: line 1 answer `Y` only if REMOVED is exactly `rsync*`; lines 2–3 must show `0 to remove` and `0 newly installed`; anything else (in particular `ubuntu-standard`) → `n`, stop. |
| F4 | Low | B5 "Firewall still works", Assumption 4 | "Prints the default policy lines" is not an exact expected output, and there is no baseline. iptables 1.8.11 `nft.c` lists through `nft_xt_fake_builtin_chains()` (lines 846–877, called from `nft_rule_list_save()` line 2941). It builds the built-in chains in its cache and sends nothing to the kernel. So `iptables -S` creates no table and loads no module beyond what is already loaded (`nf_tables`, `nfnetlink` per live `lsmod`). The ruleset itself cannot be read as `aj`. **[Assumption]** It is empty today (ufw `ENABLED=no`, rev 12 "no rules staged"). | Add `sudo iptables -S` to B0 as a baseline, and expect the same output in B5. If empty: exactly `-P INPUT ACCEPT`, `-P FORWARD ACCEPT`, `-P OUTPUT ACCEPT`. Reword Assumption 4 to: "confirmed from source: listing creates no kernel objects". |
| F5 | Low | B6 rollback | The commands and versions are right: SIM9 reproduces, 9 installed, 0 removed. Gaps: (1) If Q2 = remove, the rollback installs **11** (adds `libnftables1` and `libntfs-3g89t64` as auto). Verified on the copy. (2) fuse3's postinst `configure` runs `chmod 4755 /usr/bin/fusermount3`, `modprobe fuse` and `update-initramfs -u` (F1). (3) The install unpacks packages, so the needrestart hook runs and may print or prompt. (4) rsync after purge: its postinst runs `update-rc.d rsync defaults` (S01rsync returns, as today). Its systemd branch enables nothing on a fresh install (`deb-systemd-helper debian-installed` is false), so `rsync.service` stays disabled, as read today. No action needed. (5) No path for a half-done B3 (see F2). | Add the Q2 = remove variant (11 `Inst` lines) and notes (2)–(4) to B6. Point B6 to the F2 failure branch for a failed B3. |
| F6 | Low | Live state, ufw/iptables paragraph; Assumption 3 | **Explained, not unexplained.** ufw stays because `openssh-server` 1:10.2p1-2ubuntu3.8 has `Suggests: … ufw`, and `APT::AutoRemove::SuggestsImportant` defaults to true (apt 3.2.0 `apt-pkg/depcache.cc` line 2297). iptables stays because ufw Depends on it. B1 still marks both manual, which is correct. | Replace Assumption 3 with this explanation. |
| F7 | Low | B5 7.1.13 expected; B1 expected | The 2026-11-01 report (`~/cis-audit/7-root.txt`, 00:32 UTC) has `List of "15" SUID` (it includes `/usr/bin/fusermount3` and `/usr/bin/ntfs-3g`) and `List of "6" SGID`. 13/6 is right. Give the exact grep lines: ` - List of "13" SUID executable files:` and ` - List of "6" SGID executable files:` (leading space-dash, as in the report). B1: all 43 are `auto` today (`apt-mark showauto` → 43). If unattended-upgrades or AJ changes one first, apt prints `… was already set to manually installed.`, which is not a failure. | Put the exact lines in B5. Add the "was already set" variant to B1's expected output. |
| F8 | Info | SBOM "Kept on purpose" | `libfuse3-4` is also a **Depends of `grub2-common`** 2.14-2ubuntu2.1, which is part of the boot chain. That is the stronger reason it must stay, and nothing in B3 removes it (verified). It also `Suggests: fuse3`, an unmet Suggests, which does no harm. | Name grub2-common in the SBOM line. |
| F9 | Info | sim file header; Assumption 2 | The copy-of-state method is sound (C10). The header does not say which apt version rock-box ran, or whether Johnny's `/etc/apt/apt.conf.d` was in the isolated config. | Add both to the header. |
| F10 | Info | Context for AJ | `grub-pc` is already `rc` on Johnny (`deinstall ok config-files`, version 2.14-2ubuntu2.1), from before this batch. After Batch 2, `dpkg -l \| grep ^rc` lists it next to fuse3 and nftables. No Batch 2 command touches it. The SBOM date "2026-11-0x" is a fill-in in prose, not a command. Fill it at apply time. | Mention grub-pc in B5's dpkg notes so AJ doesn't mistake it for a Batch 2 effect. |

## Claims checked

| # | Claim | Result | Evidence |
|---|---|---|---|
| C1 | B0 = SIM3 | **Confirmed** | Own `apt-get -s remove ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables` on Johnny at 05:50:05 UTC: same 29-name "no longer required" list, same 9 `Remv` lines and versions, `0 newly installed, 9 to remove`. |
| C2 | Live state unchanged since 05:37 UTC | **Confirmed** | `/var/lib/dpkg/status` and `/var/lib/apt/extended_states` mtime 2026-10-29 21:12 UTC, so no package has changed since. `apt-cache policy`: Installed = Candidate for all 9, plus ufw and iptables. `update-success-stamp` 2026-11-03 04:57:44 UTC. InRelease: security 02:58 Nov 3, updates 20:08 Nov 2. `/run/reboot-required` and `.pkgs`: No such file. `apt-mark showhold`: `secureboot-db`, `shim-signed`. Kernel 7.0.0-42-generic. |
| C3 | B1 = ubuntu-standard 1.570.4 Depends + Recommends − 5 − apparmor | **Confirmed exactly** | `apt-cache show ubuntu-standard=1.570.4`: 27 Depends + 22 Recommends = 49. Minus ftp, nftables, rsync, ntfs-3g, telnet, apparmor = 43. A sorted `diff` against B1 and against B6 line 3 is empty, with no duplicates. `apparmor` and `ubuntu-standard` are manual. All 43 are auto. |
| C4 | `ftp-ssl` `Provides: ftp`; B3 → B4 order; B4 installs nothing | **Confirmed, with F3 correction** | `apt-cache show ftp-ssl` 0.17.34+really0.17-3: `Provides: ftp`, `Replaces: ftp (<= 0.17-31)`. `showpkg ftp` Reverse Provides: ftp-ssl, tnftp. `inetutils-telnet` provides `telnet`. `rdepends --installed`: only ubuntu-standard needs ftp, telnet or rsync. After B3 nothing installed Depends on them, and every B4 name is a purge target, so B4 cannot install anything (SIM8b/c reproduced). |
| C5 | Assumption 1: `rc` + `dpkg-query -s` succeeds → purge needed for 2.1.13 | **Confirmed (live + source)** | Johnny already has an `rc` package: `dpkg-query -s grub-pc` → exit 0, `Status: deinstall ok config-files`. dpkg 1.23.7 `src/query/main.c` `print_status()` errors only on a non-informative not-installed package. CIS p. 310 audit is `dpkg-query -s rsync &>/dev/null && echo …`, so an `rc` rsync fails it. 2.2.4/2.2.6 grep `install ok installed`, so `rc` would pass those. |
| C6 | 7 dropped fully, fuse3/nftables `rc`, B5 dpkg-query lines | **Confirmed (source + scripts)** | dpkg 1.23.7 `src/main/remove.c` `removal_bulk()` lines 704–736: no postrm **and** no conffiles → straight to purge → not-installed. `writedb` skips non-informative stanzas (`lib/dpkg/dump.c` line 541), so `dpkg-query -W` prints `no packages found matching …` (live: `ftp-ssl`, `atftp`). Maintainer scripts on Johnny: ubuntu-standard (none), ftp (preinst), tnftp (postinst, prerm), telnet (preinst), inetutils-telnet (postinst, prerm), ntfs-3g (triggers): no postrm, no conffiles → dropped. rsync, fuse3, nftables have conffiles + postrm → `rc`. Conffile md5s on disk match dpkg's record for all 4. |
| C7 | Assumption 5: unmet Recommends stay unmet across upgrades | **Confirmed for apt's classic resolver** | apt 3.2.0 `depcache.cc` lines 1558–1607 (`MarkInstall`): a Recommends that the installed version already had and that is unsatisfied now is skipped ("ignore old unsatisfied important dependency"). Only a **new** Recommends target is installed. unattended-upgrades goes through python-apt → this depcache. **[Assumption]** apt's newer solver3 behaves the same; not checked. Relations seen live: iptables Recommends nftables, udisks2 Recommends ntfs-3g, open-vm-tools Recommends fuse3, libfuse3-4 Suggests fuse3. |
| C8 | Assumption 4: `iptables -S` | **Refined** | F4: fake built-in chains, no kernel write. `iptables --version` → `iptables v1.8.11 (nf_tables)`. Alternative → `/usr/sbin/iptables-nft` → `xtables-nft-multi`. iptables Depends on libnftnl11, not libnftables1. ufw Depends `iptables, procps, ucf, debconf`. No `nft` string in ufw's Python, `/usr/sbin/ufw`, `/usr/lib/ufw` or `/etc/ufw`. |
| C9 | Assumption 3: why ufw/iptables are kept | **Explained** | F6. |
| C10 | Copy-of-state method (SIM5–SIM9) | **Sound; reproduced independently** | Copied Johnny's `dpkg/status`, `extended_states`, `*_Packages`, `*InRelease`, `apt.conf.d`, `preferences.d`, `sources.list.d` read-only. Ran apt 3.3.3 (laptop; Johnny has 3.2.0) with an isolated `APT_CONFIG` (`Dir` → the copy, `Dir::Etc::main /dev/null`). SIM5 = SIM3, then after the 43 marks SIM6, SIM7, SIM8a–d and SIM9 all match the record line for line. The emulated post-B3 status (6 dropped, 3 `rc`) matches dpkg's `removal_bulk()` (C6). Limits: it predicts apt's solution, not maintainer-script effects (it could not have shown F1). B2, run live after B1, is the binding gate. |
| C11 | B5 expected lines | **Confirmed, except F4/F7** | `modinfo -F filename nf_tables` → `/lib/modules/7.0.0-42-generic/kernel/net/netfilter/nf_tables.ko.zst` (live, `/lib` prefix as the draft says). `dpkg -S` on the `/usr/lib` path → linux-modules-7.0.0-42-generic. `lsmod` → `nf_tables 401408 0`. `systemctl --failed` → `0 loaded units listed.` today. `nft` lives at `/usr/sbin/nft`, so the `ls` paths are right, and each gives `ls: cannot access '…': No such file or directory`. `fusectl` on `/sys/fs/fuse/connections` is systemd's, not fuse3's, and is unaffected. No FUSE mounts. |
| C12 | ubuntu-server does not need ubuntu-standard | **Confirmed** | `apt-cache show ubuntu-server=1.570.4` Depends/Recommends: 0 matches for ubuntu-standard. |
| C13 | Scope: no holds, PCR 7, SSH, PAM, sudo, GRUB | **Confirmed, except F1** | No command names `shim-signed`, `secureboot-db`, grub*, openssh-server, sudo*, or libpam* except as `apt-mark manual` (a mark only: `openssh-client`, `libpam-systemd`). apt-get never upgrades held packages in `remove`/`purge`/`install <names>`. `libfuse3-4` (Depends of grub2-common) stays. The initrd rebuild (F1) is boot-path but not PCR 7. `sudo bash ~/cis-audit/cis-7-root.sh` writes only its report. |
| C14 | CIS lines quoted correctly | **Confirmed** | Local PDF: `# systemctl stop rsync.service` / `# apt purge rsync` (2.1.13); `# apt purge telnet inetutils-telnet telnet-ssl` (2.2.4); `# apt purge ftp tnftp atftp inetutils-ftp ftp-ssl` (2.2.6); audit loops as in B5. |

## Platform's five assumptions

| # | Status | Basis |
|---|---|---|
| 1 | **Confirmed** (live + source) | C5. |
| 2 | **Confirmed** (independent reproduction) | C10; but it predicts apt only, not script effects (F1). |
| 3 | **Resolved** | F6: openssh-server Suggests ufw + SuggestsImportant. |
| 4 | **Refined** | F4: listing creates no kernel objects. |
| 5 | **Confirmed** (apt source; solver3 not checked) | C7. |

## Open questions: Assurance view (information only; AJ decides)
- **Q1 `apt update` first:** agree, not needed. B3/B4 only remove packages, the package database has not changed since 2026-10-29 (C2), and apt-daily refreshes the lists every day anyway. Re-run B0/B2 at apply time; a difference from SIM3/SIM6 is the signal.
- **Q2 orphan libraries:** removing them by name is safe. On the copy it removes exactly those 2 and nothing else. Their only reverse dependencies are nftables and ntfs-3g. If chosen, B6 installs 11 (F5).
- **Q3 leftover config:** either is safe. The conffiles are stock (md5 matches). Purging an `rc` fuse3 runs only its empty `purge` branch, so it causes no second initrd rebuild. Purging nftables runs `deb-systemd-helper purge`. Keeping them is the CIS minimum; purging leaves a cleaner `dpkg -l`.
- **Q4 43 manual marks:** recommended. Without them, any later `autoremove` takes sysstat (Batch 1 config), tcpdump, mtr-tiny and 26 more (SIM2). The cost: those 43 then leave only when removed by name.
- **New (from F1):** a console reboot to prove the rebuilt initrd now, or accept the risk until the next planned reboot. That is AJ's call.

## Acceptance gates

Run on Johnny. Lines marked **(sudo, read-only)** are AJ's. A gate fails if the output differs from what is expected. On a failure, stop and tell the Brain. Run B6 only after review. Mid-batch failures go to the F2 branch, not B6.

### Safety (after B3, from a second SSH session)
- GS1, from the laptop: `ssh aj@192.168.50.152 'id -un'` → `aj`
- GS2 (AJ): `sudo -k && sudo true && echo sudo-ok` → password prompt, then `sudo-ok`
- GS3: `apt-mark showhold` → `secureboot-db`, `shim-signed`, nothing else
- GS4: `systemctl --failed --no-pager --plain` → `0 loaded units listed.`
- GS5: `dpkg --audit; echo rc=$?` → only `rc=0` (no half-configured or trigger-pending package)

### Before B3
- GB0a: B0 output = SIM3 (9 `Remv`, 0 new, the same 29-name list). Then B2 after B1 = SIM6 (2-name list: `libnftables1 libntfs-3g89t64`).
- GB0b **(sudo, read-only; writes a file in ~)**: `sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic > ~/cis-audit/initrd-mods-pre-batch2.txt` → file non-empty. `ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic` → note mtime (2026-10-29 05:12:42 UTC today).
- GB0c **(sudo, read-only)**: `sudo iptables -S` → record as baseline (expected `-P INPUT ACCEPT`, `-P FORWARD ACCEPT`, `-P OUTPUT ACCEPT`).

### After B3/B4 (rules)
- G2.1.13: `dpkg-query -s rsync &>/dev/null && echo "rsync is installed"` → nothing
- G2.2.4: `for pkg in telnet inetutils-telnet telnet-ssl; do dpkg-query -s "$pkg" 2>/dev/null | grep -q '^Status: install ok installed' && echo "$pkg is installed"; done` → nothing
- G2.2.6: `for pkg in ftp tnftp atftp inetutils-ftp ftp-ssl; do dpkg-query -s "$pkg" 2>/dev/null | grep -q '^Status: install ok installed' && echo "$pkg is installed"; done` → nothing
- G7.1.13 **(sudo, writes only the report)**: `sudo bash ~/cis-audit/cis-7-root.sh > ~/cis-audit/7-root-batch2.txt 2>&1`, then `grep -E 'List of|ntfs-3g|fusermount3' ~/cis-audit/7-root-batch2.txt` → exactly ` - List of "13" SUID executable files:` and ` - List of "6" SGID executable files:`

### After B3/B4 (state)
- GP1: `dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables` → stdout `rc  fuse3 3.18.2-1`, `rc  nftables 1.1.6-1` (Q3 = purge: nothing); stderr 7 `no packages found matching` lines (Q3 = purge: 9)
- GP2: `ls -l /usr/bin/ntfs-3g /usr/bin/fusermount3 /usr/sbin/nft` → three `No such file or directory`
- GP3: `apt-mark showauto ufw iptables sysstat tcpdump mtr-tiny nano plymouth friendly-recovery` → nothing
- GP4: `apt-get -s autoremove` → `Remv libnftables1 [1.1.6-1]`, `Remv libntfs-3g89t64 [1:2022.10.3-5ubuntu1.1]` only (Q2 = remove: `0 to remove`)

### Firewall and module
- GF1: `iptables --version` → `iptables v1.8.11 (nf_tables)`
- GF2: `modinfo -F filename nf_tables` → `/lib/modules/7.0.0-42-generic/kernel/net/netfilter/nf_tables.ko.zst`
- GF3: `dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' ufw iptables linux-modules-7.0.0-42-generic libfuse3-4 grub2-common` → five `ii` lines
- GF4 **(sudo, read-only)**: `sudo ufw status` → `Status: inactive`. `sudo iptables -S` → identical to GB0c

### Boot path (F1)
- GI1: `ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic` → mtime at B3 time, size within a few MB of 42 620 636
- GI2 **(sudo, read-only)**: `sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic | diff ~/cis-audit/initrd-mods-pre-batch2.txt -` → nothing. **[Assumption]** No dracut module depends on fuse3 or ntfs-3g, so the module list does not change. Any diff: stop, no reboot, tell the Brain.
- GI3 (only if AJ chooses the reboot proof): console reboot via AMT KVM → TPM unlock without a passphrase → GS1 and GS4 pass → `lsmod | grep -c '^nf_tables'` may be `0` (ufw off). That is not a failure; GF2 is the check.

### Release gate (Governance re-audit; all must pass)
Governance re-runs 2.1.13, 2.2.4, 2.2.6 and 7.1.13 with the section scripts. 2.1.13, 2.2.4 and 2.2.6 are PASS. 7.1.13 lists 13/6 with no ntfs-3g and no fusermount3. No rule that passed in `docs/cis-26.04-l1-results.csv` now fails. GS1–GS5 and GI1–GI2 pass. The SBOM and Config changes rows are in the same commit.

### Durability (recurring)
- GR5 (after any `apt install`): rerun G2.1.13, G2.2.4, G2.2.6 and GP2 → nothing / three "No such file". A hit means a new Depends or Recommends brought a package back (C7).

## Sources
- CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0 (local PDF): 2.1.13, 2.2.4, 2.2.6 remediation and audit lines; 7.1.13.
- dpkg 1.23.7: https://salsa.debian.org/dpkg-team/dpkg/-/raw/1.23.7/src/main/remove.c, https://salsa.debian.org/dpkg-team/dpkg/-/raw/1.23.7/src/query/main.c, https://salsa.debian.org/dpkg-team/dpkg/-/raw/1.23.7/lib/dpkg/dump.c, https://salsa.debian.org/dpkg-team/dpkg/-/raw/1.23.7/lib/dpkg/pkg.c
- apt 3.2.0: https://salsa.debian.org/apt-team/apt/-/raw/3.2.0/apt-pkg/depcache.cc
- iptables 1.8.11: https://salsa.debian.org/pkg-netfilter-team/pkg-iptables/-/raw/upstream/1.8.11/iptables/nft.c
- dracut ships `/usr/sbin/update-initramfs` in resolute: https://packages.ubuntu.com/resolute/amd64/dracut/filelist
- Live Johnny reads (no sudo): `/var/lib/dpkg/info/{fuse3,ntfs-3g,nftables,rsync,tnftp,inetutils-telnet,dracut,libnftables1:amd64,libntfs-3g89t64:amd64}.*`, `/usr/sbin/update-initramfs`, `/usr/lib/needrestart/apt-pinvoke`, `/etc/dracut.conf.d/*`, `/boot` listing, `~/cis-audit/7-root.txt`, `apt-cache show/policy/rdepends`, `apt-mark`, `dpkg-query`, `modinfo`, `lsmod`, `systemctl`.

## Assumptions (marked)
- **[Assumption]** GI2: the dracut module list does not change when fuse3 and ntfs-3g go. Their initramfs hooks are initramfs-tools hooks, which dracut does not use. I could not read the current initrd (0600 root).
- **[Assumption]** F4/GB0c: the live iptables ruleset is empty. `aj` cannot read it.
- **[Assumption]** C7: apt's solver3 handles old unsatisfied Recommends the way the classic depcache does.
- **[Assumption]** F2: the exact dracut message text on success varies. The `Generating` line and the absence of `failed` are the markers.

---

# Rev 2 spot-check (batch-2.md DRAFT rev 2)

**Reviewer:** Assurance. **Date:** 2026-11-03. **Method:** read the actual blocks of rev 2 (not the change-log table); read-only `ssh aj@...` reads (initrd stat, `dpkg -l dracut`, `apt.conf.d` grep); local `/usr/bin/lsinitrd` and `/usr/bin/dracut` 110 scripts on this laptop for the output format. No sudo, nothing written on Johnny, batch-2.md not edited.

## Verdict: APPROVE WITH CHANGES (two small command fixes, R1 and R2; both would cause a false stop at B5, not harm)

## F1-F10 against the blocks

| # | Result | Where verified |
|---|---|---|
| F1 | Fixed. Risk line states the dracut rebuild, PCR 7 unaffected, no auto reboot. B2a has the baseline, the required `cp -a` copy, the matching delete (Cleanup), B5 module diff and mtime, B6 note, and Q5 A/B. **But the B5 diff and grep need R1 and R2.** | Risk, B2a, B5, Cleanup, B6, Q5 |
| F2 | Fixed. B3 lists the trigger lines with the `Generating` line and no `failed` as markers. "If B3 fails" says stop, no B4, no reboot, no B6, read-only `dpkg --audit`, restore by `cp -a`, `dpkg --configure -a` only after review. | B3 |
| F3 | Fixed. Paragraph corrected (only `purge ftp tnftp` installs ftp-ssl; the full CIS line removes ubuntu-standard). B4 guard is the one I asked for. | "Why one combined removal", B4 |
| F4 | Fixed. Baseline `sudo iptables -S` in B2a; B5 expects identical output; source cited. | B2a, B5 |
| F5 | Fixed. 11-install variant, initrd rebuild, needrestart, rsync, pointer to the B3 branch. | B6 |
| F6 | Fixed (SuggestsImportant explanation; Assumption 3). | Live state, Assumptions |
| F7 | Fixed. Exact grep lines with leading space-dash; "was already set" variant. | B1, B5 |
| F8 | Fixed (grub2-common named). | SBOM |
| F9 | Fixed (apt versions, apt.conf.d absence stated). See below. | sim header |
| F10 | Fixed (grub-pc `rc` note). | B5 |

## New findings

| # | Sev | Location | Finding (root cause) | Fix requested of Platform |
|---|---|---|---|---|
| R1 | Medium | B2a (save) and B5 (diff) | **`lsinitrd -m` output is not only the module list.** In dracut 110 `lsinitrd.sh` (same as `/usr/bin/lsinitrd` here, line 456) the non-verbose header is `Image: /boot/initrd.img-7.0.0-42-generic: 41M` (from `du -h`), then a `====` line, then `Version: dracut-...`, a blank line, `dracut modules:`, the names, and a closing `====` line (source: https://raw.githubusercontent.com/dracut-ng/dracut-ng/refs/heads/main/lsinitrd.sh, functions `list_modules` and the `-m` branch). The image is 42 620 636 bytes, about 40.6 MiB, so `du -h` prints `41M`. The rebuild "may change size slightly" (Platform's own words). A change across a 1 MiB rounding step, or a dracut patch version in the `Version:` line, makes the B5 `diff` print a line even though the module list is identical. That is a false stop (restore copy, no reboot) on a good image. | Compare only the module block, on both sides. B2a: `sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic \| sed -n '/^dracut modules:/,/^=====/p' > ~/cis-audit/initrd-mods-pre-batch2.txt`. B5: `sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic \| sed -n '/^dracut modules:/,/^=====/p' \| diff ~/cis-audit/initrd-mods-pre-batch2.txt -`. Keep the `wc -l` check (expect above 2). Alternative: `grep -v '^Image:'` on both sides, but that still compares the `Version:` line, which is fine only if dracut is not updated in between. |
| R2 | Medium | B5 `grep -E '^(crypt\|tpm2)'` and "shows both `crypt` and `tpm2`" | **Module names are at line start, so the anchor is right** (`dracut.sh` line 2799 writes `printf "%s\n" "$i"` to `lib/dracut/modules.txt`; `lsinitrd` prints the file raw, no indent). **The names are wrong.** dracut 110 has no module called `tpm2`; the module is `tpm2-tss` (`/usr/lib/dracut/modules.d/73tpm2-tss`), and the prefix match `^tpm2` only works by accident. On a systemd initrd, TPM2 unlock may be carried by `systemd-cryptsetup` (71) alone, and dracut includes `tpm2-tss` only if its check passes and it is wanted. I could not read Johnny's initrd (0600 root), so I cannot say which of these is present. "grep shows both" can therefore false-stop, or pass on `crypt-gpg`/`crypt-loop` (also match `^crypt`) for the wrong reason. | State the expected set from the baseline, not from assumption. B2a add: `grep -E '^(crypt\|systemd-cryptsetup\|tpm2-tss)' ~/cis-audit/initrd-mods-pre-batch2.txt` and record the result. B5: same grep on the new image; expected output **identical to the B2a grep**. (The full diff already covers it; the grep is a readable cross-check.) Use `$` anchors: `'^(crypt\|systemd-cryptsetup\|tpm2-tss)$'`. |

## Specific checks requested

- **B2a:** commands are exact and copy-paste, no placeholders. The redirect `> ~/cis-audit/...` is done by aj's shell, so the file is owned by aj, as intended. `ls` on the 0600 initrd works (it needs directory read only). `cp -a` keeps mode 0600 and the mtime. `sudo iptables -S` is read-only. Only the `sed` fix R1 is needed.
- **B3:** exact. Expected output cannot false-stop: the markers are only the `Generating` line and no `failed`; "Processing triggers for man-db" absent would not be a stop under that rule, but Platform should say that man-db and the dracut version line are not markers. The "If B3 fails" branch is correct: restore with `cp -a` (same 0600 mode), no reboot, `dpkg --configure -a` only after review. Step 6 (GRUB `e` edit) is clearly marked last-resort and unchecked.
- **B5:** all other lines unchanged from what I confirmed in rev 1, plus the baseline match for `iptables -S`. Module diff and grep: see R1, R2.
- **Cleanup:** exact (`sudo rm` of one named file, then `ls` expects "No such file or directory"; `ls` of a /boot path works without sudo).
- **Q5 A:** exact and safe in order. `sudo systemctl reboot` is an AJ-run line, after B3 exit 0 and the B5 boot-path checks. Fallbacks are correct. The step 3 SSH one-liner prints `cat: /run/reboot-required: No such file or directory` as expected. Q5 B: consistent with Cleanup and the risk register. Neither branch touches PCR 7 (kernel, shim and GRUB unchanged).
- **lsinitrd -m pattern for Johnny:** anchored form is correct, names are wrong. See R2. Sources: dracut `lsinitrd.sh` above and `/usr/bin/lsinitrd` and `/usr/bin/dracut` 110 on this laptop. Johnny has dracut and dracut-core 110-11ubuntu0.1 (read-only `dpkg -l`).
- **Sim header, apt.conf.d (F9):** does not matter. Platform's SIM5-SIM9 did not have Johnny's `apt.conf.d`; mine did, and matched line for line (C10). I also grepped Johnny's `apt.conf.d` just now for `AutoRemove`, `Recommends`, `Suggests` and solver keys: only `NeverAutoRemove` (kernel patterns, from `01autoremove-kernels`) and `KeepCompressed` (list storage). Neither changes which of the 9 packages or 29 auto packages apt picks. SIM6-SIM9 are valid. B2 on Johnny remains the binding gate. The header and Assumption 2 are accurate.
- **Scope:** nothing new outside Batch 2. No held package, PCR 7, SSH, PAM, sudo or Secure Boot command. GRUB appears only in the marked last-resort manual edit. Cleanup and Q5 touch only `/boot/initrd.img-7.0.0-42-generic.pre-batch2` and a reboot that AJ chooses.

## Remaining fixes (before the Brain shows AJ)
1. R1: module-block-only save and diff (B2a, B5).
2. R2: grep names and baseline-based expectation (B2a, B5, Assumption 6 wording).
3. Optional wording: in B3 say that the man-db and dracut version lines are not stop markers.

**[Assumption]** `modules.txt` has the same content format in Johnny's image as in dracut 110 here (names one per line, no number prefix); not readable without sudo. The B2a baseline will show it.
