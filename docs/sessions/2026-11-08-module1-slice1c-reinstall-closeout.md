# 2026-11-08 UTC (~01:15 to ~01:21 America/Chicago): Module 1 slice 1c rev 3 boot helper reinstalled on Johnny (closeout)

Seat: code-writer (Claude Code). Branch `claude/module1-slice1c-reinstall-closeout`, from `origin/claude/practical-ritchie-4c6vvf` tip `ef6e6fc` (PR #28 merged there). Docs-only closeout. **No SSH, no sudo, no write on Johnny in this closeout.** No deployed helper (`module1-slice1c-boot.sh`, attach, detach), `.service`, or `.o` file changed; no sha256 pin changed. The rock-box self-test gained one runbook check.

**What AJ ran (from rock-box to Johnny).**
- **Paste 1** on the rev 3 branch: `E2E-OK scenarios=8`, `RUNBOOK-OK blocks=8`, **`SELF-TEST-OK`**.
- **Nits reinstall (rev 3)** at **2026-11-08 07:15:55 UTC (1:15:55 AM CST)**: hashes OK; installed `/root/m1s1b/module1-slice1c-boot.sh` sha256 `a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06`; `verify` `OK-xdp-mode driver id=75` before and after, IRQ pins unchanged, `l3_diff=0 l4_diff=0`, 5 s window `xdp=443 tcpdump=345 pct=77` `NOTE-pass-ratio-low`, kernel drops `0`, NIC drops `0`, `ETHTOOL-DROP-DELTAS none`, `M1S1C-VERIFY-DONE`, **`M1S1C-NITS-REINSTALL-DONE`**.
- No reboot, no unit restart, no Rollback.

**Not claimed.** 77 % is one observed 5 s window (earlier windows 90, 87, 84), not a normal value; zero drops were measured in that window only, not proof of lossless capture. The rev 3 fail-closed `start` path has not run at a boot; an optional later reboot + Paste 6 would prove it (the 02:26 UTC cold boot passed on the rev 2 helper). Not a required step.

**Docs changed (nits N1–N4).** N1: handoff heading said rev 102 at rev 103; now rev 104. N2: handoff Next steps: nits fixed and reinstalled; next is AJ's choice of Module 1 slice. N3: Paste 6 wait loop no longer sleeps after its final sample (`if [ "$w" -lt 120 ]; then sleep 5; fi`), so the `active` gate reads a sample taken at 120 s; still fail closed; self-test now rejects the old form. N4: Paste 5 prose rewritten to match Paste 6's wait (`STOP-locked` from the start race no longer expected; what `STOP-unit-not-active-after-wait state=failed|activating` means). Files: `docs/tool-install/module1-slice1c-boot-unit.md` (rev 4), `docs/tool-install/module1-slice1c-self-test.sh`, `docs/os-handoff.md` (rev 104), `README.md`, this note and its CSV.

**Next Module 1 step (identified, not started).** AJ chooses the next slice: header-only ringbuf records, symmetric RSS, or AF_XDP evaluation (`docs/tool-install/module1-slice1b-attach.md` § Not decided here, items 4–5; `docs/tool-install/module1-slice1-span-xdp.md` open questions).
