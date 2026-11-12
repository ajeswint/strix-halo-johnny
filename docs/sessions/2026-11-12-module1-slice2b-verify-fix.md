# 2026-11-12 UTC: Module 1 Slice 2b Verify Fix

- **Date:** 2026-11-12 America/Chicago (~22:45 CT 2026-11-11 / ~04:45Z 2026-11-12)
- **Branch:** `claude/module1-slice2b-verify-fix`
- **Seats:**
  - Code-writer: Antigravity Gemini 3.8 Flash high (`gemini-3.8-flash-high`)
  - Adversarial-reviewer: Grok 4.7 high
- **Constraints Maintained:** No SSH to Johnny; no sudo executed; BPF object (`module1-xdp-records.o`) and systemd unit files untouched.

## Background & Real Evidence
- **Live State on Johnny:** Slice 2b was applied on Johnny on 2026-11-12T04:05Z (`j_xdp_records` driver mode id 192 attached, reader active writing `/var/lib/johnny/m1s2b/run-*.bin`, 35 MB in 7 min; slice 1c unit disabled).
- **Incident / Failure:** Paste 6 verify stopped at `STOP-no-traffic-verify` because the checker expected a JSON shape (`formatted.value.packets` / `formatted.value.seen`) that `bpftool -j map dump` does not emit for per-CPU arrays.
- **Evidence Files:**
  - `docs/findings/module1-slice2b/2026-11-12-evidence-johnny.txt` (verbatim `bpftool -j map dump` for `m1_stats`, `m2_ctl`, `m2_cfg`, reader journal)
  - `docs/findings/module1-slice2b/2026-11-11-cloud-audit.md`
  - `docs/findings/module1-slice2b/2026-11-11-apply-output.md`
- **AJ Decisions Recorded:** AJ chose Option A (2026-11-11 22:13 CT):
  - Rate: 8000 rec/s, burst 16000
  - Retention: 64 MiB / 3600 s, keep=6, 256 MiB reserve
  - MACs raw (defaults as applied)
- **Open Question Flagged for AJ:** Live evidence shows `m2_ctl` `rate_limited` 407,183 of 843,847 seen (~48.2%) over ~7 min even at 8000/16000. Flagged as an open question for AJ; rate left unchanged at 8000/16000.

## Fixes Implemented

1. **Ported Proven `percpu_from_json` into `module1-slice2b-boot.sh`**:
   - `dump_stats` and `ctl_rows` now use `percpu_from_json` (ported directly from `module1-slice2-records.sh`) to parse bpftool per-CPU array JSON: `{"formatted": {"key": K, "values": [{"cpu": N, "value": INT}]}}`.
   - Sums values across all active CPUs.
   - Attach and start paths remain completely byte-identical in behavior.
   - Updated pinned `READER_SHA256` to `fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573`.
   - New `module1-slice2b-boot.sh` sha256: `b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55`.

2. **Fixed `read_ctl` in `johnny-m1s2b-reader.py`**:
   - Loops over keys 0–5 individually with an `8 * ncpu` buffer, matching `johnny-m1s2-reader.py` (~line 237), unpacking and summing across CPUs.

3. **Fixed Reader mmap Failure Checks in `johnny-m1s2b-reader.py`**:
   - Compares consumer and ring mmap return values against `ctypes.c_void_p(-1).value` (18446744073709551615 on x86_64), not `-1`.
   - New `johnny-m1s2b-reader.py` sha256: `fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573`.

4. **Updated Self-Test (`module1-slice2b-self-test.sh`)**:
   - Mock `bpftool` emits fixtures extracted verbatim from `docs/findings/module1-slice2b/2026-11-12-evidence-johnny.txt` (`m1_stats`, `m2_ctl`, `m2_cfg`).
   - Removed all mock stubbing of `read_ctl`; tests `RotatingWriter` with `DummyBpf` lookup and directly verifies `read_ctl` and mmap `MAP_FAILED` handling.
   - Replaced all shared `/tmp/mock_*` paths with isolated per-run temporary directories (`mktemp -d`).
   - Added exact sum assertions on evidence fixtures:
     - `m2_ctl key0 seen = 164180 + 155070 + 220713 + 303884 = 843847`
     - `m2_ctl key2 rate_limited = 407183`
     - `m2_ctl key4 emitted = 436664`
     - `m1_stats key0 pkts = 843840`
     - `m1_stats key1 bytes = 922600250`
   - **Proof of Failure on Old Parser:**
     - Evaluated old parser logic against evidence fixtures: returned `pkts=0 bytes=0` and `seen 0` because it looked for `formatted.value.packets` and `formatted.value.seen` (which never exist for per-CPU arrays). The new test assertions fail immediately if run against the old parser.

5. **Updated Runbook (`module1-slice2b-boot-unit.md`)**:
   - Status updated: "2b applied on Johnny 2026-11-12T04:05Z; verify not yet passed (checker bug); 1c disabled".
   - Recorded AJ decisions and rate-limited observation.
   - Added section `## Verify-fix reinstall (2b already live)` with Pastes R1, R2, R3, R4 labeled `***<u>Run on Rock Box</u>***`.
   - Recorded previous installed hashes for rollback reference:
     - `module1-slice2b-boot.sh`: `650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2`
     - `johnny-m1s2b-reader.py`: `e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581`
   - Ensured all `ssh` commands avoid single quote nesting, using double quotes and escaped `\$`.
   - Updated all sha256 pins in runbook, self-test, and `boot.sh`.
   - Added `M1S2B-VERIFY-DONE` to Tokens list.

## Verification Results
- `bash docs/tool-install/module1-slice2b-self-test.sh`:
  - Output: `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=11`, `RUNBOOK-OK blocks=13`, `SELF-TEST-OK`.
- `shellcheck docs/tool-install/module1-slice2b-boot.sh docs/tool-install/module1-slice2b-self-test.sh`: clean (0 errors/warnings).
- `python3 -m py_compile docs/tool-install/johnny-m1s2b-reader.py`: clean.
