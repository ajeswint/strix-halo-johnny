# 2026-11-11 UTC (~21:40 UTC; ~3:40 PM America/Chicago): Module 1 slice 2b review fixes (draft, not applied)

Seat: code-writer (Antigravity, Gemini 3.8 Flash / `gemini-3.8-flash-high`).
Branch `claude/module1-slice2b-boot` (PR #33).
Draft only; **NOT APPLIED** on Johnny. **No SSH, no scp, no sudo, no write to Johnny in this session.**

## Summary of Fixes Addressed (B1–B3, N1–N5)

- **B1 (Rollback predicate & net-show proof)**:
  - Updated the rollback verification block in `docs/tool-install/module1-slice2b-boot-unit.md`: extracts the driver id from `bpftool net show dev eno1np0`, queries `bpftool prog show id <id>` to verify prog name is `j_xdp_observe`, checks `johnny-capture-xdp.service` is `enabled` and `active`, and verifies both 2b units (`johnny-capture-xdp-records.service` and `johnny-m1s2b-reader.service`) are `disabled` and `inactive`.
  - Added fixture for real `bpftool net show` text `xdp: eno1np0(4) driver id 138` and `bpftool prog show id 138` mock in `docs/tool-install/module1-slice2b-self-test.sh`.
  - Added automated rollback test scenario (Scenario 11) in `module1-slice2b-self-test.sh` covering both clean success (`M1S2B-ROLLBACK-DONE`) and unclean fail-closed (`STOP-rollback-not-clean`).

- **B2 (Paste 5 cutover 5-file pin check)**:
  - Updated Paste 5 in `docs/tool-install/module1-slice2b-boot-unit.md` to run `sudo sha256sum -c` across all five installed deployable paths before any `systemctl stop` or `disable` of `johnny-capture-xdp.service`.

- **B3 (IRQ baseline queue name & affinity comparison)**:
  - Fixed `verify_attached_invariants` in `docs/tool-install/module1-slice2b-boot.sh` to compare queue name (`$3`) and affinity (`$4`) only, ignoring the IRQ number (`$2`), matching slice 1b `irq_norm` semantics.
  - Added Scenario 10 in `module1-slice2b-self-test.sh` testing that renumbered IRQs with identical queue names and affinities pass cleanly, while affinity changes trigger `STOP-irq-baseline-diff`.

- **N1 (owner_ok file and mode check)**:
  - Hardened `owner_ok()` in `docs/tool-install/module1-slice2b-boot.sh` to require a regular file (`[ -f "$p" ] && [ ! -L "$p" ]`), root:root ownership (`0:0`), and mode regex `^[0-7]*[0145][0145]$`, rejecting modes with group/other write bits such as `0622`.

- **N2 (Scenario count in Paste 1)**:
  - Updated Paste 1 expect text in `docs/tool-install/module1-slice2b-boot-unit.md` to expect `E2E-OK scenarios=11` matching the script's output with the two added scenarios.

- **N3 (Paste 7 reboot 5-file pin check)**:
  - Updated Paste 7 in `docs/tool-install/module1-slice2b-boot-unit.md` to run `sudo sha256sum -c` on all five installed paths before issuing `sudo reboot`.

- **N4 (Rate-limit math and documentation precision)**:
  - Updated `## Rate-Limit Reasoning` in `docs/tool-install/module1-slice2b-boot-unit.md` with exact values: 15,527/46,978 = 33.1% rate-limited ratio; 16,000/8,000 = exact 2.0 s burst; `1000000000/8000` = exact 125,000 ns token period; explained ~479 pps divides cumulative `ctl_seen` by one file's 98.160 s span; noted 80 B on-disk size (~625 KiB/s per CPU) vs 88 B ring slot (~1.49 s ring buffer backlog at 4×8,000 rec/s).

- **N5 (Reader failure under systemd)**:
  - Documented in `docs/tool-install/module1-slice2b-boot-unit.md` (Design Addendum and STOP table) that reader `STOP` exits 1 (`johnny-m1s2b-reader.py:671-673`), and after `StartLimitBurst=5` with `Restart=on-failure`, systemd leaves the reader failed while the XDP unit stays active (`Wants=johnny-m1s2b-reader.service` without `BindsTo=`).

## Updated sha256 Pins
- `docs/tool-install/module1-xdp-records.o`: `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481` (unmodified)
- `docs/tool-install/module1-slice2b-boot.sh`: `650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2` (updated)
- `etc/systemd/system/johnny-capture-xdp-records.service`: `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a` (unmodified)
- `docs/tool-install/johnny-m1s2b-reader.py`: `e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581` (unmodified)
- `etc/systemd/system/johnny-m1s2b-reader.service`: `5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c` (unmodified)
- `etc/johnny/capture-cores`: `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b` (unmodified)
- `etc/johnny/irq-affinity.sh`: `db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4` (unmodified)

## Verification
- `bash docs/tool-install/module1-slice2b-self-test.sh`:
  `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=11`, `RUNBOOK-OK blocks=9`, `SELF-TEST-OK`.
- `bash docs/tool-install/module1-slice2-self-test.sh`:
  `PINS-OK`, `SHELLCHECK-OK`, `ENUM-ORDER-OK`, `OBJECT-DISASM-OK`, `OBJECT-LIBBPF-PARSE-OK`, `HOST-TEST-OK cases=44`, `READER-TEST-OK cases=22`, `E2E-OK scenarios=23`, `RUNBOOK-OK blocks=12`, `SELF-TEST-OK`.
