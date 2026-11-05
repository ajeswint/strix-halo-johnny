# Step 12 — signed UKI research (inventory done)

Inventory done 2026-11-05 on Johnny. Handoff rev 83. Option D is not applied. Lab TPM unlock stays option A (PCR 7 only). **[Inference]** No package was installed. The pastes do not call apt, and AJ's summary is not a pre/post `dpkg` diff. `sbsigntool` `0.9.4-3.1ubuntu9` is the version the inventory printed. No UKI was built or signed. No LUKS slot was enrolled or wiped. GRUB, the shim holds, and Secure Boot keys are unchanged. No secrets are in this note.

AJ ran the main paste from tip `058fc60`. That text is `git show 058fc60:docs/tool-install/step-12-signed-uki.md`. The non-blocking nits in `0052cf7` do not require a re-run. The sudo summary lists `/boot/efi/EFI/BOOT/BOOTX64.EFI`. The `058fc60` find uses `-name` and does not match that name. **[Inference]** the optional paste that printed `EFI-FILE-SUDO` is the `-iname` find from `0052cf7`. Confirming which `find` printed that line would need the raw logs on Johnny. Those logs stay at `/home/aj/cis-audit/step12-signed-uki/`. This closeout does not SSH.

**[Assumption]** rock-box was the SSH client. AJ's summary does not name the client. ABLETON_BOX was not part of this closeout. Raw logs stay on Johnny at `/home/aj/cis-audit/step12-signed-uki/`.

## Result

`STEP12-RESEARCH-DONE` at `2026-11-05T19:24:09Z` (~13:24 CT). `SLOTS-DONE`. `HOST johnny`. `KERNEL 7.0.0-42-generic`. `EUID 1000`. `USER aj`. `GROUPS aj,adm,cdrom,sudo,dip,plugdev,users,lxd,wireshark`. Lockdown `none [integrity] confidentiality`. `NOTE-cmdline-aspm`. `NOTE-grub-aspm`. `CRYPTTAB-MATCH`. `SB-STATE SecureBoot enabled`. `NOTE-no-bootctl`. `EFIBOOTMGR-OK`. `BootCurrent` `0000`. `BootOrder` `0000`. `Boot0000` Ubuntu → `\EFI\ubuntu\shimx64.efi`. Holds `secureboot-db,shim-signed`.

`systemd` `259.9-0ubuntu0.1`. `systemd-ukify` not installed. Candidate `259.9-0ubuntu0.1` (`NOTE-ukify-candidate-match`). `systemd-boot`, `systemd-boot-efi`, `systemd-boot-efi-signed`, `systemd-boot-tools`, `systemd-repart`, `pesign`, `python3-pefile`, and `python3-zstandard` are not installed. Candidates: `systemd-boot`, `systemd-boot-efi`, and `systemd-repart` `259.9-0ubuntu0.1`. `systemd-boot-efi-signed` NONE. `pesign` `116-8.1build1`. `sbsigntool` `0.9.4-3.1ubuntu9` is installed. `python3-cryptography` `46.0.5-1ubuntu2.2`. `mokutil` `0.7.2-2`. `shim-signed` `1.59+15.8-0ubuntu2`. `secureboot-db` `1.9build2`. `grub-efi-amd64-signed` `1.215+2.14-2ubuntu1`. `grub-efi-amd64-bin` `2.14-2ubuntu1`. `tpm2-tools` `5.7-1build1`. `dracut` and `dracut-core` `110-11ubuntu0.1`. `cryptsetup` and `cryptsetup-bin` `2:2.8.4-1ubuntu4`.

`/usr/lib/systemd/systemd-measure` is present. `MEASURE-STATUS-OK`. `linuxx64.efi.stub`, `systemd-bootx64.efi`, and `/usr/bin/ukify` are absent.

`NOTE-efi-errors`. `EFI-FILES 7`. `NOTE-efi-extra` on `/boot/grub/x86_64-efi/core.efi` and `grub.efi`. Those are GRUB modules. Do not delete them. The sudo listing adds `/boot/efi/EFI/BOOT/BOOTX64.EFI` and repeats the other EFI paths.

`LUKS-DEV /dev/nvme0n1p3`. LUKS version 2. Keyslots 0 and 1 are luks2, `aes-xts-plain64`, normal priority. Filtered token lines: `systemd-tpm2` and `Keyslot: 1`, and a `pbkdf2` line. `NOTE-pcr-unreadable` as `aj`. `PCR-SUDO-OK`. `NOTE-pcr7-baseline` (`B6D0F97FA80D8614711B20726D7FB7B00D77D52F24C3C0251630F925BA07F3FF`). `NOTE-pcr11-zero`. PCR 14 `306F9D8B94F17D93DC6E7CF8F5C79D652EB4C6C4D13DE2DDDC24AF416E13ECAF`.

The summary AJ returned does not contain `NOTE-luks-dump-failed`, `NOTE-pcr-sudo-failed`, `NOTE-efi-sudo-failed`, or `NOTE-chown-failed`.

## Unchanged

CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Steps 6, 8, 9, and 11 stay applied. Next open item is IRQ affinity later. Fleet option D stays research. The runbook's open questions stay open, except the inventory itself (item 8), which ran.

## Summary

The block below is the summary AJ returned. It is the main inventory and the optional sudo lines. It is not a raw `luksDump`.

```
HOST johnny
KERNEL 7.0.0-42-generic
DATE-UTC 2026-11-05T19:24:09Z
EUID 1000
USER aj
GROUPS aj,adm,cdrom,sudo,dip,plugdev,users,lxd,wireshark
LOCKDOWN none [integrity] confidentiality
CMDLINE BOOT_IMAGE=/vmlinuz-7.0.0-42-generic root=/dev/mapper/ubuntu--vg-ubuntu--lv ro pcie_aspm=off crashkernel=2G-4G:320M,4G-32G:512M,32G-64G:1024M,64G-128G:2048M,128G-:4096M
NOTE-cmdline-aspm
NOTE-grub-aspm
PKG systemd 259.9-0ubuntu0.1
PKG systemd-ukify NOT-INSTALLED
PKG systemd-boot NOT-INSTALLED
PKG systemd-boot-efi NOT-INSTALLED
PKG systemd-boot-efi-signed NOT-INSTALLED
PKG systemd-boot-tools NOT-INSTALLED
PKG systemd-repart NOT-INSTALLED
PKG sbsigntool 0.9.4-3.1ubuntu9
PKG pesign NOT-INSTALLED
PKG python3-pefile NOT-INSTALLED
PKG python3-zstandard NOT-INSTALLED
PKG python3-cryptography 46.0.5-1ubuntu2.2
PKG mokutil 0.7.2-2
PKG shim-signed 1.59+15.8-0ubuntu2
PKG secureboot-db 1.9build2
PKG grub-efi-amd64-signed 1.215+2.14-2ubuntu1
PKG grub-efi-amd64-bin 2.14-2ubuntu1
PKG tpm2-tools 5.7-1build1
PKG dracut 110-11ubuntu0.1
PKG dracut-core 110-11ubuntu0.1
PKG cryptsetup 2:2.8.4-1ubuntu4
PKG cryptsetup-bin 2:2.8.4-1ubuntu4
POLICY systemd-ukify 259.9-0ubuntu0.1
POLICY systemd-boot 259.9-0ubuntu0.1
POLICY systemd-boot-efi 259.9-0ubuntu0.1
POLICY systemd-boot-efi-signed NONE
POLICY sbsigntool 0.9.4-3.1ubuntu9
POLICY pesign 116-8.1build1
POLICY systemd-repart 259.9-0ubuntu0.1
NOTE-ukify-candidate-match
HOLDS secureboot-db,shim-signed
FILE present /usr/lib/systemd/systemd-measure
FILE absent /usr/lib/systemd/boot/efi/linuxx64.efi.stub
FILE absent /usr/lib/systemd/boot/efi/systemd-bootx64.efi
FILE absent /usr/bin/ukify
SB-STATE SecureBoot enabled
NOTE-no-bootctl
EFIBOOTMGR-OK
EFI BootCurrent: 0000
EFI BootOrder: 0000
EFI Boot0000* Ubuntu	HD(1,GPT,2ec6d044-e209-4374-be79-ab7d770721ac,0x800,0x219800)/\EFI\ubuntu\shimx64.efi
NOTE-efi-errors
EFI-FILES 7
EFI-FILE /boot/efi/EFI/ubuntu/grubx64.efi
EFI-FILE /boot/efi/EFI/ubuntu/shimx64.efi
EFI-FILE /boot/efi/EFI/ubuntu/mmx64.efi
EFI-FILE /boot/efi/EFI/BOOT/fbx64.efi
EFI-FILE /boot/efi/EFI/BOOT/mmx64.efi
EFI-FILE /boot/grub/x86_64-efi/core.efi
NOTE-efi-extra /boot/grub/x86_64-efi/core.efi
EFI-FILE /boot/grub/x86_64-efi/grub.efi
NOTE-efi-extra /boot/grub/x86_64-efi/grub.efi
CRYPTTAB-MATCH
MEASURE-BIN present
MEASURE-STATUS-OK
NOTE-pcr-unreadable
STEP12-RESEARCH-DONE
LUKS-DEV /dev/nvme0n1p3
LUKS Version:       	2
LUKS Data segments:
LUKS   0: crypt
LUKS Keyslots:
LUKS   0: luks2
LUKS 	Priority:   normal
LUKS 	Cipher:     aes-xts-plain64
LUKS   1: luks2
LUKS 	Priority:   normal
LUKS 	Cipher:     aes-xts-plain64
LUKS Tokens:
LUKS   0: systemd-tpm2
LUKS   0: systemd-tpm2
LUKS 	Keyslot:    1
LUKS   0: pbkdf2
PCR-SUDO-OK
PCR-7-SUDO B6D0F97FA80D8614711B20726D7FB7B00D77D52F24C3C0251630F925BA07F3FF
PCR-11-SUDO 0000000000000000000000000000000000000000000000000000000000000000
PCR-14-SUDO 306F9D8B94F17D93DC6E7CF8F5C79D652EB4C6C4D13DE2DDDC24AF416E13ECAF
NOTE-pcr7-baseline
NOTE-pcr11-zero
EFI-FILE-SUDO /boot/efi/EFI/ubuntu/grubx64.efi
EFI-FILE-SUDO /boot/efi/EFI/ubuntu/shimx64.efi
EFI-FILE-SUDO /boot/efi/EFI/ubuntu/mmx64.efi
EFI-FILE-SUDO /boot/efi/EFI/BOOT/BOOTX64.EFI
EFI-FILE-SUDO /boot/efi/EFI/BOOT/fbx64.efi
EFI-FILE-SUDO /boot/efi/EFI/BOOT/mmx64.efi
EFI-FILE-SUDO /boot/grub/x86_64-efi/core.efi
EFI-FILE-SUDO /boot/grub/x86_64-efi/grub.efi
SLOTS-DONE
```
