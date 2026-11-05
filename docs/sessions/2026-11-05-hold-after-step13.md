# Hold after step 13 (2026-11-05 ~14:30 CT)

AJ hold: Cursor tokens exhausted; second daily LLM usage spiking. Resume only on AJ go.

## Repo

- Base: `claude/practical-ritchie-4c6vvf`
- Step 13 merged: PR #10 merge `475bfe08`, nit tip `c08c642`, handoff **rev 87**
- CIS L1: **225 PASS / 18 PASS (manual) / 31 N/A / 0 FAIL**

## Applied on Johnny

- Steps **6, 8, 9, 11, 13** applied; step **12** research-complete (lab option A; option D research only)
- Paste tip `c765e01` → `STEP13-IRQ-DONE`, `NOTE-no-irqbalance`
- Live names `ice-eno1np0-TxRx-N` → all recorded IRQs on **CPU 1** (ice 187–201, irdma 217–229); `CPU0-CLEAR`
- `johnny-capture-irq.service` enabled, inactive (oneshot; helper run directly); live unit `9df4969f…` (no `Wants=`)
- Capture cores `1 2 3 4` hash `16fbd7d1…219bd`; eno3 `192.168.50.152`

## Next open (AJ go)

1. Name-match paste: accept `ice-eno1np0-TxRx-N`, spread TxRx queues across CPUs 1–4; leave irdma alone / restore from backup
2. Optional: deploy `Wants=network-online.target` unit; confirm oneshot under systemd
3. Do not re-run `c765e01`

## CLIs

- Killed rock-box `claude --chrome-native-host` and confirmed no `claude -p` / `cursor-agent` CLI
- Cursor IDE left running; cloud agents finished / cancelled (name-match draft `bc-466a36d4` cancelled)
