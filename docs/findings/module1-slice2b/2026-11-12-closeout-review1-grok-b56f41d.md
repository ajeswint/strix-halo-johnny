REQUEST-CHANGES

Reviewer: adversarial-reviewer (review only). Range: `git diff 6891fa3..HEAD` (commits 5ca9257, b56f41d; tip b56f41d). Worktree only. No repo edit, no commit, no push, no ssh, no sudo.

Diff is seven docs files (158 insertions, 15 deletions). No script, unit, BPF object, or sha256 pin line changed. `bash docs/tool-install/module1-slice2b-self-test.sh` in this worktree exited 0: `PINS-OK SHELLCHECK-OK STATIC-CHECKS-OK READER-TESTS-OK E2E-OK scenarios=11 RUNBOOK-OK blocks=13 SELF-TEST-OK`.

## B1 — handoff Context still states the pre-apply live state

`docs/os-handoff.md:34` (Context, Sequence bullet; not touched by this diff, contradicted by the new rev 111 text in the same file).

Present tense, and false after this closeout:

- "the live observer is now `j_xdp_observe` `driver id=138`"
- "`j_xdp_records` is not attached"
- "slice 2b boot-time j_xdp_records and persistent rotating reader drafted, not applied"
- "live Johnny remains slice 1c observer driver id=138"

Rev 111 (`docs/os-handoff.md:3-11`), Next steps (`docs/os-handoff.md:187`), the carried decision (`docs/os-handoff.md:262`), `README.md:20`, and the cold-boot transcript say the opposite: slice 2b applied 2026-11-12T04:05Z, cold-boot proven 2026-11-12T05:54:49Z, driver `prog_id=78`, `ATTACH records 78`, `observer=none`, 1c disabled/inactive, port-mirror sniffing complete.

`docs/os-handoff.md` is the current-state doc. This sentence was already stale at rev 110. This closeout makes the contradiction sharper by declaring COMPLETE above it and leaving "not applied" / "records is not attached" in the sequence agents read as current. A later session can treat Johnny as still on the slice 1c observer and cut over again.

Required fix (words only): rewrite that Module 1 clause. Keep slices 1, 1b, 1c, and the slice 2 trial in the past, including that the trial rolled back to observer `driver id=138` on 2026-11-11. Then state the live facts: 2b applied 2026-11-12T04:05Z, verified with PR #34 (`6891fa3`), cold-boot proven 2026-11-12 ~05:54Z, `j_xdp_records` attached in driver mode `prog_id=78`, `johnny-m1s2b-reader.service` enabled and active, `johnny-capture-xdp.service` disabled and inactive, port-mirror sniffing complete, symmetric RSS and AF_XDP not started, host LSM still deferred. Do not leave `j_xdp_records` "not attached" or id 138 as the live program.

## N1 — Paste R4 counts are repeated, not in a committed transcript

Same pair in:

- `docs/findings/module1-slice2b/README.md:8`
- `docs/os-handoff.md:6`
- `docs/os-handoff.md:187`
- `docs/sessions/2026-11-12-module1-slice2b-closeout.md:8`

All say Paste R4 passed with xdp 491 vs tcpdump 426 and no NIC drops. No committed file contains `xdp-pkts-delta=491` or `tcpdump-captured=426`. `docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md` is the cold-boot window (3882 / 3141), not R4. `docs/findings/module1-slice2b/2026-11-12-evidence-johnny.txt` and `docs/findings/module1-slice2b/2026-11-11-apply-output.md` do not have this window. The four cites agree with each other. They are not checkable against a saved paste.

Required fix: commit the Paste R4 verify transcript under `docs/findings/module1-slice2b/`, or mark 491 / 426 as operator-reported with no saved paste. Do not invent a pct; the docs do not claim one, and integer `426*100/491` is 86, which is not in the text.

## N2 — ordering-cycle gate fail-opens if journalctl produces no stdout

`docs/tool-install/module1-slice2b-boot-unit.md:226-227` (same text at `docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md:13-14`, `docs/os-handoff.md:8`, `docs/sessions/2026-11-12-module1-slice2b-closeout.md:14-15`).

The zero-match path is correct. Local bash (`--noprofile --norc`, pipefail off): `printf 'hello\n' | grep -ci "ordering cycle"` prints `0` and exits 1; `cyc=$(... || true)` yields exactly `0` (length 1), not empty and not `0\n0`; the `if` is false and the `&&` chain continues. One match sets `cyc=1`, prints `STOP-ordering-cycle-warning count=1`, and `false` stops the chain before the next command. `bash -n` on the Paste 8 remote script succeeded. The fence has exactly two single quotes; the remote script contains none. `|| true` is what keeps grep's exit 1 from killing the chain, and `true` writes nothing, so it does not append a second 0. `pipefail` is not set in the paste. With `pipefail` on, the same `|| true` still leaves `cyc=0` on zero matches. The `if` returns 0 when the test is false (bash: no branch taken), so `&&` continues; when the test is true, `false` is the last command in the then-list and the `if` returns 1.

What is not correct: without `pipefail`, a journalctl failure that writes nothing to stdout is the same as zero hits. `false | grep -ci "ordering cycle" || true` yields `cyc=0` and the chain continues. `journalctl(1)` on this host (systemd 261) says exit 0 on success and non-zero otherwise; `-q` also hides inaccessible-journal warnings. The old `if sudo journalctl -b --grep ...` treated any non-zero the same way (no STOP), so this is not a new hole. stderr would still show. The passing Paste 8 transcript reached `M1S2B-VERIFY-BEGIN`, which only happens after this gate, so on that boot `cyc` compared equal to `0`.

`_PID=1` is the right filter for the rev 89 messages. Those lines are manager logs (`docs/tool-install/step-13-irq-affinity.md:195-196`: `multi-user.target: Found ordering cycle: ...`). `journalctl -u` documents PID 1 unit messages as `UNIT=<name> _PID=1`. `-o cat` prints MESSAGE, which still contains `ordering cycle`. sudo's command-log line, which contains the same words, is not `_PID=1`. `--no-pager` matters because `ssh -t` is a tty; the old unpiped `journalctl --grep` could open a pager. In this pipeline journalctl's own stdout is a pipe, so a pager would not start even without `--no-pager`. Keeping `--no-pager` is still right.

Required fix, only if the gate is edited for B1's doc pass or a later paste: do not fold journalctl's failure into grep's `|| true`. Save journalctl output, keep its non-success exit as a STOP, then count matches. Leave the zero-match result as `cyc=0` with the chain alive. Not a reason to reject the gate text that already ran.

## N3 — reinstall section still says prog id 192 is the live attach

`docs/tool-install/module1-slice2b-boot-unit.md:243`. Present tense: "id 192 attached". That was the 2026-11-12T04:05Z attach (`docs/findings/module1-slice2b/2026-11-11-apply-output.md:14`, `ATTACH records 192`). After the cold boot the transcript says `driver id=78` and `ATTACH records 78`. The banner at `docs/tool-install/module1-slice2b-boot-unit.md:3` already says cold-boot proven. Mark line 243 as the pre-reboot id, or say the live id after 2026-11-12 ~05:54Z is 78.

## N4 — "COMPLETE" date can be read as 2026-11-05

`docs/os-handoff.md:262`: "Module 1 port-mirror sniffing COMPLETE (AJ, 2026-11-05 America/Chicago; slice 2b cold-boot proven 2026-11-12 ~05:54Z, rev 111)."

The cold-boot date in the same parenthesis is right (`2026-11-12T05:54:49Z` in the transcript). The 2026-11-05 date is the OS-gate / AJ-go date, sitting against COMPLETE. Split them so COMPLETE is not dated 2026-11-05.

## N5 — one sentence calls the status "Module 1 complete"

`docs/sessions/2026-11-12-module1-slice2b-closeout.md:42`: "and Module 1 complete status."

The State section of the same note (`docs/sessions/2026-11-12-module1-slice2b-closeout.md:33-37`), `README.md:20`, and `docs/findings/module1-slice2b/README.md:5` correctly say port-mirror sniffing is complete and that symmetric RSS and AF_XDP are not started. Line 42 drops that scope. Say port-mirror sniffing.

## N6 — Next steps lead paragraph dropped the parked-open tail

`docs/os-handoff.md:187` replaces the previous lead paragraph and stops at "host-side LSM deferred." The previous tail named open, non-blocking items: idle-memory investigation, the 92 °C register entry, GRUB register text, agent-team doc drift, soft nits from PR #20 and PR #22, per-step review verdicts, and architecture-logic items in `docs/agent-team.md` §7. This diff does not close them. Most still appear in the numbered steps below. The new lead paragraph does not say they are closed, but it no longer points at them. Put one sentence back so the closeout summary is not the only "what's open" line.

## Checked, not findings

Paste 8 gate, as requested. Correct for the zero-match and hit paths. See N2 for the journalctl-failure residual only.

Evidence cross-check against `docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md:22-66`. These match everywhere they are quoted (`README.md:20`, `docs/findings/module1-slice2b/README.md:9`, `docs/os-handoff.md:4-9`, `docs/os-handoff.md:187`, `docs/os-handoff.md:262`, `docs/sessions/2026-11-12-module1-slice2b-closeout.md:9-25`, session CSV row 1):

- Hashes in the transcript match the repo files and the unchanged pin block in `docs/tool-install/module1-slice2b-boot-unit.md:48-59`: object `a73c5bd2…9481`, reader `fbe2449e…d573`, reader unit `5e685d3d…c10c`, boot unit `4e2e359d…de0a`, irq helper `db58d7c7…59e4`, cores `16fbd7d1…179b`. sha256 of those seven paths (including boot helper `b3c0b6bc…1f55`) matches the pin block. The transcript prints the six `OK-*-hash` lines plus `/root/m1s2b/module1-slice2b-boot.sh: OK` (sha256sum -c, digest not reprinted). The session note's "6 sha256" list is those six `OK-*` lines.
- `prog_id=78` is `OK-xdp-mode driver id=78` before and after, `ATTACH records 78`, `PROG-XDP-COUNT 1 records=78 observer=none`. `ATTACH records <id>` is the helper's name for the pinned `j_xdp_records` id (`docs/tool-install/module1-slice2b-boot.sh:42`, `:238-253`, `:746-747`).
- `PASS-RATIO tcpdump=3141 xdp=3882 pct=80`. `3141*100/3882` is 80 in integer division, which is what `module1-slice2b-boot.sh:732` prints. Threshold is `>= 80`, and the transcript has no `NOTE-pass-ratio-low`. Docs that say 80% are quoting that token.
- Units: records and reader `enabled=enabled active=active`; 1c `enabled=disabled active=inactive`.
- `m2_ctl`: seen 33436, sampled_out 0, rate_limited 0, rb_full 0, emitted 33436, discarded 0. The "33,436 seen" wording is this CTL seen, not `STATS pkts=33433`. Window `ctl-seen-delta=3662` is not quoted as the cumulative counter.
- Apply time 2026-11-12T04:05Z matches `docs/findings/module1-slice2b/2026-11-11-apply-output.md:1`. Cold boot ~05:54Z matches `DATE-UTC 2026-11-12T05:54:49Z`.
- `ETHTOOL-DROP-DELTAS none (checked=16)` and `tcpdump-kernel-drops=0` match where quoted.

Rev 110 rate figures, repeated in the new text: `docs/findings/module1-slice2b/2026-11-12-evidence-johnny.txt` `m2_ctl` formatted sums are key 0 seen 843847, key 2 rate_limited 407183, key 4 emitted 436664 (407183+436664=843847). 407183/843847 is 48.253%. Both "~48.2%" and "~48%" are that ratio. Key order is `seen sampled_out rate_limited rb_full emitted discarded` (`docs/tool-install/module1-slice2b-boot.sh:44`). The new text does not claim the 48% question is closed; it says rate stays 8000/16000 and is still AJ's call. Cold-boot `rate_limited 0` of 33436 is what the transcript shows, over the post-boot counters, not a second 7-minute sample.

Status scope of the new sentences: port-mirror sniffing complete; symmetric RSS and AF_XDP not started; host LSM deferred. That holds in `README.md:20`, `docs/findings/module1-slice2b/README.md:5` and `:12`, `docs/os-handoff.md:3-11`, `docs/os-handoff.md:187`, and `docs/sessions/2026-11-12-module1-slice2b-closeout.md:33-37`. N5 is the one looser phrase. B1 is the contradictory stale sentence, not an over-claim in the new banner.

No secrets, passwords, tokens, or private keys in the added lines (scanned the diff for private-key blocks, `password=`, `api_key`, `AKIA`, `ghp_`, `jwtKey`).

Pins and code: `git diff --name-only 6891fa3..HEAD` is only `README.md`, the cold-boot evidence file, `docs/findings/module1-slice2b/README.md`, `docs/os-handoff.md`, the session note, the session CSV, and `docs/tool-install/module1-slice2b-boot-unit.md`. The runbook pin block is unchanged. Self-test `PINS-OK` agrees.
