# 2026-11-14 UTC: Module 1 Slice 2b XDP Rate Cap Removal (DRAFTED, NOT APPLIED)

- **Date:** 2026-11-14 America/Chicago
- **Status:** **DRAFTED, NOT APPLIED**
- **Branch:** `claude/module1-slice2b-no-ratecap`
- **Revision:** rev 114
- **Seats:**
  - Code-writer: Antigravity agy
  - Review: Awaiting adversarial-reviewer review
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

### Capacity & Reader Drain Micro-Benchmark
- **Ring buffer capacity:** 4 MiB ring buffer holds 4,194,304 / 88 B = 47,662 slots.
  - At average observed LAN rate (~300 pps): ring fills in ~158 seconds if reader is stalled.
  - At line rate 83k pps: ring fills in 574 ms if undrained.
  - At theoretical peak 1.488M pps: ring fills in 32 ms if undrained.
- **Reader hot-path micro-benchmark on Rock Box:**
  - Micro-benchmark simulated reader per-record loop: `ctypes` record copy (80 B) + sink buffer tracking + sequence tracking + write buffering + `statvfs` check.
  - Result: **1,480,183 records/s** sustained drain rate in user space.
  - If incoming traffic ever exceeds reader drain speed, `m2_ctl` increments `rb_full`, which is now an immediate fail-closed `STOP` in `verify`, `window`, and Paste W.
- **Ring buffer consumer pointer persistence across reader restart:**
  - `johnny-m1s2b-reader.py` mmaps `cons_addr` directly from the pinned BPF ring map page 0 (`/sys/fs/bpf/johnny_m1s2b/m2_rb`).
  - Kernel ring state and consumer offset persist in the pinned map across reader restarts.
  - Records emitted by XDP during the brief reader restart sit safely in the ring and are drained immediately upon startup without loss.

## Changes Implemented

1. **`docs/tool-install/module1-slice2b-boot.sh`**:
   - Centralized constants: `CFG_WANT="ver=1 sample_every=1 rate=1000000 burst=100000"` and `CFG_HEX="01 00 00 00 01 00 00 00 40 42 0f 00 a0 86 01 00"`.
   - Updated `write_and_verify_cfg` and `verify_attached_invariants` to assert new cfg.
   - Added `apply-cfg`: live update of `m2_cfg` map without detaching XDP or restarting capture service. Gated, locked, verifies attach state is records with prog id matching pin and full pin set, executes `write_and_verify_cfg`, writes baseline file `/root/m1s2b/no-ratecap-baseline.txt` (mode 0600) with UTC timestamp, `boot_id`, STATS line, and CTL rows, and prints `M1S2B-APPLY-CFG-DONE`. Idempotent (preserves existing baseline if already present).
   - Added `window SECS`: read-only (10..3600 s, default 60 s), snapshots CTL and STATS before and after sleep, outputs deltas, stops with `STOP-drops-in-window` if `rate_limited`, `rb_full`, or `discarded` delta > 0, else prints `OK-no-drops-window` and `M1S2B-WINDOW-DONE`.
   - Updated `do_verify`: computes drop deltas from before/after CTL snapshots, prints `VERIFY-DROPS`, and stops with `STOP-drops-in-verify-window` if any drop delta > 0.
   - Shellcheck clean.

2. **`docs/tool-install/module1-slice2b-boot-unit.md`**:
   - Added section `## Rate cap removal (2b already live)`.
   - Added Pastes A (read-only preflight), B (apply & reader restart), C (verify with drop gates), W (one-week validation gate), and Rate cap rollback, all labelled `***<u>Run on Rock Box</u>***`, with fail-closed checks, single-quoted ssh strings, and token echoes:
     - `M1S2B-NORC-PREFLIGHT-DONE`
     - `M1S2B-NORC-APPLY-DONE`
     - `M1S2B-NORC-VERIFY-DONE`
     - `M1S2B-NORC-WEEK-DONE`
     - `M1S2B-NORC-ROLLBACK-DONE`
   - Updated STOP codes table and token reference list.
   - Preserved all bash blocks outside the new section byte-identical to `17dbf85`.

3. **`docs/tool-install/module1-slice2b-self-test.sh`**:
   - Pinned new `WANT_BOOT_SHA` (`1f449f12...`).
   - Added static checks verifying hex decoding to `ver=1 sample_every=1 rate=1000000 burst=100000` and subcommand presence.
   - Added mock fixtures and scenarios:
     - Scenario 8: Clean verify, verify STOP on `rate_limited > 0`, verify STOP on `rb_full > 0`.
     - Scenario 12: `apply-cfg` happy path, 0600 baseline file creation, idempotency, and refusal when not attached.
     - Scenario 13: `window` zero deltas pass, STOP on `rate_limited > 0`, STOP on `rb_full > 0`, STOP on `discarded > 0`.
   - Section 6 runbook block validator audits 22 blocks and confirms all blocks 0..16 are byte-identical to base commit.
   - Shellcheck clean.

## Hash Summary

| File | sha256 | Status |
|---|---|---|
| `docs/tool-install/module1-xdp-records.o` | `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481` | Unchanged |
| `etc/systemd/system/johnny-capture-xdp-records.service` | `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a` | Unchanged |
| `docs/tool-install/johnny-m1s2b-reader.py` | `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37` | Unchanged |
| `etc/systemd/system/johnny-m1s2b-reader.service` | `e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c` | Unchanged |
| `docs/tool-install/module1-slice2b-boot.sh` | `1f449f12a0975f05005e16703f96dc21a5a133b10608c3506dbe49e670f3989d` | Updated |

## Verification Result

- `bash docs/tool-install/module1-slice2b-self-test.sh`:
  - `PINS-OK`
  - `SHELLCHECK-OK`
  - `STATIC-CHECKS-OK`
  - `READER-TESTS-OK`
  - `E2E-OK scenarios=13`
  - `RUNBOOK-OK blocks=22`
  - `SELF-TEST-OK`
- `shellcheck docs/tool-install/module1-slice2b-boot.sh docs/tool-install/module1-slice2b-self-test.sh`: clean (exit code 0, no output)
