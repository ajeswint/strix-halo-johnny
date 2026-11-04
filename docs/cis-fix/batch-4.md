# CIS L1 fix pass, Batch 4: kernel modules, kernel parameters, core dumps and apport

**Status:** DRAFT rev 5 (Grok, 2026-11-04: A3's `head -1` stop is a spec bug. The check counts `install /bin/false` on the full dry-run. P4 and A1 have run. A2 and F4 have not. Q5 is open). Rev 4 (Claude, 2026-11-04: P1-P3 results recorded; the ufw `rp_filter` premise behind Q5 was wrong, so Q5 is reopened for AJ). Rev 3 (Claude, 2026-11-04: AJ chose "recommendations" for Q1-Q9, recorded below; no command changed). Rev 2 (Claude, 2026-11-04, after Assurance's review `docs/findings/cis-batch-4-review.md`, approve with changes; applies F1, F2, F3, F4, F5, F6, F7, F8; F9-F11 are residuals for Governance). Rev 1 was drafted by Platform. P4 and A1 have run. A2 has not. Group B has not. **Nothing below has run on Johnny and nothing was read from Johnny while drafting** (this session has no route to `192.168.50.152`). Every "current state" below comes from `docs/cis-26.04-l1-results.csv` (audit 2026-10-30 and 2026-10-31) and the repo docs, so the P-blocks re-read it at apply time and stop on any difference. Not reviewed yet. Per the handoff, Batch 4 starts after Batch 3's second C9 and Governance's re-audits of 6.1.1.1.5, 6.1.2.7, 6.3.1 and 6.3.2. AJ runs every `sudo` block, shown first, with a second SSH session open (fix gate met, handoff rev 16). Stop on any error.

**Rules in scope (32):** 1.1.1.1, .2, .3, .4, .5, .9, .10, .11 (8) · 3.2.1, .2, .4, .5, .6 (5) · 3.3.1.1, .2, .3, .4, .5, .8, .9, .10, .11, .12, .13, .14, .18, .19 (14) · 1.5.4, 1.5.5, 1.5.7, 1.5.9, 1.5.10 (5).
**Not in this batch, on purpose:** 3.3.1.16 and 3.3.1.17 (`log_martians`; Batch 6, because `/etc/ufw/sysctl.conf` sets them to 0 when ufw is enabled; this batch does not touch that file). 3.2.7 (FAIL (manual), waits for Governance's module list). 3.1.1 and 3.3.2.x (IPv6, Batch 7). 3.2.3 dccp is already PASS (no dccp module in the kernel). 3.3.1.6, .7 and .15 pass today; Group C optionally pins them (Q8).

**Benchmark:** CIS Ubuntu Linux 26.04 LTS v1.0.0 (local PDF only). **The PDF and `docs/cis-local/` are not in this checkout** (both are gitignored; the audit scripts and raw `*-out.txt` files live on rock-box and in `~/cis-audit/` on Johnny, not verified from here). So this draft quotes only the rule titles from the CSV, which are CIS's own wording, and takes each rule's pass state from the CSV evidence column. Where a CIS remediation shape is described, it follows that evidence and Johnny's own precedent files (`etc/modprobe.d/johnny-no-*.conf`). Governance's re-audit with the local scripts (`cis-1.1.1.11-audit.sh`, `cis-1.5-audit.sh`, `cis-3-audit.sh`, and the 1.1.1.1 to 1.1.1.10 module script, whose file name the session log does not record) decides every verdict. The read-only checks below are my own cross-checks, not the verdict.

## Open questions for AJ (recommendation marked)
1. **Initrd and reboot.** The batch table said "rebuild the initramfs if modprobe.d changes". Reading dracut's source says that is not needed (see "Boot-path facts"). **Rec: do not rebuild; take the baseline and a `.pre-batch4` copy anyway; one attended console reboot at the end (Group D) to prove sysctl persistence and TPM unlock.** Alternatives: (b) skip the reboot until the next planned one; (c) rebuild now (Group R, not recommended).
2. **1.1.1.11 unused filesystems (manual).** (a) **Rec: block 60 unused filesystem modules (A2); the keep set is xfs, autofs4, binfmt_misc, ramoops, pstore_blk, pstore_zone and the 51 `nls_*` encodings; Governance then judges the manual rule.** (b) Do only 1.1.1.1 to .10 and leave 1.1.1.11 FAIL (manual) until a site list exists. (c) Block the pstore trio too (`ramoops`, `pstore_blk`, `pstore_zone`): the keep set shrinks to xfs, autofs4, binfmt_misc and the `nls_*` encodings; they load only with a RAM or block backend that is not configured, and none is loaded now (Assurance F5). (d) Keep `nfs*`, `cifs`, `9p`, `virtiofs`, `isofs`, `udf` and `exfat` off the blocklist if a NAS or NFS/SMB backup target, pcap datasets or an installer ISO mount is planned (Data Services, Assurance and SLM should say). Unblocking any of them is one file deleted, no rebuild.
3. **`overlay` (container filesystem).** **Rec: block it with A2b** (nothing on Johnny uses it; strict CIS, loosen later by deleting one file). Alternative: keep it if an on-box container runtime for the SLM is planned.
4. **1.1.1.10 `usb-storage`.** Blocking means no USB flash drives or disks can be mounted on Johnny (keyboards and other HID still work). **Rec: block**; copy files over the network. Alternative: leave 1.1.1.10 FAIL.
5. **3.3.1.12 and 3.3.1.13 `rp_filter` (strict = 1).** **Rec: defer both to Batch 6**, when `log_martians` is decided and Detection checks capture once. **Rev 4 correction (P2, 2026-11-04):** the original reason, "`ufw enable` applies the same value anyway", is wrong for Johnny: its `/etc/ufw/sysctl.conf` has no active `rp_filter` line, so Batch 6 will not set it and deferring buys nothing. The log-noise concern comes from `log_martians`, which this batch does not change. **Updated rec: apply now** (Group C line), unless AJ prefers to keep 3.3.1.12/.13 FAIL until Batch 6. AJ's "recommendations" answer predates this correction, so Q5 is open. Alternatives: apply now (Group C line is provided, commented out; it takes effect on `eno1np0` at once); skip for good (accept FAIL).
6. **3.3.1.1 to .5 (`ip_forward`, `forwarding`, `send_redirects`).** The file values equal today's running values, so nothing changes at runtime. **Rec: apply.** Alternative: defer if an on-box container network (NAT) or inline forwarding is planned, because any later `ip_forward=1` would fight these lines.
7. **1.5.7 apport.** **Rec A: `enabled=0` in `/etc/default/apport` plus `systemctl mask --now apport.service`** (minimal, reversible, the CIS remediation shape). B: purge the two apport packages (apt-get simulation first). C: leave FAIL.
8. **Pin the three rules that already pass (3.3.1.6, .7, .15) in the same file?** **Rec: yes** (same values, so they keep passing if `/etc/ufw/sysctl.conf` or `50-default.conf` ever change).
9. **Only if Governance's re-audit of 1.5.10 still fails on the vendor `* hard core infinity` line:** allow a local `dpkg-divert` of `/etc/security/limits.d/10-coredump-debian.conf`? (Not run now; see B6.)

## Decisions (AJ, 2026-11-04: "recommendations")
All nine questions are answered with the marked recommendation: **Q1** no rebuild, take the baseline and `.pre-batch4` copy, one attended reboot at the end (Group D, after D0). **Q2** (a) block the 60 unused filesystem modules (A2), **gated on Governance's F4 diff** of the raw 1.1.1.11 list before A2 runs. **Q3** block `overlay` (A2b). **Q4** block `usb-storage`. **Q5** was "defer `rp_filter`" but is **reopened** (rev 4: the ufw premise was wrong; new rec is apply now). **Q6** apply `ip_forward`, `forwarding`, `send_redirects`. **Q7** option A: `enabled=0` plus `systemctl mask --now apport.service`. **Q8** pin 3.3.1.6, .7 and .15. **Q9** only if Governance still fails 1.5.10 after B3. Not chosen: Q2 (c) pstore trio, Q2 (d) keeping nfs/cifs; either can be added by a one-line change before A2. Next step: Group P.

## P1-P3 results (AJ, no sudo, 2026-11-04 ~05:2x UTC)
Everything matched the draft except two points. **Matched:** kernel `7.0.0-42-generic`; 0 failed units; none of the 12 modules loaded; `xfs` and `autofs4` loaded; no existing blacklist or install line for them; `/etc/modprobe.d/` holds the two `johnny-no-*` files plus stock vendor files and no `johnny-cis-*`; `/etc/sysctl.d/` and `limits.d/` have no Batch 4 files; no `/etc/sysctl.conf`; `modules-load.d` and `/etc/modules` name only `i2c_dev` and `msr` (neither is on any blocklist here); every sysctl value as expected (`suid_dumpable` 2, redirects 1, `rp_filter` 2, `log_martians` 0, forwarding 0); apport active and enabled with `enabled=1` once; `apport`, `apport-core-dump-handler`, `python3-apport` installed 2.34.1-0ubuntu0.1; `systemd-coredump` not installed; `ulimit -Hc` unlimited; ufw `ENABLED=no`. **Differences:** (1) `/etc/ufw/sysctl.conf` has no active `rp_filter` or `accept_source_route` line (corrected above; reopens Q5). (2) `/usr/lib/sysctl.d/10-coredump-debian.conf` sets `kernel.core_pattern=core`, which is the value D2 expects once apport is masked (no change needed; it is why the running pattern reverts after the mask and reboot). **Note:** the vendor limits file also has `* soft core 0` and `root soft core 0` and `root hard core infinity`; B3's `* hard core 0` does not change the `root` lines, and CIS audits the `*` line.

## Recorded output
Each output line is prefixed with `# ` so it is not a shell command.

**P4 (AJ, sudo, 2026-11-04).** Initrd and the `.pre-batch4` copy:
```
# -rw------- 1 root root 42618411 2026-11-03 06:13:32.840646209 +0000 /boot/initrd.img-7.0.0-42-generic
# -rw------- 1 root root 42618411 2026-11-03 06:13:32.840646209 +0000 /boot/initrd.img-7.0.0-42-generic.pre-batch4
# 40 /home/aj/cis-audit/initrd-mods-pre-batch4.txt
# crypt
# systemd-cryptsetup
# tpm2-tss
# 2
# /dev/nvme0n1p2  2.0G  118M  1.7G   7% /boot
# f0a42b98383cce09397c4fa998a518a1452ed303701a732e390e5433137618a7  /boot/initrd.img-7.0.0-42-generic
# f0a42b98383cce09397c4fa998a518a1452ed303701a732e390e5433137618a7  /boot/initrd.img-7.0.0-42-generic.pre-batch4
```
The copy hash is from `sudo sha256sum /boot/initrd.img-7.0.0-42-generic.pre-batch4` (AJ, 2026-11-04). It matches the live image. The `2` is `etc/modprobe.d/johnny-no-bluetooth.conf` and `etc/modprobe.d/johnny-no-thunderbolt.conf` inside the image. Hostonly. No rebuild.

**A0 (Grok, read-only, just before A1).**
```
# OK-kernel
# 0 loaded units listed.
# xfs
# autofs4
```
The showconfig grep for the twelve names printed nothing.

**A1 (AJ, sudo, 2026-11-04 05:34 UTC).** `tee` printed each file body. `chown` and `chmod` printed nothing. Modes `644 root:root`. Sizes 296, 210, and 293 bytes. Mirrors under `etc/modprobe.d/` match Johnny:
```
# ebf42bf47095169cc7abfb8e81f0a6f2c3de32ed449c9570ca3da2df2735def3  johnny-cis-fs.conf
# 4510b705d550fbaed58e45102107a4a58a82c115ef1337a5e9f77edbad116d70  johnny-cis-drivers.conf
# 756c6360afc36408c4d0222cedd68c85f779a27261ef91aa293e7798e9d907dd  johnny-cis-net.conf
```

**A3 count (Grok, read-only).** Full dry-run, one `install /bin/false` each:
```
# cramfs 1
# freevxfs 1
# hfs 1
# hfsplus 1
# jffs2 1
# firewire-core 1
# usb-storage 1
# atm 1
# can 1
# rds 1
# sctp 1
# tipc 1
```
`can` alone is also `1`. Showconfig count `24`. `UFW-MODULES-CLEAR`. `xfs` and `autofs4` loaded. Failed units `0`.

**Accidental paste.** AJ pasted the dry-run record into the shell. **[Assumption]** no pasted line began with `sudo`. The transcript Claude saw has no `sudo`. `insmod` of the `...` paths failed. GNU `install /bin/false` had no destination and wrote nothing. `tipc` is a userspace tool and did not load the module. `lsmod` afterward showed none of `firewire_core`, `sctp`, `tipc`, `crc_itu_t`, `udp_tunnel`, or `ip6_udp_tunnel`.

**Not done.** A2 has not run. Governance's F4 diff of the raw 1.1.1.11 list has not been done. Q5 is still open with AJ. Group A is not signed off.

## Risk
None for access or boot in the recommended path. **No step touches SSH, PAM, sudo, GRUB, Secure Boot, the shim, a held package or PCR 7.** No package is installed or removed (Option A of Q7). The initrd is not rebuilt: Group P records its hash and keeps a copy, and Group D proves it unchanged. Runtime effects: 12 modules (plus 60 or 61 filesystem modules with A2) can no longer be loaded; core dumps stop (apport off, `fs.suid_dumpable=0`, `* hard core 0`); ICMP redirects are refused and not sent. Capture and the port mirror are not affected (next section). One attended reboot at the end.

## Capture and mirror impact (flag, Constraint 4)
The kernel's receive path hands every frame to AF_PACKET taps (`ptype_all` in `__netif_receive_skb_core`) and runs native XDP before the IPv4 stack, and `ip_rcv_core` drops `PACKET_OTHERHOST` frames (a mirrored unicast frame for another host's MAC) before routing or source validation. Sources: https://raw.githubusercontent.com/torvalds/linux/master/net/core/dev.c and https://raw.githubusercontent.com/torvalds/linux/master/net/ipv4/ip_input.c (`master`; Johnny runs 7.0.0-42, **[Assumption]** same logic). So none of the sysctls here can drop a frame that AF_PACKET, XDP or AF_XDP would see. Per rule:
- **`ip_forward`, `forwarding` (3.3.1.1 to .3):** pinned at the running value 0. Per https://docs.kernel.org/networking/ip-sysctl.html, a change of `ip_forward` "resets all configuration parameters to their default state"; writing the same value changes nothing. Do not turn forwarding on later on this box: it also disables LRO on every NIC, the E810 included (kernel `inet_forward_change`; **[Assumption]** from memory of the source).
- **`send_redirects`, `accept_redirects`, `secure_redirects` (3.3.1.4, .5, .8 to .11):** apply only to hosts that route or receive redirects over IP. Johnny is a single-homed host with no forwarding. The kernel doc: send/secure redirects are enabled if "at least one of conf/{all,interface}" is TRUE, and writing a `default` key also updates existing interfaces that were never set by name (kernel `devinet_copy_dflt_conf`, Assurance F3), so the new values reach `eno3` and `eno1np0` at once; the CIS audit reads `all` and `default` only.
- **`rp_filter` (3.3.1.12, .13): the one that could matter.** Strict mode would fail broadcast and multicast frames that reach the IPv4 stack on `eno1np0` (no address; mirrored hosts' source IPs are best reached via `eno3`). That does not hide anything from capture, but with `log_martians=1` (Batch 6) it can flood the kernel log (Governance's untested reasoning, handoff step 10 section 3). The kernel doc also says "The max value from conf/{all,interface}/rp_filter is used", so `all=1` cannot be relaxed per interface later. Hence Q5.
- **`/etc/ufw/sysctl.conf`:** see Group C. It is applied only when ufw is enabled, so none of this interacts with it in this batch.

## Boot-path facts (hard constraint 1)
- A `/etc/modprobe.d` change does not rebuild anything. The initrd is rebuilt only by `update-initramfs` (dracut's wrapper, `/usr/sbin/update-initramfs`; `/etc/kernel/postinst.d/dracut`; the `interest-await update-initramfs` trigger): https://packages.ubuntu.com/resolute/amd64/dracut/filelist and https://git.launchpad.net/ubuntu/+source/dracut/plain/debian/dracut.triggers?h=applied/ubuntu/resolute.
- dracut copies `/etc/modprobe.d/*.conf` into the initrd **only in hostonly mode**: `[[ $hostonly ]] && inst_multiple -H -o /etc/modprobe.d/*.conf /etc/modprobe.conf` (dracut-ng tag 110, `modules.d/80base/module-setup.sh`, line 99: https://raw.githubusercontent.com/dracut-ng/dracut-ng/110/modules.d/80base/module-setup.sh). **[Assumption]** Ubuntu's `dracut 110-11ubuntu0.1` behaves like upstream 110. Whether Johnny's initrd is hostonly is not known; P4 reads it. The history suggests generic: the thunderbolt block needed `omit_drivers` as well as modprobe.d (handoff closed issue 1).
- In non-strict mode dracut also installs every module under `kernel/fs` except nfs/nfsd/lockd (`dracut_instmods -o -P ... '=fs'`) and `=drivers/usb/storage` plus `firewire-ohci` (https://raw.githubusercontent.com/dracut-ng/dracut-ng/110/modules.d/70kernel-modules/module-setup.sh). So the blocked modules may sit inside the initrd file. They are not needed to boot from NVMe, LUKS and XFS, and `xfs` stays unblocked.
- Therefore: a blocked module in a baked-in copy is harmless, and a not-yet-baked copy is harmless. The only way these files reach the initrd is a later rebuild (kernel or dracut update), which would bake them in without trouble. P4 still takes the baseline and a copy, because a surprise rebuild is the one Batch 2 lesson that applies.
- `systemd-sysctl` rules in the initrd (if the dracut `systemd-sysctl` module is present) are also stale-but-harmless: sysctl.d(5) says an initrd copy of a vendor file "has to be regenerated" only to change it there; the real root re-applies everything at boot.

---

## Group P: pre-checks and baselines (read-only unless marked sudo)

### P1. State assertions (no sudo)
```
[ "$(uname -r)" = "7.0.0-42-generic" ] && echo OK-kernel || echo STOP-kernel
systemctl --failed --no-pager --plain | tail -1
lsmod | awk '$1 ~ /^(cramfs|freevxfs|hfs|hfsplus|jffs2|firewire_core|usb_storage|atm|can|rds|sctp|tipc)$/'
lsmod | awk '$1=="xfs"||$1=="autofs4"{print $1}'
modprobe --showconfig | grep -E '^(blacklist|install) (cramfs|freevxfs|hfs|hfsplus|jffs2|firewire_core|usb_storage|atm|can|rds|sctp|tipc)( |$)'
ls /etc/modprobe.d/ /etc/sysctl.d/ /etc/security/limits.d/
ls -l /etc/sysctl.conf /run/sysctl.d /usr/local/lib/sysctl.d
cat /etc/modules-load.d/*.conf /usr/lib/modules-load.d/*.conf /etc/modules 2>/dev/null | grep -vE '^[[:space:]]*(#|;|$)'
```
Expected, **stop and tell the Brain on any difference**:
- Line 1 `OK-kernel`. Line 2 `0 loaded units listed.`
- Line 3 prints nothing (none of the 12 is loaded; CSV 2026-10-30 and 10-31). Line 4 prints `xfs` and `autofs4` (CSV: xfs mounted, autofs4 loaded; autofs4 is what `proc-sys-fs-binfmt_misc.automount` uses **[Assumption]**).
- Line 5 prints nothing (CSV: "no blacklist/install in modprobe --showconfig"). `modprobe --showconfig` prints names with underscores, which is why `firewire_core` and `usb_storage` are written that way.
- Line 6: `/etc/modprobe.d/` holds `johnny-no-bluetooth.conf` and `johnny-no-thunderbolt.conf` (plus any vendor files) and **no** `johnny-cis-*` file; `/etc/sysctl.d/` has **no** `60-johnny-cis-*` file; `/etc/security/limits.d/` has no `60-johnny-cis-core.conf`.
- Line 7: `/etc/sysctl.conf` absent or all comments; `/run/sysctl.d` and `/usr/local/lib/sysctl.d` absent or empty. systemd 259's `systemd-sysctl` does **not** read `/etc/sysctl.conf` (https://manpages.ubuntu.com/manpages/resolute/en/man5/sysctl.conf.5.html), but procps `sysctl --system` and a CIS scan might; an active line there for any key in this batch would be a stop.
- Line 8 (Assurance F6): no name from A1, A2 or A2b (netfilter-style names such as `ip_tables` are fine). A blocked name here would fail `systemd-modules-load.service` at boot: **stop**, tell the Brain.

### P2. Sysctl and ufw state (no sudo)
```
sysctl fs.suid_dumpable kernel.dmesg_restrict kernel.randomize_va_space kernel.core_pattern kernel.core_pipe_limit
sysctl net.ipv4.ip_forward net.ipv4.conf.all.forwarding net.ipv4.conf.default.forwarding net.ipv4.conf.all.send_redirects net.ipv4.conf.default.send_redirects net.ipv4.icmp_ignore_bogus_error_responses net.ipv4.icmp_echo_ignore_broadcasts net.ipv4.conf.all.accept_redirects net.ipv4.conf.default.accept_redirects net.ipv4.conf.all.secure_redirects net.ipv4.conf.default.secure_redirects net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter net.ipv4.conf.all.accept_source_route net.ipv4.conf.default.accept_source_route net.ipv4.conf.all.log_martians net.ipv4.conf.default.log_martians net.ipv4.tcp_syncookies net.ipv4.conf.all.route_localnet
/usr/lib/systemd/systemd-sysctl --tldr | grep -E '^# /|rp_filter|accept_source_route|redirects|forwarding|ip_forward|syncookies|route_localnet|icmp_|log_martians|suid_dumpable|dmesg_restrict|randomize_va_space|core_'
grep -nE '^(net|kernel|fs)/' /etc/ufw/sysctl.conf
grep -nE '^(IPT_SYSCTL|IPT_MODULES|DEFAULT_FORWARD_POLICY)' /etc/default/ufw
grep -E '^ENABLED' /etc/ufw/ufw.conf
```
Expected (CSV): `fs.suid_dumpable = 2`, `kernel.dmesg_restrict = 1`, `kernel.randomize_va_space = 2`, `kernel.core_pattern` starting `|/usr/share/apport/apport`, `kernel.core_pipe_limit = 10` (apport's `--start` writes these, see Group B). `ip_forward`, both `forwarding`, `accept_source_route` (both), `route_localnet` = 0; `send_redirects`, `accept_redirects`, `secure_redirects` (all and default) = 1; `rp_filter` (both) = 2; `log_martians` (both) = 0; `tcp_syncookies`, `icmp_*` = 1. The `--tldr` lines show `/usr/lib/sysctl.d/50-default.conf`, `55-kernel-hardening.conf`, `55-network-security.conf` (`rp_filter` = 2 for default and all), `55-ptrace.conf`, with **no** line for the three kernel keys and nothing under `/etc`. (The Brain's brief wrote `/etc/sysctl.d/55-network-security.conf`; the file is shipped by `procps` in `/usr/lib/sysctl.d`: https://packages.ubuntu.com/search?suite=resolute&arch=any&searchon=contents&keywords=usr%2Flib%2Fsysctl.d%2F55-network-security.conf. Sorting is by file name across directories, so the `60-` drop-ins in `/etc/sysctl.d` sort after it either way.)
- **`/etc/ufw/sysctl.conf`:** Johnny's copy (P2, 2026-11-04) has active lines only for `accept_redirects` 0 (IPv4 and IPv6), `icmp_echo_ignore_broadcasts` 1, `icmp_ignore_bogus_error_responses` 1, `icmp_echo_ignore_all` 0 and `log_martians` 0. It has **no active `rp_filter` or `accept_source_route` line** (rev 1 wrongly said the stock file sets `rp_filter` 1 and `accept_source_route` 0). **[Assumption]** the copy is the stock file with those lines commented.
- **What ufw does with it:** `ufw-init start` runs `sysctl -e -q -p $IPT_SYSCTL` (`src/ufw-init-functions` line 386, https://git.launchpad.net/ubuntu/+source/ufw/plain/src/ufw-init-functions?h=applied/ubuntu/resolute), and at boot `ufw-init start quiet` exits at once when `ENABLED=no` (`src/ufw-init` lines 36 to 38). So today (`ENABLED=no`, CSV) the file is inert. After `ufw enable` (Batch 6) it runs after `systemd-sysctl` and **overrides any shared key in our drop-in**. That is why Group C's values equal ufw's wherever they overlap (`accept_redirects` 0, `icmp_*` 1). ufw has no active `rp_filter` or `accept_source_route` line on Johnny, so it will not touch them. The one conflict, `log_martians` 0 versus CIS 1, is Batch 6's job and is not touched here.

### P3. Apport and core-dump state (no sudo)
```
systemctl is-active apport.service
systemctl is-enabled apport.service
systemctl cat apport.service | grep -E '^(ExecStart|ExecStop)='
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' apport apport-core-dump-handler python3-apport systemd-coredump 2>&1
cat -A /etc/default/apport | grep -n 'enabled'
grep -c '^enabled=1$' /etc/default/apport
cat /etc/security/limits.d/10-coredump-debian.conf
grep -vE '^[[:space:]]*(#|$)' /etc/security/limits.conf
dpkg -S /etc/security/limits.d/10-coredump-debian.conf
ulimit -Hc
```
Expected: `active`; `enabled`; `ExecStart=/usr/share/apport/apport --start` and `ExecStop=/usr/share/apport/apport --stop`; `ii` rows for `apport`, `apport-core-dump-handler`, `python3-apport` and `dpkg-query: no packages found matching systemd-coredump` (CSV: systemd-coredump not installed); `enabled=1` on one line (the `cat -A` line ends in `$`); count `1`; the vendor file shows `* hard core infinity` (CSV); `limits.conf` prints nothing (no active line); `dpkg -S` says `systemd: /etc/security/limits.d/10-coredump-debian.conf` (https://packages.ubuntu.com/search?suite=resolute&arch=any&searchon=contents&keywords=etc%2Fsecurity%2Flimits.d%2F10-coredump-debian.conf); `ulimit -Hc` prints `unlimited`. **Stop if the unit text or the `enabled=1` line differs**: B1's `sed` and the whole apport reasoning rest on them.

### P4. Boot-path baseline and required initrd copy (AJ, sudo; before any apply block)
Run `sudo -v` on its own line first (enter the password), then paste the block (Assurance F7).
```
mkdir -p ~/cis-audit
sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic | sed -n '/^dracut modules:/,/^=====/p' > ~/cis-audit/initrd-mods-pre-batch4.txt
sudo lsinitrd /boot/initrd.img-7.0.0-42-generic | grep -E '(etc|usr/lib)/(modprobe|sysctl)\.d/' > ~/cis-audit/initrd-conf-pre-batch4.txt
sudo sha256sum /boot/initrd.img-7.0.0-42-generic > ~/cis-audit/initrd-sha256-pre-batch4.txt
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic
sudo cp -a /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch4
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic /boot/initrd.img-7.0.0-42-generic.pre-batch4
wc -l ~/cis-audit/initrd-mods-pre-batch4.txt ~/cis-audit/initrd-conf-pre-batch4.txt
grep -E '^(crypt|systemd-cryptsetup|tpm2-tss)$' ~/cis-audit/initrd-mods-pre-batch4.txt
grep -c 'etc/modprobe.d/johnny' ~/cis-audit/initrd-conf-pre-batch4.txt
df -h /boot | tail -1
```
Expected: the first `ls` shows size `42618411` and mtime `2026-11-03 06:13:32` (the value Batch 3 C0 and C3 recorded; a different value means something rebuilt it since, so tell the Brain before continuing); the second `ls` shows two identical lines (the copy is required); `wc` shows the module file above 2 lines; the `grep` prints `crypt`, `systemd-cryptsetup`, `tpm2-tss`; `df` shows enough free space (`/boot` had 1.9G).
- **The `grep -c` line decides the branch.** `0` means the initrd is generic (no `/etc/modprobe.d/johnny-*` inside): the new files cannot reach it. `1` or `2` means hostonly: the two existing johnny files are baked in, and a future rebuild would bake the new ones in too (harmless, see Boot-path facts). **Either way the plan does not rebuild.** Record the number.
- GRUB does not list the `.pre-batch4` copy. Using it needs a manual GRUB edit at the AMT console (as in Batch 2 B3, last resort only; **[Assumption]** the entry has a single `initrd` line).

---

## Group A: module blocklist (1.1.1.x and 3.2.x)

| Rule | CIS title (CSV) | Current (CSV) | File |
|---|---|---|---|
| 1.1.1.1 to 1.1.1.5 | "Ensure cramfs / freevxfs / hfs / hfsplus / jffs2 kernel module is not available" | module under `kernel/fs`, not loaded, no blacklist or install | `johnny-cis-fs.conf` |
| 1.1.1.9 | "Ensure firewire-core kernel module is not available" | under `kernel/drivers`, not loaded, no blacklist or install | `johnny-cis-drivers.conf` |
| 1.1.1.10 | "Ensure usb-storage kernel module is not available" | same | `johnny-cis-drivers.conf` |
| 3.2.1, 3.2.2, 3.2.4, 3.2.5, 3.2.6 | "Ensure atm / can / rds / sctp / tipc kernel module is not available" | under `kernel/net`, not loaded, no blacklist or install | `johnny-cis-net.conf` |
| 1.1.1.11 | "Ensure unused filesystems kernel modules are not available" (manual) | xfs mounted, autofs4 loaded, CIS script counts 60 loadable; composition to be diffed (F4); ext4, fat, vfat built in | A2, `johnny-cis-fs-unused.conf` (Q2) |

Change: for each module, one `blacklist` line and one `install NAME /bin/false` line, the same pair Johnny already uses for thunderbolt and bluetooth (modprobe.d(5), resolute: `blacklist` ignores a module's internal aliases; `install` runs the given command instead of inserting the module: https://manpages.ubuntu.com/manpages/resolute/en/man5/modprobe.d.5.html). Nothing is loaded, so no `rmmod`. **Kept on purpose, and not in any file:** `xfs`, `autofs4`, and every netfilter module ufw needs (`nf_tables`, `nft_*`, `x_tables`, `xt_*`, `ip_tables`, `ip6_tables`, `nf_conntrack*`, `nf_reject_*`); the `nf_tables` module already survived Batch 2. `ext4`, `fat`, `vfat` are built in and cannot be blocked.

**Wider effects of the three modules you might notice:** `usb-storage` (Q4): no USB mass storage on Johnny; the installer-USB recovery path boots its own kernel and is unaffected. `can`, `atm`, `rds`, `sctp`, `tipc`: no tool in the step 7 candidate list needs the kernel module (nmap, masscan, hping3, tcpreplay and netsniff-ng use raw sockets or AF_PACKET; Suricata and Zeek decode SCTP from packets). `firewire-core`: Johnny has no FireWire port **[Assumption]** (Thunderbolt is already off).

### A0. Pre-check (read-only; P1 already covered the loaded and showconfig assertions)
Re-run P1 lines 1 to 5 at apply time. Nothing else.

### A1. Apply the CIS 1.1.1.1 to .10 and 3.2.x files (AJ, sudo)
Run `sudo -v` on its own line first (enter the password), then paste the block (Assurance F7).
```
sudo tee /etc/modprobe.d/johnny-cis-fs.conf <<'EOF'
# Johnny: CIS 1.1.1.1 to 1.1.1.5 filesystem kernel modules not available (Batch 4)
blacklist cramfs
install cramfs /bin/false
blacklist freevxfs
install freevxfs /bin/false
blacklist hfs
install hfs /bin/false
blacklist hfsplus
install hfsplus /bin/false
blacklist jffs2
install jffs2 /bin/false
EOF
sudo tee /etc/modprobe.d/johnny-cis-drivers.conf <<'EOF'
# Johnny: CIS 1.1.1.9 firewire-core and 1.1.1.10 usb-storage kernel modules not available (Batch 4)
blacklist firewire-core
install firewire-core /bin/false
blacklist usb-storage
install usb-storage /bin/false
EOF
sudo tee /etc/modprobe.d/johnny-cis-net.conf <<'EOF'
# Johnny: CIS 3.2.1, 3.2.2, 3.2.4, 3.2.5, 3.2.6 network protocol kernel modules not available (Batch 4)
blacklist atm
install atm /bin/false
blacklist can
install can /bin/false
blacklist rds
install rds /bin/false
blacklist sctp
install sctp /bin/false
blacklist tipc
install tipc /bin/false
EOF
sudo chown root:root /etc/modprobe.d/johnny-cis-fs.conf /etc/modprobe.d/johnny-cis-drivers.conf /etc/modprobe.d/johnny-cis-net.conf
sudo chmod 0644 /etc/modprobe.d/johnny-cis-fs.conf /etc/modprobe.d/johnny-cis-drivers.conf /etc/modprobe.d/johnny-cis-net.conf
```
(Q4 = no: delete the `usb-storage` pair from the second file before running. The hyphens in `firewire-core` and `usb-storage` are fine: kmod treats `-` and `_` as the same in module names, and `--showconfig` prints underscores.)

### A2. Optional: 1.1.1.11 unused filesystems (Q2 = a; AJ, sudo)
**Gate (Assurance F4):** before AJ runs A2, Governance diffs the raw 60-name list from the 1.1.1.11 audit output against this file's blocked names plus the keep set. CIS's 60 and A2's 60 are different sets. Any name in neither goes to AJ as a Q2 addendum.
The list is every module under `kernel/fs` of linux-modules-7.0.0-42-generic except: the five A1 modules, the keep set (`xfs`, `autofs4`, `binfmt_misc`, `ramoops`, `pstore_blk`, `pstore_zone`), `overlay` (A2b), and the 51 `nls/*` encodings. Source for the module names: https://packages.ubuntu.com/resolute-updates/amd64/linux-modules-7.0.0-42-generic/filelist (123 files under `kernel/fs`; 72 outside `nls`). Why the keeps: `binfmt_misc` is mounted at boot by systemd (an automount, so it needs the module), the pstore trio keeps crash records, `nls_iso8859-1` and `nls_utf8` are what a FAT mount such as `/boot/efi` may load **[Assumption]**, so all `nls_*` stay. The support modules in the block list (`netfs`, `lockd`, `grace`, `nfs_acl`, `dlm`, `cifs_md4`, `quota_*`) are only used by filesystems that are also blocked.

**A2 pre-check (read-only). Stops if Johnny's kernel has a module this draft did not classify, or lacks one it names:**
```
find /usr/lib/modules/7.0.0-42-generic/kernel/fs -name '*.ko*' -not -path '*/nls/*' | sed -E 's#.*/##; s#\.ko.*$##' | sort > ~/cis-audit/b4-fs-modules.txt
wc -l < ~/cis-audit/b4-fs-modules.txt
printf '%s\n' cramfs freevxfs hfs hfsplus jffs2 xfs autofs4 binfmt_misc ramoops pstore_blk pstore_zone overlay 9p adfs affs befs bfs blocklayoutdriver btrfs cachefiles ceph cifs cifs_md4 coda cuse dlm efs erofs exfat f2fs gfs2 grace hpfs isofs jfs kafs ksmbd lockd minix msdos netfs nfs nfs_acl nfs_layout_flexfiles nfs_layout_nfsv41_files nfsd nfsv2 nfsv3 nfsv4 nilfs2 ntfs3 ocfs2 ocfs2_dlm ocfs2_dlmfs ocfs2_nodemanager ocfs2_stack_o2cb ocfs2_stack_user ocfs2_stackglue omfs orangefs qnx4 qnx6 quota_tree quota_v1 quota_v2 romfs ubifs udf ufs vboxsf virtiofs zonefs | sort | comm -3 ~/cis-audit/b4-fs-modules.txt -
lsmod | awk '$1 ~ /^(9p|adfs|affs|befs|bfs|blocklayoutdriver|btrfs|cachefiles|ceph|cifs|cifs_md4|coda|cuse|dlm|efs|erofs|exfat|f2fs|gfs2|grace|hpfs|isofs|jfs|kafs|ksmbd|lockd|minix|msdos|netfs|nfs|nfs_acl|nfs_layout_flexfiles|nfs_layout_nfsv41_files|nfsd|nfsv2|nfsv3|nfsv4|nilfs2|ntfs3|ocfs2|ocfs2_dlm|ocfs2_dlmfs|ocfs2_nodemanager|ocfs2_stack_o2cb|ocfs2_stack_user|ocfs2_stackglue|omfs|orangefs|overlay|qnx4|qnx6|quota_tree|quota_v1|quota_v2|romfs|ubifs|udf|ufs|vboxsf|virtiofs|zonefs)$/'
```
Expected: `72`; the `comm -3` prints nothing (the 72 names match the kernel exactly: 5 + 6 keeps + `overlay` + 60); the `lsmod` prints nothing. **Any `comm` output or a loaded module: stop, show the Brain.** (`netfs` or `quota_*` loaded would mean something is using them.)

**A2 apply (AJ, sudo):**
```
{ echo '# Johnny: CIS 1.1.1.11 unused filesystem kernel modules not available (Batch 4). Kept: xfs autofs4 binfmt_misc ramoops pstore_blk pstore_zone nls_*'; for m in 9p adfs affs befs bfs blocklayoutdriver btrfs cachefiles ceph cifs cifs_md4 coda cuse dlm efs erofs exfat f2fs gfs2 grace hpfs isofs jfs kafs ksmbd lockd minix msdos netfs nfs nfs_acl nfs_layout_flexfiles nfs_layout_nfsv41_files nfsd nfsv2 nfsv3 nfsv4 nilfs2 ntfs3 ocfs2 ocfs2_dlm ocfs2_dlmfs ocfs2_nodemanager ocfs2_stack_o2cb ocfs2_stack_user ocfs2_stackglue omfs orangefs qnx4 qnx6 quota_tree quota_v1 quota_v2 romfs ubifs udf ufs vboxsf virtiofs zonefs; do printf 'blacklist %s\ninstall %s /bin/false\n' "$m" "$m"; done; } | sudo tee /etc/modprobe.d/johnny-cis-fs-unused.conf | wc -l
sudo chown root:root /etc/modprobe.d/johnny-cis-fs-unused.conf
sudo chmod 0644 /etc/modprobe.d/johnny-cis-fs-unused.conf
```
Expected: `121` (one comment line plus 60 pairs).

**A2b `overlay` (Q3 = block; AJ, sudo):**
```
sudo tee /etc/modprobe.d/johnny-cis-fs-overlay.conf <<'EOF'
# Johnny: CIS 1.1.1.11 overlay kernel module not available (Batch 4). Delete this file if an on-box container runtime is added.
blacklist overlay
install overlay /bin/false
EOF
sudo chown root:root /etc/modprobe.d/johnny-cis-fs-overlay.conf
sudo chmod 0644 /etc/modprobe.d/johnny-cis-fs-overlay.conf
```
After A2/A2b, the CIS script will still list the keep set as loadable. That is the manual part: Governance judges 1.1.1.11 PASS (manual) if AJ accepts the keep set, or FAIL (manual) with the reason. A module blocked here but needed later is unblocked by deleting its line or the file; no rebuild is needed.

### A3. Verification (read-only, no sudo)
```
for m in cramfs freevxfs hfs hfsplus jffs2 firewire-core usb-storage atm can rds sctp tipc; do printf '%s %s\n' "$m" "$(modprobe -n -v "$m" 2>&1 | grep -c '^install /bin/false')"; done
modprobe --showconfig | grep -E '^(blacklist|install) (cramfs|freevxfs|hfs|hfsplus|jffs2|firewire_core|usb_storage|atm|can|rds|sctp|tipc)( |$)' | sort | wc -l
lsmod | awk '$1 ~ /^(cramfs|freevxfs|hfs|hfsplus|jffs2|firewire_core|usb_storage|atm|can|rds|sctp|tipc)$/'
lsmod | awk '$1=="xfs"||$1=="autofs4"{print $1}'
for m in nf_tables nft_compat nft_ct nft_limit nft_log nft_reject_inet nf_conntrack nf_nat nf_log_syslog nf_reject_ipv4 nf_reject_ipv6 nf_conntrack_ftp nf_nat_ftp nf_conntrack_netbios_ns ip_tables ip6_tables iptable_filter ip6table_filter xt_conntrack xt_tcpudp xt_multiport xt_limit xt_LOG xt_addrtype xt_comment xt_hl ipt_REJECT ip6t_REJECT; do modprobe -n -v "$m" 2>&1; done | grep -E '/bin/false|/(atm|can|rds|sctp|tipc|usb-storage|firewire-core|cramfs|freevxfs|hfs|hfsplus|jffs2)\.ko' || echo UFW-MODULES-CLEAR
modprobe -n -v can_raw 2>&1 | head -3
modprobe -n -v uas 2>&1 | head -3
systemctl --failed --no-pager --plain | tail -1
```
Expected:
- Line 1: twelve lines, each the module name then `1`. Count `^install /bin/false` over the full `modprobe -n -v` output. Do not use `head -1`. For a module with dependencies, kmod prints those dependency `insmod` lines before the module's own `install /bin/false`, so the first line can be `insmod` on a correct block. A count other than `1` is a stop. A real `modprobe` of `firewire-core`, `sctp`, or `tipc` loads `crc_itu_t`, `udp_tunnel`, and `ip6_udp_tunnel` first. Those dependencies are harmless. The target module is not inserted.
- Line 2: `24` (12 blacklist plus 12 install). Lines 3 and 4: nothing, then `xfs` and `autofs4`.
- ufw line: `UFW-MODULES-CLEAR`. Not a stop if some names print `FATAL: Module ... not found` (they are not in the filter's output). A hit means a ufw module depends on a blocked one: **stop, remove that pair, tell the Brain.**
- `can_raw` and `uas` lines (Assurance F2, from kmod source: a blocked parent's `install /bin/false` also refuses its dependents): the correct dry-run output is two lines each, first `install /bin/false` (for the parent), then `insmod .../can_raw.ko.zst` (or the `uas` file). That **is** the blocked case; the real load stops at the first line. **[Assumption]** Ubuntu's kmod 34.2 matches the source read. If `install /bin/false` does not appear first, record it and tell the Brain.
- With A2: `awk '/^install /{print $2}' /etc/modprobe.d/johnny-cis-fs-unused.conf | while read m; do modprobe -n -v "$m" 2>&1 | grep -c '^install /bin/false'; done | sort | uniq -c` prints `60 1`. Same rule as line 1: count the full dry-run, not `head -1`. Run it as shown (read-only).
- Then Governance's re-audit with the local scripts (verdict). Initrd unchanged: `ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic` still `42618411` and `2026-11-03 06:13:32`.

### A4. Rollback
```
sudo rm /etc/modprobe.d/johnny-cis-fs.conf /etc/modprobe.d/johnny-cis-drivers.conf /etc/modprobe.d/johnny-cis-net.conf
sudo rm -f /etc/modprobe.d/johnny-cis-fs-unused.conf /etc/modprobe.d/johnny-cis-fs-overlay.conf
modprobe -n -v can 2>&1 | grep -c '^install /bin/false'
```
Expected: the count is `0` (no `install /bin/false` left for `can`). No reboot, no rebuild: nothing was loaded and the initrd was not changed.

---

## Group B: kernel parameters, core dumps and apport (1.5.4, 1.5.5, 1.5.9, 1.5.10, 1.5.7)

| Rule | CIS title (CSV) | Current (CSV) | Change |
|---|---|---|---|
| 1.5.4 | "Ensure fs.suid_dumpable is configured" | running **2**, in no sysctl file | `fs.suid_dumpable = 0` in `60-johnny-cis-kernel.conf` **and** apport stopped (it sets 2) |
| 1.5.5 | "Ensure kernel.dmesg_restrict is configured" | running 1 (correct), in no file | `kernel.dmesg_restrict = 1` |
| 1.5.9 | "Ensure kernel.randomize_va_space is configured" | running 2 (correct), in no file | `kernel.randomize_va_space = 2` |
| 1.5.10 | "Ensure core file size is configured" | `limits.d/10-coredump-debian.conf`: `* hard core infinity`; no `* hard core 0` | new `limits.d/60-johnny-cis-core.conf`: `* hard core 0` |
| 1.5.7 | "Ensure Automatic Error Reporting is configured" | apport installed; `enabled=1`; `apport.service` active | `enabled=0` plus mask and stop `apport.service` (Q7) |

**Why 1.5.4 and 1.5.7 are one job.** On 26.04 `apport.service` is shipped by `apport-core-dump-handler` (not by `apport`) and is a oneshot with `ExecStart=/usr/share/apport/apport --start`. That function writes `kernel.core_pattern` to the apport pipe, **`fs.suid_dumpable` to 2** and `kernel.core_pipe_limit` to 10; `--stop` writes `core_pipe_limit` 0, `suid_dumpable` 0 and `core_pattern` `core`. Sources: https://packages.ubuntu.com/resolute/all/apport-core-dump-handler/filelist, https://git.launchpad.net/ubuntu/+source/apport/plain/data/systemd/apport.service?h=applied/ubuntu/resolute, and `start_apport` / `stop_apport` in https://git.launchpad.net/ubuntu/+source/apport/plain/data/apport?h=applied/ubuntu/resolute (apport 2.34.0-0ubuntu2, **[Assumption]** Johnny's unit matches; P3 reads it). `apport.service` starts after `systemd-sysctl`, so a sysctl file alone would show 0 until the next boot and then be overwritten with 2. That is why the running value is 2 today with no file setting it. The `enabled=` line in `/etc/default/apport` is read by apport's own helper scripts (`/usr/share/apport/is-enabled`), not by `--start`, so `enabled=0` alone leaves the unit active and `suid_dumpable` at 2; **the unit must be stopped and masked.**
After the change `kernel.core_pattern` is the kernel default `core` and nothing writes a core unless a process raises its own limit: `* hard core 0` caps login sessions, and systemd services start with a soft core limit of 0. Not done (not CIS): pointing `core_pattern` at `|/bin/false`.

### B0. Pre-check
P3 and P4 already ran. Re-run P3 lines 1 to 6 right before B1 (stop on a difference).

### B1. Apport off (AJ, sudo)
Run `sudo -v` on its own line first (enter the password), then paste the block (Assurance F7).
```
sudo cp -a /etc/default/apport /root/apport.default.pre-batch4
sudo sed -i 's/^enabled=1$/enabled=0/' /etc/default/apport
sudo systemctl mask --now apport.service
```
Expected: `Created symlink '/etc/systemd/system/apport.service' → '/dev/null'.` (wording may differ slightly). `sed` prints nothing. The `--now` runs `ExecStop`, so `suid_dumpable` becomes 0 and `core_pattern` becomes `core` at once. `/etc/default/apport` becomes a locally modified conffile (residual below).

### B2. Kernel parameters file (AJ, sudo)
Run `sudo -v` on its own line first (enter the password), then paste the block (Assurance F7).
```
sudo tee /etc/sysctl.d/60-johnny-cis-kernel.conf <<'EOF'
# Johnny: CIS 1.5.4, 1.5.5, 1.5.9 kernel parameters (Batch 4)
fs.suid_dumpable = 0
kernel.dmesg_restrict = 1
kernel.randomize_va_space = 2
EOF
sudo chown root:root /etc/sysctl.d/60-johnny-cis-kernel.conf
sudo chmod 0644 /etc/sysctl.d/60-johnny-cis-kernel.conf
sudo systemctl restart systemd-sysctl.service
systemctl is-failed systemd-sysctl.service
```
The `60-` name sorts after every vendor file (`50-default`, `55-*`); sysctl.d(5): "the entry in the file with the lexicographically latest name will take precedence" and files in `/etc` are the administrator's (https://manpages.ubuntu.com/manpages/resolute/en/man5/sysctl.d.5.html). `systemd-sysctl.service` is a oneshot; `is-failed` prints `inactive` (exit 1) when healthy, the same reading as Batch 3 B5.

### B3. Core limit (AJ, sudo)
Run `sudo -v` on its own line first (enter the password), then paste the block (Assurance F7).
```
sudo tee /etc/security/limits.d/60-johnny-cis-core.conf <<'EOF'
# Johnny: CIS 1.5.10 core file size (Batch 4). Sorts after the vendor 10-coredump-debian.conf.
* hard core 0
EOF
sudo chown root:root /etc/security/limits.d/60-johnny-cis-core.conf
sudo chmod 0644 /etc/security/limits.d/60-johnny-cis-core.conf
```
Why a new file and not an edit: `10-coredump-debian.conf` belongs to the `systemd` package, so editing it would put a conffile prompt on the `systemd` package, which unattended-upgrades would then skip (GR3). Why this ordering works: pam_limits reads `limits.conf` then `limits.d/*.conf` in glob order, and for two entries from the same kind of domain (`*`) "src_hard < source" is false, so the later line overwrites the earlier (`process_limit`, https://raw.githubusercontent.com/linux-pam/linux-pam/master/modules/pam_limits/pam_limits.c, master; **[Assumption]** Ubuntu's build matches; B4 proves it with a new login).

### B4. Verification
No sudo:
```
sysctl fs.suid_dumpable kernel.dmesg_restrict kernel.randomize_va_space kernel.core_pattern kernel.core_pipe_limit
systemctl is-active apport.service
systemctl is-enabled apport.service
grep -n '^enabled' /etc/default/apport
grep -Psi -- '^\h*enabled\h*=\h*[^0]\b' /etc/default/apport
grep -Ps -- '^\h*\*\h+hard\h+core\h+0\b' /etc/security/limits.conf /etc/security/limits.d/*
/usr/lib/systemd/systemd-sysctl --tldr | grep -E '^# /|suid_dumpable|dmesg_restrict|randomize_va_space'
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic
```
AJ, sudo:
```
sudo dpkg --verify apport apport-core-dump-handler
sudo sha256sum -c ~/cis-audit/initrd-sha256-pre-batch4.txt
```
Then **open a new SSH session** (existing ones keep the old limit) and run `ulimit -Hc; ulimit -Sc`.
Expected:
- Line 1: `fs.suid_dumpable = 0`, `kernel.dmesg_restrict = 1`, `kernel.randomize_va_space = 2`, `kernel.core_pattern = core`, `kernel.core_pipe_limit = 0`.
- Lines 2 and 3: `inactive` and `masked`. Line 4: `enabled=0`. Line 5: nothing (that is the CIS-style audit for `enabled` not being non-zero; **[Assumption]** CIS 26.04's exact pattern, the local script is the verdict).
- Line 6: `/etc/security/limits.d/60-johnny-cis-core.conf:* hard core 0`.
- Line 7: `60-johnny-cis-kernel.conf` appears after `55-*` with the three keys and nothing later overrides them. Line 8: unchanged (`42618411`).
- `dpkg --verify`: exactly `??5?????? c /etc/default/apport` (the intended conffile edit). `sha256sum -c`: `/boot/initrd.img-7.0.0-42-generic: OK`.
- New session: `0` then `0`. If the hard limit is still `unlimited`, pam_limits did not take the later file: stop, do not continue to Group D; the fallback is B6.

### B5. Rollback
```
sudo rm /etc/sysctl.d/60-johnny-cis-kernel.conf
sudo rm /etc/security/limits.d/60-johnny-cis-core.conf
sudo systemctl unmask apport.service
sudo cp -a /root/apport.default.pre-batch4 /etc/default/apport
sudo systemctl start apport.service
sudo dpkg --verify apport apport-core-dump-handler
sysctl fs.suid_dumpable kernel.core_pattern
```
Expected: `dpkg --verify` prints nothing (conffile back to the package copy); `suid_dumpable = 2` and `core_pattern` back to the apport pipe (the unit's `--start` sets them again). The three dropped sysctl lines are not set by any file after this, as before.

### B6. Option B (purge apport) and the 1.5.10 fallback (only if chosen or needed)
- **Q7 = B:** first `apt-cache rdepends --installed apport apport-core-dump-handler` and `apt-get -s purge apport apport-core-dump-handler`; read every line (the Batch 2 lesson: no `--autoremove`, and expect no package outside the apport family). **[Assumption]** nothing important depends on them; the simulation is the evidence, so stop if it removes anything else. Then purge, `systemctl is-active apport.service` prints `inactive`, and `fs.suid_dumpable` still needs B2. Rollback: `sudo apt-get install apport apport-core-dump-handler`, which re-enables the unit. SBOM gets two "Removed" entries.
- **Q9 fallback:** `sudo dpkg-divert --local --rename --add /etc/security/limits.d/10-coredump-debian.conf` moves the vendor file aside without a conffile prompt (undo: `sudo dpkg-divert --local --rename --remove /etc/security/limits.d/10-coredump-debian.conf`). Not run unless Governance says the vendor line still fails 1.5.10.

### Residual (conffile; same class as Batch 1 and 3, AJ to accept)
`/etc/default/apport` is now a modified conffile of `apport`. If a later apport update ships a changed copy, unattended-upgrades skips the package and logs `has conffile prompt` (GR3 shows it). The mask is a file under `/etc/systemd/system`, not a package file, so it has no such risk. An apport upgrade does not unmask a masked unit.

---

## Group C: IPv4 network parameters (3.3.1.x)

| Rule | CIS title (CSV) | Current (CSV) | Line |
|---|---|---|---|
| 3.3.1.1 | "Ensure net.ipv4.ip_forward is configured" | running 0, in no file | `net.ipv4.ip_forward = 0` |
| 3.3.1.2, .3 | "… conf.all / conf.default.forwarding …" | running 0, in no file | `net.ipv4.conf.all.forwarding = 0`, `...default.forwarding = 0` |
| 3.3.1.4, .5 | "… all / default.send_redirects …" | running **1** | `= 0` both |
| 3.3.1.8, .9 | "… all / default.accept_redirects …" | running **1**; 0 only in `/etc/ufw/sysctl.conf` (inert) | `= 0` both |
| 3.3.1.10, .11 | "… all / default.secure_redirects …" | running **1** | `= 0` both |
| 3.3.1.12, .13 | "… all / default.rp_filter …" | running **2** (`55-network-security.conf`, `50-default.conf`) | **deferred (Q5)**: `= 1` both, commented out |
| 3.3.1.14 | "… all.accept_source_route …" | running 0, in no file | `= 0` |
| 3.3.1.18 | "Ensure net.ipv4.tcp_syncookies is configured" | running 1, in no file | `= 1` |
| 3.3.1.19 | "… all.route_localnet …" | running 0, in no file | `= 0` |
| 3.3.1.6, .7, .15 (pass today) | bogus-error, echo-broadcasts, default.accept_source_route | pass via `/etc/ufw/sysctl.conf` / `50-default.conf` | pinned (Q8) |

Target values are CIS's standard values for these parameters **[Assumption]** (no PDF here); the CSV verdicts agree: "correct" at 0, 0, 0, 0, 1, 0 for .1, .2, .3, .14, .18, .19 and "wrong" at 1 for the redirect keys and at 2 for `rp_filter`.

### C0. Pre-check
P1 line 7 and P2 ran (no active `/etc/sysctl.conf` line; values as listed; ufw `ENABLED=no`). Re-run P2 line 2 and the `grep ^ENABLED` right before C1.
Capture snapshot first (Detection reads it; no sudo):
```
ip -s link show eno1np0
nstat -az IPReversePathFilter
```
Expected: `eno1np0` is `UP` with RX counters rising from mirrored traffic; `IPReversePathFilter` is a counter (0 or small). **[Assumption]** `IPReversePathFilter` is the `TcpExt` counter for `rp_filter` drops (kernel `proc.c`); if `nstat` is missing or names it differently, skip that line, it is only for the Q5 apply-now option.

### C1. Apply (AJ, sudo)
Run `sudo -v` on its own line first (enter the password), then paste the block (Assurance F7).
```
sudo tee /etc/sysctl.d/60-johnny-cis-network.conf <<'EOF'
# Johnny: CIS 3.3.1 IPv4 network parameters (Batch 4). Sorts after the vendor /usr/lib/sysctl.d/55-network-security.conf.
# Keep ip_forward first: changing it resets other values (kernel ip-sysctl). It stays 0, so nothing resets.
net.ipv4.ip_forward = 0
net.ipv4.conf.all.forwarding = 0
net.ipv4.conf.default.forwarding = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
# 3.3.1.12 and 3.3.1.13 rp_filter: deferred to Batch 6 (Q5). Uncomment both to apply strict mode.
#net.ipv4.conf.all.rp_filter = 1
#net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.route_localnet = 0
EOF
sudo chown root:root /etc/sysctl.d/60-johnny-cis-network.conf
sudo chmod 0644 /etc/sysctl.d/60-johnny-cis-network.conf
sudo systemctl restart systemd-sysctl.service
systemctl is-failed systemd-sysctl.service
```
(Q8 = no: delete the `icmp_ignore_bogus`, `icmp_echo_ignore_broadcasts` and `default.accept_source_route` lines. Q6 = defer: delete the five forwarding and `send_redirects` lines. Q5 = apply now: remove the two `#` before running.) `restart` re-applies every sysctl file and does not touch interfaces.

### C2. Verification (read-only, no sudo)
```
sysctl net.ipv4.ip_forward net.ipv4.conf.all.forwarding net.ipv4.conf.default.forwarding net.ipv4.conf.all.send_redirects net.ipv4.conf.default.send_redirects net.ipv4.icmp_ignore_bogus_error_responses net.ipv4.icmp_echo_ignore_broadcasts net.ipv4.conf.all.accept_redirects net.ipv4.conf.default.accept_redirects net.ipv4.conf.all.secure_redirects net.ipv4.conf.default.secure_redirects net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter net.ipv4.conf.all.accept_source_route net.ipv4.conf.default.accept_source_route net.ipv4.conf.all.log_martians net.ipv4.conf.default.log_martians net.ipv4.tcp_syncookies net.ipv4.conf.all.route_localnet
/usr/lib/systemd/systemd-sysctl --tldr | grep -E '^# /|rp_filter|accept_source_route|redirects|forwarding|ip_forward|syncookies|route_localnet|icmp_|log_martians'
systemctl is-failed systemd-sysctl.service
ip -s link show eno1np0
nstat -az IPReversePathFilter
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic
```
Expected: `ip_forward`, both `forwarding`, `send_redirects` (both), `accept_redirects` (both), `secure_redirects` (both), `accept_source_route` (both), `route_localnet` = 0; `icmp_*` and `tcp_syncookies` = 1; `rp_filter` still 2 and 2 (deferred) or 1 and 1 (if applied); **`log_martians` still 0 and 0 (this batch must not change it)**. In the `--tldr` listing, the last occurrence of every key except `rp_filter` and `log_martians` is under `/etc/sysctl.d/60-johnny-cis-network.conf`; the `rp_filter` last occurrence is `55-network-security.conf` (deferred). `is-failed` prints `inactive`. `eno1np0` still UP and its RX counter still rising; `IPReversePathFilter` unchanged. Initrd unchanged.
- Writing `default` also updates existing interfaces that were never set by name; `all` is combined with the interface (OR for the redirect keys on a non-forwarding host, `max` for `rp_filter`). CIS audits `all` and `default`; Group D prints the per-interface values as information (Assurance F3).
- Governance re-audits 3.3.1.x with `cis-3-audit.sh`; the verdict is theirs.

### C3. Rollback
```
sudo rm /etc/sysctl.d/60-johnny-cis-network.conf
sudo sysctl -w net.ipv4.conf.all.send_redirects=1 net.ipv4.conf.default.send_redirects=1 net.ipv4.conf.all.accept_redirects=1 net.ipv4.conf.default.accept_redirects=1 net.ipv4.conf.all.secure_redirects=1 net.ipv4.conf.default.secure_redirects=1
sysctl net.ipv4.conf.all.send_redirects net.ipv4.conf.all.accept_redirects net.ipv4.conf.all.secure_redirects
```
Expected: three lines `= 1` (the pre-batch runtime values). Deleting the file alone leaves the runtime at 0 until reboot. If rp_filter was applied, add `net.ipv4.conf.all.rp_filter=2 net.ipv4.conf.default.rp_filter=2` to the `sysctl -w` line.

---

## Group D: attended reboot proof (Q1; recommended)
Do not start Group D until B4's new SSH session has printed `0` for `ulimit -Hc` and `0` for `ulimit -Sc`. An existing session keeps the old limit. If the hard limit is still `unlimited`, stop. The fallback is B6.

Why: the fix is only proven if the values survive a boot. In particular `fs.suid_dumpable` must stay 0 with apport masked, the per-interface sysctl values come from `default` at boot, and TPM unlock must still work. Nothing here changes the boot chain; the initrd is the same file (hash check). **Prerequisites (same as Batch 2 Q5-A):** A, B and C verified; AMT KVM session open (the **Johnny KVM** icon on rock-box, handoff step 5); LUKS recovery passphrase at hand; a second SSH session. No `/run/reboot-required` surprise: run `cat /run/reboot-required` first (expect "No such file").

### D0. Kernel pin gate (read-only; run right before D1; Assurance F1)
```
ls /boot/vmlinuz-* /boot/initrd.img-*
dpkg -l 'linux-image-*' | awk '/^ii/{print $2,$3}'
systemctl is-active apt-daily-upgrade.service unattended-upgrades.service
ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic
cat /run/reboot-required
```
Expected: only the `7.0.0-42-generic` kernel and initrd (plus the `.pre-batch4` initrd copy); one `ii` line, `linux-image-7.0.0-42-generic`; `inactive` twice; initrd size `42618411` and mtime `2026-11-03 06:13:32` (as in P4); `cat: /run/reboot-required: No such file or directory`. If a second kernel appears, either service is `active`, or the initrd size or time differs, **stop**: a security update landed, so the reboot would first-boot an unproven kernel with no fallback kernel. Tell the Brain; re-run P4 to re-baseline, or reboot only when nothing else changed.

### D1. Reboot (AJ; only after D0 passes)
```
sudo systemctl reboot
```
Watch the KVM. **Expected:** no LUKS passphrase prompt (TPM2 unlock), then the login prompt. A passphrase prompt means TPM unlock failed: enter the recovery passphrase, finish booting, tell the Brain (PCR 7 should not have moved: nothing here changes Secure Boot, the shim or the BIOS; find out why before anything else). A drop to the dracut emergency shell means the image is bad (not expected, it is unchanged): tell the Brain, then use the `.pre-batch4` copy by the Batch 2 GRUB edit.

### D2. After login (read-only; from the laptop or rock-box)
```
ssh aj@192.168.50.152 'uname -r; uptime -p; systemctl --failed --no-pager --plain | tail -1; dpkg --audit; echo rc=$?; cat /run/reboot-required; systemctl is-enabled apport.service; sysctl fs.suid_dumpable kernel.core_pattern kernel.dmesg_restrict kernel.randomize_va_space net.ipv4.conf.all.send_redirects net.ipv4.conf.default.accept_redirects net.ipv4.conf.all.rp_filter; ulimit -Hc'
ssh aj@192.168.50.152 'lsmod | awk "\$1==\"xfs\"||\$1==\"autofs4\"{print \$1}"; modprobe -n -v can 2>&1 | grep -c "^install /bin/false"; ls -l --time-style=full-iso /boot/initrd.img-7.0.0-42-generic'
ssh aj@192.168.50.152 'journalctl -b --no-pager | grep -E "Error running install command"; ip -s link show eno1np0 | head -4; kdump-config status 2>&1 | head -2'
```
Expected:
- `7.0.0-42-generic`; a short uptime; `0 loaded units listed.`; `rc=0`; `cat: /run/reboot-required: No such file or directory`; `masked`; `fs.suid_dumpable = 0`; `kernel.core_pattern = core`; `dmesg_restrict = 1`; `randomize_va_space = 2`; `send_redirects = 0`; `default.accept_redirects = 0`; `all.rp_filter = 2` (deferred) or 1; `ulimit -Hc` `0`.
- `xfs` and `autofs4`; the `can` count is `1`; the initrd line identical to P4 (`42618411`, `2026-11-03 06:13:32`).
- The journal grep prints nothing (no blocked module was tried at boot); `eno1np0` UP with a rising counter; `kdump-config status` informational (**[Assumption]** it reports ready as before; the kdump crash-kernel initrd is not examined or touched by this batch).
- AJ, sudo: `sudo sha256sum -c ~/cis-audit/initrd-sha256-pre-batch4.txt` prints `OK`, and `sudo lsinitrd -m /boot/initrd.img-7.0.0-42-generic | sed -n '/^dracut modules:/,/^=====/p' | diff ~/cis-audit/initrd-mods-pre-batch4.txt -` prints nothing.
- Information only: `ssh aj@192.168.50.152 'sysctl -a 2>/dev/null | grep -E "^net\.ipv4\.conf\.(eno3|eno1np0|eno4)\.(send_redirects|accept_redirects|secure_redirects|rp_filter) "'`. Expect 0 on every NIC for the three redirect keys (the `default` write reached them at C1); a surviving 1 means something wrote that interface by name: tell the Brain. `rp_filter` per NIC is information for Batch 6.

### D3. Cleanup (after D2 passes; or at AJ's word)
```
sudo rm /boot/initrd.img-7.0.0-42-generic.pre-batch4
ls -l /boot/initrd.img-7.0.0-42-generic.pre-batch4
```
Expected: `No such file or directory`. Keep `~/cis-audit/*-pre-batch4.txt` and `/root/apport.default.pre-batch4` until Governance's re-audit passes.

### Group R. Rebuild the initrd (Q1 = c; not recommended)
Only if AJ wants the new blocks inside the image. P4's `grep -c` result decides whether it would even change anything (`0` means a generic image: no change at all). Commands: `sudo update-initramfs -u`, then the P4 `lsinitrd -m ... | sed ... | diff ~/cis-audit/initrd-mods-pre-batch4.txt -` (must print nothing) and the `grep -E '^(crypt|systemd-cryptsetup|tpm2-tss)$'` (identical to P4). **Any diff or an error: stop, do not reboot, restore with `sudo cp -a /boot/initrd.img-7.0.0-42-generic.pre-batch4 /boot/initrd.img-7.0.0-42-generic`.** Group D then becomes mandatory, not optional.

---

## Files to mirror under `etc/` (create after the apply; real paths; same commit as the handoff Config changes rows)
The three A1 files are mirrored in this rev. Their sha256 matches Johnny (see Recorded output). The rest are not created yet. Contents of the applied files are the heredocs above.
- `etc/modprobe.d/johnny-cis-fs.conf`, `etc/modprobe.d/johnny-cis-drivers.conf`, `etc/modprobe.d/johnny-cis-net.conf` (mirrored)
- `etc/modprobe.d/johnny-cis-fs-unused.conf` and `etc/modprobe.d/johnny-cis-fs-overlay.conf` (only if A2 and A2b ran)
- `etc/sysctl.d/60-johnny-cis-kernel.conf`, `etc/sysctl.d/60-johnny-cis-network.conf` (as applied, with the `rp_filter` lines commented or not)
- `etc/security/limits.d/60-johnny-cis-core.conf`
- `etc/default/apport` (the whole modified conffile, `enabled=0`)
- `etc/systemd/system/apport.service` as a symlink to `/dev/null` (like the masked sleep targets already in `etc/systemd/system/`)

Hash line for the Brain's Config changes rows (read-only, no sudo; the symlink target first):
```
readlink /etc/systemd/system/apport.service
sha256sum /etc/modprobe.d/johnny-cis-*.conf /etc/sysctl.d/60-johnny-cis-*.conf /etc/security/limits.d/60-johnny-cis-core.conf /etc/default/apport
```

## SBOM and Config changes (for the handoff)
- **SBOM:** no package change in the recommended path (Q7 = A). Q7 = B adds a "Removed" entry for `apport` and `apport-core-dump-handler` (versions from P3's `dpkg-query`). No held package, no kernel change.
- **Config changes table rows to add (rollback pointers):** the three or five `/etc/modprobe.d/johnny-cis-*.conf` files (A4); `/etc/sysctl.d/60-johnny-cis-kernel.conf` and `60-johnny-cis-network.conf` (B5, C3); `/etc/security/limits.d/60-johnny-cis-core.conf` (B5); `/etc/default/apport` modified conffile, `enabled=0`, copy `/root/apport.default.pre-batch4` (B5); `/etc/systemd/system/apport.service` mask (B5). The Batch 2 rows are unchanged.
- **Recurring checks (add to GR list):** after any `apt install` or upgrade, `systemctl is-enabled apport.service` (expect `masked`) and `sysctl fs.suid_dumpable` (expect 0); GR3 for an apport conffile prompt; `ls /etc/modprobe.d/johnny-cis-*.conf` still present. After any kernel or dracut update, repeat the P4 `lsinitrd` comparison before the next reboot (a rebuild may bake the new modprobe.d files in; harmless, but verify).

## Handoffs (for the Brain to route)
- **Governance:** re-audit 1.1.1.1 to .5, .9, .10, .11, 3.2.1, .2, .4 to .6, 3.3.1.1 to .5, .8 to .11, .14, .18, .19 (and .12 and .13 if Q5 = apply), 1.5.4, 1.5.5, 1.5.7, 1.5.9, 1.5.10, with the local scripts; judge 1.1.1.11 against AJ's keep set; confirm the 1.5.10 verdict with the vendor `infinity` line present (Q9). Note for 3.2.7: the three `johnny-cis-*` files are the start of the site list.
- **Detection:** read C0 and C2's `eno1np0` snapshot (and the `IPReversePathFilter` counter if rp_filter is applied); confirm capture is unchanged. If Q5 is deferred, repeat the check once after Batch 6's `ufw enable`.
- **Assurance:** review this draft before AJ runs anything (Groups P4, A, B, C, D). The points that need a second reader are the apport mechanism (B), the pam_limits ordering (B3), and the "no rebuild needed" reading of dracut (Boot-path facts).

## Assumptions (marked above; collected)
1. All live state is from the CSV (2026-10-30 and 10-31) and the repo docs; nothing was read from Johnny. Batches 1 to 3 ran in between; P1 to P4 re-read it.
2. The CIS PDF and `docs/cis-local/` are absent here; target values and audit patterns follow the CSV evidence and CIS's usual parameter values; Governance's local scripts decide.
3. Johnny's apport unit and `/usr/share/apport/apport` match the resolute source read (2.34.0-0ubuntu2); P3 prints the unit.
4. Ubuntu's `dracut 110-11ubuntu0.1` behaves like upstream tag 110 for `/etc/modprobe.d` (hostonly only) and `=fs`; P4 prints what Johnny's image actually holds.
5. pam_limits in Ubuntu's build lets a later `limits.d` file override an earlier one for `*`; B4's new-login test proves it.
6. kmod does or does not apply a parent's `install /bin/false` to dependents: unknown, observed in A3.
7. `/etc/ufw/sysctl.conf` on Johnny is Ubuntu's stock file; P2 prints it.
8. Kernel 7.0.0-42 receive-path behavior matches current `master` (`ip_rcv_core`, `ptype_all`); `IPReversePathFilter` is the rp_filter drop counter.
9. `nls_iso8859-1` and `nls_utf8` may be loaded for the FAT `/boot/efi` mount, so all `nls_*` stay; `autofs4` is used by systemd's `binfmt_misc` automount.
10. Johnny has no FireWire hardware and no planned use of USB mass storage, SCTP, CAN, ATM, RDS or TIPC.

## Ubuntu 26.04 (resolute) and kernel sources checked 2026-11-04
- apport files: https://packages.ubuntu.com/resolute/amd64/apport/filelist (no `apport.service`), https://packages.ubuntu.com/resolute/all/apport-core-dump-handler/filelist (`apport.service`, `/etc/init.d/apport`); package page https://packages.ubuntu.com/resolute/apport (2.34.0-0ubuntu2).
- apport unit and behavior: https://git.launchpad.net/ubuntu/+source/apport/plain/data/systemd/apport.service?h=applied/ubuntu/resolute, https://git.launchpad.net/ubuntu/+source/apport/plain/data/apport?h=applied/ubuntu/resolute (`start_apport`, `stop_apport`), https://git.launchpad.net/ubuntu/+source/apport/plain/data/is-enabled?h=applied/ubuntu/resolute.
- systemd limits file owner: https://packages.ubuntu.com/search?suite=resolute&arch=any&searchon=contents&keywords=etc%2Fsecurity%2Flimits.d%2F10-coredump-debian.conf (package `systemd`). pam_limits: https://raw.githubusercontent.com/linux-pam/linux-pam/master/modules/pam_limits/pam_limits.c and https://manpages.ubuntu.com/manpages/resolute/en/man5/limits.conf.5.html.
- sysctl: https://manpages.ubuntu.com/manpages/resolute/en/man5/sysctl.d.5.html, https://manpages.ubuntu.com/manpages/resolute/en/man8/systemd-sysctl.service.8.html (`--cat-config`, `--tldr`), https://manpages.ubuntu.com/manpages/resolute/en/man5/sysctl.conf.5.html (systemd-sysctl does not use `/etc/sysctl.conf`). `55-network-security.conf` (procps, `rp_filter` 2): https://git.launchpad.net/ubuntu/+source/procps/plain/debian/sysctl.d/55-network-security.conf?h=applied/ubuntu/resolute. `50-default.conf` belongs to `linux-sysctl-defaults` (https://packages.ubuntu.com/resolute/all/linux-sysctl-defaults/filelist); its text was not fetched, Johnny's copy comes from P2.
- ufw: https://git.launchpad.net/ubuntu/+source/ufw/plain/conf/sysctl.conf?h=applied/ubuntu/resolute, https://git.launchpad.net/ubuntu/+source/ufw/plain/src/ufw-init-functions?h=applied/ubuntu/resolute, https://git.launchpad.net/ubuntu/+source/ufw/plain/src/ufw-init?h=applied/ubuntu/resolute.
- dracut: https://packages.ubuntu.com/resolute/amd64/dracut/filelist, https://git.launchpad.net/ubuntu/+source/dracut/plain/debian/dracut.triggers?h=applied/ubuntu/resolute, upstream tag 110 `modules.d/80base/module-setup.sh` and `modules.d/70kernel-modules/module-setup.sh` (URLs in Boot-path facts).
- Kernel modules of 7.0.0-42: https://packages.ubuntu.com/resolute-updates/amd64/linux-modules-7.0.0-42-generic/filelist (atm, can, rds, sctp, tipc under `kernel/net`; firewire-core and usb-storage under `kernel/drivers`; no dccp). modprobe.d(5): https://manpages.ubuntu.com/manpages/resolute/en/man5/modprobe.d.5.html.
- Kernel behavior: https://docs.kernel.org/networking/ip-sysctl.html, https://raw.githubusercontent.com/torvalds/linux/master/net/ipv4/ip_input.c, https://raw.githubusercontent.com/torvalds/linux/master/net/core/dev.c.
