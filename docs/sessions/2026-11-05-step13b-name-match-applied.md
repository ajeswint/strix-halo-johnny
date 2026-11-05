# Step 13b — name match (applied)

Applied 2026-11-05 America/Chicago. Handoff rev 88. PR #11 (`claude/step13b-name-match`), not merged. Paste tip `bf89820`. AJ's paste printed `STEP13B-NAME-MATCH-DONE`. Johnny install time of the helper and unit is 21:03:23Z (~15:03 CT), read over read-only SSH. This closeout used no sudo and did not re-run the paste. Rows 5 to 7 are in `Johnny_Step13_Session_Log_2026-11-05.csv`.

## Result

- `ice-eno1np0-TxRx-0..11` (IRQs 189–200) on CPUs `1,2,3,4,1,2,3,4,1,2,3,4`. `SPREAD-COUNT cpu1=3 cpu2=3 cpu3=3 cpu4=3`.
- `misc` 187 and `ll_ts` 188 and `ctrl-TxRx-0` 201 on CPU 1 (`NOTE-irq-aux` three times).
- irdma 217–229: `NOTE-irdma-skip` 13 times, then written back to `0-23` from the first-run TSV (`IRDMA-RESTORED`). They are intentionally not on the capture CPUs.
- `ENO2-IRQ-UNCHANGED` (IRQs 204–215 unrequested), `ENO3-OK`, `PIN-OK`, `LOCKDOWN-UNCHANGED`, queues RX/TX 12, `RPS/XPS 000000`.
- The `bf89820` script printed `CPU0-CLEAR`, an unconditional echo. It is not a claim about irdma.

## Live state (read-only SSH, 21:06Z)

Helper `29f0d0d2…5530` (NEW), unit `03ce0ceb…2c6a` (NEW, `Wants=network-online.target`), `step13b-prev/` has the `c765e01` helper `77b899e3…` and unit `9df4969f…`, `/home/aj/cis-audit/step-13b-name-match.sh` is the `bf89820` script `da03abac…`. Unit `inactive` / enabled. Johnny booted at 16:07Z, before the apply.

## Nits

Six soft nits from the adversarial review (`APPROVE-WITH-NITS`) are in `82962b8`: entry-copy rollback, `ICE-CPU0-CLEAR`, `cpulist_flat` fails on a bad spec, hash-checked paste, `STOP-queue-count` and `STOP-spread-sum`, per-run log. They changed the 13b script and the self-test only. They did not run on Johnny. Johnny already succeeded on `bf89820`.

## Open

First reboot: check `Wants=network-online.target` and the helper under systemd. Block in `docs/tool-install/step-13-irq-affinity.md` § After the next reboot.
