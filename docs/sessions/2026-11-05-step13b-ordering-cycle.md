# Step 13b — ordering cycle found at first reboot

2026-11-05 America/Chicago. Handoff rev 89. Code-writer seat (rock-box checkout, no SSH write, no sudo). Branch `claude/step13b-irq-unit-cycle`, off tip `1d7c028`.

## Finding (AJ's paste, Johnny boot 2026-11-05 23:10:49Z, ~17:10 CT)

```
multi-user.target: Found ordering cycle: johnny-capture-irq.service/start after johnny-capture-tuning.service/start after multi-user.target/start - after johnny-capture-irq.service
multi-user.target: Job johnny-capture-irq.service/start deleted to break ordering cycle starting with multi-user.target/start
```

- Unit inactive/dead, enabled, `Wants=` count 1. Live unit `03ce0ceb…`, helper `29f0d0d2…`, equal to `1d7c028`.
- Pins at kernel defaults (TxRx 0–11, aux 0–23): the oneshot never ran.
- Cause: irq unit `After=… johnny-capture-tuning.service` + `WantedBy=multi-user.target`; tuning unit `After=multi-user.target`. A target is implicitly ordered after units it wants, which closes the loop.
- 13b's closeout had flagged the first reboot as the real test. It was.

## Drafted (not applied, not reviewed)

- `etc/systemd/system/johnny-capture-irq.service`: `After=network-online.target irqbalance.service`. New sha256 `a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a`. Tuning unit untouched.
- `docs/tool-install/step-13b-unit-cycle-fix.sh`: hash-gated, unit only, `daemon-reload`, `systemctl start`, name-matched IRQ verify, `STEP13B-IRQ-UNIT-CYCLE-FIXED`. Old unit saved once under `/var/lib/johnny/step13b-cyclefix-prev/`.
- Runbook § Ordering cycle: evidence, cause, paste, verify, rollback. 13b re-run paste retired.
- `step-13-irq-affinity.sh` and `step-13b-name-match.sh` pins moved to the new unit hash only because the self-test requires the unit hash in both; neither is to be run again. 13b script header says so.
- Self-test: cycle asserts added; prints `SELF-TEST-OK`.

## Open

Review of the unit-only paste, AJ runs it, then a reboot to confirm no `Found ordering cycle`. Johnny is not fixed until then. Session CSV not added (no Johnny session was run by this seat).
