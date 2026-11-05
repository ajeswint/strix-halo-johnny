# Step 9 — EDAC (applied)

Applied 2026-11-05 on Johnny. Handoff rev 81. AJ ran the main paste and the optional sudo log paste from tip `e08260f`. The paste he ran is `git show e08260f:docs/tool-install/step-9-edac.md`. The runbook now holds the post-nit paste. This closeout does not change Johnny's live config. No module was loaded. No sysfs write. No BIOS or RAM change. No secrets are in this note.

The nit commit `68b22e7` landed after that run. It labels `ECC-UNAVAILABLE` as the 2026-10-28 DIMM record, states that IBECC was not evaluated, and adds `|| true`, `STOP-no-denial`, and a single paste fence. Do not re-run to pick those lines up. `NOTE-dmesg-denied` was already in the summary AJ produced.

## Result

`STEP9-DONE` at `2026-11-05T18:15:40Z` (~12:15 CT). `LOGS-DONE`. `HOST johnny`. `KERNEL 7.0.0-42-generic`. `EUID 1000`. `CPU Intel(R) Core(TM) Ultra 9 285HX`. `DMESG-RESTRICT 1`. `MCE-DIR present`.

`GROUPS aj,adm,cdrom,sudo,dip,plugdev,users,lxd,wireshark`. **[Inference]** `adm` is why `journalctl -k` returned a line without sudo. The summary shows the group and `JOURNAL-EDAC-LINES 1`. It does not show a journal ACL. `dmesg` still failed.

`KO edac_core not-loaded (builtin)`. `EDAC-POLL-MSEC 1000`. `igen6_edac`, `ie31200_edac`, `i10nm_edac`, `skx_edac`, `sb_edac`, `pnd2_edac`, and `amd64_edac` were `KO` and `not-loaded`, each with a `.ko.zst` path under `/lib/modules/7.0.0-42-generic/kernel/drivers/edac/`.

`HB 0000:00:00.0 class 0x060000 vendor 0x8086 device 0x7d1c`. `NOTE-no-alias` for `igen6_edac`, `ie31200_edac`, `i10nm_edac`, and `skx_edac`. `0x7d1c` is outside the Arrow Lake-UH IDs in Ubuntu `7.0.0-42` `igen6_edac` (`0x7d06`, `0x7d20`, `0x7d30`). See `docs/tool-install/step-9-edac.md` (Drivers on kernel 7.0.0-42) for the Launchpad citation of those IDs.

`MC-DIRS 0`. `CSROW-DIRS 0`. `DIMM-DIRS 0`. `RANK-DIRS 0`. `NOTE-no-mc`. Sysfs directories present: `/sys/devices/system/edac` and `/sys/devices/system/edac/mc`. No `mc*` controller directory.

`NOTE-dmesg-denied`. The error line was `dmesg: read kernel buffer failed: Operation not permitted`. `JOURNAL-EDAC-LINES 1`. That match was `EDAC MC: Ver: 3.0.0`. The EDAC core is present. No memory controller is bound.

`DIMM-RECORD CT32G56C46S5 non-ECC single-channel 2026-10-28`. `ECC-UNAVAILABLE` restates that record. It is not a probe measurement. Per the 2026-10-28 record, no side-band ECC DIMM is seated. **[Assumption]** The stick is unchanged since that read. The 2026-11-05 probe did not run `dmidecode`. IBECC was not evaluated.

Sudo log paste: `DMESG-SUDO-LINES 1`, `JOURNAL-SUDO-LINES 1`, `LOGS-DONE`. The return did not quote those two line bodies. It did not include `NOTE-dmesg-sudo-stderr`, `NOTE-journal-sudo-stderr`, or `NOTE-chown-failed`.

## Unchanged

CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Next open items are 12 signed UKI (option D) and IRQ affinity later. rock-box was the SSH client. ABLETON_BOX was not probed.

## Logs

On Johnny: `/home/aj/cis-audit/step9-edac/`. Raw files stay there. The summary lines AJ returned are below. The `.ko.zst` paths are not copied out in full. The sudo match bodies are not copied, because the return gave counts only.

## Summary

**Abridged.** The block below leaves out the seven non-builtin `KO` lines. The sentence after the block records those lines.

```
HOST johnny
KERNEL 7.0.0-42-generic
DATE-UTC 2026-11-05T18:15:40Z
EUID 1000
GROUPS aj,adm,cdrom,sudo,dip,plugdev,users,lxd,wireshark
CPU Intel(R) Core(TM) Ultra 9 285HX
DMESG-RESTRICT 1
MCE-DIR present
KO edac_core not-loaded (builtin)
EDAC-POLL-MSEC 1000
HB 0000:00:00.0 class 0x060000 vendor 0x8086 device 0x7d1c
NOTE-no-alias igen6_edac
NOTE-no-alias ie31200_edac
NOTE-no-alias i10nm_edac
NOTE-no-alias skx_edac
MC-DIRS 0
CSROW-DIRS 0
DIMM-DIRS 0
RANK-DIRS 0
NOTE-no-mc
SYSFS DIR /sys/devices/system/edac
SYSFS DIR /sys/devices/system/edac/mc
NOTE-dmesg-denied
DMESG-ERR dmesg: read kernel buffer failed: Operation not permitted
JOURNAL-EDAC-LINES 1
DIMM-RECORD CT32G56C46S5 non-ECC single-channel 2026-10-28
ECC-UNAVAILABLE
STEP9-DONE
DMESG-SUDO-LINES 1
JOURNAL-SUDO-LINES 1
LOGS-DONE
```

Journal match (one line, not a summary token): `EDAC MC: Ver: 3.0.0`.

The seven non-builtin `KO` lines were `not-loaded` with `.ko.zst` paths under `/lib/modules/7.0.0-42-generic/kernel/drivers/edac/`.
