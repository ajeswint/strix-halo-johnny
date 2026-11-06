# 2026-11-06 UTC (2026-11-06 ~09:57 to ~10:10 America/Chicago): Module 1 slice 1 probe applied on Johnny (read-only)

Seat: code-writer (Sonnet, effort high). Branch `claude/module1-slice1-probe-applied`, from `claude/practical-ritchie-4c6vvf` tip `9a10212` (PR #22 merged there). Docs only. **No sudo, no apt, no write on Johnny, no merge.** One read-only SSH `grep` of Johnny's `summary.txt` (below). Handoff rev 98.

**What AJ ran (2026-11-06, from rock-box, America/Chicago CST = UTC-6).**
- **Paste 1** (`user`, as `aj`, no sudo) about 09:57 CT. `DATE-UTC 2026-11-06T15:57:17Z`. Token **`M1S1-PROBE-DONE`**. No `STOP-` line. Findings are in the runbook section "Applied on Johnny".
- **Paste 2** (`root`, `bpftool` only; `sudo -v` runs on Johnny inside the `ssh -t` line) about 09:59 CT. `DATE-UTC 2026-11-06T15:59:11Z`. Token **`M1S1-PROBE-ROOT-DONE`**. No `STOP-` line. `have_xdp_prog_type yes`, `have_xskmap_map_type yes`, `OK-no-xdp-on-eno1np0`, `PROG-XDP-COUNT 0`.
- Paste 2 must run from rock-box: it `scp`s the script from the rock-box checkout path.

**What this session did.**
- `docs/tool-install/module1-slice1-span-xdp.md` rev 2: title and banner say probe applied, still no attach; new section "Applied on Johnny" (tokens, dates in UTC and CT, a results table, "what this probe did not settle"); "Applied" lines under Paste 1 and Paste 2 (paste blocks untouched); "What comes after" says AJ's path confirmation is next and that Johnny has no compiler; the assumptions list shows which are retired (MTU 1500), partly retired (bpftool key names), or still open (IRQ pins on first attach, UMEM accounting, zero-copy).
- `docs/os-handoff.md` rev 98 (banner, Rev 98 paragraph, Sequence, Next steps, Decisions) and `README.md` Sequence 4.
- This note and `docs/sessions/Johnny_Module1Slice1ProbeApplied_Session_Log_2026-11-06.csv`.

**Read-only SSH by this seat (2026-11-06 ~16:01Z).** `ssh aj@192.168.50.152`: `ls -l` and `sha256sum` of `/home/aj/cis-audit/module1-slice1-probe.sh` (sha256 `93d62537…fba47`, equals the repo file; mtime 15:59:06Z is Paste 2's `scp`), and `grep` of `/home/aj/cis-audit/m1s1-probe/summary.txt` (mtime 15:57:23Z) for the `HOST`, `KERNEL`, `DDP-LINE`, `NOTE-`, `QUEUES`, `ZC-QUEUES`, `BTF`, `BPFFS`, `SYSCTL`, `ULIMIT`, `HUGEPAGES`, `MEM-AVAILABLE`, `TOOL`, `BPFTOOL`, `PKG`, `APT-CANDIDATE`, `UNIT` and token lines. I did not read the `FEATURE`, `RING`, `RSS-HASH`, `RX-RULES`, `PRIV`, `STAT` or `FIRMWARE` lines, and I did not read `/root/m1s1-probe-root/` (root only). The brief's words "toolchain mostly absent" are replaced in the runbook by the exact lines: every compiler and loader tool probed is absent.

**Probe script unchanged.** sha256 `93d6253720dab71f1b7cc63704f844068daa2c54f7ad78922c9751ebf44fba47`. The self-test script is unchanged. Re-run on rock-box after the runbook edit: `SELF-TEST-OK`, `E2E-OK`, `STATIC-INVOCATIONS-OK 25` (it checks the runbook's hash line, tokens, paste shape and STOP table).

**Not done, on purpose.** No attach paste (1b) and no sketch change beyond the status lines. No Suricata config. `docs/agent-team.md` not touched. Soft nits N3 to N6 stay parked. No CIS change: totals **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274).

**Gaps flagged for the reviewer.**
- Whether the adversarial-reviewer re-reviewed the exact Paste 1 and Paste 2 after the B1/B2 fix is not in the repo (rev 97 said not re-reviewed). The runbook says so.
- Paste 2's full `BPF-XDP-HELPER` and `BPF-FEATURE` lines, and whether any `NOTE-feature-key-absent` printed, are not in the closeout brief; the runbook marks the key-name assumption only partly retired.
- The runbook's "Applied" table rests on AJ's relayed output plus my `summary.txt` grep; the raw files stay on Johnny and are not committed.
- The martian count comparison (3478 vs step 11's 2477) assumes the same command per the runbook table; no rate or cause is claimed.

**Next open.** AJ confirms the path choice (native-XDP observer, always `XDP_PASS`, is a draft recommendation). Then the slice 1b attach draft, in its own PR, with the compiler question as an input. Johnny needs no further paste for this closeout.
