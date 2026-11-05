# Step 8 — thermal soak (draft)

Drafted 2026-11-05 ~10:55 CT. Not applied. No command from this session ran on Johnny or on rock-box.

## Status

Handoff rev 77. Step 8 is **drafted, not applied**. Runbook: `docs/tool-install/step-8-thermal-soak.md`. AJ has not run the paste. CIS L1 totals unchanged: **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274).

MeshCommander cleanup on rock-box is **closed** (AJ, 2026-11-05): computer deleted, node killed, Chrome site data for `http://127.0.0.1:3000` cleared. This draft did not watch that desktop.

Next after AJ runs the soak: 9 EDAC, 12 signed UKI, IRQ affinity later. Those were not drafted here.

## Check on this draft

The paste was extracted and `bash -n` exited 0. A fixture file with the step 11 idle map returned success from the tuning check. An extra `C1E` state on CPU 2 returned the idle-name stop. CPU 0 with an extra state still passed. EPP other than `performance` on CPU 3 failed the check. The summary awk, on a two-interval sample, reported max `CoreTmp` 91, `PkgTmp` 78, `PkgWatt` 95.25, `CoreThr` 2, and `PKG_%` 3.50. A header with only `CPU` and `Busy%` produced `SOAK-NOTE-no-PkgWatt` and the other missing-column notes. Apt `Candidate: (none)` stops. `Installed: (none)` with a real candidate does not.

That check did not execute `stress-ng` or `turbostat`.
