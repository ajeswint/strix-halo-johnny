# 2026-11-14 UTC: Module 1 Slice 2b Retention Raise (DRAFTED, NOT APPLIED)

- **Date:** 2026-11-14 America/Chicago
- **Status:** **DRAFTED, NOT APPLIED**
- **Branch:** `claude/module1-slice2b-retention`
- **Revision:** rev 112
- **Seats:**
  - Code-writer: Antigravity Gemini 3.8 Flash high
  - Adversarial-reviewer: Sonnet medium effort (review1 completed, fixes applied)
- **Constraints Maintained:** No SSH to Johnny; no sudo executed; no secrets in repo; BPF object (`module1-xdp-records.o`) and XDP unit (`johnny-capture-xdp-records.service`) unchanged.

## Goal & AJ Decisions

AJ approved raising Module 1 slice 2b reader retention limits on Johnny ("we have plenty of room"):
- **Per-file rotation:** 1 GiB (1073741824 bytes) or 3600 s, whichever first.
- **Directory cap:** 200 GiB (214748364800 bytes), oldest file deleted first. Keep count 200 files (`--keep 200`).
- **Free-space reserve:** 100 GiB (107374182400 bytes): reader prunes oldest / stops writing rather than dip below reserve.
- **File size limit:** `LimitFSIZE=1025M` (raised from 257M) in `etc/systemd/system/johnny-m1s2b-reader.service`; the 96-byte header is included in the 1 GiB file cap (max file 1073741776 bytes; `LimitFSIZE=1025M` = 1074790400 bytes covers it without triggering SIGXFSZ).
- **Tradeoff note:** At low traffic, hourly rotation means `keep=200` bounds retention to ~200 hours (~8.3 days) before the 200 GiB byte cap is reached; at high traffic, 1 GiB per-file rotation reaches the 200 GiB cap and retains 200 GiB of packet captures. Cap + reserve = 300 GiB exactly, so a disk that only just passes preflight may stop recording (low-disk, ~100 GiB still free) once the cap fills.

## Changes Implemented

1. **Systemd Unit (`etc/systemd/system/johnny-m1s2b-reader.service`)**:
   - Added explicit CLI arguments to `ExecStart`:
     `--file-max-bytes 1073741824 --file-max-seconds 3600 --keep 200 --dir-cap-bytes 214748364800 --reserve-bytes 107374182400`.
   - Raised `LimitFSIZE` to `1025M` (1,074,790,400 bytes; the 96-byte header is included in the 1 GiB file cap [max file 1073741776 bytes], providing ~1 MiB of headroom).
   - Verified with `systemd-analyze verify`.

2. **Reader Python Script (`docs/tool-install/johnny-m1s2b-reader.py`)**:
   - Raised `MAX_FILE_BYTES` ceiling to 2 GiB (`2 << 30`).
   - Raised `MAX_KEEP` ceiling to 1000.
   - Bounded `dir_cap_bytes` to `MAX_DIR_CAP_BYTES = 16 << 40` (16 TiB) with `floor=file_max_bytes` (ensuring directory cap is always >= file max size).
   - Bounded `reserve_bytes` to `MAX_RESERVE_BYTES = 16 << 40` (16 TiB) with default `floor=1`.
   - Python defaults (`DEF_*`) left intact for standalone runs without CLI flags.
   - Streamed write buffer is capped in code (not tied to file size); the cgroup memory check after the first large file is still AJ's to do.

3. **Boot Helper (`docs/tool-install/module1-slice2b-boot.sh`)**:
   - Updated pinned `READER_SHA256` and `R_UNIT_SHA256` to match new hashes.
   - Shellcheck clean.

4. **Self-Test (`docs/tool-install/module1-slice2b-self-test.sh`)**:
   - Updated pinned hashes (`WANT_BOOT_SHA`, `WANT_READER_SHA`, `WANT_RUNIT_SHA`).
   - Added static check verifying unit `ExecStart` carries all new retention arguments and `LimitFSIZE` covers 1 GiB file cap (header included).
   - Added unit tests verifying `bounded()` accepts target retention arguments and rejects floor/ceiling violations.
   - Added prune test verifying byte cap (not keep count) forces oldest-first file deletion.
   - Added disk free reserve check test.
   - Updated runbook validation to accept previous hashes and verify all 17 runbook blocks.

5. **Runbook (`docs/tool-install/module1-slice2b-boot-unit.md`)**:
   - Updated "Final sha256 Pins" table.
   - Added section "Retention raise (2b already live)" with:
     - **Paste A:** Read-only preflight (checks available space >= 300 GiB / 322122547200 B, verifies current installed hashes, checks dir usage; token `M1S2B-RET-PREFLIGHT-DONE`).
     - **Paste B:** Copy changed files, hash-verify copies, sudo verify old installed hashes, back up to `/root/m1s2b/backup-pre-retention/` (0700), install new files, verify installed hashes, daemon-reload, restart reader service only, status; token `M1S2B-RET-APPLY-DONE`.
     - **Paste C:** Verify units active, run boot.sh verify and status, verify `systemctl show` has new args and LimitFSIZE, verify reader journal startup line shows new parameters; token `M1S2B-RET-VERIFY-DONE`.
     - **Rollback:** Restore backed-up files, verify old hashes, daemon-reload, restart reader, status; token `M1S2B-RET-ROLLBACK-DONE`. Prominently warns that restoring old reader prunes down to `keep=6` / 384 MiB.
   - Updated STOP and token tables.

## Hash Summary

| File | sha256 | Status |
|---|---|---|
| `docs/tool-install/module1-xdp-records.o` | `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481` | Unchanged |
| `etc/systemd/system/johnny-capture-xdp-records.service` | `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a` | Unchanged |
| `docs/tool-install/johnny-m1s2b-reader.py` | `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37` | Updated |
| `etc/systemd/system/johnny-m1s2b-reader.service` | `e986073148d5bb617c1f8608034fe8a0bf787ea9620595e03c41ce5924e01903` | Updated |
| `docs/tool-install/module1-slice2b-boot.sh` | `ea799ee6a42e08dec3d15b1c8c7f9dad28ab81e73fda6a6ee5d9c7956873ab3f` | Updated |

## Verification Result
- `bash docs/tool-install/module1-slice2b-self-test.sh`:
  - `PINS-OK`
  - `SHELLCHECK-OK`
  - `STATIC-CHECKS-OK`
  - `READER-TESTS-OK`
  - `E2E-OK scenarios=11`
  - `RUNBOOK-OK blocks=17`
  - `SELF-TEST-OK`
