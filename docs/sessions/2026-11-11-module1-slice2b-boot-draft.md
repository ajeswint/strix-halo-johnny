# 2026-11-11 UTC (~20:50 UTC; ~2:50 PM America/Chicago): Module 1 slice 2b boot-time j_xdp_records and persistent rotating reader (draft, not applied)

Seat: code-writer (Antigravity, Gemini 3.8 Flash High / `gemini-3.8-flash-high`).
Branch `claude/module1-slice2b-boot`, based on `e771fa86b28e9932c74afaf157179aa1367759d8` (handoff rev 106).
Draft only; **NOT APPLIED** on Johnny. **No SSH, no scp, no sudo, no write to Johnny in this session.**

## Summary
AJ chose Module 1 slice 2b by name (2026-11-11). Drafted boot-time `j_xdp_records` on `eno1np0` replacing slice 1c's observer unit/helper as the boot attach, with the root-only reader as a bounded, rotating, persistent service (`johnny-m1s2b-reader.service`) outputting to `/var/lib/johnny/m1s2b/run-<UTC>.bin` so the mirror port is continuously recorded.

Reuses the verified slice 2 BPF object (`module1-xdp-records.o`, sha256 `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481`). The slice 2 pinned deployables and sources remain byte-identical; slice 2 self-test continues to pass cleanly.

## Key Decisions Implemented
1. **Rate / burst**: 8,000 rec/s per CPU, burst 16,000 written to `m2_cfg` by the helper at `start` and verified before attach. If write or verify fails, helper fails closed (no attach, clean exit 1).
2. **Retention**: 64 MiB or 3600 s per file, `keep=6` (dir cap 384 MiB), 256 MiB free space reserve under `/var/lib/johnny/m1s2b`. Reader stops writing if reserve would be breached.
3. **This-boot cutover**: Stop/disable slice 1c unit first, then enable/start slice 2b (clean brief capture gap; no overwrite).
4. **Slice 1c files**: Disabled, not uninstalled; left in place for rollback.
5. **MACs**: Remain raw.
6. **Cold-reboot proof**: Dedicated separate later paste (Paste 7 reboot, Paste 8 post-reboot verify) after this-boot verify passes.

## Deployables & Hashes
- `docs/tool-install/module1-xdp-records.o` (reused slice 2): `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481`
- `docs/tool-install/module1-slice2b-boot.sh`: `468853baaeb009ac39a4a75e52e40a875a7d4040b4cde7a4b8efdb4fe96b269c`
- `etc/systemd/system/johnny-capture-xdp-records.service`: `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a`
- `docs/tool-install/johnny-m1s2b-reader.py`: `e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581`
- `etc/systemd/system/johnny-m1s2b-reader.service`: `5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c`

## Verification
- `bash docs/tool-install/module1-slice2b-self-test.sh`:
  `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=9`, `RUNBOOK-OK blocks=9`, `SELF-TEST-OK`.
- `bash docs/tool-install/module1-slice2-self-test.sh`:
  `PINS-OK`, `HOST-TEST cases=44`, `READER-TEST cases=22`, `E2E scenarios=23`, `RUNBOOK blocks=12`, `SELF-TEST-OK`.
- Live Johnny remains untouched and running slice 1c observer `driver id=138`.
