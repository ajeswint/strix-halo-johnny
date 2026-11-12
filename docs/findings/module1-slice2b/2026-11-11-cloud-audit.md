# Independent cloud audit (Claude Code cloud agent), 2026-11-11, relayed by AJ

Verdict: OS work solid; process drifted; slice 2b draft not ready to apply. Three defects, confirmed by running the code; the self-test can't see them. Nothing checked against live Johnny.

1. main is at handoff rev 52 (2026-11-04); real state is claude/practical-ritchie-4c6vvf (rev 109, 153 commits ahead, clean fast-forward). ~30 merged branches remain.
2. Slice 2b defects:
   - Verify can never pass: module1-slice2b-boot.sh dump_stats (l.328) and ctl_rows (l.293) parse a JSON shape bpftool doesn't emit; on real per-CPU output they return zeros, so verify always stops at no-traffic-verify (l.708). Fails closed.
   - Reader header counters wrong: johnny-m1s2b-reader.py read_ctl (l.274) looks up key 0 only; seen is right, the other five are always 0.
   - Failed mmap segfaults: reader l.242/246 compare to -1 but ctypes returns 18446744073709551615.
   - Self-test is circular: mock bpftool emits the invented shape (self-test l.287, 293) and stubs read_ctl (l.175).
   - Cause: 2b rewrote slice 2's proven percpu_from_json, read_ctl, and mmap check instead of reusing them.
3. Seat docs stale: AGENTS.md/README seats don't match; no reviewer named in session logs; Module 1 review findings not in docs/findings/.
4. docs/os-handoff.md is 144 KB (line 3 is a 42,000-char revision-history paragraph), ~40k tokens per session start; tools/relay/logs adds 78 files.
5. Smaller: product code under docs/tool-install/ instead of bpf/ and tests/; no retention/governance policy for persistent household metadata; per-queue sequence stored in per-CPU map.

Recommended order: (1) fast-forward main and delete merged branches; (2) send slice 2b back with the three defects; (3) split revision history out of the handoff; (4) fix AGENTS.md/README seats and require findings in docs/findings/.

Relay for the writer: don't rewrite; reuse slice 2. Port percpu_from_json and callers from module1-slice2-records.sh into dump_stats/ctl_rows (real shape {"formatted":{"key":K,"values":[{"cpu":N,"value":INT}]}}); read_ctl must look up keys 0-5 with an 8*ncpu buffer as in johnny-m1s2-reader.py l.237; compare mmap result to ctypes.c_void_p(-1).value; self-test mock must emit the real shape (fixtures at module1-slice1b-self-test.sh l.292-296), not stub read_ctl, not use shared /tmp/mock_*; re-pin sha256.
