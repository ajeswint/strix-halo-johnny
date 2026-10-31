# Johnny — OS Handoff (rev 13, 2026-10-31 18:20 CT)

Supersedes rev 12 and the earlier handoffs in `docs/sessions/` (each bannered historical) for current state. Next-session brief: `docs/sessions/2026-10-31-cis-s6-handoff.md` (CIS section 6, 17 L1, fresh session). Rev 13: no change on Johnny. CIS section 5 audited by Governance (70 L1: 32 pass, 38 fail, 0 N/A); running 233/274 L1: 103 pass, 108 fail, 22 N/A (step 10). Grok reviewed each block. AJ: no `apt update` for 5.3.1.x (lists 20 h old). Site-policy values for the section 5 fix pass are open (step 10). Session log: `docs/sessions/Johnny_CIS_Session_Log_2026-10-31.csv`. Rev 12: no change on Johnny. CIS section 4 audited by Governance (4 L1: 1 pass, 3 fail, 0 N/A); running 163/274 L1: 71 pass, 70 fail, 22 N/A (step 10). AJ: ufw is the firewall method. Session log: `docs/sessions/Johnny_CIS_Session_Log_2026-10-31.csv`. Rev 11: no change on Johnny. CIS section 3 audited by Governance (37 L1: 6 pass, 31 fail, 0 N/A); running 159/274 L1: 70 pass, 67 fail, 22 N/A (step 10). AJ decisions: IPv6 not used (fix pass disables it); wireless not required; 3.2.7 FAIL (manual) until a site module list is drafted and approved. Session log: `docs/sessions/Johnny_CIS_Session_Log_2026-10-31.csv`. Rev 10: no change on Johnny. CIS section 2 audited by Governance (44 L1: 30 pass, 11 fail, 3 N/A); running 122/274 L1: 64 pass, 36 fail, 22 N/A (step 10). AJ decisions: Ubuntu NTS pools approved as the time source; 4 listeners approved; `ubuntu-standard` **not** approved (strict CIS: "we play by the rules for now and we will loosen if we need later"). Time sync is chrony, not timesyncd (Installed state). Session log: `docs/sessions/Johnny_CIS_Session_Log_2026-10-31.csv`. Rev 9: no change on Johnny. Agent team live: 9 agents in `.claude/agents/`, Brain = main session, `docs/agent-team.md` rev 5 (Grok confirmed). First skill: `.claude/skills/cis-audit/`. Reply format Detail → Relay (for Grok) → Outline (`AGENTS.md`). ableton_box recorded (`docs/hosts/ableton_box.md`, .211); 3 decisions parked (§ Parked). Session log: `docs/sessions/Johnny_AgentTeam_Session_Log_2026-10-31.csv`. Rev 8: no change on Johnny. Agent team proposed: `docs/agent-team.md` (Brain + Architect + 8 arms, 78 skills); Grok review brief `docs/sessions/2026-10-31-grok-handoff.md`. On-box SLM is in, full function for now (AJ); "No LLM on the box" removed from README and AGENTS.md. Session log: `docs/sessions/Johnny_AgentTeam_Session_Log_2026-10-31.csv`. Rev 7: step 10 method (c) chosen, CIS 26.04 1.0.0 Level 1 – Server; section 1 audited (78 rules: 34 pass, 25 fail, 19 N/A); fix gate added. Audit only, no change on Johnny. Session log: `docs/sessions/Johnny_CIS_Session_Log_2026-10-30.csv`. Rev 6: repo audit only, no change on Johnny. `etc/` now mirrors every file in Config changes (hashes match Johnny), incl. the masked sleep targets as links to `/dev/null`; session-log times corrected from commit times; step 10 compliance status corrected (26.04 has no USG/STIG profile; CIS 26.04 1.0.0 exists). Rev 5: L1-2 applied (SFP+7 mirror → `eno1np0`), router DHCP reservation .152. Network and switch ports: `docs/network-map.md`. Session logs: `docs/sessions/`. Prior records: `claude/L1 Handoff.md` (rev 5, location unknown: not on rock-box or in this repo), `claude/Johnny_L1_Session_Log_2026-10-28.csv`.

## Context
- Johnny = Minisforum MS-02 Ultra (Core Ultra 9 285HX, 1× 32GB DDR5 non-ECC, Crucial P310 1TB). Defensive network-security platform; AJ designs, Claude builds.
- Sequence: L1 lab → **2. OS (installed; boot/firmware/TPM/closet move/AMT done; AMT cabling + L1-2 mirror + DHCP reservation done; tools, capture config pending)** → 3. Overseer review → 4. Module 1 (eBPF fast-path).
- Location: closet, headless, unattended boot. PCR 7 at baseline.

## Rules
- Replies: Detail → Relay (for Grok) → Outline (`AGENTS.md`). One step at a time. Show commands before running. AJ runs anything needing sudo/credentials. Never echo or store passwords.
- Mark assumptions. Search before stating Ubuntu 26.04 specifics (package names, dracut behavior, kernel).
- Access: `ssh aj@192.168.50.152` from aj-rock-box or the laptop (aj-Thin-15-B13VE, over Wi-Fi) (key auth only). Read-only checks run by Claude over SSH; `aj` has no passwordless sudo.
- Switch: AJ manages the CRS309 from a laptop on ether1 only. Physical cabling is the truth; docs follow it.

## Installed state
| Item | Value |
|---|---|
| OS | Ubuntu Server 26.04.1 LTS (`resolute`), no third-party drivers. `ubuntu-server-minimal` removed with snapd (its 27 deps `apt-mark manual` first) |
| Kernel | 7.0.0-42-generic (only kernel; installer's unsigned 7.0.0-30 purged). Cmdline adds `pcie_aspm=off` (`/etc/default/grub.d/johnny.cfg`); kernel logs "PCIe ASPM is disabled" |
| Initramfs | dracut 110-11ubuntu0.1; rebuild with `sudo update-initramfs -u` (dracut's own wrapper, writes `/boot/initrd.img-<ver>`) |
| Hostname / user | `johnny` / `aj` |
| Mgmt NIC | `eno3` = RTL8127 (`r8169`, ab:00.0), `38:05:25:3a:a3:71`, DHCP **192.168.50.152**/24, reserved on the RT-BE88U (2026-10-30); sole wait-online link. CRS309 **SFP+2** |
| AMT NIC | `eno4` = I226-LM (`igc`, ac:00.0), `38:05:25:3a:a3:70`, no host addressing, `optional: true`. AMT 192.168.51.10/24 static. CRS309 **SFP+6** (isolated to SFP+4 / rock-box, verified); link up 1000 full (2026-10-30 01:06 UTC) |
| Capture NICs | `eno1np0` (…:ac:da), `eno2np1` (…:ac:db) = E810-XXV on riser in PCIe 4.0 x16 slot (bifurcated x4/x4/x4) → **Gen4 x4 by design**. No addresses (v4/v6/link-local), `optional: true`. Cage map (facing back): left = `eno1np0`, right = `eno2np1`. DACs: SFP+7 DAC → `eno1np0` (left), link 10000, **mirror target** (L1-2, 2026-10-30); SFP+8 DAC Johnny end **out**, switch port disabled. `eno2np1` down |
| Disk | CT1000P310SSD8: p1 ESP 1G `/boot/efi`; p2 2G ext4 `/boot`; p3 **LUKS2** (aes-xts-plain64, argon2id) → LVM `ubuntu-vg` → `ubuntu-lv` 460G XFS `/` |
| LUKS slots | 0 = passphrase (recovery, tested OK 2026-10-29); 1 = TPM2, PCR 7 |
| Secure Boot | Enabled; kernel lockdown active. PK = MINISFORUM PK. db = MS UEFI CA 2011 + **MS UEFI CA 2023** + **Option ROM UEFI CA 2023** + Windows UEFI CA 2023 + Windows PCA 2011 + MINISFORUM OWN CA. dbx 20260707 |
| PCR 7 baseline | `B6D0F97FA80D8614711B20726D7FB7B00D77D52F24C3C0251630F925BA07F3FF` (unchanged by BIOS admin password, RTL8127 enable, GRUB cmdline) |
| Boot | Unattended, 19.9 s total (2026-10-29, after RTL8127 enable) |
| SSH | OpenSSH; password auth OFF; 3× ed25519 from `gh:ajeswint`. Host key ED25519 `SHA256:8YASZyfuArzZSXjusI8OphopsKKm+ntmDuqbnT1v3OM` (laptop scan matched rock-box `known_hosts`, 2026-10-30) |
| Updates | `full-upgrade` done 2026-10-29 04:18 UTC. `unattended-upgrades` **security-only**, no auto reboot (`/etc/apt/apt.conf.d/52johnny-unattended-upgrades`). Holds: `shim-signed`, `secureboot-db` |
| Removed | `snapd` (purged + pinned -1, `/etc/apt/preferences.d/johnny-no-snapd`); `ModemManager` + 8 modem-related pkgs incl. tcl (`--autoremove`) |
| AMT | ME 19.0.5. **Activated, admin control mode (ACM).** TLS-only: 16993 + 16995 + 664 open; 16992/16994/623/5900 closed (from rock-box 2026-10-30; bench record had 16995 closed; 16995 = TLS redirection for KVM/SOL). KVM on, User Opt-in None, MEBx password changed. Self-signed Intel cert SHA-256 `8C:D6:65:E9:E5:0C:49:00:65:D3:D9:D3:13:5B:66:97:5C:E3:89:4F:F5:04:48:B0:75:BC:44:5C:47:35:3D:0A`. `rpc-go` v2.52.8 at `~/rpc/rpc` (sha256 verified, not system-wide) |
| Time | UTC, RTC local = no. **chrony** 4.8-2ubuntu1 enabled + active; sources = Ubuntu NTS pools (`/etc/chrony/sources.d/ubuntu-ntp-pools.sources`), approved by AJ 2026-10-31 (CIS 2.3.3.1). `systemd-timesyncd` not installed |

Secrets: LUKS passphrase (recovery; needed if PCR 7 changes), `aj` login password, BIOS admin password, MEBx password, AMT admin password. DMT Console (rock-box) admin password + `jwtKey`: rotate before reuse (`jwtKey` was exposed in a Claude transcript).

## BIOS (AMI 2.22.0059, Minisforum 1.04)
- 1.04 confirmed latest on Minisforum support (2026-10-29). fwupd/LVFS offers no BIOS/ME/E810/SSD firmware.
- Quiet Boot off: verified (POST text visible).
- Boot #1 = NVME: Ubuntu; only UEFI entry `Boot0000 Ubuntu` → shimx64.efi. No Disabled option for #2–#5.
- Advanced: **RTL8127 on**, I226 on, WIFI off, SSD1–4 on, J4301 x4 on, E810 slot on, x16 Slot Device 1 Disabled; ASPM/L1 off. No Thunderbolt toggle.
- ME 19.0.5.1992; AMT activated (ACM).
- **Admin password set**, user password blank. Not measured into PCR 7 (tested: reboot + power pull, TPM unlock both times).
- RAM 4800 MT/s = board max per Minisforum (closed).

## Closed issues
| # | Issue | Root cause | Fix |
|---|---|---|---|
| 1 | AER flood (~41 lines/s, buried LUKS prompt) | `thunderbolt` driver activating the TB5 NHI (84:00.0) → PTM Request TLPs with Requester ID 0000 (header `0x34000000 0x00000052`) → root port 80:1b.4 flags ACSViol (+UnsupReq). Proven: unload stops it, reload restarts it (417/15 s). Matches a known MS-02 Ultra report and Linux PTM/TB AER patch history. Not a bad chip (protocol-level, deterministic). | `/etc/modprobe.d/johnny-no-thunderbolt.conf` (`blacklist` + `install /bin/false`) and `omit_drivers+=" thunderbolt "` in dracut. 0 AER errors on 3 boots. |
| 2 | `systemd-networkd-wait-online` 120 s timeout | E810 entries in netplan required for online, no carrier | netplan: E810 `optional: true` + no addressing. netplan 1.2 generates a drop-in: wait-online `-i eno3` only |
| 3 | Stale UEFI entries | — | None present; nothing to do |
| 4 | initramfs ran networkd with catch-all `DHCP=yes` (all NICs, v4+v6) at LUKS prompt; `zzzz-dracut-default.network` persisted in `/run` | `cloud-initramfs-dyn-netconf` dracut module (no `check()`, always included) depends on `systemd-networkd` | Symlink Ubuntu's `no-network/10-no-network.conf` into `/etc/dracut.conf.d/`; `omit_dracutmodules+=" dyn-netconf "`. Package kept (`ubuntu-server` depends on it). initrd 64.0 → 36.9 MB |
| 5 | Auto-update could change PCR 7 unattended | `unattended-upgrades` allowed `resolute` + `resolute-security`; `shim-signed` / `secureboot-db` installed | Holds on both + security-only origins, no auto reboot |
| 6 | Port names moved when RTL8127 was enabled | Firmware onboard index: RTL8127 took `eno3`, I226 became `eno4` | Netplan matches by MAC; `eno3` = RTL8127 mgmt, `eno4` = I226 AMT-only |

## Config changes (all on Johnny)
| Path | Content / purpose | Rollback |
|---|---|---|
| `/etc/netplan/00-installer-config.yaml` | Match by MAC. `eno3` (RTL8127) DHCP. `eno4` (I226) and E810: `dhcp4/dhcp6: false`, `accept-ra: false`, `link-local: []`, `optional: true` | `/root/00-installer-config.yaml.orig` (installer original) |
| `/etc/default/grub.d/johnny.cfg` | `pcie_aspm=off` appended to `GRUB_CMDLINE_LINUX_DEFAULT` | delete, `sudo update-grub` |
| `/etc/apt/apt.conf.d/52johnny-unattended-upgrades` | security pockets only; `Automatic-Reboot "false"` | delete |
| `/etc/apt/preferences.d/johnny-no-snapd` | `snapd` Pin-Priority -1 | delete |
| apt holds | `shim-signed`, `secureboot-db` | `sudo apt-mark unhold shim-signed secureboot-db` |
| `/etc/modprobe.d/johnny-no-thunderbolt.conf` | blacklist + install /bin/false | delete, rebuild initramfs |
| `/etc/modprobe.d/johnny-no-bluetooth.conf` | btusb, bluetooth: blacklist + install /bin/false (BE200 BT on USB; BIOS WIFI-off doesn't kill it) | delete |
| `/etc/dracut.conf.d/johnny.conf` | `omit_drivers+=" thunderbolt "`, `omit_dracutmodules+=" dyn-netconf "`, `add_dracutmodules+=" tpm2-tss "` | edit, rebuild |
| `/etc/dracut.conf.d/10-no-network.conf` | symlink → `/usr/lib/dracut/dracut.conf.d/no-network/10-no-network.conf` | remove link, rebuild |
| `/etc/crypttab` | `dm_crypt-0 UUID=a6d02318-e79b-4a4c-bafa-0097695493db none luks,tpm2-device=auto` | `/root/crypttab.orig` |
| `/etc/systemd/system/{sleep,suspend,hibernate,hybrid-sleep,suspend-then-hibernate}.target` | masked → /dev/null | `systemctl unmask …` |
| LUKS slot 1 | TPM2, PCR 7 | `sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p3` |
| UEFI db / dbx | +MS UEFI CA 2023, +Option ROM CA 2023; dbx 20260707 (fwupd) | not reversible (additive/revocation) |
| BIOS | RTL8127 enabled; admin password set | BIOS setup |
| AMT | MEBx password, KVM on, opt-in none, static IP, activated ACM | not designed (untested) |

Switch changes (CRS309): `docs/network-map.md`.

## Known gaps and notes
- **PCR-7-only binding (option A, chosen).** `/boot` is plaintext and the initrd is unsigned/unmeasured in PCR 7: a physical attacker can edit the initrd (or boot MS-signed media via BBS menu) and get the key released. No GRUB password yet (CIS 1.4.1): editing the kernel cmdline at the GRUB menu (e.g. `init=`) doesn't touch PCR 7, so it's another unlock path (understanding, untested). Accepted for the lab. **Fleet: option D**: signed UKI + signed PCR 11 policy (26.04 support unverified; research before fleet autoinstall). Options B (PIN) and C (PCR 7+9, re-enroll every update) rejected.
- **PCR 7 changes** on any Secure Boot db/dbx/KEK/PK change, BIOS update, MOK change, shim re-signed by a different CA (2011 → 2023 expected), or shim raising `SbatLevel` → boot falls back to passphrase; re-enroll: `sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3`. Routine shim/GRUB/kernel updates signed by the same CA don't change PCR 7 (understanding, untested).
- **Held-package update procedure:** `apt-mark unhold` → install → console reboot (AMT KVM) → passphrase → re-enroll → `apt-mark hold`.
- **Remote console = AMT KVM** (chosen over PiKVM/JetKVM). Bench test (Intel DMT Console v1.47.0 alpha, rock-box): TLS connect OK, video OK with a display attached, **black with HDMI unplugged** (HDMI dummy ordered), keyboard OK. Power Off / Soft Reset / Ctrl+Alt+Del: "Device did not respond", AMT stayed reachable → likely Console alpha bug; retest with MeshCommander or `rpc-go`. Session indicator: flashing red/yellow border on the local screen (expected).
- **DMT Console (rock-box):** serves HTTPS on 8181 on **all interfaces**; v1.47 generates a random admin password in `dist/linux/config/config.yml`. `jwtKey` exposed in a Claude transcript: rotate it and the admin password before reuse. Stopped. DB `~/.config/device-management-toolkit/console.db` holds the device entry.
- **AMT port isolation is one-way** (frames entering SFP+6 may leave only via SFP+4). Two-way not applied; see `docs/network-map.md`.
- **`tpm2-tools` is a boot dependency**: dracut's `tpm2-tss` module requires `/usr/bin/tpm2`. Forced via `add_dracutmodules` so a missing dep fails the rebuild loudly.
- **Kernel lockdown (Module 1 impact):** eBPF/XDP OK; out-of-tree modules (Intel OOT `ice`, PF_RING, DPDK kmods) need MOK signing; `bpf_probe_write_user` blocked; `setpci` writes past the standard config header blocked (believed; untested).
- **No fallback kernel** until the next kernel update; recovery = installer USB.
- **USB-C ports** with TB driver off: plain USB likely works (xhci 97:00.0 still bound); TB/USB4 tunneling and docks don't. Untested.
- **Barlow Ridge NVM version** not visible to fwupd while `thunderbolt` is blacklisted.
- E810: NVM 4.70, fw 1.3755.0, mgmt 7.7.3, DDP "ICE OS Default" 1.3.43.0 loaded. LnkCap Gen4 x8, LnkSta Gen4 x4 (slot wiring), ASPM not supported. ~50 Gb/s usable (estimate): one 25G capture port fine; both at line rate marginal.
- kdump installed, `crashkernel=` reserves 512 MB. Recommend keep (Module 1 kernel debugging).
- `bolt.service` idle (TB off). `grub-pc` in `rc` state (left alone). KHO "failed to reserve scratch" on every boot (pre-existing; likely harmless).
- Journal 77.5 MB (flood-era).
- LAN is 1G end to end by design.

## Next steps (in order)
1. ~~AMT cabling~~ done 2026-10-29: SFP+6 isolated to SFP+4 (verified), `eno4` → SFP+6, link up 1000 full, no host IP.
2. ~~rock-box 192.168.51.2/24~~ done (persistent, `/etc/netplan/60-johnny-amt-oob.yaml` on rock-box); AMT reachable, cert matches. Negative test passed (unreachable from Johnny `eno3` on SFP+2; see `docs/network-map.md`).
3. ~~L1-2~~ done 2026-10-30: designed from the physical layout (`docs/network-map.md` § L1-2 design): SFP+7 standalone mirror target, SFP+8 out of `bridge` + disabled, ingress mirror on SFP+1/3/4/5, SFP+7 DAC → `eno1np0`. **Applied 2026-10-30**: `eno1np0` 10000, no addresses, mirrored frames counted at the NIC; A/B ping test from rock-box confirmed SFP+4 and SFP+5 ingress reach `eno1np0` (see `docs/network-map.md` § L1-2 result).
4. ~~Router reservation~~ done 2026-10-30: kept .152 (no address change). RT-BE88U LAN → DHCP Server: Manual Assignment was **off** (listed entries inactive); turned on, added johnny `38:05:25:3A:A3:71` → .152. See `docs/network-map.md` § Router DHCP.
5. HDMI dummy into Johnny's HDMI when it arrives; retest headless KVM video incl. BIOS.
6. AMT power control retest with MeshCommander or `rpc-go`. Rotate DMT Console `jwtKey` + admin password before any reuse.
7. Tool install (**after step 10's baseline**, AJ 2026-10-30): one pinned apt block, versions recorded for SBOM. Candidates: tshark/wireshark-common, tcpdump, zeek, suricata, nmap, masscan, iperf3, hping3, tcpreplay, netsniff-ng, bpftrace, bpftool, bpfcc-tools, mtr-tiny, ethtool, bind9-dnsutils, stress-ng. Verify names in 26.04; zeek may need upstream repo.
8. Thermal soak: `stress-ng --cpu 0 --timeout 30m` + `turbostat`.
9. EDAC: document (non-ECC now).
10. **Compliance baseline: (c) chosen** (AJ, 2026-10-30): hand-check against CIS Ubuntu Linux 26.04 LTS 1.0.0 to get close now; run Canonical's `usg audit` (CIS + DISA-STIG) once USG ships a 26.04 profile. CIS-CAT Lite can't automate it: Lite covers Ubuntu 20.04 v3.0.0 only; 26.04 v1.0.0 is CIS-CAT Pro only ([coverage guide](https://ciscat-assessor.docs.cisecurity.org/en/latest/Coverage%20Guide/)). Benchmark PDF free for non-commercial use ([CIS](https://www.cisecurity.org/benchmark/ubuntu_linux/)); local copy `docs/CIS_Ubuntu_Linux_26.04_LTS_Benchmark_v1.0.0.pdf` (gitignored; 1138 pp, sha256 `4acce51f65a3f5597c6083e78ee334733fb814bc733c10b566764295885a4af8`). **Profile (AJ, 2026-10-30): Level 1 – Server now (274 recs); Level 2 – Server (+76) as a second pass** once the log volume exists (L2 adds `auditd` ×55, separate `/home` `/var` `/var/tmp` `/var/log` `/var/log/audit` partitions, all AppArmor enforcing, ufw outbound deny, and 6.2.2.3 halt-on-full-audit-log). `auditd` is L2-only in this benchmark. Results: `docs/cis-26.04-l1-results.csv` (audit only; nothing changed on Johnny). **Fix gate:** no CIS remediation until a working console exists (HDMI dummy in + AMT KVM video verified, step 5, or a monitor at the closet); L1 fixes touch ufw, SSH, PAM lockout and a GRUB password. Keep a second SSH session open while testing each change.
    - **Progress (2026-10-31):** sections 1–5 done, 233/274 L1: 103 pass, 108 fail, 22 N/A. Section 5 (2026-10-31, Governance): 70 L1: 32 pass, 38 fail, 0 N/A; L2-only skipped: 5.2.4, 5.3.3.1.3, 5.4.1.2, 5.4.3.1. **Next: section 6** (17 L1), then 7 (24). Earlier sections: Section 4 (2026-10-31, Governance): 4 L1: 1 pass (4.1.1), 3 fail (4.1.2, 4.1.3, 4.1.5), 0 N/A; 4.1.4 L2-only. Section 1 (2026-10-30): 78 L1: 34 pass, 25 fail, 19 N/A. Section 2 (2026-10-31, Governance): 44 L1: 30 pass (2 manual: 2.1.23, 2.3.3.2), 11 fail, 3 N/A (2.3.2.1, 2.3.2.2 timesyncd not installed; 2.4.2.1 `at` not installed). Section 3 (2026-10-31, Governance): 37 L1: 6 pass, 31 fail (2 manual: 3.1.1, 3.2.7), 0 N/A. Method: CIS's own audit commands, PDF line wraps rejoined (shared checker bodies wrapped as functions); Claude runs non-root parts as `aj`, AJ runs root parts with output to `~/cis-audit/*.txt` on Johnny (kept). Scripts and raw output: `docs/cis-local/` (gitignored, licensed content; section 2 = `cis-2-audit.sh`, `cis-2-out.txt`). Procedure: `.claude/skills/cis-audit/SKILL.md` (2026-10-31).
    - Section 1 fails by fix type: module blocklist (1.1.1.1–5, .9, .10, .11; keep `xfs` + `autofs4`; `ext4`/`fat`/`vfat` built-in); `noexec` on `/tmp` + `/dev/shm` (1.1.2.1.4, 1.1.2.2.4); apt (1.2.1.11 http mirrors: verify HTTPS support first; 1.2.1.15 Check-Date); `apparmor-utils` missing (1.3.1.1); **GRUB password (1.4.1)**: needs console gate and `--unrestricted` default boot (26.04 method unverified); sysctl/core (1.5.4 suid_dumpable=2, 1.5.5, 1.5.9 not in a conf file, 1.5.10 `limits.d/10-coredump-debian.conf` hard core infinity); apport active (1.5.7); banners/motd (1.6.2–1.6.6; banner wording is AJ's); update-notifier-motd.timer (1.6.12).
    - Section 2 fails by fix type (none touch SSH, ufw, PAM or GRUB; fix gate still applies): **package removal** (strict CIS, AJ 2026-10-31): 2.1.13 `rsync`, 2.2.4 `telnet` + `inetutils-telnet`, 2.2.6 `ftp` + `tnftp`. `ubuntu-standard` (not approved) depends on rsync and ftp; removing ftp alone installs `ftp-ssl` (also CIS-listed). Fix: `apt-mark manual` ubuntu-standard's other deps first (as with ubuntu-server-minimal), then remove `ubuntu-standard ftp tnftp telnet inetutils-telnet rsync`. A careless `--autoremove` takes 33 pkgs incl. tcpdump, mtr-tiny (step 7 candidates), nano, plymouth, friendly-recovery (`apt-get -s`, 2026-10-31). **File modes**: 2.4.1.2 `/etc/crontab` 644; 2.4.1.3–2.4.1.8 `/etc/cron.{hourly,daily,weekly,monthly,yearly,d}` 755 (all root:root; CIS wants no group/other access). **Cron allow list**: 2.4.1.9 no `/etc/cron.allow`.
    - Section 2 decisions (AJ, 2026-10-31): Ubuntu NTS pools approved (2.3.3.1). Listeners approved (2.1.23): sshd 0.0.0.0:22 + [::]:22, resolved stub 127.0.0.53/54:53, networkd DHCP client eno3:68, chrony cmdport 127.0.0.1/[::1]:323; owners from a non-root unit check (root `sudo ss -plntu > ~/cis-audit/2-root.txt` optional, not run). `ubuntu-standard` not approved: play by the rules now, loosen later if needed. 2.3.3.2 PASS (manual): CIS's check matches chrony's root starter script `/usr/lib/systemd/scripts/chronyd-starter.sh`; chronyd runs as `_chrony`.
    - Section 3 fails by fix type (31 rules, 4 fixes; fix gate applies): **module blocklist** (`install /bin/false` + `blacklist` in `/etc/modprobe.d/`, batch with 1.1.1.x): 3.2.1 atm, 3.2.2 can, 3.2.4 rds, 3.2.5 sctp, 3.2.6 tipc (dccp not in the kernel: 3.2.3 pass). **sysctl drop-in** (16): 3.3.1.1–3.3.1.5, 3.3.1.8–3.3.1.14, 3.3.1.16–3.3.1.19: 10 wrong values (send/accept/secure_redirects 1, rp_filter 2, log_martians 0; all + default) and 6 correct but not in a file. Name it to sort after `55-network-security.conf` (e.g. `60-…`): systemd applies sysctl files in filename order across directories, last wins ([sysctl.d(5)](https://www.freedesktop.org/software/systemd/man/latest/sysctl.d.html)); don't edit `/usr/lib/sysctl.d/`. Optionally also pin 3.3.1.6/3.3.1.7/3.3.1.15 there (they pass via `/etc/ufw/sysctl.conf` and `50-default.conf`). **IPv6 disable** (AJ policy): fixes 3.1.1 and makes 3.3.2.1–3.3.2.8 N/A (judged FAIL now because IPv6 is enabled). Method is Platform's: `ipv6.disable=1` boot option or `disable_ipv6=1` on all + default; the boot option may break ssh.socket's `[::]:22` bind (untested), so test with a console and a second SSH session. **3.2.7 site list**: Governance drafts, Detection confirms capture/XDP needs (e.g. xsk_diag, cls_bpf, act_bpf), AJ approves; keep ufw's netfilter modules (nf_tables, nft_*, x_tables, xt_*, ip(6)_tables, nf_conntrack*, nf_reject_*); AF_PACKET is built in. CIS example candidates esp4, esp6, rxrpc.
    - Section 3 decisions and notes (2026-10-31): AJ: "no ipv6 . no wireless, follow 3.2.7 recommendation." 3.3.1.6/3.3.1.7 pass via `/etc/ufw/sysctl.conf` (CIS's scan includes ufw's `IPT_SYSCTL` file with no active-service test; Grok and Governance agree). Interactions: (1) **section 4**: enabling ufw applies `/etc/ufw/sysctl.conf`, whose `log_martians=0` lines would undo 3.3.1.16/3.3.1.17, so comment them out then (CIS remediation); re-audit after ufw package updates. (2) **step 11**: system-wide IPv6 disable makes the planned per-interface `disable_ipv6=1` on `eno1np0` redundant; strict `rp_filter=1` + `log_martians=1` may log martians for mirrored broadcast frames reaching `eno1np0`'s IPv4 stack (Governance's reasoning, untested; per-interface values can't override `all` here); check `journalctl -k | grep -c martian` after the fix.
    - Section 4 (firewall; AJ 2026-10-31: "ufw ... if CIS says built in ufw is fine we use it"): ufw 0.36.2-9build1 installed; `ufw.service` enabled + active but `/etc/ufw/ufw.conf` `ENABLED=no`, root `ufw status` = inactive, no rules staged. Saved defaults already pass: `DEFAULT_INPUT_POLICY="DROP"`, `DEFAULT_FORWARD_POLICY="DROP"`, OUTPUT ACCEPT (4.1.4 outgoing is L2), `IPV6=yes`. 4.1.5 fails both CIS paths (no `disabled (routed)` while inactive; note's `grep -i routed /etc/default/ufw` finds nothing because the file says `DEFAULT_FORWARD_POLICY`); after enable, judge it (manual) on DROP. **Fix (one job, behind the gate):** console + second SSH session → comment out `log_martians=0` in `/etc/ufw/sysctl.conf` (section 3 clash) → SSH allow rule (22/tcp is the only approved listener needing one) → `ufw enable` → re-audit 4.1.2/4.1.3/4.1.5 and 3.3.1.16/17 → Detection confirms capture on `eno1np0`. **Open for AJ (fix pass):** SSH source (Brain rec 192.168.50.0/24 on `eno3`); deny vs reject (Brain rec deny); `nftables` package (installed only via `ubuntu-standard`, unit disabled): Brain + Grok rec remove it with `ubuntu-standard`, keep the `nf_tables` kernel module (ufw's iptables-nft backend needs it), AJ to confirm. Detection to confirm a ufw incoming deny doesn't affect AF_PACKET/XDP capture (understanding: capture taps run before netfilter).
    - Section 5 (access control; 2026-10-31, Governance, Grok reviewed): by block 5.1 SSH 24: 13 pass, 11 fail; 5.2 sudo/su 6: 4/2; 5.3 PAM 25: 5/20; 5.4 accounts 15: 10/5. Scripts `docs/cis-local/cis-5.{1,2,3,4}-audit.sh` + `cis-5.{1,2,4}-root.sh`, output `cis-5.*-out.txt` / `cis-5.*-root-out.txt`. State found: openssh-server 1:10.2p1-2ubuntu3.8 via `ssh.socket`, no Match blocks, one drop-in `50-cloud-init.conf` (0600); `sudo` = **sudo-rs** 0.2.13 (alternatives; classic sudo 1.9.17p2 also installed); stock PAM (pam_unix only; no pwquality, cracklib, faillock or pwhistory); `aj` is the only account with a password, root locked (`L`); aj session umask 0002 (`USERGROUPS_ENAB yes`, no UMASK set, pam_umask active).
    - Section 5 fails by fix type (38; fix gate applies; **all lockout-risk**: console + second session, risk-register entries first, because aj's password is used for sudo): **sshd drop-in** (9): 5.1.5 allow/deny list, 5.1.6 banner, 5.1.8 ClientAliveInterval 0, 5.1.9 DisableForwarding, 5.1.15 LoginGraceTime 120, 5.1.17 umac MACs, 5.1.18 MaxAuthTries 6, 5.1.20 MaxStartups 10:30:100, 5.1.22 PermitRootLogin prohibit-password. sshd uses the first value read and `Include` is at `sshd_config:24`, so the drop-in must sort before `50-cloud-init.conf`; `sshd -t` before reload. **sshd modes** (2): 5.1.1 `sshd_config` 0644 → 0600, 5.1.2 `sshd_config.d` 0755 → 0700. **sudo/su** (2): 5.2.6 `timestamp_timeout` unset; 5.2.7 pam_wheel commented out (enabling with an empty group blocks su for everyone incl. aj; sudo unaffected). 5.2.3 passes on journald; do **not** add `Defaults logfile` (sudo-rs). **Packages** (2, AJ approves): 5.3.1.3 libpam-pwquality, 5.3.1.4 cracklib-runtime. **PAM stack** (6, via pam-auth-update): 5.3.2.2 faillock, 5.3.2.3 pwquality, 5.3.2.4 pwhistory, 5.3.3.4.1 remove `nullok`, 5.3.3.4.4 `use_authtok`. **PAM settings** (13): 5.3.3.1.1–.2 faillock.conf; 5.3.3.2.1–.8 pwquality.conf.d (5.3.3.2.6 dictcheck and .7 enforcing are FAIL (manual): greps empty only because pwquality is absent; expected to pass once installed); 5.3.3.3.1–.3 pwhistory.conf, set in one place only. **Aging** (2): 5.4.1.1 PASS_MAX_DAYS 99999 (login.defs + `chage` on aj), 5.4.1.5 INACTIVE -1 (`useradd -D` + aj). **Shell env** (2): 5.4.3.2 TMOUT unset; 5.4.3.3 umask FAIL (manual): with `USERGROUPS_ENAB yes`, UMASK 027 in login.defs alone gives 007, so also set 027 in `/etc/profile.d/`. **Root PATH** (1): 5.4.2.5 `/snap/bin` (not a directory) in root's login PATH (source assumed `/etc/environment`, confirm) and sudoers `secure_path`; remove both (no snaps), sudoers via `visudo` + `visudo -c`, confirm which visudo (sudo-rs or classic), root shell already open.
    - Section 5 decisions and notes (2026-10-31): 5.4.2.6 root umask PASS (Governance from the PDF; Grok and Brain agree): it forbids only a weak umask in root's dotfiles (none set); the weak default is counted once under 5.4.3.3; root effective umask assumed 0022 (unverified). No `apt update` before 5.3.1.x (lists refreshed 2026-10-31 02:43). 5.2.3 side note: `/var/log/auth.log` exists but CIS's grep found no sudo lines (journal has them; not investigated). **Site-policy values (AJ, 2026-10-31: "accept all"; Grok checked against the CIS bounds):** SSH `AllowUsers aj`; banner `Authorized use only. Activity is monitored.`; ClientAliveInterval 15 + ClientAliveCountMax 3 (drops a dead client after ~45 s; not an idle logout); sudo `timestamp_timeout=15`; empty su group `sugroup` (su off for everyone, use `sudo -i`); faillock deny 5, unlock_time 900; pwquality minlen 14, difok 2, maxrepeat 3, maxsequence 3; complexity length-only: the PDF (5.3.3.2.3, manual) requires only that no `[dulo]credit` is above 0 and that complexity follows site policy, so write the policy explicitly (`dcredit`/`ucredit`/`lcredit`/`ocredit = 0` in `pwquality.conf.d`) so the audit grep has a line to read; minclass 3 is the alternative if AJ changes it; pwhistory remember 24; PASS_MAX_DAYS 365 (yearly password change), INACTIVE 45, TMOUT 900 (idle shell logout); install libpam-pwquality + cracklib-runtime (approved). **Lockout:** faillock's account line also blocks SSH key logins for aj during the 15-min lock (Grok's correction; Brain had said keys were unaffected), so a mistyped sudo password ×5 means no new sessions for 15 min: keep a session open when testing.
    AJ (2026-10-30): baseline before tool install (step 7). Verified 2026-10-30:
    - Canonical lists 26.04 FIPS 140-3, DISA-STIG and CIS as "Planned" ([release cycle](https://ubuntu.com/about/release-cycle)). USG profiles exist for 20.04/22.04/24.04 only ([USG](https://documentation.ubuntu.com/security/compliance/usg/)), so `pro attach` → `usg audit` cannot run on 26.04 today. No FIPS for 26.04.
    - CIS has published Ubuntu Linux 26.04 LTS Benchmark 1.0.0; CIS-CAT Pro and Build Kit are CIS membership tools ([CIS](https://www.cisecurity.org/benchmark/ubuntu_linux/)).
    - Do not scan 26.04 with 24.04 SCAP content: its rules are gated to 24.04 and return "not applicable" ([ComplianceAsCode #14857](https://github.com/ComplianceAsCode/content/discussions/14857)). Upstream 26.04 product has a default profile only ([#14721](https://github.com/ComplianceAsCode/content/pull/14721)). Resolute ships `openscap-scanner` 1.4.3+dfsg-1ubuntu1 and `ssg-*` 0.1.79-1; not installed; whether 0.1.79 holds a 26.04 datastream is unverified.
    - Choices: (a) stay on 26.04, wait for USG; (b) rebuild on 24.04, audit with USG before tools; (c) stay on 26.04, check by hand against CIS 26.04 1.0.0 (CIS only, not DISA).
    - Gaps vs typical CIS rules (read-only check 2026-10-30): no `auditd`, no AIDE, `ufw` installed but inactive, no `libpam-pwquality`, no login banner. SSH offers `publickey` only. Do not fix from a 24.04 checklist; wait for the chosen benchmark.
11. E810 capture config (see step 10 section 3 interactions: IPv6 disable, rp_filter/log_martians): capture port `eno1np0` promisc, `disable_ipv6=1`, `arp off`, link-up only; second port `eno2np1` admin-down (netplan `activation-mode: off`, verify); verify native XDP on ice (count with XDP); capture-core tuning (EPP performance, per-core deep C-state off). DDP COMMS package optional.
12. Research option D (signed UKI + PCR 11) for fleet.
13. Agent team: ~~Grok review~~ done 2026-10-31 (agrees with §1–3, 5–7, 9; its 3 edits applied in `docs/agent-team.md` rev 3). ~~Wire `.claude/agents/`~~ done 2026-10-31: 9 agent files (rev 4). Architecture-logic items deferred (`docs/agent-team.md` §7).

## Closet move gate (closed 2026-10-29)
1. SSH key login ✓
2. AER flood resolved ✓
3. TPM unlock + unattended reboot ✓
4. BIOS final: Quiet Boot ✓, 1.04 latest ✓, admin password ✓ (reboot + power pull → TPM unlock, PCR 7 baseline)

**DAC gate (closed 2026-10-30):** SFP+7/8 out of `bridge`, SFP+8 disabled, then SFP+7 DAC → `eno1np0`. SFP+8 DAC's Johnny end stays out.

## Decisions
- Netplan E810: no addressing + optional (needed for the final capture config anyway).
- Thunderbolt: blacklist (driver + initramfs) over AER masking; keep TB off even if a firmware fix appears (unused DMA surface). Never `pci=noaer`; never disable ACS Source Validation.
- Initramfs: no networking (local LUKS root).
- Don't remove `cloud-initramfs-dyn-netconf` (`ubuntu-server` metapackage dep); omit the dracut module instead.
- Bluetooth: kernel blacklist (bluez not installed).
- Secure Boot db/dbx updates applied **before** TPM enrollment (PCR 7).
- TPM policy: option A (PCR 7), passphrase kept as recovery.
- Host mgmt on RTL8127 (`eno3`); I226 (`eno4`) dedicated to AMT, no host IP.
- AMT: ACM, TLS-only, KVM on, opt-in none, static 192.168.51.10/24 on its own switch port isolated to rock-box. Remote console = AMT KVM.
- snapd purged + pinned; ModemManager purged; `unattended-upgrades` security-only, no auto reboot; shim-signed + secureboot-db held.
- `pcie_aspm=off` via `/etc/default/grub.d/` drop-in.
- LAN 1G by design.
- On-box SLM: yes, full function for now (AJ, 2026-10-31). Limits, if any, come with the architecture pass.
- Switch: managed from laptop on ether1 only; physical cabling wins over the 2026-10-20 port plan.
- Carried from rev 2: headless; XFS root (FICLONE same-FS only); no snaps; no bond; STIG partition split deferred to fleet autoinstall; firmware lockdown = admin password + Secure Boot.

## SBOM
| Package | Version |
|---|---|
| linux-image-7.0.0-42-generic | 7.0.0-42.42 |
| systemd / systemd-cryptsetup | 259.9-0ubuntu0.1 |
| netplan.io | 1.2-1ubuntu5.1 |
| dracut / dracut-core | 110-11ubuntu0.1 |
| cryptsetup-bin | 2:2.8.4-1ubuntu4 |
| shim-signed (held) | 1.59+15.8-0ubuntu2 |
| secureboot-db (held) | 1.9build2 |
| grub-efi-amd64-signed | 1.215+2.14-2ubuntu1 |
| fwupd | 2.1.1-1ubuntu3.1 |
| mokutil | 0.7.2-2 |
| tpm2-tools | 5.7-1build1 |
| libtss2-* (fapi1, rc0, tctildr0, tcti-libtpms0, tcti-spi-helper0) | 4.1.3-6 |
| cloud-initramfs-dyn-netconf (kept) | 0.58ubuntu |
| rpc-go (`~/rpc/rpc`, not packaged) | v2.52.8, sha256 verified |
| Removed | linux-image-unsigned/modules/main-modules-zfs/headers/tools 7.0.0-30; snapd; ubuntu-server-minimal; ModemManager + 8 modem pkgs incl. tcl |
| UEFI | db 2023, dbx 20260707 |

Versions as of rev 3 except where noted; security updates since may have moved some. Re-read with `dpkg-query` before the tool-install SBOM.

Off-box: Intel DMT Console v1.47.0 (alpha) on rock-box.

## Parked
- **ableton_box and the Security Onion pattern** (raised 2026-10-31; record `docs/hosts/ableton_box.md`). Three decisions for AJ:
  1. Adopt the Security Onion 2.4 pattern: Johnny = sensor, ableton_box = manager search (storage, search, console), strix-halo = model endpoint behind an OpenAI-compatible API, model write actions need AJ's approval (replaces SLM "full function").
  2. ableton_box OS: Ubuntu Server 26.04 + CIS 26.04 Level 1, same as Johnny (recommended).
  3. `docs/hosts/` owner: Architect (provisional).
  Before any rebuild: copy anything needed off E: (failing SATA RAID 0; unreadable once either drive is pulled).
- **Cursor cloud environment** for this repo: AJ sets it up after Cursor's Cloud Agent degradation (2026-10-30) clears. Docs/research only: the VM is in Cursor's data center, off 192.168.50.0/24, so no SSH to Johnny, switch, or AMT. Prior attempt's branch `cursor/cloud-agent-env-2b7e` (commit `02690d8`, based on rev 3) deleted 2026-10-30. Its install script only checked that `README.md`, `AGENTS.md`, `docs/os-handoff.md`, `docs/sessions/`, `etc/.gitkeep` exist. Re-add to `AGENTS.md` (updated to current facts):
  ```
  ## Cursor Cloud specific instructions
  - Docs and `etc/` mirrors only. No app, lockfile, test suite, or dev server. Do not apt-install the tool-block candidates; those run on Johnny.
  - This VM is not on 192.168.50.0/24. Do not `ssh aj@192.168.50.152` from here. Read-only SSH runs from aj-rock-box or the laptop.
  - No secrets. Install checks `README.md`, `AGENTS.md`, `docs/os-handoff.md`, `docs/sessions/`, and `etc/.gitkeep`, then exits.
  ```
- ECC: 2× Kingston KSM56T46BD8KM-48HM (Minisforum-validated). Confirm Saitech $335/stick special-order price before buying. Two sticks also fixes **single-channel** memory.
- Memory 19–20% used at idle (6.2 GB): userspace+slab+cache ≈ 0.5 GB; ~5.7 GB is direct kernel/driver allocation. Hypothesis: ice (48 queues) or GPU driver. Investigate before Module 1 sizing.

## Legal
- Anyone else on this network gets captured. Lab default: metadata-first, header-only snaplen, short retention.
