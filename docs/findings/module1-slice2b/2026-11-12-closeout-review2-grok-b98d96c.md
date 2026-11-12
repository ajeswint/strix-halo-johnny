APPROVE

Reviewer: adversarial-reviewer (re-review 2, review only). Range: `git diff 6891fa3..HEAD` (commits 5ca9257, b56f41d, b9d317d, b98d96c; tip b98d96c). Fix range checked separately: `git diff b9d317d..HEAD` (b98d96c). Worktree only. No repo edit, no commit, no push, no ssh, no sudo. The two review1 record files were used only as the checklist.

Review 1 was REQUEST-CHANGES on b56f41d. B1 and N1–N6 are resolved as that review asked. The full PR diff still meets checks 1–5. No new blocking findings. No new nits.

## Review 1 disposition

### B1 — resolved

`docs/os-handoff.md:34` (Context, Sequence) no longer states the pre-apply live state. The slice 2 trial is past tense: rolled back to observer `driver id=138` on 2026-11-11 (rev 105). The same sentence then states the live facts: slice 2b APPLIED 2026-11-12T04:05Z, VERIFIED with PR #34 (`6891fa3`), COLD-BOOT PROVEN 2026-11-12 ~05:54Z, `j_xdp_records` attached driver mode `prog_id=78`, `johnny-m1s2b-reader.service` enabled+active, `johnny-capture-xdp.service` disabled+inactive, port-mirror sniffing complete, symmetric RSS and AF_XDP not started, host LSM still deferred.

The only "not applied" left on that line is "option D not applied" (signed UKI, step 12). `j_xdp_records` is not described as unattached. Historical rev 109/110 banners (`docs/os-handoff.md:14`, `:19`) still say "verify not yet passed" and "DRAFTED, NOT APPLIED". Those are the older rev records, under the rev 111 banner. Leaving them is the right history.

### N1 — resolved

491 / 426 is marked operator-reported, transcript not saved, in all four places review 1 named:

- `docs/findings/module1-slice2b/README.md:8`
- `docs/os-handoff.md:6`
- `docs/os-handoff.md:187`
- `docs/sessions/2026-11-12-module1-slice2b-closeout.md:8`

No committed file contains `xdp-pkts-delta=491` or `tcpdump-captured=426`. No pct was invented for that window. Integer `426*100/491` is 86, and 86 is not in the closeout text.

### N2 — resolved as the documented limitation

The gate text that ran was not rewritten. The same two lines remain at `docs/tool-install/module1-slice2b-boot-unit.md:226-227`, `docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md:13-14`, `docs/sessions/2026-11-12-module1-slice2b-closeout.md:14-15`, and (joined on one line) `docs/os-handoff.md:8`.

The limitation is now in the runbook, outside the paste fence, at `docs/tool-install/module1-slice2b-boot-unit.md:239`: without pipefail, a journalctl failure with empty stdout reads as `cyc=0`; stderr would still show; a future revision could capture journalctl output and STOP on its non-zero exit. Local test agrees: `false | grep -ci "ordering cycle" || true` yields `cyc` of exactly `0` (length 1) and the `&&` chain continues, with or without `pipefail`, because `|| true` still swallows the pipeline. That is the residual review 1 already accepted.

### N3 — resolved

`docs/tool-install/module1-slice2b-boot-unit.md:243` now says id 192 was the 2026-11-12T04:05Z pre-reboot attach and the live id after the ~05:54Z cold boot is 78. That matches `docs/findings/module1-slice2b/2026-11-11-apply-output.md:14` (`ATTACH records 192`) and the cold-boot transcript (`driver id=78`, `ATTACH records 78`).

### N4 — resolved

`docs/os-handoff.md:262` splits the dates: OS gate approved (AJ, 2026-11-05 America/Chicago); Module 1 port-mirror sniffing COMPLETE (cold-boot proven 2026-11-12 ~05:54Z, rev 111). COMPLETE is no longer dated 2026-11-05.

### N5 — resolved

`docs/sessions/2026-11-12-module1-slice2b-closeout.md:42` now says "Module 1 port-mirror sniffing complete status." The State section (`:33-37`) keeps symmetric RSS and AF_XDP as not started.

### N6 — resolved

`docs/os-handoff.md:187` puts the parked-open tail back: idle-memory investigation (Parked) and the 92 °C register entry before sizing; GRUB register text refresh; agent-team doc drift; soft nits N1–N5 from PR #20; soft nits N3–N6 from PR #22; per-step review verdicts; architecture-logic items in `docs/agent-team.md` §7 items 3–7. The sentence says they are still open, not blockers. It does not close them.

## Check 1 — Paste 8 ordering-cycle gate

The paste fence is `docs/tool-install/module1-slice2b-boot-unit.md:212-234`. It is one `ssh -t '...'` argument. The fence body contains exactly two single quotes (open and close). The remote script contains none, including the gate. `bash -n` on the extracted remote script succeeded.

Gate, chained with `&&`:

```
cyc=$(sudo journalctl -b --no-pager -q _PID=1 -o cat | grep -ci "ordering cycle" || true) &&
if [ "$cyc" != "0" ]; then echo "STOP-ordering-cycle-warning count=$cyc"; false; fi &&
```

Local bash `--noprofile --norc`, pipefail off:

- Zero matches: `grep -ci` prints `0` and exits 1 (`od` of the raw write is `30 0a`). `|| true` keeps the assignment's status 0, so the `&&` chain stays alive. `true` writes nothing, so it does not append a second 0. Command substitution strips the trailing newline. `cyc` is exactly `0` (length 1, repr `'0'`), not empty and not `0\n0`. The `if` test is false, the `if` returns 0 (no branch taken), and the next `&&` command runs.
- One match: `cyc=1`, the then-list prints `STOP-ordering-cycle-warning count=1`, `false` is the last command in the then-list, the `if` returns 1, and the chain stops.
- Two matches: `cyc=2`, same STOP, chain exit 1, the command after `&&` does not run.

`||` binds looser than `|`, so the grouping is `(journalctl | grep) || true`, which is what keeps grep's exit 1 from killing a zero-match chain. The paste does not set `pipefail`. With `pipefail` on, the zero-match path still leaves `cyc=0` because of `|| true`.

`_PID=1` is the right filter for the rev 89 messages. Those lines are manager logs (`docs/tool-install/step-13-irq-affinity.md:195-196`: `multi-user.target: Found ordering cycle: ...`). `journalctl(1)` on this host (systemd 261.3-0ubuntu3; EXAMPLES) documents `journalctl -u name` as including `UNIT=<name> _PID=1` for the manager's own messages about a unit. `-o cat` prints MESSAGE, which still contains `ordering cycle`. sudo's command-log line, which contains the same words, is not `_PID=1`. Johnny's recorded systemd at the step 12 inventory is `259.9-0ubuntu0.1` (`docs/os-handoff.md:23`). This check did not run journalctl on Johnny. The field and the `-u` expansion are the same pattern in the upstream man page: https://www.freedesktop.org/software/systemd/man/latest/journalctl.html and https://www.freedesktop.org/software/systemd/man/latest/systemd.journal-fields.html (`_PID=` is the process the entry originates from).

`--no-pager` is set. `ssh -t` allocates a tty; the old unpiped `journalctl --grep` could open a pager (`$SYSTEMD_PAGER` / `$PAGER`, man page ENVIRONMENT). In this pipeline journalctl's stdout is a pipe, so a pager would not start even without `--no-pager`. Keeping `--no-pager` is still right. `-q` suppresses the "-- No entries --" banner, so a real zero-match boot does not put extra text into `cyc`.

`journalctl(1)` EXIT STATUS on this host: 0 on success, non-zero otherwise. A failure that writes nothing to stdout is indistinguishable from zero hits, because pipefail is off and `|| true` also covers the pipeline. That is the N2 limitation, now written at `docs/tool-install/module1-slice2b-boot-unit.md:239`. The passing transcript reaches `M1S2B-VERIFY-BEGIN` (`docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md:23`) only after this gate in the `&&` chain, so on that boot `cyc` compared equal to `0`.

## Check 2 — numbers match the cold-boot transcript

Source: `docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md:22-66`. Quoted figures in `README.md:20`, `docs/findings/module1-slice2b/README.md:8-11`, `docs/os-handoff.md:4-9`, `docs/os-handoff.md:187`, `docs/os-handoff.md:262`, `docs/sessions/2026-11-12-module1-slice2b-closeout.md:8-25`, and session CSV row 1 (`docs/sessions/Johnny_Module1Slice2bCloseout_Session_Log_2026-11-12.csv:2`) match it.

- Hashes in the transcript match the unchanged pin block `docs/tool-install/module1-slice2b-boot-unit.md:48-59` and the self-test constants: object `a73c5bd2…9481`, reader `fbe2449e…d573`, reader unit `5e685d3d…c10c`, boot unit `4e2e359d…de0a`, irq helper `db58d7c7…59e4`, cores `16fbd7d1…179b`. The transcript's seventh check is `/root/m1s2b/module1-slice2b-boot.sh: OK` (sha256sum -c, digest not reprinted). That digest is `b3c0b6bc…1f55`, quoted in the session note (`docs/sessions/2026-11-12-module1-slice2b-closeout.md:8`) and in the pin block. The session note's "6 sha256" list is the six `OK-*-hash` lines (`:18`). `bash docs/tool-install/module1-slice2b-self-test.sh` printed `PINS-OK` against those seven files.
- `prog_id=78`: `OK-xdp-mode driver id=78` before and after (`:36`, `:39`), `ATTACH records 78` (`:48`), `PROG-XDP-COUNT 1 records=78 observer=none` (`:49`). `ATTACH records <id>` is the helper's name for the pinned `j_xdp_records` id (`docs/tool-install/module1-slice2b-boot.sh:238-253`, printed at `:746`).
- `PASS-RATIO tcpdump=3141 xdp=3882 pct=80` (`:43`). `3141*100/3882` is 80 in integer division, which is what `docs/tool-install/module1-slice2b-boot.sh:732` prints. Threshold is `>= 80` (`:734`). The transcript has no `NOTE-pass-ratio-low`. Docs that say 80% are quoting that token.
- Units (`:30-31`, `:50-52`): records and reader `enabled=enabled active=active`; 1c `enabled=disabled active=inactive`.
- `m2_ctl` (`:55-60`): seen 33436, sampled_out 0, rate_limited 0, rb_full 0, emitted 33436, discarded 0. The "33,436 seen" wording is this CTL seen, not `STATS pkts=33433` (`:54`). Window `ctl-seen-delta=3662` (`:42`) is not quoted as the cumulative counter. Key order is `seen sampled_out rate_limited rb_full emitted discarded` (`docs/tool-install/module1-slice2b-boot.sh:44`).
- Apply time 2026-11-12T04:05Z matches `docs/findings/module1-slice2b/2026-11-11-apply-output.md:1`. Cold boot ~05:54Z matches `DATE-UTC 2026-11-12T05:54:49Z` (`:23`).
- `ETHTOOL-DROP-DELTAS none (checked=16)` (`:44`) and `tcpdump-kernel-drops=0` (`:42`) match where quoted.
- R4 stays xdp 491 vs tcpdump 426, operator-reported, no saved paste, no pct. See N1 above.

Rev 110 rate figures, repeated and not closed: `docs/findings/module1-slice2b/2026-11-12-evidence-johnny.txt` `m2_ctl` formatted sums (recomputed this review) are key 0 seen 843847, key 2 rate_limited 407183, key 4 emitted 436664 (407183+436664=843847). 407183/843847 is 48.253%. Both "~48.2%" (`docs/findings/module1-slice2b/README.md:11`, `docs/os-handoff.md:16`, session note `:29`) and "~48%" (`docs/os-handoff.md:9`, runbook `:23`) are that ratio. The new text says the cold boot showed `rate_limited` 0 of 33436 at the same 8000/16000 config, the rate stays 8000/16000, and it is still AJ's call. It does not claim the 48% question is closed. Cold-boot zeros are the post-boot counters in the transcript, not a second 7-minute sample. The evidence file's run-file stamp is 04:13 (`:30`) and its attach line is `driver id 192` (`:4`), which is the pre-reboot snapshot, consistent with id 192 at apply and id 78 after the cold boot.

## Check 3 — no pin or code change; self-test passes

`git diff --name-only 6891fa3..HEAD` is nine files, all docs: `README.md`, the two review1 records, the cold-boot evidence file, `docs/findings/module1-slice2b/README.md`, `docs/os-handoff.md`, the session note, the session CSV, and `docs/tool-install/module1-slice2b-boot-unit.md`. The runbook diff does not touch the pin block. `git diff 6891fa3..HEAD` on the boot helper, reader, object, both units, `capture-cores`, `irq-affinity.sh`, and the self-test is empty. `git diff --check 6891fa3..HEAD` is clean.

`bash docs/tool-install/module1-slice2b-self-test.sh` in this worktree, no sudo, exited 0: `PINS-OK SHELLCHECK-OK STATIC-CHECKS-OK READER-TESTS-OK E2E-OK scenarios=11 RUNBOOK-OK blocks=13 SELF-TEST-OK`. Worktree was still clean after that run.

## Check 4 — no secrets

The added diff has no private-key blocks and no `password=`, `api_key`, `AKIA`, `ghp_`, or token assignments. The only scan hits are the review1 record quoting the words it searched for, and the pre-existing historical handoff text that says `jwtKey` and `adminPassword` were rotated and are not in this repo (`docs/os-handoff.md:19`, rev 75). This closeout does not add those values.

## Check 5 — status scope

New claims say Module 1 port-mirror sniffing is complete, and that symmetric RSS and AF_XDP are not started. That holds in `README.md:20`, `docs/findings/module1-slice2b/README.md:5` and `:12`, `docs/os-handoff.md:3-11`, `docs/os-handoff.md:34`, `docs/os-handoff.md:187`, `docs/os-handoff.md:262`, `docs/tool-install/module1-slice2b-boot-unit.md:3`, and `docs/sessions/2026-11-12-module1-slice2b-closeout.md:33-37`. Host LSM stays deferred. N5's looser "Module 1 complete" phrase is gone.

## Findings

No blocking findings.

No nits.
