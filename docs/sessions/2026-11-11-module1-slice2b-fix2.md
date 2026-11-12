# 2026-11-11 UTC (~22:35 UTC; ~4:35 PM America/Chicago): Module 1 slice 2b review fix 2 (draft, not applied)

Seat: code-writer (Antigravity, Gemini 3.8 Flash / `gemini-3.8-flash-high`).
Branch `claude/module1-slice2b-boot` (PR #33).
Draft only; **NOT APPLIED** on Johnny. **No SSH, no scp, no sudo, no write to Johnny in this session.**

## Summary of Fixes Addressed (B1)

- **B1 (Rollback single-quoted ssh argument nesting)**:
  - In `docs/tool-install/module1-slice2b-boot-unit.md` rollback fence (~lines 256, 259), nested single quotes (`'driver id [0-9]*'`, `'{print $3}'`, `'name [^ ]*'`, `'{print $2}'`) inside the outer single-quoted `ssh -t '...'` argument prematurely terminated the ssh argument on the host, causing argument splitting and empty expansion of `$3` and `$2`.
  - Replaced with double quotes: `grep -o "driver id [0-9]*"`, `awk "{print \$3}"`, `grep -o "name [^ ]*"`, and `awk "{print \$2}"`. The entire `ssh -t` script remains one single-quoted argument (`body.count("'") == 2`).
  - Strengthened `docs/tool-install/module1-slice2b-self-test.sh`:
    - Scenario 11 extracts the markdown rollback fence directly from `docs/tool-install/module1-slice2b-boot-unit.md`.
    - Added mock shims for `sudo`, `sha256sum`, and `ssh` in `$E2E_DIR/bin/` so the extracted rollback fence runs exactly as invoked by bash, simulating ssh argument joining and remote bash execution against fixtures `xdp: eno1np0(4) driver id 138` and `138: xdp  name j_xdp_observe  tag b5b852630d7539c7  gpl`.
    - Requires clean rollback token `M1S2B-ROLLBACK-DONE` and verifies fail-closed `STOP-rollback-not-clean` on unclean mock state.
    - Strengthened RUNBOOK-OK in section 6: audits all bash blocks with `shlex.split`, verifies sudo blocks start and end with single quotes and contain no internal single quotes (`count("'") == 2`), and ensures all `ssh` commands pass exactly 1 remote command argument string after destination host.
  - Bumped handoff rev to 109 in `docs/os-handoff.md` and `README.md`.

## Verification
- `bash docs/tool-install/module1-slice2b-self-test.sh`:
  `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=11`, `RUNBOOK-OK blocks=9`, `SELF-TEST-OK`.
- `bash docs/tool-install/module1-slice2-self-test.sh`:
  `PINS-OK`, `SHELLCHECK-OK`, `ENUM-ORDER-OK`, `OBJECT-DISASM-OK`, `OBJECT-LIBBPF-PARSE-OK`, `HOST-TEST-OK cases=44`, `READER-TEST-OK cases=22`, `E2E-OK scenarios=23`, `RUNBOOK-OK blocks=12`, `SELF-TEST-OK`.
