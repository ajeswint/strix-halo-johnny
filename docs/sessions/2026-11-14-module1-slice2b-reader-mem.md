# 2026-11-14 UTC: Module 1 Slice 2b Reader MemoryMax 128M -> 1G in Retention Draft (DRAFTED, NOT APPLIED)

- **Date:** 2026-11-14 America/Chicago
- **Status:** **DRAFTED, NOT APPLIED**
- **Branch:** `claude/module1-slice2b-reader-mem`
- **Revision:** rev 113
- **Seats:**
  - Code-writer: Antigravity agy (Gemini 3.8 Flash high)
  - Review: Review 2 nits addressed
- **Constraints Maintained:** No SSH to Johnny; no sudo executed; no contact with 192.168.50.152; no secrets in repo; BPF object (`module1-xdp-records.o`), reader python (`johnny-m1s2b-reader.py`), and XDP unit (`johnny-capture-xdp-records.service`) unchanged.

## Scope of Changes (Rev 113)

1. **Reader Memory Limit Raised (`etc/systemd/system/johnny-m1s2b-reader.service`)**:
   - Raised `MemoryMax=128M` to `MemoryMax=1G` (1 GiB = 1073741824 bytes).
   - Kept `MemorySwapMax=0`.
   - Verified with `systemd-analyze verify`.

2. **Boot Helper Updated (`docs/tool-install/module1-slice2b-boot.sh`)**:
   - Updated `R_UNIT_SHA256` constant to match new unit hash.
   - Shellcheck clean.

3. **Runbook Updated (`docs/tool-install/module1-slice2b-boot-unit.md`)**:
   - Pinned new hashes in the "Retention raise draft" table.
   - Reworded line 324 note from 128M/128 MiB to `MemoryMax=1G` / 1 GiB.
   - Paste B: Updated scp source path to `/home/aj/Projects/strix-halo-johnny-slice2b-reader-mem` and pinned new staging/post-install hashes.
   - Paste C: Added `-p MemoryMax` to `systemctl show` and added `echo "$show_out" | grep -q -- "MemoryMax=1073741824"`.
   - Review 2 N1: Corrected reader `STOP` exit citation at line 41 from lines 671-673 to 674-675.
   - Review 2 N2: Added note outside code fences at Paste 6, Paste 8, and the slice-1c rollback explaining the pinned helper `b3c0b6bc…` is pre-retention and will fail closed after Paste B until retention rollback restores it.

4. **Self-Test Updated (`docs/tool-install/module1-slice2b-self-test.sh`)**:
   - Pinned new `WANT_BOOT_SHA` and `WANT_RUNIT_SHA`.
   - Added assertions for `MemoryMax=1G` and `MemorySwapMax=0` in static checks.
   - Added verification that Paste C greps `MemoryMax=1073741824`.
   - Maintained reject guard against unapplied draft hashes outside retention section (rejects PR #36 draft hashes `e9860731…`/`ea799ee6…` and new ones).
   - `SELF-TEST-OK` confirmed.

5. **Review 2 N3**:
   - In `docs/sessions/2026-11-14-module1-slice2b-retention.md`, removed unmeasured "confirmed memory-bounded" claim; noted write buffer is capped in code and cgroup memory check after first large file is still AJ's to do.

## Hash Summary

| File | sha256 | Status |
|---|---|---|
| `docs/tool-install/module1-xdp-records.o` | `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481` | Unchanged |
| `etc/systemd/system/johnny-capture-xdp-records.service` | `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a` | Unchanged |
| `docs/tool-install/johnny-m1s2b-reader.py` | `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37` | Unchanged |
| `etc/systemd/system/johnny-m1s2b-reader.service` | `e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c` | Updated (`MemoryMax=1G`) |
| `docs/tool-install/module1-slice2b-boot.sh` | `0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f` | Updated (`R_UNIT_SHA256` pin) |

## Verification Result
- `bash docs/tool-install/module1-slice2b-self-test.sh`:
  - `PINS-OK`
  - `SHELLCHECK-OK`
  - `STATIC-CHECKS-OK`
  - `READER-TESTS-OK`
  - `E2E-OK scenarios=11`
  - `RUNBOOK-OK blocks=17`
  - `SELF-TEST-OK`
- `systemd-analyze verify etc/systemd/system/johnny-capture-xdp-records.service etc/systemd/system/johnny-m1s2b-reader.service`: clean (exit 0, no output)
