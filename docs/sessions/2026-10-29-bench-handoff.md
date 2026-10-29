# Johnny bench handoff (2026-10-29, for Claude chat) — updated after RTL8127 rename

Repo: ajeswint/strix-halo-johnny. Base state: `docs/os-handoff.md` rev 3. Project is "Johnny", never "Sentinel". Terse, one step at a time, exact commands only, AJ runs sudo, never echo/store passwords. AJ is new/rusty on many concepts: give a one-line "what this does" per step.

## PORT NAMES CHANGED — read first
Enabling the RTL8127 in BIOS renamed the onboard copper ports. Rev 3's "eno3 = I226" is **obsolete**.

| Name now | MAC | Chip (driver, PCI) | Role |
|---|---|---|---|
| `eno3` | `38:05:25:3a:a3:71` | RTL8127 (`r8169`, ab:00.0) | Host mgmt, DHCP (192.168.50.152) |
| `eno4` | `38:05:25:3a:a3:70` | I226-LM (`igc`, ac:00.0) | AMT only, no host IP; AMT 192.168.51.10 |

Verified by sysfs driver binding, lspci, udev hwdb, firmware onboard index, `rpc amtinfo` (AMT wired MAC = `:70`), and ARP (192.168.51.10 → `:70`). Netplan matches both by MAC.

**Closet cabling, by jack:** the jack Johnny is SSH'd through (`eno3`, RTL8127) → CRS309 SFP+3. The other copper jack (`eno4`, I226/AMT) → SFP+4 (isolated). No DACs until L1-2.

## Done this session (after rev 3)
- **Closet gate closed.** BIOS admin password set, user pw blank. Reboot + power pull: TPM unlock both times, PCR 7 = baseline `B6D0F97F…BA07F3FF`. Admin password not measured into PCR 7 (tested).
- **E810 cage map** (facing back): left = `eno1np0`, right = `eno2np1`. Both DACs out (they had landed in default-bridge ports).
- **snapd purged + pinned** (`/etc/apt/preferences.d/johnny-no-snapd`, Pin-Priority -1). `ubuntu-server-minimal` removed with it; its 27 deps `apt-mark manual` first.
- **ModemManager purged** with `--autoremove` (8 modem-related pkgs incl. tcl).
- **unattended-upgrades security-only**, no auto reboot (`/etc/apt/apt.conf.d/52johnny-unattended-upgrades`). Holds on `shim-signed`, `secureboot-db` intact.
- **Recovery passphrase** (slot 0) tested OK.
- **RTL8127 enabled** in BIOS: in-tree `r8169`, PCR 7 unchanged. RAM 4800 = board max per Minisforum (closed).
- **Netplan** applied (`etc/netplan/00-installer-config.yaml`, commit 4d25052): `eno3` DHCP, `eno4` no addressing, E810 blocks unchanged. Survived reboots.
- **GRUB `pcie_aspm=off`** via `/etc/default/grub.d/johnny.cfg` (df21154). Kernel logs "PCIe ASPM is disabled". PCR 7 unchanged.
- **AMT** (ME 19.0.5): MEBx password changed, KVM on, User Opt-in None, static 192.168.51.10/24, Network Access activated → `rpc amtinfo`: **activated in admin control mode**. TLS-only: 16993 + 664 open; 16992/16994/623/5900 closed; 16995 closed. Self-signed Intel cert, SHA-256 `8C:D6:65:E9:E5:0C:49:00:65:D3:D9:D3:13:5B:66:97:5C:E3:89:4F:F5:04:48:B0:75:BC:44:5C:47:35:3D:0A`.
- `rpc-go` v2.52.8 at `~/rpc/rpc` on Johnny (not installed system-wide; sha256 verified).
- Leftovers: `grub-pc` in `rc` state (left alone). KHO "failed to reserve scratch" on every boot (pre-existing; likely harmless).

## In progress
- KVM viewer test from rock-box: Intel DMT Console v1.47.0 (alpha), `https://localhost:8181` (listens on all interfaces; stop it after). rock-box has temp alias 192.168.51.2/24 on `enp11s0`. `eno4` temporarily on office LAN for the test.
- HDMI dummy plug ordered (UGREEN 4-pack). Headless KVM needs it (Minisforum).

## After the bench (no console needed)
1. Unplug `eno4`; remove rock-box alias.
2. CRS309 SwOS: SFP+4 isolated (forwards only to rock-box's port; SFP+5 assumed), L1-2 (`sfp-sfpplus7` out of default bridge).
3. Router: optional .151 reservation → `38:05:25:3a:a3:71`.
4. Closet cabling per table above; insert HDMI dummy when it arrives.
5. Thermal soak, tool install (pinned, SBOM), rest of rev 3 next steps.
6. Session end: `docs/os-handoff.md` rev 4 (port rename, AMT, all of the above), session CSV, commit, push.
