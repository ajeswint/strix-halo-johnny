# Johnny bench handoff (2026-10-29, for Claude chat) — updated after RTL8127 rename

Repo: ajeswint/strix-halo-johnny. Base state: `docs/os-handoff.md` rev 3. Project is "Johnny", never "Sentinel". Terse, one step at a time, exact commands only, AJ runs sudo, never echo/store passwords. AJ is new/rusty on many concepts: give a one-line "what this does" per step.

> **Historical.** Do not act on the steps below. Superseded by `docs/os-handoff.md` (latest rev) and `docs/network-map.md` (audit 2026-10-29). Switch ports: Johnny `eno3` = **SFP+2** (not SFP+3), SFP+3 = bedroom drop, rock-box SFP+4, Framework SFP+5, AMT `eno4` = **SFP+6**. The switch runs RouterOS and is managed from a laptop on ether1 (not the SwOS UI via Chrome). Johnny IP = .152.

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

## KVM bench test (Intel DMT Console v1.47.0, alpha, on rock-box)
| Test | Result |
|---|---|
| Connect over TLS (16993, self-signed allowed) | ✅ Console reads AMT 19.0.5, ACM, KVM/IDE-R/SOL enabled, consent none |
| KVM video, Ubuntu + BIOS password prompt | ✅ with display connected; **black with HDMI unplugged** → HDMI dummy required (ordered, UGREEN 4-pack) |
| KVM keyboard | ✅ typed `kvmtest` at login prompt, erased |
| Power Off / Soft Reset / Ctrl+Alt+Del from Console | ❌ "Device did not respond" / no effect; AMT stayed reachable → likely Console alpha bug. Retest with MeshCommander or `rpc-go` |
| AMT session indicator | Flashing red/yellow border on local screen while KVM connected (expected) |

Console notes: serves **HTTPS** on 8181 on **all interfaces**; v1.47 generates a random 16-char admin password in `dist/linux/config/config.yml` (docs' `G@ppm0ym` is stale). Its `jwtKey` was exposed in the Claude transcript: rotate it and the admin password before reuse. Console is stopped. DB at `~/.config/device-management-toolkit/console.db` holds the device entry.

## Current state (2026-10-29 23:49 UTC): Johnny in the closet
- `eno3` (Realtek) → CRS309 SFP+3, 1G, 192.168.50.152. PCR 7 baseline, unattended boot 19.9 s.
- `eno4` (I226/AMT) **unplugged** until SFP+4 is isolated. E810 cages empty (DAC gate).
- rock-box temp alias removed; office test cable removed.

## Next (no console needed)
1. **CRS309 SwOS (in progress):** SFP+4 isolated (forwards only to rock-box's port; SFP+5 assumed, verify), then plug `eno4` → SFP+4. rock-box needs 192.168.51.2/24 to reach AMT (make persistent or add on demand). L1-2: `sfp-sfpplus7` out of default bridge, then DACs.
2. Router: optional .151 reservation → `38:05:25:3a:a3:71`.
3. HDMI dummy into HDMI port when it arrives; retest headless BIOS picture.
4. AMT power control with another tool.
5. Thermal soak, tool install (pinned, SBOM: add rpc-go v2.52.8 in `~/rpc/rpc`, DMT Console v1.47.0 on rock-box), rest of rev 3 next steps.
6. Session end: `docs/os-handoff.md` rev 4 (port rename, AMT, all of the above; also README hardware table still says I226 = mgmt `eno3`), session CSV, commit, push.
