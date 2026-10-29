# Johnny — OS Handoff (rev 3, 2026-10-29 00:25 CT)

Supersedes rev 2. Prior records: `claude/L1 Handoff.md` (rev 5), `claude/Johnny_L1_Session_Log_2026-10-28.csv`. This session: `claude/Johnny_OS_Session_Log_2026-10-28.csv`.

## Context
- Johnny = Minisforum MS-02 Ultra (Core Ultra 9 285HX, 1× 32GB DDR5 non-ECC, Crucial P310 1TB). Defensive network-security platform; AJ designs, Claude builds.
- Sequence: L1 lab → **2. OS (installed; boot/firmware/TPM done; tools + capture config pending)** → 3. Overseer review → 4. Module 1 (eBPF fast-path).

## Rules
- Terse. One step at a time. Show commands before running. AJ runs anything needing sudo/credentials. Never echo or store passwords.
- Mark assumptions. Search before stating Ubuntu 26.04 specifics (package names, dracut behavior, kernel).
- Access: `ssh aj@192.168.50.151` from aj-rock-box (key auth only). Read-only checks run by Claude over SSH; `aj` has no passwordless sudo.

## Installed state
| Item | Value |
|---|---|
| OS | Ubuntu Server 26.04.1 LTS (`resolute`), full server, no third-party drivers |
| Kernel | 7.0.0-42-generic (only kernel; installer's unsigned 7.0.0-30 purged) |
| Initramfs | dracut 110-11ubuntu0.1; rebuild with `sudo update-initramfs -u` (dracut's own wrapper, writes `/boot/initrd.img-<ver>`) |
| Hostname / user | `johnny` / `aj` |
| Mgmt NIC | eno3 = I226-LM, 38:05:25:3a:a3:70, DHCP 192.168.50.151/24; sole wait-online link |
| Capture NICs | eno1np0 (…:ac:da), eno2np1 (…:ac:db) = E810-XXV on riser in PCIe 4.0 x16 slot (bifurcated x4/x4/x4) → **Gen4 x4 by design**. No addresses (v4/v6/link-local), `optional: true`, no cable |
| Disk | CT1000P310SSD8: p1 ESP 1G `/boot/efi`; p2 2G ext4 `/boot`; p3 **LUKS2** (aes-xts-plain64, argon2id) → LVM `ubuntu-vg` → `ubuntu-lv` 460G XFS `/` |
| LUKS slots | 0 = passphrase (recovery); 1 = TPM2, PCR 7 |
| Secure Boot | Enabled; kernel lockdown active. PK = MINISFORUM PK. db = MS UEFI CA 2011 + **MS UEFI CA 2023** + **Option ROM UEFI CA 2023** + Windows UEFI CA 2023 + Windows PCA 2011 + MINISFORUM OWN CA. dbx 20260707 |
| PCR 7 baseline | `B6D0F97FA80D8614711B20726D7FB7B00D77D52F24C3C0251630F925BA07F3FF` |
| Boot | Unattended, 17.8 s total (firmware 11.6 / loader 1.5 / kernel 0.5 / initrd 1.5 / userspace 2.7) |
| SSH | OpenSSH; password auth OFF; 3× ed25519 from `gh:ajeswint` |
| Updates | `full-upgrade` done 2026-10-29 04:18 UTC (40 pkgs). `unattended-upgrades` **enabled** (decision pending) |
| Time | UTC, NTP synced, RTC local = no |

Secrets: LUKS passphrase (now recovery only — still record it; needed if PCR 7 changes) and `aj` login password. No installer recovery key.

## BIOS (AMI 2.22.0059, Minisforum 1.04)
- 1.04 confirmed latest on Minisforum support (2026-10-29). fwupd/LVFS offers no BIOS/ME/E810/SSD firmware.
- Quiet Boot off — **verified** (POST text visible).
- Boot #1 = NVME: Ubuntu; only UEFI entry `Boot0000 Ubuntu` → shimx64.efi. No Disabled option for #2–#5.
- Advanced: RTL8127 off, I226 on, WIFI off, SSD1–4 on, J4301 x4 on, E810 slot on, x16 Slot Device 1 Disabled; ASPM/L1 off. No Thunderbolt toggle.
- ME 19.0.5.1992; AMT unprovisioned.
- Admin password **not set** — set after it's in the password manager, then one unattended reboot to confirm PCR 7 unchanged (assumption: setup password not measured into PCR 7).

## Closed issues
| # | Issue | Root cause | Fix |
|---|---|---|---|
| 1 | AER flood (~41 lines/s, buried LUKS prompt) | `thunderbolt` driver activating the TB5 NHI (84:00.0) → PTM Request TLPs with Requester ID 0000 (header `0x34000000 0x00000052`) → root port 80:1b.4 flags ACSViol (+UnsupReq). Proven: unload stops it, reload restarts it (417/15 s). Matches a known MS-02 Ultra report and Linux PTM/TB AER patch history. Not a bad chip (protocol-level, deterministic). | `/etc/modprobe.d/johnny-no-thunderbolt.conf` (`blacklist` + `install /bin/false`) and `omit_drivers+=" thunderbolt "` in dracut. 0 AER errors on 3 boots. |
| 2 | `systemd-networkd-wait-online` 120 s timeout | E810 entries in netplan required for online, no carrier | netplan: E810 `optional: true` + no addressing. netplan 1.2 generates a drop-in: wait-online `-i eno3` only |
| 3 | Stale UEFI entries | — | None present; nothing to do |
| 4 | initramfs ran networkd with catch-all `DHCP=yes` (all NICs, v4+v6) at LUKS prompt; `zzzz-dracut-default.network` persisted in `/run` | `cloud-initramfs-dyn-netconf` dracut module (no `check()`, always included) depends on `systemd-networkd` | Symlink Ubuntu's `no-network/10-no-network.conf` into `/etc/dracut.conf.d/`; `omit_dracutmodules+=" dyn-netconf "`. Package kept (`ubuntu-server` depends on it). initrd 64.0 → 36.9 MB |

## Config changes (all on Johnny)
| Path | Content / purpose | Rollback |
|---|---|---|
| `/etc/netplan/00-installer-config.yaml` | E810: `dhcp4/dhcp6: false`, `accept-ra: false`, `link-local: []`, `optional: true`; eno2np1 got `match`/`set-name` | `/root/00-installer-config.yaml.orig` |
| `/etc/modprobe.d/johnny-no-thunderbolt.conf` | blacklist + install /bin/false | delete, rebuild initramfs |
| `/etc/modprobe.d/johnny-no-bluetooth.conf` | btusb, bluetooth: blacklist + install /bin/false (BE200 BT on USB; BIOS WIFI-off doesn't kill it) | delete |
| `/etc/dracut.conf.d/johnny.conf` | `omit_drivers+=" thunderbolt "`, `omit_dracutmodules+=" dyn-netconf "`, `add_dracutmodules+=" tpm2-tss "` | edit, rebuild |
| `/etc/dracut.conf.d/10-no-network.conf` | symlink → `/usr/lib/dracut/dracut.conf.d/no-network/10-no-network.conf` | remove link, rebuild |
| `/etc/crypttab` | `dm_crypt-0 UUID=a6d02318-e79b-4a4c-bafa-0097695493db none luks,tpm2-device=auto` | `/root/crypttab.orig` |
| `/etc/systemd/system/{sleep,suspend,hibernate,hybrid-sleep,suspend-then-hibernate}.target` | masked → /dev/null | `systemctl unmask …` |
| LUKS slot 1 | TPM2, PCR 7 | `sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p3` |
| UEFI db / dbx | +MS UEFI CA 2023, +Option ROM CA 2023; dbx 20260707 (fwupd) | not reversible (additive/revocation) |

## Known gaps and notes
- **PCR-7-only binding (option A, chosen).** `/boot` is plaintext and the initrd is unsigned/unmeasured in PCR 7: a physical attacker can edit the initrd (or boot MS-signed media via BBS menu) and get the key released. Accepted for the lab. **Fleet: option D** — signed UKI + signed PCR 11 policy (26.04 support unverified; research before fleet autoinstall). Options B (PIN) and C (PCR 7+9, re-enroll every update) rejected.
- **PCR 7 changes** on any Secure Boot db/dbx/KEK/PK change, BIOS update, MOK change, shim re-signed by a different CA (2011 → 2023 expected), or shim raising `SbatLevel` → boot falls back to passphrase; re-enroll: `sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3`. Routine shim/GRUB/kernel updates signed by the same CA don't change PCR 7 (understanding, untested).
- **Auto-update exposure (open, decide before closet):** `shim-signed` 1.59+15.8-0ubuntu2 and `secureboot-db` 1.9build2 (apt-delivered db/dbx) are installed; `unattended-upgrades` allows `resolute` + `resolute-security`, empty blacklist. Either can change PCR 7 unattended; the next reboot (incl. power loss) stops at the passphrase prompt. fwupd only refreshes metadata (no auto-apply). **Hold applied 2026-10-29 05:29 UTC** (`apt-mark hold shim-signed secureboot-db`, verified). Update procedure: `apt-mark unhold` → install → console reboot → passphrase → re-enroll → `apt-mark hold`. Also decide remote console for passphrase entry (AMT KVM on isolated OOB port, or PiKVM/JetKVM); initrd network unlock conflicts with no-network initrd.
- **`tpm2-tools` is a boot dependency**: dracut's `tpm2-tss` module requires `/usr/bin/tpm2`. Now forced via `add_dracutmodules` so a missing dep fails the rebuild loudly.
- **Kernel lockdown (Module 1 impact):** eBPF/XDP OK; out-of-tree modules (Intel OOT `ice`, PF_RING, DPDK kmods) need MOK signing; `bpf_probe_write_user` blocked; `setpci` writes past the standard config header blocked (believed; untested).
- **No fallback kernel** until the next kernel update; recovery = installer USB.
- **USB-C ports** with TB driver off: plain USB likely works (xhci 97:00.0 still bound); TB/USB4 tunneling and docks don't. Untested.
- **Barlow Ridge NVM version** not visible to fwupd while `thunderbolt` is blacklisted.
- E810: NVM 4.70, fw 1.3755.0, mgmt 7.7.3, DDP "ICE OS Default" 1.3.43.0 loaded. LnkCap Gen4 x8, LnkSta Gen4 x4 (slot wiring), ASPM not supported. ~50 Gb/s usable (estimate): one 25G capture port fine; both at line rate marginal.
- `pcie_aspm=off` **not yet** on cmdline (policy `[default]`, follows BIOS = off).
- kdump installed, `crashkernel=` reserves 512 MB. Recommend keep (Module 1 kernel debugging).
- Running but unwanted: `snapd` (conflicts with no-snaps decision), `ModemManager`. `bolt.service` idle (TB off).
- Journal 77.5 MB (flood-era). AMT ports 16992–16995/5900/623/664 TCP closed/filtered from rock-box (UDP 623 untested; nmap not installed).

## Next steps (in order)
1. BIOS admin password (20 chars, in password manager first) → unattended reboot → confirm PCR 7 = baseline. **Closes closet gate.**
2. Package decisions before tool install (`shim-signed` + `secureboot-db` already held); purge `snapd`? purge `ModemManager`? `unattended-upgrades` off vs. security-only (pinning/SBOM)? Remote console for passphrase (AMT KVM vs. PiKVM/JetKVM) — decide before closet move.
3. Tool install: one pinned apt block, versions recorded for SBOM. Candidates: tshark/wireshark-common, tcpdump, zeek, suricata, nmap, masscan, iperf3, hping3, tcpreplay, netsniff-ng, bpftrace, bpftool, bpfcc-tools, mtr-tiny, ethtool, bind9-dnsutils, stress-ng. Verify names in 26.04; zeek may need upstream repo.
4. Thermal soak: `stress-ng --cpu 0 --timeout 30m` + `turbostat`.
5. GRUB cmdline: `pcie_aspm=off` (+ any capture-core params) → `update-grub` → reboot. Does not affect PCR 7.
6. EDAC: document (non-ECC now).
7. `pro attach` (free personal token) → USG (STIG/CIS), FIPS (verify 26.04 status).
8. E810 capture config: SFP28 cage → ifname map; capture port promisc, `disable_ipv6=1`, `arp off`, link-up only; second port admin-down (netplan `activation-mode: off`, verify); verify native XDP on ice (count with XDP); capture-core tuning (EPP performance, per-core deep C-state off). DDP COMMS package optional.
9. Research option D (signed UKI + PCR 11) for fleet.

## Closet move gate
1. SSH key login ✓
2. AER flood resolved ✓
3. TPM unlock + unattended reboot ✓ (2026-10-29 05:14 UTC; cryptsetup 0.42 s)
4. BIOS final — Quiet Boot verified ✓, 1.04 latest ✓, admin password ☐

DACs: only after the closet move AND CRS309 `sfp-sfpplus7` is out of the default bridge (L1-2, paused). Now safe at the OS level (no addressing, no initrd DHCP), but keep the gate.

## Decisions this session
- Netplan E810: no addressing + optional (needed for the final capture config anyway; cabling would not have been a fix).
- Thunderbolt: blacklist (driver + initramfs) over AER masking; keep TB off even if a firmware fix appears (unused DMA surface). Never `pci=noaer`; never disable ACS Source Validation.
- Initramfs: no networking (local LUKS root).
- Don't remove `cloud-initramfs-dyn-netconf` (`ubuntu-server` metapackage dep); omit the dracut module instead.
- Bluetooth: kernel blacklist (bluez not installed).
- Secure Boot db/dbx updates applied **before** TPM enrollment (PCR 7).
- `tpm2-tools` installed ahead of step 7 tool block (TPM check + cryptenroll need it); versions in SBOM below.
- TPM policy: option A (PCR 7), passphrase kept as recovery.
- Carried from rev 2: headless; XFS root (FICLONE same-FS only); no snaps; no bond; STIG partition split deferred to fleet autoinstall; firmware lockdown = admin password + Secure Boot.

## SBOM (installed or changed this session)
| Package | Version |
|---|---|
| linux-image-7.0.0-42-generic | 7.0.0-42.42 |
| systemd / systemd-cryptsetup | 259.9-0ubuntu0.1 |
| netplan.io | 1.2-1ubuntu5.1 |
| dracut / dracut-core | 110-11ubuntu0.1 |
| cryptsetup-bin | 2:2.8.4-1ubuntu4 |
| shim-signed | 1.59+15.8-0ubuntu2 |
| grub-efi-amd64-signed | 1.215+2.14-2ubuntu1 |
| fwupd | 2.1.1-1ubuntu3.1 |
| mokutil | 0.7.2-2 |
| tpm2-tools (new) | 5.7-1build1 |
| libtss2-* (new: fapi1, rc0, tctildr0, tcti-libtpms0, tcti-spi-helper0) | 4.1.3-6 |
| cloud-initramfs-dyn-netconf (kept) | 0.58ubuntu |
| Removed | linux-image-unsigned/modules/main-modules-zfs/headers/tools 7.0.0-30 |
| UEFI | db 2023, dbx 20260707 |

## Parked
- ECC: 2× Kingston KSM56T46BD8KM-48HM (Minisforum-validated). Confirm Saitech $335/stick special-order price before buying. Two sticks also fixes **single-channel** memory.
- RAM runs **4800 MT/s** (CT32G56C46S5 is a 5600 part). Check BIOS memory settings / board limits.
- Memory 19–20% used at idle (6.2 GB): userspace+slab+cache ≈ 0.5 GB; ~5.7 GB is direct kernel/driver allocation. Hypothesis: ice (48 queues) or GPU driver. Investigate before Module 1 sizing.

## Legal
- Anyone else on this network gets captured. Lab default: metadata-first, header-only snaplen, short retention.
