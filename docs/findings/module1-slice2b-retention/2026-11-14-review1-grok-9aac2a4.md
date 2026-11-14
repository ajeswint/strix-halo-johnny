REQUEST-CHANGES

Reviewed `git diff e9332b5..HEAD` (`9aac2a4`) in `/home/aj/Projects/strix-halo-johnny-slice2b-retention`. No repo edits, no commit, no push, no SSH, no sudo. Self-test was run here: `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=11`, `RUNBOOK-OK blocks=17`, `SELF-TEST-OK`. `systemd-analyze verify` on both units exited 0 with empty stderr (this host is systemd 261; Johnny's recorded systemd is 259.9 in `docs/os-handoff.md`). `systemd.exec(5)` on this host: byte-limit suffixes K/M/G are base 1024, so `LimitFSIZE=1025M` is 1074790400 bytes.

The reader change and Pastes A–C are internally right. The runbook around them was only half moved onto the new pins, and that half-move breaks the emergency slice-1c rollback on today's Johnny. That is the block.

## B1. Runbook pins and the 1c rollback no longer describe one box

`docs/tool-install/module1-slice2b-boot-unit.md` line 3 says the retention raise is DRAFTED, NOT APPLIED. Live Johnny is still the parent blobs. I hashed both trees:

| File | This tree (new) | e9332b5 (live) |
|---|---|---|
| `docs/tool-install/johnny-m1s2b-reader.py` | `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37` | `fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573` |
| `etc/systemd/system/johnny-m1s2b-reader.service` | `e986073148d5bb617c1f8608034fe8a0bf787ea9620595e03c41ce5924e01903` | `5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c` |
| `docs/tool-install/module1-slice2b-boot.sh` | `ea799ee6a42e08dec3d15b1c8c7f9dad28ab81e73fda6a6ee5d9c7956873ab3f` | `b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55` |
| `docs/tool-install/module1-xdp-records.o` | `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481` | unchanged |
| `etc/systemd/system/johnny-capture-xdp-records.service` | `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a` | unchanged |

Those new hashes match `module1-slice2b-boot.sh` lines 32 and 34, the self-test `WANT_*` lines 29–32, the handoff, the session table, the findings README, and retention Pastes A–C. The old hashes match Paste A's installed-file gate (lines 334–336), Paste B's pre-install gate (lines 355–357), and the retention rollback (lines 416–424). BPF object and XDP unit are not in the diff.

The same runbook then uses the other pin set for the same paths:

- Lines 46–52, headed "Deployables (copied to Johnny)", list the new hashes. They are not copied. Johnny still has the parent blobs.
- Paste 2 lines 95–100 scp from `/home/aj/Projects/strix-halo-johnny-slice2b-fix3` (that checkout is `8d7aabb`, and its runbook still expects `blocks=13`) and then require the new hashes.
- Paste 3 line 112 and Paste 4 lines 130–146 require the new hashes.
- Paste 5 lines 160–164 and Paste 7 lines 195–199 still require the live hashes for `/root/m1s2b/module1-slice2b-boot.sh`, the reader, and the reader unit.
- Paste 6 line 182 and Paste 8 line 213 require the new boot.sh hash before verify / the post-reboot loop.
- The slice-1c rollback line 441 requires the new boot.sh hash, and the hash check is the first command, before any `systemctl stop`.

What that does if AJ runs the block:

- Re-running Paste 6, Paste 8, or the 1c rollback from this document against today's Johnny fails `sha256sum -c` and does not change the box. The emergency rollback that worked on `e9332b5` no longer runs. Fail-closed, and useless in an incident.
- Paste 4's install gate and Paste 5's cutover gate cannot both succeed: Paste 4 would only pass after the new files are staged, and Paste 5 would then reject them.
- Paste 1 lines 83–87 and Paste R1 lines 256–260 still `cd /home/aj/Projects/strix-halo-johnny-slice2b-fix3` but the expect text was changed to `RUNBOOK-OK blocks=17`. That tree's runbook still says `blocks=13`.

Pastes A–C themselves are not this bug. Leave their old→new gates as they are.

Why the self-test stayed green: `docs/tool-install/module1-slice2b-self-test.sh` lines 793–804 put both hashes in `prev_hashes`, and lines 867–874 accept either hash in any block. A swapped gate cannot fail that check. Lines 873–874 also call `die` twice; the second call is dead.

Required fix:

1. While the banner says NOT APPLIED, every gate that reads a file already on Johnny must keep the live hashes above. Restore `b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55` on Paste 6 line 182, Paste 8 line 213, and the 1c rollback line 441. Restore the live trio on Paste 2, Paste 3, and Paste 4 if those pastes still copy from `slice2b-fix3` and still mean the applied install. Paste 5 and Paste 7 already have the live trio; they should stay that way.
2. Lines 46–52 must not call the new hashes deployables copied to Johnny. Label them as the draft repo pins. Point at the retention section for the apply.
3. Paste 1 line 83 and Paste R1 line 256: either put `blocks=13` back, or `cd` to `/home/aj/Projects/strix-halo-johnny-slice2b-retention` and expect `blocks=17`. Do not mix the directory and the count.
4. Do not retarget the 1c rollback onto `ea799ee6…` until Paste B has actually replaced `/root/m1s2b/module1-slice2b-boot.sh`. A single hash cannot be right both before and after the apply; before the apply it has to be the live one.
5. After that edit, `prev_hashes` must not keep treating the two boot.sh hashes as valid in every block. A Paste 6 / Paste 8 / 1c-rollback block that contains `ea799ee6…` has to fail the self-test for as long as those blocks are the live-box gates.

## Checked, not blocking

Reader (`docs/tool-install/johnny-m1s2b-reader.py`):

- `bounded` (line 477) is `floor <= val <= ceiling`, default floor 1. `2 << 30` is 2147483648 (2 GiB). `16 << 40` is 17592186044416 (16 TiB). Python ints, no wrap.
- Production args sit inside the ceilings: file 1073741824 with floor `HDR.size + REC_SIZE` (176), seconds 3600, keep 200 (ceiling 1000), dir cap 214748364800 with floor equal to the file max, reserve 107374182400 (floor 1). Defaults are still 64 MiB / keep 6 / 384 MiB / 256 MiB, so a unit that forgot the new flags would not jump to 1 GiB.
- `prune` (lines 332–359) deletes oldest first (`run_files` is a sorted name list). Keep loop uses `len >= keep`, so keep=6 leaves at most 5 existing files, and keep=200 leaves at most 199, before the new file. Byte loop deletes while `total + new_file_reserved_bytes > dir_cap`. `open_next_file` line 401 passes `file_max_bytes` as that reservation. Empty directory plus a 1 GiB reservation fits under the 200 GiB cap, so `dir-cap-exceeded` does not fire on a healthy start. The new self-test case (5×500 B, cap 1600, reserve 500, keep 200) kept the two newest names. I watched that prune run.
- `check_disk_free` (lines 311–318) is `f_bavail * f_frsize`, same byte count as `df --output=avail -B1`. It runs at `do_run` line 496 (before the ring is used), twice in `open_next_file` (before and after prune), and in `flush` line 468 before every write. A flush is at most 256×80 = 20480 bytes. The file itself cannot grow past `file_max_bytes`: the header is stored in `file_bytes` (line 426) and the next record is refused when `file_bytes + 80 > file_max_bytes` (line 447). Max file is 1073741776 bytes. That is under 1 GiB and under `LimitFSIZE` 1074790400, with 1048624 bytes of headroom. SIGXFSZ does not fire on this unit. A full disk is not reachable through this writer while the reserve check runs: the miss is at most one flush past the reserve, against a 100 GiB floor.
- `MemoryMax=128M` and `MemorySwapMax=0` are untouched (`johnny-m1s2b-reader.service` lines 21–22). `ExecStart` is one `Type=exec` line, no shell, arguments match argparse. `systemd-analyze verify` accepted it.

Retention pastes:

- Labels are `***<u>Run on Rock Box</u>***`. Commands ssh to `aj@192.168.50.152`.
- No nested single quotes. shlex sees one remote string per ssh. Paste B has two ssh invocations (plain `ssh` for `mkdir`, then `ssh -t` for sudo); that is why the old "exactly two quotes" rule was removed. The remaining shlex check holds.
- No `grep -c` in A–C. Paste C's journal pipeline ends in `tail`, so a miss does not fail the assignment; the following `grep -q` on the captured line does, and the done token is not printed. The pattern is not in the `journalctl` argv, and the query is `-u johnny-m1s2b-reader.service -o cat`, so it does not repeat the old sudo-command self-match.
- Paste A's `322122547200` is 300 GiB. `df --output=avail -B1` here prints a header and an ungrouped integer; bash `[` accepts that integer. `free < 300 GiB` exits 1 with `STOP-low-disk`.
- Paste B copies, hash-checks the copies, hash-checks the live old files, then `cp -p` into `/root/m1s2b/backup-pre-retention`, and only then `install`s. A failure before the first `install` leaves Johnny on the old files. A failure after that is restored by the retention rollback, whose warning is present (lines 409–410) and matches `prune`: keep=6 leaves at most 5 files, and the 384 MiB cap applies. XDP is not restarted.
- Paste C's ExecStart greps match the `systemctl show` shape I printed locally (`argv[]=` with spaces between arguments). The reader begin line really is `file_max_bytes=%d file_max_seconds=%d keep=%d dir_cap=%d reserve=%d` (reader lines 524–526).

Docs that are right: `docs/os-handoff.md` rev 112 and `docs/findings/module1-slice2b/README.md` both say DRAFTED, NOT APPLIED, and the byte figures match the unit. No secrets in the diff.

## N1. Paste C does not check the LimitFSIZE value

`docs/tool-install/module1-slice2b-boot-unit.md` line 398: `grep -q -- "LimitFSIZE="`. `systemctl show -p LimitFSIZE` always prints that key. On this host an untouched service prints `LimitFSIZE=infinity`, which would pass. The ExecStart greps would still reject the old unit, so this does not wave through today's 257M unit. It also does not prove 1025M was loaded.

Required fix: match `LimitFSIZE=1074790400`.

## N2. Session note and README never say the raise is not applied

`docs/sessions/2026-11-14-module1-slice2b-retention.md` has no "DRAFTED, NOT APPLIED". Line 20 says "Changes Implemented", which reads as finished. `README.md` line 20 still describes slice 2b as applied and complete, with no draft clause. The handoff does say it. Neither file claims the new limits are live.

Required fix: put "DRAFTED, NOT APPLIED" in the session header. Add one clause to README step 4 that the 1 GiB / 200 GiB / 100 GiB raise is drafted and not on Johnny.

## N3. Dead `die` and a late mock save

`docs/tool-install/module1-slice2b-self-test.sh` lines 873–874: delete the second `die`. `orig_check_disk_free` is assigned at line 223, inside the try, and the finally at line 251 always reads it. An assert that fails before line 223 becomes a `NameError`. Save the original before the try.

## N4. Preflight has no slack past cap + reserve

Paste A line 333 stops only when free is under 300 GiB, and 300 GiB = 200 GiB cap + 100 GiB reserve. `check_disk_free` allows `free == reserve` and the next call then writes the 96-byte header. A disk that barely passes preflight and then fills the cap trips `low-disk`, exit 1, and the existing `StartLimitBurst=5` (`johnny-m1s2b-reader.service` lines 6–7 and 13). The disk is not filled; recording stops with about 100 GiB still free. Raise the preflight floor by a GiB if that boundary should stay quiet.

## N5. "1 GiB plus 96-byte header" overstates the file

The header is inside `file_max_bytes`, not after it. Max file is 1073741776, not 1073741920. `LimitFSIZE=1025M` still covers it. Handoff line 9, session line 17, runbook line 316, and the self-test compare at line 87 (`>= 1 GiB + 96`) are conservative, not a SIGXFSZ hole. Say the header is included in the 1 GiB cap.

## N6. Rollback warning stops one step short

Lines 409–410 are present and match the code. After this raise, a 1 GiB file is larger than the restored 384 MiB cap, so the byte prune deletes those files rather than keeping five of them. Say that in the warning so the keep=6 sentence is not read as "five 1 GiB files survive".

## N7. MemoryMax stayed 128M; page cache is still charged to the unit

Unchanged, as required. `memory.current` includes dirty pages of the open run file, and `IOSchedulingClass=idle` slows writeback. The 8000/16000 cap is about 2.44 MiB/s, so a 30 s dirty expire is on the order of 73 MiB, under 128 MiB if the Python RSS stays modest. Not demonstrated under the unit's cgroup. On the first file that passes 128 MiB, check the unit was not oom-killed. No code change requested unless that happens.
