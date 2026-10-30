# Johnny — OS Handoff (rev 6, 2026-10-29 22:10 CT)

Supersedes rev 5 and every handoff in `docs/sessions/` (each bannered historical) for current state. Rev 6: repo audit only, no change on Johnny. `etc/` now mirrors every file in Config changes (hashes match Johnny), incl. the masked sleep targets as links to `/dev/null`; session-log times corrected from commit times; step 10 compliance status corrected (26.04 has no USG/STIG profile; CIS 26.04 1.0.0 exists). Rev 5: L1-2 applied (SFP+7 mirror → `eno1np0`), router DHCP reservation .152. Network and switch ports: `docs/network-map.md`. Session logs: `docs/sessions/`. Prior records: `claude/L1 Handoff.md` (rev 5, location unknown: not on rock-box or in this repo), `claude/Johnny_L1_Session_Log_2026-10-28.csv`.

## Context
- Johnny = Minisforum MS-02 Ultra (Core Ultra 9 285HX, 1× 32GB DDR5 non-ECC, Crucial P310 1TB). Defensive network-security platform; AJ designs, Claude builds.
- Sequence: L1 lab → **2. OS (installed; boot/firmware/TPM/closet move/AMT done; AMT cabling + L1-2 mirror + DHCP reservation done; tools, capture config pending)** → 3. Overseer review → 4. Module 1 (eBPF fast-path).
- Location: closet, headless, unattended boot. PCR 7 at baseline.

## Rules
- Terse. One step at a time. Show commands before running. AJ runs anything needing sudo/credentials. Never echo or store passwords.
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
| Time | UTC, NTP synced, RTC local = no |

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
- **PCR-7-only binding (option A, chosen).** `/boot` is plaintext and the initrd is unsigned/unmeasured in PCR 7: a physical attacker can edit the initrd (or boot MS-signed media via BBS menu) and get the key released. Accepted for the lab. **Fleet: option D**: signed UKI + signed PCR 11 policy (26.04 support unverified; research before fleet autoinstall). Options B (PIN) and C (PCR 7+9, re-enroll every update) rejected.
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
10. **Compliance baseline: method not chosen (AJ decides).** AJ (2026-10-30): baseline before tool install (step 7). Verified 2026-10-30:
    - Canonical lists 26.04 FIPS 140-3, DISA-STIG and CIS as "Planned" ([release cycle](https://ubuntu.com/about/release-cycle)). USG profiles exist for 20.04/22.04/24.04 only ([USG](https://documentation.ubuntu.com/security/compliance/usg/)), so `pro attach` → `usg audit` cannot run on 26.04 today. No FIPS for 26.04.
    - CIS has published Ubuntu Linux 26.04 LTS Benchmark 1.0.0; CIS-CAT Pro and Build Kit are CIS membership tools ([CIS](https://www.cisecurity.org/benchmark/ubuntu_linux/)).
    - Do not scan 26.04 with 24.04 SCAP content: its rules are gated to 24.04 and return "not applicable" ([ComplianceAsCode #14857](https://github.com/ComplianceAsCode/content/discussions/14857)). Upstream 26.04 product has a default profile only ([#14721](https://github.com/ComplianceAsCode/content/pull/14721)). Resolute ships `openscap-scanner` 1.4.3+dfsg-1ubuntu1 and `ssg-*` 0.1.79-1; not installed; whether 0.1.79 holds a 26.04 datastream is unverified.
    - Choices: (a) stay on 26.04, wait for USG; (b) rebuild on 24.04, audit with USG before tools; (c) stay on 26.04, check by hand against CIS 26.04 1.0.0 (CIS only, not DISA).
    - Gaps vs typical CIS rules (read-only check 2026-10-30): no `auditd`, no AIDE, `ufw` installed but inactive, no `libpam-pwquality`, no login banner. SSH offers `publickey` only. Do not fix from a 24.04 checklist; wait for the chosen benchmark.
11. E810 capture config: capture port `eno1np0` promisc, `disable_ipv6=1`, `arp off`, link-up only; second port `eno2np1` admin-down (netplan `activation-mode: off`, verify); verify native XDP on ice (count with XDP); capture-core tuning (EPP performance, per-core deep C-state off). DDP COMMS package optional.
12. Research option D (signed UKI + PCR 11) for fleet.

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
