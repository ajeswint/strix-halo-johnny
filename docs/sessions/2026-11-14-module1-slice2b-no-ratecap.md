# 2026-11-14 UTC: Module 1 Slice 2b XDP Rate Cap Removal (DRAFTED, NOT APPLIED)

- **Date:** 2026-11-14 America/Chicago
- **Status:** **DRAFTED, NOT APPLIED (Review 1 fixes incorporated)**
- **Branch:** `claude/module1-slice2b-no-ratecap`
- **Revision:** rev 114
- **Seats:**
  - Code-writer: Antigravity agy
  - Review: Adversarial review 1 (REQUEST-CHANGES on `6995a32`, Grok 4.7 high) addressed in full (B1–B4, N1–N4)
- **Constraints Maintained:**
  - Never SSH to Johnny (192.168.50.152); no sudo executed; no network contact with Johnny.
  - Do not kill or touch any other `agy` or `cursor-agent` process.
  - No secrets in repo.
  - No BPF rebuild: `module1-xdp-records.o` (`a73c5bd2...`) unchanged.
  - Reader and retention deployables untouched: `johnny-m1s2b-reader.py` (`476cf867...`), `johnny-m1s2b-reader.service` (`e5c16249...`), and `johnny-capture-xdp-records.service` (`4e2e359d...`) remain byte-identical.
  - Runbook bash blocks outside the new section remain byte-identical to `17dbf85`.

## Goal & Design Rationale

AJ approved removing the Module 1 slice 2b XDP rate-limit cap to record ALL mirrored LAN traffic for 1 week uninterrupted, followed by a formal 7-day validation gate.

### BPF Rate-Limiter Analysis
Inspection of `module1_xdp_records.c` (`admit()` function):
1. `rate == 0` turns records OFF completely (`if (rate == 0) return 0;`), not unlimited.
2. There is no bypass flag in the BPF code.
3. Rates and bursts are clamped at configuration load to compiled maxima:
   - `M2_RATE_MAX = 1000000` records/sec per CPU.
   - `M2_BURST_MAX = 100000` records per CPU.
4. Token bucket state (`m2_state`) is allocated per-CPU (`BPF_MAP_TYPE_PERCPU_ARRAY`).
5. Setting `m2_cfg` to `ver=1 sample_every=1 rate=1000000 burst=100000` (hex `01 00 00 00 01 00 00 00 40 42 0f 00 a0 86 01 00`) unlocks up to 1,000,000 records/sec per CPU across Johnny's 12 queues / 4 capture cores, far exceeding 1 Gbps port-mirror line rate (~1.488M pps at min-size 64 B frames, ~81k pps at 1500 B frames) except under a pathological single-queue flood.

### Capacity & Reader Drain Micro-Benchmark (N1 / Discarded Note)
- **Ring buffer capacity:** 4 MiB ring buffer holds 4,194,304 / 88 B = 47,662 slots.
  - At average observed LAN rate (~300 pps): ring fills in ~158 seconds if reader is stalled.
  - At line rate 83k pps: ring fills in 574 ms if undrained.
  - At theoretical peak 1.488M pps: ring fills in 32 ms if undrained.
- **Reader drain throughput:**
  - Micro-benchmark loop committed as `docs/tool-install/module1-slice2b-drain-bench.py` (46 lines): simulated reader per-record loop with `ctypes` record copy (80 B) + sink buffer tracking + sequence tracking + write buffering + `statvfs` check.
  - Rock Box (Ryzen 9 9900X) userspace loop ~1.48M rec/s, not measured on Johnny; the Johnny reader is one thread with CPUQuota=50%, CPUAffinity=0, Nice=10, IOSchedulingClass=idle, so its real drain is lower and unmeasured; sustained admits above it show as `rb_full`, which `verify`, `window`, and `week` now STOP on.
  - `m2_ctl.discarded` is reserved / not incremented by the kernel path (not to be described as reader's ring-discard counter; ring drops in kernel show as `rb_full`).
- **Ring buffer consumer pointer persistence across reader restart:**
  - `johnny-m1s2b-reader.py` mmaps `cons_addr` directly from the pinned BPF ring map page 0 (`/sys/fs/bpf/johnny_m1s2b/m2_rb`).
  - Kernel ring state and consumer offset persist in the pinned map across reader restarts; records admitted during the restart are drained immediately upon startup provided total admitted during the window does not exceed 4 MiB (47,662 slots), else `rb_full` increments.

## Changes Implemented (Review 1 Fixes: B1–B4, N1–N4)

1. **`docs/tool-install/module1-slice2b-boot.sh`**:
   - Centralized constants: `CFG_WANT="ver=1 sample_every=1 rate=1000000 burst=100000"` and `CFG_HEX="01 00 00 00 01 00 00 00 40 42 0f 00 a0 86 01 00"`.
   - Updated `write_and_verify_cfg` and `verify_attached_invariants` to assert new cfg.
   - Added `apply-cfg`: live update of `m2_cfg` map without detaching XDP or restarting capture service. Gated, locked, verifies attach state is records with prog id matching pin and full pin set, executes `write_and_verify_cfg`, writes baseline file `/root/m1s2b/no-ratecap-baseline.txt` (mode 0600) with UTC timestamp, `boot_id`, XDP records prog id, STATS line, and CTL rows, and prints `M1S2B-APPLY-CFG-DONE`. Idempotent (preserves existing baseline if already present).
   - Added `mark-reader`: executed by Paste B after reader service restart. Appends `READER-INVOCATION`, `READER-NRESTARTS`, `READER-MAINPID`, and `READER-MARK-DATE-UTC` to baseline file. Gated, locked, refuses if baseline missing, idempotent (prints `READER-MARK-EXISTS` if already present), prints `M1S2B-MARK-READER-DONE`.
   - Added `week`: read-only subcommand running as root without locks, never writes. Supports optional `--precheck`. Fail-closed validation checks:
     - Baseline file existence and completeness (`STOP-baseline-missing`, `STOP-baseline-incomplete`).
     - Boot ID matches baseline (`STOP-rebooted-since-apply`).
     - XDP records prog ID matches baseline (`STOP-xdp-reattached-since-apply`).
     - Reader InvocationID and NRestarts match baseline mark, Result is success (`STOP-reader-restarted-since-apply`).
     - CTL keys present; drop deltas (`rate_limited`, `rb_full`, `discarded`) == 0 (`STOP-drops-since-apply`).
     - No counter deltas negative (`STOP-counter-went-backwards`).
     - Parses start timestamps from `run-%Y%m%dT%H%M%SZ.bin` and `run-<stamp>-NN.bin`, retaining only files with `start >= baseline DATE-UTC`.
     - File count >= 168, total span >= 604800 s, first file delay <= 3700 s (`STOP-coverage-short`).
     - No consecutive post-baseline start gap > 3700 s (`STOP-gap-detected`).
     - Newest file mtime <= 3700 s ago (`STOP-reader-stale`).
     - `journalctl` reader check error-free, fails closed on journalctl execution error (`STOP-journal-unreadable`, `STOP-reader-journal-errors`).
     - Output directory bytes <= 200 GiB (`STOP-out-dir-bytes-exceeded`), free space >= 100 GiB reserve (`STOP-free-space-below-reserve`).
     - Prints summary line and `M1S2B-WEEK-DONE`.
   - Updated `status`: dumps `BASELINE ...` lines if baseline file exists.
   - Updated `window SECS`: read-only (10..3600 s, default 60 s), snapshots CTL and STATS before and after sleep, outputs deltas, stops with `STOP-drops-in-window` if `rate_limited`, `rb_full`, or `discarded` delta > 0, else prints `OK-no-drops-window` and `M1S2B-WINDOW-DONE`.
   - Updated `do_verify`: computes drop deltas from before/after CTL snapshots, prints `VERIFY-DROPS`, and stops with `STOP-drops-in-verify-window` if any drop delta > 0.
   - Shellcheck clean.

2. **`docs/tool-install/module1-slice2b-boot-unit.md`**:
   - Added section `## Rate cap removal (2b already live)`.
   - Updated intro prose and Assumption 3 per N2 to reflect 1M/100k cfg and applied rev 113 retention (1 GiB, 200 GiB, 100 GiB reserve, MemoryMax=1G).
   - Pastes:
     - Paste A: preflight read-only checks.
     - Paste B: apply cfg, restart reader, run `mark-reader`, verify new CFG.
     - Paste C: verify with drop gates, verify reader mark in baseline via `status`.
     - Paste W: simplified root validation invoking `boot.sh week` and `boot.sh status`, gating `M1S2B-NORC-WEEK-DONE`.
     - Rollback: restores old CFG (8000/16000) and removes `/root/m1s2b/no-ratecap-baseline.txt`.
   - Updated STOP codes table with all new STOP strings.
   - Preserved all 17 bash blocks outside the new section byte-identical to `17dbf85`.

3. **`docs/tool-install/module1-slice2b-self-test.sh`**:
   - Pinned new `WANT_BOOT_SHA` (`a4d4dfa4...`).
   - Added static checks verifying `mark-reader` and `week` subcommands.
   - Added mock fixtures and scenarios (15 scenarios total):
     - Scenario 8: Clean verify, verify STOP on `rate_limited > 0`, `rb_full > 0`, and `discarded > 0` (N4).
     - Scenario 12: `apply-cfg` happy path, 0600 baseline file creation, idempotency, and refusal when not attached.
     - Scenario 13: `window` zero deltas pass, STOP on `rate_limited > 0`, `rb_full > 0`, `discarded > 0`.
     - Scenario 14: `mark-reader` refusal without baseline, happy path, idempotency.
     - Scenario 15: `week` comprehensive coverage (15a-15q): baseline missing, incomplete, reboot, reattach, reader restarted (invocation/nrestarts/result), counter backwards, drop delta, coverage short (count < 168, pre-baseline excluded, first-file delay > 3700, span < 604800), gap > 3700, stale mtime, journalctl failure, journal errors, du > 200 GiB, df < 100 GiB reserve, precheck flag, status baseline dump, and happy path.
   - Section 6 runbook validator:
     - N3: Diffs all 17 bash fences outside the Rate cap section against `git show 17dbf85:docs/tool-install/module1-slice2b-boot-unit.md` (emits `OUTSIDE-FENCE-DIFF-OK blocks=17`).
     - Audits 22 blocks and confirms all tokens and sha256 gates match.
   - Shellcheck clean.

## Hash Summary

| File | sha256 | Status |
|---|---|---|
| `docs/tool-install/module1-xdp-records.o` | `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481` | Unchanged |
| `etc/systemd/system/johnny-capture-xdp-records.service` | `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a` | Unchanged |
| `docs/tool-install/johnny-m1s2b-reader.py` | `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37` | Unchanged |
| `etc/systemd/system/johnny-m1s2b-reader.service` | `e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c` | Unchanged |
| `docs/tool-install/module1-slice2b-boot.sh` | `a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb` | Updated (Rev 114) |
| `docs/tool-install/module1-slice2b-drain-bench.py` | `52150476d1c004698ae7f7384329bd448e946455d3d2624f99ec4083cfc037a2` | New (46 lines) |

## Verification Result

- `bash docs/tool-install/module1-slice2b-self-test.sh`:
  - `PINS-OK`
  - `SHELLCHECK-OK`
  - `STATIC-CHECKS-OK`
  - `READER-TESTS-OK`
  - `E2E-OK scenarios=15`
  - `OUTSIDE-FENCE-DIFF-OK blocks=17`
  - `RUNBOOK-OK blocks=22`
  - `SELF-TEST-OK`
- `shellcheck docs/tool-install/module1-slice2b-boot.sh docs/tool-install/module1-slice2b-self-test.sh`: clean (exit code 0, no output)
