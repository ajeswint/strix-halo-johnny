# Module 1 slice 2b review and apply records

## Summary

Module 1 port-mirror sniffing is **COMPLETE**.

- **Applied:** Slice 2b applied on Johnny 2026-11-12T04:05Z. Pastes 1–5 passed; initial Paste 6 verify stopped at `STOP-no-traffic-verify` due to a checker bug parsing per-CPU map JSON.
- **Verified:** Reinstall Pastes R1–R4 applied after verify fix (PR #34, `6891fa3`). Paste R4 verify passed: xdp 491 vs tcpdump 426 (operator-reported by AJ in chat; transcript not saved), no NIC drops.
- **Cold-Boot Proven:** 2026-11-12 ~05:54Z (see [`2026-11-12-cold-boot-verify.md`](2026-11-12-cold-boot-verify.md)). All deployable and system hashes OK; native-XDP driver mode `prog_id=78` (`j_xdp_records`); both units (`johnny-capture-xdp-records.service`, `johnny-m1s2b-reader.service`) enabled and active; slice 1c `johnny-capture-xdp.service` disabled and inactive; PASS-RATIO 80% (tcpdump 3141 / xdp 3882); `ETHTOOL-DROP-DELTAS none (checked=16)`; BPF map `m2_ctl` counters: seen 33436, sampled_out 0, rate_limited 0, rb_full 0, emitted 33436, discarded 0; `M1S2B-COLD-BOOT-VERIFY-DONE`.
- **Runbook Gate Fix:** First Paste 8 run hit a false positive because `sudo journalctl -b --grep "ordering cycle" -q` matched sudo's own logged command line and opened a pager. Corrected to filter PID 1 messages with `--no-pager` (`cyc=$(sudo journalctl -b --no-pager -q _PID=1 -o cat | grep -ci "ordering cycle" || true)`).
- **Rate-Limiting Observation:** Rev 110 flagged an open question about ~48.2% rate_limited at 8000/16000 over ~7 min. In the cold boot run at the same 8000/16000 configuration, `rate_limited` was 0 across 33,436 seen packets. Rate is left configured at 8000/16000; still AJ's call whether to revisit.
- **Optional Future Add-ons (not started):** Symmetric RSS, AF_XDP.

## Review History

Earlier seat records (review1 on 8fdbea9, review2 on b906d89, review3 first launch) lived in /tmp/johnny-seats/ on Rock Box and were lost when Rock Box rebooted on 2026-11-11. Their verdicts, from the operator journal:

- review1, Grok 4.7 high, tip 8fdbea9: REQUEST-CHANGES. B1 rollback predicate couldn't see the j_xdp_observe name in bpftool net show; B2 Paste 5 disabled 1c before hash-checking installed files; B3 cold-boot IRQ baseline compared IRQ numbers; nits N1-N5.
- review2, Grok 4.7 high, tip b906d89: REQUEST-CHANGES. A single blocker: nested single quotes in the rollback ssh -t '...' broke grep/awk so M1S2B-ROLLBACK-DONE never printed.
- review4, Grok 4.7 high, tip 0815d9b: APPROVE (see `2026-11-11-review4-grok-0815d9b.md`). PR #33 squash-merged as `b4c475d`.

Seats used on 2026-11-11/12: writer = Antigravity agy, Gemini 3.8 Flash high (fresh conversation per seat); reviewer = Grok 4.7 high via cursor-agent.

Apply result on Johnny: see `2026-11-11-apply-output.md` and `2026-11-12-evidence-johnny.txt`.
Cold-boot verification transcript: see `2026-11-12-cold-boot-verify.md`.
