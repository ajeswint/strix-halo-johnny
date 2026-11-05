# Step 13 — IRQ affinity (applied)

Applied 2026-11-05 America/Chicago. Handoff rev 87. Closeout commit `e0a7c42` is 2026-11-05 20:19:35Z (~14:19 CT), after `b19ab07` at 20:13:58Z. CSV times in `Johnny_Step13_Session_Log_2026-11-05.csv` are those commit times, in order. The Johnny paste clock was not in the summary. AJ's paste printed `STEP13-IRQ-DONE`. The paste was tip `c765e01`. **[Inference]** AJ's scp file sizes matched that tip. This repo does not store that listing. Soft nits in `b19ab07` did not run and do not require a re-run. This closeout did not SSH to Johnny. The raw log stays at `/root/step13-apply.log`.

## Result

`CAPTURE-CPUS 1 2 3 4`. `OK-tuning`. `NOTE-no-irqbalance`. No `IRQ-HELD`. PCI `eno1np0` `0000:01:00.0`, `eno2np1` `0000:01:00.1`. RX and TX queues 12. RPS and XPS `000000`. `eno2np1` IRQs 204–215 were `NOTE-eno2-unrequested`.

Live IRQ names are `ice-eno1np0-TxRx-0` through `11`, `ice-0000:01:00.0:misc`, `ll_ts`, `ctrl-TxRx-0`, and `irdma-0000:01:00.0-*`. The script matched only `eno1np0-TxRx-N` with no `ice-` prefix, so every vector was `NOTE-irq-fallback` and landed on CPU 1. irdma names also printed `NOTE-irq-name`. Ice IRQs 187–201 and irdma IRQs 217–229 have `smp_affinity_list` 1 and `effective_affinity_list` 1. CPUs 2, 3, and 4 received none of these. `CPU0-CLEAR` is still true.

`ENO2-IRQ-UNCHANGED`. `ENO3-OK`. `LOCKDOWN-UNCHANGED` (`none[integrity]confidentiality`). Helper line 28 printed `printf: write error: Broken pipe` during the pin. SIGPIPE is ignored. The run still printed `STEP13-IRQ-DONE`.

rock-box `sudo -v` failed three times (wrong password for that host). Johnny `ssh -t` sudo succeeded on the retry. No password is stored.

## Verify

Same day, read-only from rock-box. `HOST johnny`. `KERNEL 7.0.0-42-generic`. Tuning `active enabled`. `IRQUNIT inactive enabled`: the unit is enabled, and systemd has not started the oneshot, because the paste ran the helper itself. **[Inference]** A later boot would start it after `network-online.target`. The unit has not run under systemd, and there has been no reboot since this paste. `IRQBALANCE inactive`. `eno3` `192.168.50.152/24`. Default via `192.168.50.1` dev `eno3`. `ip -br link show eno1np0 eno2np1 eno3` failed (`eno2np1` is garbage). The corrected read is one `ip -br link show dev` per name. That corrected command was not re-run for this note. IRQs 187–201 and 217–229 confirm CPU 1.

## Not on Johnny

`b19ab07` adds `Wants=network-online.target` to the repo unit. The installed unit is the `c765e01` file, sha256 **[Inference]** `9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355`. This closeout did not re-hash the live files. The paste hashes before install and reached `STEP13-IRQ-DONE`.

## Open

A later paste, after Claude reviews this closeout, should accept `ice-eno1np0-TxRx-N` so the twelve queues can use CPUs 1–4, and should not pin `irdma-` completion queues via the fallback. No new paste is in this closeout. Do not re-run `c765e01`.

CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Steps 6, 8, 9, 11, and 13 are applied. Step 12 stays research-complete. Not merged.
