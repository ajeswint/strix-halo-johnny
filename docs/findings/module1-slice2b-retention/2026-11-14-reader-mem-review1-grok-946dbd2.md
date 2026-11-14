APPROVE-WITH-NITS

Blocking: none.

N1. The OOM follow-up on the retention raise tells AJ to look after a file size the rotator will not produce.
File: docs/tool-install/module1-slice2b-boot-unit.md:328
Why: The same section at line 327 states the max run file is 1073741776 bytes (96-byte header inside the 1073741824 cap; records are 80 bytes, so the last record that fits leaves 48 bytes unused). Line 328 then says to check NRestarts and Result "after the first file passes 1 GiB", and that bullet defines 1 GiB as 1073741824. A file never crosses that number, so the sentence as written has no trigger. The show command itself is the right check; only the timing clause is wrong. Not a paste hazard: Pastes A–C do not wait on file size.
Fix: Change the timing clause to after the first run file closes (M1S2B-FILE-CLOSED bytes at or under 1073741776). Leave the show command as `systemctl show -p NRestarts -p Result johnny-m1s2b-reader.service`.

Evidence (checked, not findings)

Scope. git diff a77dae8..HEAD at 946dbd2. Nine files. Reader `docs/tool-install/johnny-m1s2b-reader.py` is byte-identical to a77dae8 (git diff exit 0). Computed sha256 `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37`. No SSH, no sudo, no repo edits.

1. Unit. `etc/systemd/system/johnny-m1s2b-reader.service:21` is the only unit change: `MemoryMax=128M` to `MemoryMax=1G`. `MemorySwapMax=0` stays at line 22. No MemoryHigh, MemoryLow, MemoryMin, MemoryZSwapMax, or StartupMemoryMax. `MemoryDenyWriteExecute=yes` (line 58) is the W^X sandbox, not a size. `LimitFSIZE=1025M` (line 27) is the file rlimit, unchanged, and is larger than the 1 GiB file cap.
`systemd-analyze verify` on `johnny-capture-xdp-records.service` and `johnny-m1s2b-reader.service`: exit 0, empty stdout and stderr (this host, systemd 261.3-0ubuntu3).
Empirical `systemctl --user show` on a transient oneshot with `MemoryMax=1G`, `MemorySwapMax=0`, `LimitFSIZE=1025M` printed:
```
MemoryMax=1073741824
MemorySwapMax=0
LimitFSIZE=1074790400
```
That is the Paste C grep string. Assumption: Johnny's recorded systemd is 259.9 (`docs/os-handoff.md` package table). This show was on 261, not on Johnny. Suffix rule is the same text in systemd.resource-control(5) here: K/M/G/T are base 1024 (https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html#MemoryMax=bytes). Paste C already required `LimitFSIZE=1074790400` from that parser before this diff; `1G` uses it too. 1*1024^3 = 1073741824. 1025*1024^2 = 1074790400.

2. Pins. Computed this tree:
- reader `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37` (unchanged)
- unit `e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c`
- boot.sh `0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f`
- object `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481` (unchanged)
- XDP unit `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a` (unchanged)
boot.sh pins those reader and unit hashes at `module1-slice2b-boot.sh:32` and `:34`. The only boot.sh diff is the unit constant (was `e9860731…`).
Same new trio in the draft pin list `module1-slice2b-boot-unit.md:58-60`, Paste B staging `:366-368`, Paste B post-install `:379-381`, Paste C boot.sh gate `:402` (unit and reader are re-checked by `boot.sh verify` → `need_files` → `R_UNIT_SHA256` / `READER_SHA256`, `module1-slice2b-boot.sh:162-163` and `:685`), self-test `WANT_*` at `module1-slice2b-self-test.sh:29-32`, handoff rev 113 `docs/os-handoff.md:12-13` (reader abbreviated `476cf867…` on `:14`; full reader hash is in the pin list and boot.sh), session `docs/sessions/2026-11-14-module1-slice2b-reader-mem.md:47-49`, findings `docs/findings/module1-slice2b/README.md:12`.
Old trio `b3c0b6bc…` / `fbe2449e…` / `5e685d3d…` remains the live pin list `:49-52`, Paste A `:348-350`, Paste B pre-install `:369-371`, retention rollback `:431-433` and `:437-439`. Not retargeted.
Stale PR #36 draft hashes `e9860731…` and `ea799ee6…` are absent from boot.sh, the draft pin list, and Pastes A–C and the retention rollback. They remain only as history (handoff rev 112 `docs/os-handoff.md:28-29`, rev 112 session `docs/sessions/2026-11-14-module1-slice2b-retention.md:65-66`, prior review files) and as a reject set in `module1-slice2b-self-test.sh:795-796` so a live bash block that still carries them fails. That reject set is not an install gate.

3. Fences. All 13 bash blocks outside `## Retention raise` are byte-identical to a77dae8. N2 notes are prose outside the fences at `module1-slice2b-boot-unit.md:185` (Paste 6), `:218` (Paste 8), and `:452` (slice 1c rollback). Each says `b3c0b6bc…` will not match after retention Paste B and fails closed until the retention rollback restores it. Those three pastes hash that helper before any further action, so a mismatch stops the `&&` chain (Paste 7's reboot and the 1c stop never start). Labels on the four retention fences are exactly `***<u>Run on Rock Box</u>***` (`:341`, `:359`, `:392`, `:427`). shlex: each `ssh` has one remote argument. `bash -n` on each remote script exited 0. No nested single quotes. Paste C greps are `echo … | grep -q … &&` (`:407-413`, including `MemoryMax=1073741824` at `:413`); a miss exits 1 and blocks `M1S2B-RET-VERIFY-DONE`. The journal `grep | tail` assignment is unchanged and still fail-closes on the following `grep -q`. Paste B scp sources are `/home/aj/Projects/strix-halo-johnny-slice2b-reader-mem/…` (`:363`). No `strix-halo-johnny-slice2b-retention` path remains in a paste.

4. Self-test. `bash docs/tool-install/module1-slice2b-self-test.sh` (no sudo) printed `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=11`, `RUNBOOK-OK blocks=17`, `SELF-TEST-OK`. Static checks require `^MemoryMax=1G$` and `^MemorySwapMax=0$` (`module1-slice2b-self-test.sh:75-76`). Runbook check requires Paste C to contain `grep -q -- "MemoryMax=1073741824"` (`:923-924`) and still rejects the new draft hashes and the stale `ea799ee6…` / `e9860731…` pair outside the retention section (`:793-797`, `:881-887`).

5. N1/N2/N3 from review 2, status, secrets.
- N1 closed. `module1-slice2b-boot-unit.md:41` cites `johnny-m1s2b-reader.py:674-675`. Those lines are `print("STOP-%s" …)` and `return 1`. `sys.exit(main())` is line 679. The old 671-673 cite is gone from the runbook.
- N2 closed. Notes at the three sites above, outside fences, hashes inside the fences unchanged.
- N3 closed. `docs/sessions/2026-11-14-module1-slice2b-retention.md:35` no longer says the stream was "confirmed memory-bounded". It says the write buffer is capped in code and the cgroup check is still AJ's. The buffer flushes at 256 records (`johnny-m1s2b-reader.py:462-463`); that cap was not re-measured under the unit cgroup here.
- DRAFTED, NOT APPLIED: runbook banner line 3, retention section heading, README step 4, `docs/findings/module1-slice2b/README.md:12`, handoff rev 113 `docs/os-handoff.md:4`, session `docs/sessions/2026-11-14-module1-slice2b-reader-mem.md:1` and `:4`. Live Johnny is described as the rev 111 limits including `MemoryMax=128M`. This review did not SSH, so that live state is the draft's claim plus the pre-install gates, not a fresh host read.
- Secrets: the diff's only `secret` hit is the session line that says no secrets were stored. No keys, passwords, or tokens.

Not filed. Rev 112 handoff and the rev 112 session still record `e9860731…` / `ea799ee6…` as that revision's pins. They are not what Paste B installs. Paste 7 (`:204`) and Paste R4 (`:314`) also require `b3c0b6bc…` and have no extra note; both fail closed on `sha256sum -c` before reboot or verify. Review 2 asked for the note on Pastes 6, 8, and the 1c rollback only, and those hashes were not to be edited.
