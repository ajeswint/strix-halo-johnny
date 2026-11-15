REQUEST-CHANGES

Review 2 of PR #39 tip `146dfcd` against `ded80c6`, fixes in `git diff cc4caec..HEAD`. Docs-only. No repo edits, no SSH, no sudo, no contact with 192.168.50.152. `bash docs/tool-install/module1-slice2b-self-test.sh` on this host exited 0: `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=15`, `OUTSIDE-FENCE-DIFF-OK blocks=17`, `RUNBOOK-OK blocks=22`, `SELF-TEST-OK`. All 22 ` ```bash ` fences in `docs/tool-install/module1-slice2b-boot-unit.md` are byte-identical to `ded80c6`. `git diff --name-only ded80c6..HEAD` is 11 `.md` files and nothing else. No secrets (no passwords, keys, or tokens; the apply file adds operational ids already in the handoff plus `READER-MAINPID=25996`).

Resolved from review 1 (re-opened the cited lines; these hold):
- B1. Tag `b5b852630d7539c7` is gone. `docs/architecture/architecture-pass.md:11` now cites `prog_id=78` to `docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md:48` (`ATTACH records 78`), object hash to `:24`, `struct m2_rec` to `docs/tool-install/module1_xdp_records.c:133-165`, `M2_REC_VERSION 1` to `:78`, and the 4 MiB ring to `:80` (`M2_RB_BYTES (1 << 22)`) and `:218-221` (`m2_rb`).
- B2. The retargeted cites contain the claimed text. Checked: `docs/os-handoff.md:405` (6.2 GB idle), `:201` (CPUs 1, 2, 3, 4) and `:289` (`CAPTURE-CPUS 1 2 3 4`), `:84` and `:109` (`7.0.0-42-generic`, recorded fact, not an Assumption), `:81` (rev 98 probe: `kernel config BPF_SYSCALL, XDP_SOCKETS, ICE, BTF ok`), `:115` (XFS root layout), `:326` (FICLONE same-FS only), `:17` and `:36-39` (retention numbers), `:19-22` (`rate=1000000 burst=100000`), `:370` (`suricata | 1:8.0.3-1`) and `:375` (disabled, inactive), `:90` (225 PASS, 18 PASS manual, 31 N/A, 0 FAIL), `docs/agent-team.md:260`, `:85`, `:264`, `:265`, `:266`, `:267`, `:268`, `:54`, `:97`, `:113`, `:52`. `README.md:18` is the queue-spread sentence. Paste W's clock is `docs/tool-install/module1-slice2b-boot-unit.md:3` and `docs/os-handoff.md:10`; `:583-596` is only labeled as the runbook fence (heading at `:583`, fence opens at `:587`). Gap row 6 splits BrightCloud `docs/BEGIN_Network_Security_Software_Enterprise.md:13-17` (200+ TB), `<100 ms` to `docs/Security Software Architecture Overview.md:70`, and millions of endpoints to BEGIN `:42`.
- B3. "What the repo says" keeps per-process K3 (`docs/JOHNNY_ Executive Architectural Summary.md:87-94`) and quotes both LTL disjuncts, including `dst ∈ WhiteList` and `CoWCloned(f) U Verdict(p)` (`summary:70-75`). The network-entity map, actor table, and mermaid sit inside Option 1 and are labeled a proposal (`architecture-pass.md:222-224`). Known-Bad recovery agrees: mermaid `:233` and table `:245` both go to Known-Good, AJ only. The SLM tighten row is marked "only if AJ picks Item A Option 1" (`:241`). The gap formula cite (`:365`) names `summary:26` and `summary:75` as two formulas. Leftover second exit is N1.
- B4. The compiled-consumer prescription, the schema-header design advice, and the `#[repr(C)]` / shared-header advice are gone. `:320` and `:469` say language per §4 question 2. `:382` reports `docs/agent-team.md:52` and `summary:77-98` (`#[repr(C)]` is on `summary:97`) and says AJ has not adopted Rust or an ABI. `:380` matches the reader: 96-byte header at `docs/tool-install/johnny-m1s2b-reader.py:58-63` (magic `JM1S2RB\0`, `HDR_VERSION = 1`, `m2_cfg` snapshot, `m2_ctl` start sums) plus 80-byte records. VLAN is present (`module1_xdp_records.c:128` `F_VLAN`, `:132` `F_VLAN_DEEP`, `:142` `vlan_tci`). §4 (`:338-353`) still asks eight questions and does not answer them.
- B5. The 4B / 1.5–3.5 GiB band is gone. `:34` calls an on-box fit an unverified assumption and cites `summary:7` ("4-bit quantized") and BEGIN `:4720` ("e.g., Qwen-1.5B"), which say that and do not give a RAM band. Decision 3 (`:424`) does not claim a RAM fit; it points at `README.md:25`. `rate_limited 18217138` is in the committed Paste A/C transcript (`docs/findings/module1-slice2b-no-ratecap/2026-11-14-apply-output.md:23`, `:78`, `:90`) and `docs/os-handoff.md:7` cites those lines.
- B6. The named false cells are fixed. Row 5 (`:367`) describes the unit that exists: `etc/systemd/system/johnny-m1s2b-reader.service:11` `User=root`, `:32-34` `PrivateNetwork=yes` / `IPAddressDeny=any`, `:36-41` `NoNewPrivileges`, empty capability sets, `ProtectSystem=strict`, `ReadWritePaths` limited to the ring pin and the output dir, `:63` `@system-service bpf`. CIS totals match `docs/os-handoff.md:90`. AST, NDIS/eBPF, and ClickHouse/Snowflake are gone. Needs cells on rows 1–9 are questions, including Items D and E (`:365`) and Item B (`:366`). Webroot shadow cache stays on BEGIN `:67-89` and `WRkrn.sys` on the overview. Uncited remainder of the gap sentence is N3.
- B7, Item E body only. `:176` no longer gives a RouterOS command. It says advisory MAC ACL or VLAN actions, never port shutdown, and "exact RouterOS commands are not in this brief." No `/interface` line and no `action=drop` remain in Item E. `:177` says management only on `ether1`, not manageable from the LAN (`docs/network-map.md:22-23`), not an air-gap. `:181` restricts Option 2 to MAC ACL or VLAN manipulation. The decision summary was not updated. That is B1 below.
- N1. `:135` says the clone is faster than a physical copy, same mounted filesystem, `EXDEV` if not, and cites `ioctl_ficlone(2)`. "O(1)" and "every mount point" are gone. `reflink=1` is marked Assumption at `:137`.
- N2. Upstream is "the MAX" (`:48`, `:60`, `:70`, `:85`, `:423`, `:446`), cited to `README.md:26` and `docs/agent-team.md:264`. rock-box is the SFP+4 workstation (`:100`, `docs/network-map.md:12`) and the off-box build machine in §8, not a second name for the MAX. Decision 3 option C no longer says "Rock Box or the MAX".
- N3, named lines. Rev 114 heading `docs/os-handoff.md:16` says APPLIED and that the original title was DRAFTED, NOT APPLIED. `docs/findings/module1-slice2b/README.md:13` and `README.md:20` say retention 2026-11-14 19:18Z, cfg 1000000/100000 at 21:32Z, week test to 2026-11-21 15:33 CT. `architecture-pass.md:96-98` quotes the updated README sentence. Runbook status `docs/tool-install/module1-slice2b-boot-unit.md:3` matches those clocks and the 32812/32812 window. The pin ledger under that status does not. That is B2.
- N4. `:10` says verified at the 21:32Z window, week test in progress. `:100` says configured mirror sources and no link on SFP+3 at the 2026-10-29 audit (`docs/network-map.md:11`, `:25`). "sub-second" is gone. Item B Option 2 (`:75`) says a LAN client with encoding and interface per §4. No "JSON-over-TLS".
- N5. `docs/os-handoff.md:9` now has `PASS-RATIO tcpdump=486 xdp=582 pct=83` and `ETHTOOL-DROP-DELTAS none (checked=16)`. Those strings are the transcript lines `apply-output.md:59` and `:62`. `WINDOW secs=60 seen-delta=32812 emitted-delta=32812` is `:65`. Handoff also states VERIFY-DROPS 0/0/0, which is transcript `:60`, not in the `:59, 62, 65` cite. See N4.
- N6. Milestone 4 (`:470`) is only if AJ picks Item F Option 1. Milestone 7 (`:479-481`) is only if AJ picks Item A Option 1 and Item B Option 1, and names mTLS or WireGuard as that option. Milestone 6's condition is not a decision option. See N2.
- N7. NIST SP 800-207, SP 800-218, and the Webroot white-paper index are gone. RFC 9420 and RFC 8446 are used at `:68`. The BPF LSM page is used at `:103`. `ioctl_ficlone(2)` at `:135`. AML.T0051 at `:35`, still labeled as the pass's application of `summary:166` to network payloads. The CrowdStrike PDF is used at `:363`.

Holding (do not churn):
- Items A–F and Decisions 1–6 each end with `AJ decides.` Options inside each item are distinct. Each recommendation has a one-sentence reason. §4 does not pick a language, library, layout, or schema.
- `docs/agent-team.md:263` still says the pass started and every item is AJ decision pending.
- Runbook Decisions item 1 (`module1-slice2b-boot-unit.md:23`) still records the 2026-11-11 choice "Rate left at 8000/16000". Review 1 held that section, and the bash fences, untouched. Not re-opened. The status line is `:3`.
- Older handoff rev bodies stay historical. Rev 111 `:71` and rev 112 `:49-50` still say 8000/16000 and DRAFTED. Rev 115 at the top is the live state.
- §6 `:385`, `:388`, and `:391` restate the Item E / D / B recommendations as lock-in advice. They do not name a language, library, or ABI. The `#[repr(C)]` sentence at `:382` is cited source text and says AJ has not adopted it.
- Nothing in the diff tells AJ to run a command on Johnny before 2026-11-21 15:33 CT. The LSM and `reflink=1` checks say after the week test, read-only. Milestone 1 is after that clock. 15:33 CT in November is CST (UTC-6); 21:33Z on `docs/os-handoff.md:10` matches.
- Commercial-column generalizations that review 1 did not list, and this diff did not add, stay: "multiple times daily" (`:364`), "tens of thousands of endpoints" (`:366`), "billions of events per day" (`:369`), and the uncited "CrowdStrike Threat Graph … in real time" clause (`:368`). Not new.
- Quote check on the K3 comments, LTL, BEGIN `:4734-4737` (relax χ² / tighten), overseer §8 (`docs/findings/overseer-review-os-gate.md:188`), and `summary:174-176` (Module 2 SPA and LPM trie; Module 3 ringbuf consumer) matches the lines.

## B1. Decision 2 option A still says Johnny outputs exact RouterOS commands
`docs/architecture/architecture-pass.md:411`

Item E was fixed. Decision 2 was not. The line is:

`A. Human-in-the-Loop Advisory (Johnny detects and outputs exact RouterOS commands; AJ reviews and applies from laptop).`

That is the same claim review 1 rejected at Item E. Item E `:176` now says the opposite: advisory MAC ACL or VLAN actions, and "exact RouterOS commands are not in this brief." There is no RouterOS command text in Item E (no `/interface`, no `action=drop`, no `chain=`).

The next option was also left behind. `:412`:

`B. Programmatic Switch Management (Johnny given dedicated API/SSH access to CRS309 with restricted bridge filter user).`

"bridge filter" is not a command line. It is the mechanism Item E Option 2 no longer uses. `:181` says programmatic RouterOS API or SSH restricted to MAC ACL or VLAN manipulation, which is the repo's words (`README.md:28`, `docs/agent-team.md:97`, `:113`).

Fix: rewrite Decision 2 options A and B so they match Item E `:176` and `:181`. Option A must not say Johnny outputs exact RouterOS commands, and must not contain RouterOS command text. Say the exact lines are not in this brief.

## B2. Two current-state lines still say the rate cap is not applied
`docs/tool-install/module1-slice2b-boot-unit.md:45-59`
`docs/findings/module1-slice2b/README.md:11`

The status lines agree: `README.md:20`, findings README `:13`, runbook `:3`, and handoff rev 115 `:4-10` all say retention applied 2026-11-14 19:18Z, cfg 1000000/100000 applied 2026-11-14 21:32Z, week test to 2026-11-21 15:33 CT. Handoff `:14` pins the live helper at `a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb`.

The runbook pin ledger contradicts that. `:45-52` is headed "Live on Johnny (rev 113 retention…)" and lists boot helper `0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f`. `:55` says "Rate cap removal draft (this PR, NOT APPLIED; apply via the Rate cap removal section)" over the hash handoff says is live (`a4d4dfa4…`).

Findings README `:11` is present tense in the current summary, directly above the applied bullet: "Rate is left configured at 8000/16000; still AJ's call whether to revisit."

Fix: in the runbook pin ledger, outside every bash fence, mark `a4d4dfa4…` as the helper applied 2026-11-14 21:32Z and stop calling it NOT APPLIED. Point the 8000/16000 sentence at `:11` at the cold-boot observation, and say the live cfg is the one in the next bullet. Do not edit the Decisions section or any bash fence. Re-run `bash docs/tool-install/module1-slice2b-self-test.sh`.

## N1. Item F still claims one Known-Bad exit while the mermaid has two
`docs/architecture/architecture-pass.md:224`, `:234`, `:247`

The review 1 contradiction (mermaid to Unknown, table to Known-Good) is gone. Both recovery edges go to Known-Good, AJ only (`:233`, `:245`). Prose `:224` and the pros at `:247` still say a single exit from Known-Bad. The mermaid `:234` adds `KnownBad --> [*]: Purged / Decommissioned`, which the table does not list.

Fix: drop the purge edge, or add that row to the table and stop saying the exit is single.

## N2. Milestone 6's condition is not a decision in this brief
`docs/architecture/architecture-pass.md:476-478`

Milestones 4 and 7 name Item F Option 1, Item A Option 1, and Item B Option 1. Milestone 6 says "only if AJ picks local detection engines". No item or decision offers that option. The capability line still says correlation with "the $K_3$ entity verdict engine", which is Item F Option 1, and that gate is only on milestone 4.

Fix: name the decision that would turn Suricata or Zeek on (or leave the milestone out until that decision exists), and gate the K3 correlation on Item F Option 1 the way milestone 4 does.

## N3. The tamper-gap sentence is still uncited
`docs/architecture/architecture-pass.md:367`

The systemd controls and the CIS totals are cited and match the files. The new remainder, "no kernel anti-tamper protecting the daemon from root termination, and no measured pin-mode security beyond filesystem root ownership", has no file. Review 1 allowed that gap sentence only with a cite. `johnny-m1s2b-reader.service` does not mention pin mode.

Fix: cite the file that shows the absence, or delete the pin-mode clause and leave the gap as the missing kernel anti-tamper, stated as not documented in the unit.

## N4. Handoff's Paste C cite skips the VERIFY-DROPS line
`docs/os-handoff.md:9`

The sentence includes `VERIFY-DROPS rate_limited=0 rb_full=0 discarded=0` and cites `docs/findings/module1-slice2b-no-ratecap/2026-11-14-apply-output.md:59, 62, 65`. `:59` is the PASS-RATIO line, `:62` is ETHTOOL `checked=16`, `:65` is the 60 s WINDOW. VERIFY-DROPS is `:60`. The words match. The cite does not include them. `architecture-pass.md:14` cites `:58-67`, which does include `:60`.

Fix: add `:60` to the handoff cite.

## N5. Item A Option 3 still names an interface
`docs/architecture/architecture-pass.md:51`

Item B Option 2 was changed to "encoding and interface per §4" (`:75`). Option 3's cost still says "requires defining LAN RPC/mTLS schema." That picks an interface inside an option §4 question 4 and question 5 have not answered. mTLS as Item B's transport choice is the decision itself; an RPC schema is not.

Fix: say the off-box option needs a LAN channel to the MAX, and leave the schema in §4.
