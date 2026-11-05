# Step 9 — EDAC (draft)

Drafted 2026-11-05 ~12:06 CT. No command from this session has run on Johnny, on rock-box, or on ABLETON_BOX.

## Status

Handoff rev 80. Step 9 is **drafted, not applied**. Runbook: `docs/tool-install/step-9-edac.md`. AJ has not run the paste. The installed DIMM record is still 1× 32GB CT32G56C46S5, non-ECC, single channel (2026-10-28). ECC correction on that stick is unavailable. CIS L1 totals unchanged: **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274).

The main paste is unprivileged. It refuses root (`STOP-root`) and any host other than `johnny` (`STOP-host`). It does not `modprobe`, `rmmod`, or write EDAC sysfs. `NOTE-dmesg-denied` and `NOTE-journal-denied` are the only reason to run the optional sudo log paste. That second paste is not required for `STEP9-DONE`.

rock-box is the SSH client. ABLETON_BOX is Windows and is not an EDAC target. The fleet note is for a later Johnny-class sensor with ECC DIMMs. The parked Kingston pair is not bought here.

## Check on this draft

The main paste and the optional log paste were extracted and `bash -n` exited 0 on each. The main paste contains no `sudo`, `modprobe`, `rmmod`, or `insmod`.

On a host whose short name is not `johnny`, the main paste printed `STOP-host` and exited 1 before creating a log directory. The same file under `sudo -n` printed `STOP-root` and exited 1. An alias fixture matched `7d06` and did not match `7d1c`. A directory fixture counted one `mc0`, one `dimm0`, and zero `rank*`. The sysfs walk on a fake tree read `ce_count`, `ue_count`, `dimm_edac_mode`, and `size`, skipped `reset_counters` (mode 0200), and skipped `uevent`, `power`, and `subsystem`.

A copy of the main paste with the host and kernel gates opened, writing under `/tmp`, printed `STEP9-DONE`, `ECC-UNAVAILABLE`, and `NOTE-no-mc`. That host is not Johnny. A copy of the optional paste with those gates opened printed `STOP-no-aj` here, because this VM has no account `aj`. The same copy, with the account check pointed at the local user, printed `STOP-no-probe` when the summary was missing. When the summary already contained `STEP9-DONE`, it appended one `LOGS-DONE` and `chown`ed the files to that user. A second run printed `STOP-logs-already` and did not append again.

That check did not read Johnny's sysfs and did not load a module.
