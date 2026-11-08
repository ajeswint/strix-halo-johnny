# 2026-11-08 UTC (2026-11-07 ~20:26 to ~20:33 America/Chicago): Module 1 slice 1c boot persistence unit applied on Johnny

Seat: code-writer (Claude Code). Branch `claude/module1-slice1c-closeout`, from `origin/claude/practical-ritchie-4c6vvf` tip `781ca6f` (PR #26 merged there). Docs-only closeout. **No SSH, no sudo, no write on Johnny in this closeout.** No `.sh`, `.service`, or `.o` file or sha256 pin changed.

**What AJ ran (from rock-box to Johnny).**
- **Pastes 1–4**: ran; per-token output not supplied to this closeout **[not recorded here]**.
- **Paste 5**: **`M1S1C-REBOOT-ISSUED`**, cold reboot.
- **Boot**: `johnny-capture-irq.service` `PIN-OK`, `ENO3-OK`, `CPU0-CLEAR`, `CAPTURE-CPUS 1 2 3 4` (TxRx-0..11 round-robin on CPUs 1–4); then `johnny-capture-xdp.service` `M1S1C-START-BEGIN DATE-UTC 2026-11-08T02:26:28Z`, all hashes OK, `OK-link` 10000 carrier=1 up, `ATTACHED xdpdrv prog_id=75`, `OBS-WINDOW xdp-pps=186 PASS-RATIO 87 nic-rx-dropped-delta=7` (NOTE, baseline 0), `M1S1B-ATTACH-DONE`, `STATE attached by boot helper (xdpdrv prog_id=75)`, `M1S1C-START-DONE`; unit `active (exited)` since 02:26:47 UTC, `status=0`.
- **Paste 6, first try**: `verify` ran ~20 s after boot while the unit's `start` held the helper lock: `STOP-locked`, no done token.
- **Paste 6, rerun at uptime 2 min**: `systemctl is-system-running` = `running`, `OK-no-ordering-cycle-warnings`; `verify` `OK-unit` enabled/active, `OK-tuning-service active`, `OK-xdp-mode driver id=75`, IRQ pins unchanged, `l3_diff=0 l4_diff=0`, `VERIFY-WINDOW xdp-pkts-delta=1182 tcpdump-kernel-drops=0 nic-rx-dropped-delta=0 PASS-RATIO 84`, `ETHTOOL-DROP-DELTAS none (checked=16)`, `M1S1C-VERIFY-DONE`; `status` `XDP-ATTACH driver id=75`, `PROG-XDP-COUNT 1`, `PROG-OURS 1 ids=75`, PINS all present, `IRQ-COUNT 12`, `IRQ-CAPTURE ok`, `IRQ-BASELINE same`, `STAT pkts 25189 trunc 0 vlan 0`, `PART diff 0`, `KERNEL 7.0.0-42-generic`, `M1S1B-STATUS-DONE`, `M1S1C-STATUS-DONE`, **`M1S1C-COLD-BOOT-VERIFY-DONE`**.
- **Rollback**: not run.

**State.** Slice 1b's `prog_id=472` (this-boot only) is gone; `prog_id=75` is the boot-attached observer.

**Docs changed.** `docs/tool-install/module1-slice1c-boot-unit.md` (rev 2, applied + evidence + follow-ups); `docs/tool-install/module1-slice1b-attach.md` (rev 3 note; current-tense boot-only / reboot-clears sentences in the status, plain-English, apply-record, scope, STOP-rollback-failed, manual-detach and id-assumption text rewritten to point at the slice 1c unit and Rollback block; the unchanged script's printed reboot sentence is quoted as stale); `docs/tool-install/module1-slice1-span-xdp.md` (banner/status); `README.md`; `docs/os-handoff.md` (rev 102); this note and its CSV.

**Parked follow-ups (no code change).** `wait_boot_ready || true` fall-through; Paste 6 cycle `grep` does not gate the done token; rollback token prints even if the unit was never active; Paste 6 should wait for the unit to be `active` before `verify` (the `STOP-locked` race).
