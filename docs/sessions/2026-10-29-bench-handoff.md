# Johnny bench handoff (2026-10-29, for Claude chat)

Repo: ajeswint/strix-halo-johnny. Base state: `docs/os-handoff.md` rev 3. Project is "Johnny", never "Sentinel". Terse, one step at a time, exact commands only, AJ runs sudo, never echo/store passwords. AJ is new/rusty on many concepts: give a one-line "what this does" per step.

## Done this session (after rev 3)
- **Closet gate closed.** BIOS admin password set (in password manager), user pw blank. Reboot + 15 s power pull: TPM unlock both times, PCR 7 = baseline `B6D0F97F…BA07F3FF`. Admin password is **not** measured into PCR 7 (tested).
- **E810 cage map** (facing back): left = `eno1np0`, right = `eno2np1`. Both DACs pulled again: both had landed in CRS309 default-bridge ports, gate says no DACs until `sfp-sfpplus7` is out of the bridge (L1-2).
- `eno3` links at 1G (1G SFP-RJ45 module), not 2.5G. Expected.
- **snapd purged + pinned.** Snaps removed (hwctl, core24, snapd). `ubuntu-server-minimal` removed with it; its 27 deps `apt-mark manual` first (incl. cryptsetup, lvm2, xfsprogs, systemd). Pin: `/etc/apt/preferences.d/johnny-no-snapd` (Pin-Priority -1).
- **ModemManager purged** with `--autoremove` (8 pkgs: modemmanager, usb-modeswitch(+data), libmbim-utils, libqmi-utils, tcl, tcl8.6, libtcl8.6).
- **unattended-upgrades: security-only**, no auto reboot. Drop-in `/etc/apt/apt.conf.d/52johnny-unattended-upgrades` (`#clear` + `-security`, ESMApps, ESM-infra). Dry run clean. Holds on `shim-signed`, `secureboot-db` intact.
- Leftover: `grub-pc` in `rc` state (installer config). Left alone; purge may touch `/etc/default/grub`.
- `etc/apt/...` copies made in the repo, **not yet committed**.

## Decision: remote console = AMT KVM on isolated port (follow design)
- AMT shares the I226-LM (`eno3`) with the OS. To isolate it, host mgmt moves to **RTL8127** (currently Disabled in BIOS; reason not recorded) → CRS309 SFP+3; `eno3` → SFP+4 as AMT-only, no host IP.
- LAN is 1G end to end (SFP-RJ45 modules + switch). RTL8127 on SFP+3 at 1G is by design.

## Bench steps (in order; stop after each)
1. **Recovery passphrase test** before poweroff (no reboot): `sudo cryptsetup open --test-passphrase --key-slot 0 /dev/nvme0n1p3 && echo PASSPHRASE-OK`. Must pass before continuing.
2. **BIOS** (admin password now required): Advanced → RTL8127 → Enabled. Also *look at* memory settings (RAM runs 4800, part is 5600); change nothing. Save & Exit.
   - Assumption, untested: enabling a NIC whose option ROM loads can change PCR 7. If boot stops at the passphrase prompt: type the recovery passphrase, then re-enroll: `sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3`, record the new PCR 7 (`cat /sys/class/tpm/tpm0/pcr-sha256/7`) as the baseline, and do one unattended reboot to confirm.
3. **Check the new NIC:** `ip -br link` and `lspci -nnk | grep -iA3 ethernet`. Needs an in-tree driver (r8169; RTL8127 support in kernel 7.0 **unverified**). Kernel lockdown blocks out-of-tree `r8127` unless MOK-signed.
4. **MEBx / AMT provisioning** (Ctrl+P at POST, assumption): change default MEBx password (put in password manager first), enable KVM, user consent for KVM = None (headless; nobody sees a consent code), decide AMT IP (static vs DHCP on the isolated OOB port). TLS provisioning needs separate tooling; open item.
5. **Netplan:** add RTL8127 as mgmt (DHCP), `eno3` no addressing. Edit with console attached. Copy result to repo `etc/netplan/` (file is mode 600, AJ copies via sudo).
6. **GRUB `pcie_aspm=off`** → `sudo update-grub` → reboot with screen attached. Not PCR 7 relevant.
7. Optional: USB stick in a USB-C port (plain USB with TB off is untested).
8. Recable in closet: RTL8127 → SFP+3, `eno3` → SFP+4 (isolated). Still no DACs. Then thermal soak (closet airflow).

## Still open after bench
- Tool install (pinned apt block, SBOM), thermal soak, EDAC doc, `pro attach`/USG, E810 capture config, option D research (see rev 3 next steps).
- CRS309 L1-2 (`sfp-sfpplus7` out of default bridge, SFP+4 isolation) before DACs and before AMT is reachable.
- Session end: bump `docs/os-handoff.md` to rev 4, add session CSV, commit `etc/apt/*` + docs, push.
