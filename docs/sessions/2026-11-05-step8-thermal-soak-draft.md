# Step 8 — thermal soak (draft, historical)

**Historical.** Superseded 2026-11-05 by the applied closeout: `docs/sessions/2026-11-05-step8-thermal-soak-applied.md` and handoff rev 79. The text below is the draft, written before AJ ran the paste. Do not treat "not applied" in this file as current state.

Drafted 2026-11-05 ~10:55 CT. At draft time, no command from that session had run on Johnny or on rock-box.

## Status

Handoff rev 78. Step 8 is **drafted, not applied**. Runbook: `docs/tool-install/step-8-thermal-soak.md`. AJ has not run the paste. CIS L1 totals unchanged: **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274).

Claude reviewed tip `5d97dad` APPROVE-WITH-NITS. The nit commit redirects the probe, idle, and soak `turbostat` calls and the `runuser` `stress-ng` call from the heredoc with `</dev/null`. `turbostat` is stopped with INT, about 15 seconds, TERM, KILL, then `wait`, in the main path and in `cleanup`. The heartbeat subshell is stopped before its `sleep` can keep the transcript pipe. `tmux new -s step8` is a suggestion when `tmux` is already installed. This step does not install it.

Claude's read-only check on Johnny, soak not started: all three `turbostat` paths present, capture map matched (`POLL` `C1_ACPI` `C2_ACPI` `C3_ACPI`), `TZ` `Etc/UTC`, `nproc` and `_NPROCESSORS_CONF` both 24, stress-ng `0.20.01`, `thermald` active. `--cpu 0` is every configured CPU.

MeshCommander cleanup on rock-box is **closed** (AJ, 2026-11-05): computer deleted, node killed, Chrome site data for `http://127.0.0.1:3000` cleared. This draft did not watch that desktop.

Next after AJ runs the soak: 9 EDAC, 12 signed UKI, IRQ affinity later. Those were not drafted here.

## Check on this draft

The paste was extracted and `bash -n` exited 0. A fixture file with the step 11 idle map returned success from the tuning check. An extra `C1E` state on CPU 2 returned the idle-name stop. CPU 0 with an extra state still passed. EPP other than `performance` on CPU 3 failed the check. The summary awk, on a two-interval sample, reported max `CoreTmp` 91, `PkgTmp` 78, `PkgWatt` 95.25, `CoreThr` 2, and `PKG_%` 3.50. A header with only `CPU` and `Busy%` produced `SOAK-NOTE-no-PkgWatt` and the other missing-column notes. Apt `Candidate: (none)` stops. `Installed: (none)` with a real candidate does not.

That check did not execute `stress-ng` or `turbostat`.
