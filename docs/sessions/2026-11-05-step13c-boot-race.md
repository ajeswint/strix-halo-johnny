# 2026-11-05 — step 13c: boot race after the cycle fix (draft)

Seat: code-writer (Sonnet, medium). Branch `claude/step13c-eno1-wait`, PR against `claude/practical-ritchie-4c6vvf`. rock-box edits only. No SSH write to Johnny. Nothing applied.

**Johnny evidence (AJ, boot 2026-11-05 23:36:59Z).** `CYCLE 0`, unit sha `a191cdbb…`. `johnny-capture-irq.service` failed: `STOP-eno1-link speed= flags=0x1002 carrier= oper=down`, plus `tr: … Invalid input` from empty sysfs while link-down. Manual start after link-up gave `PIN-OK`.

**Cause.** `eno3` satisfies `network-online.target` before `eno1np0` is up; tuning (`After=multi-user.target`) may also start after the irq oneshot, so `STOP-tuning` would be next.

**Change.** Helper waits (bounded): eno1 link 100s, tuning `active` 60s; `read_trim` silent; unit `TimeoutStartSec=210`. No `After=` on tuning (cycle), tuning unit untouched, no `Restart=`. New apply script `step-13c-eno1-wait.sh` (`STEP13B-ENO1-WAIT-FIXED`). Self-test extended (stubbed sysfs/systemctl, no sleeps): `SELF-TEST-OK` on rock-box.

**Open.** Johnny is not fixed until AJ runs the 13c paste after APPROVE and a later reboot shows `active` + spread without a manual start. Handoff rev 90. Row 4 added to the step 13 session CSV.
