# 2026-11-06 — step 13d: eno3 wait after the third reboot (draft)

Seat: code-writer (Sonnet, medium). Branch `claude/step13d-eno3-wait`, PR against `claude/practical-ritchie-4c6vvf`. rock-box edits only. No SSH write to Johnny. Nothing applied.

**Johnny evidence (AJ reboot proof, boot 2026-11-06 01:00:55Z).** `CYCLE 0`. `johnny-capture-irq.service` failed. Journal: `NOTE-wait-eno1 try=0 … oper=down`, then about 2s later `STOP-eno3-addr`; no `STOP-eno1-link`. Pins stayed at kernel defaults. After boot eno3 had `192.168.50.152/24` and the default route; manual start works. The 13c paste (`STEP13B-ENO1-WAIT-FIXED`) had passed on a live system.

**Cause (hypothesis, fits the journal; not traced).** The eno1 wait returned quickly; `ip` did not yet show eno3's address, and `preflight` had a hard `STOP-eno3-addr` with no wait. `network-online.target` does not guarantee that check.

**Change.** `wait_eno1_link` becomes `wait_boot_ready`: one shared 100s loop (50 x 2s) polling eno1 link+flags and eno3 addr/route/admin-up (`NOTE-wait-eno1`, `NOTE-wait-eno3 try=N why=…`). Hard `STOP-eno1-*` and `STOP-eno3-*` still follow on timeout (eno3 via `eno3_ok`). Tuning stays `NOTE-tuning-*` only; no `After=tuning` (no new ordering edge, cycle risk none); tuning unit untouched. Unit: comment-only change, `TimeoutStartSec=150` (100s wait + 50s slack). New apply script `step-13d-eno3-wait.sh` (`STEP13B-ENO3-WAIT-FIXED`), hash-gated on the 13c blobs. Self-test extended (eno3 missing then appears; eno1-up/eno3-bad times out with `NOTE-wait-eno3`): `SELF-TEST-OK`.

**Nits from PR #14.** Runbook machines table said `TimeoutStartSec=210` (now 150); stray double backtick before `STOP-prev-hash` fixed. 13c/13d "live now" rows updated.

**Open.** Johnny is not fixed until AJ runs the 13d paste after APPROVE and a later reboot shows `active` + spread with no manual start. Handoff rev 91; row 9 added to the step 13 session CSV.
