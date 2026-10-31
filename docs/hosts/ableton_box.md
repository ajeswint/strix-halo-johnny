# ableton_box

Hardware record. Audit run on the box (Windows, non-admin shell) and pasted by AJ, 2026-10-31; network facts from rock-box the same day. AJ (2026-10-31): the box gets a new OS and becomes a helper in the Johnny setup; the SATA drives may come out. Role: not decided.

## Network
| Item | Value |
|---|---|
| Name | `ableton_box` (mDNS `ableton_box.local`) |
| Address | 192.168.50.211 (DHCP; no router reservation checked) |
| MAC | `3c:7c:3f:4e:14:7d` (IEEE OUI: ASUSTek) |
| NIC | Intel I225-V, linked 1 Gbps (LAN is 1G by design) |
| Switch port | not checked |
| Seen from rock-box | answers ARP; no ping reply; tcp/22 closed or filtered |

## Hardware
| Item | Value |
|---|---|
| Board | ASUS TUF X570-PRO. Onboard Intel AX200 Wi-Fi/BT not visible in Windows (likely off in BIOS) |
| BIOS | AMI 5043 (2025-09) |
| CPU | AMD Ryzen 9 5900X, 12 cores / 24 threads; virtualization on |
| RAM | 128 GB: 4 × 32 GB Corsair Vengeance LPX (two 2 × 32 GB kits), 3200 MT/s, 1.2 V. All slots full; board maximum |
| GPU | AMD Radeon RX 6900 XT, 16 GB, PCIe Gen4 x16 |
| NVMe | Samsung 990 2 TB (C:, Windows); Samsung 970 1 TB (D:, empty). Windows reports both healthy; SMART not readable through the AMD RAID driver |
| SATA | 2 drives in AMD RAID 0 "Array 2" (E:, 3.7 TB, ~1.8 TB used): **failing** |
| Storage mode | AMD RAID (driver 9.3.0.296, 2021-08; RAIDXpert2 not installed). C: and D: also sit behind the RAID driver |

## Findings
- **E: is failing.** 46 bad-block errors on `\Device\Harddisk1`, in bursts on Oct 2–3 and Oct 28. Error data says "medium error": a drive reported sectors it couldn't read (not a cable or controller fault). The failing member is unknown: the RAID driver hides each drive's model, serial and SMART data. RAID 0 has no redundancy; losing either drive loses all of E:.
- **Unexpected shutdown** Oct 28 13:22: Kernel-Power 41, no bugcheck, during sleep or hibernate. Once.
- No WHEA hardware errors in 30 days; no devices with errors; no crash dumps.
- Not checked (needs an admin shell): TPM, Secure Boot, BitLocker, temperatures.

## Before the rebuild
- Copy anything needed off E: first. Once either SATA drive is pulled, nothing on E: can be read.
- The board is in AMD RAID mode today. The new OS install changes that BIOS setting; the steps get specified, with sources, when the OS is chosen.
- Check TPM and Secure Boot in the BIOS (Johnny uses both).
