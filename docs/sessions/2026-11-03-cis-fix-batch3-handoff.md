# Johnny handoff → new session: CIS L1 fix pass, Batch 3 onward (2026-11-03)

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 27 or later). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (the seat replying writes it; Grok's is for Claude, Claude's is for Grok) → Outline.

**Model seats (AJ, 2026-11-03):** Grok writes. Claude, as Assurance, reviews and does not edit the draft. `docs/cis-fix/batch-3.md` rev 3 was written before this rule. Further edits are Grok's. The rev 3 spot-check was the Assurance agent's. Claude reviewed commits `bca0b41`, `c34b4c5`, `e40584d`, and `44efe85` (approve with changes; the fixes are in rev 4).

**Method, batch table, owed decisions, "every change" steps and the Don't list:** `docs/sessions/2026-10-31-cis-fix-handoff.md`. That brief still holds, except where this one and `2026-11-03-cis-fix-batch2-handoff.md` update it (re-check verdicts edited in place; mode-only changes as Config changes rows; log group `root adm` 0640).

## Summary (2026-11-03 20:20 CT)

Batch 3 is applied. Claude's sign-off is C4, A1b and the checkpoints only. B5 passed. The 05:00 UTC run, the second C9, and the re-audits are pending. Johnny is otherwise unchanged since Batch 2. Full state is `docs/os-handoff.md` rev 36. Rev 35's summary said rev 34 (`0fa0ac9` and later); that pointer is rev 35 (`1f917c8`). Claude reviewed C4, A1b, and the checkpoint results, not C1–C10 in full.

**On Johnny**
- Group A: journald cap `SystemMaxUse=1G` (was `max 4G`). Drop-in `/etc/systemd/journald.conf.d/60-rotation.conf`. Reload 09:22:46 UTC, same process. Seven journal files `640 root:systemd-journal`.
- Group B: `/etc/logrotate.conf` is `rotate 13` and `maxage 90`. `rsyslog` and `ufw` are `rotate 13`. B3 passed (`MODES-UNCHANGED`).
- Group C: `aide` and `aide-common` 0.19.2-3, `liblockfile1` and `liblockfile-bin` 1.17-2build2, no Postfix. `_aide` is uid/gid 982. `dotlockfile` is `755 root:mail`. Database `/var/lib/aide/aide.db` (init 3m 13s, return code 0, 111497 entries). C6 took 3m 8s. Timer next run 05:00 UTC (11:00 pm CT Nov 3). `aide.db.new` from that check is left alone.
- CIS totals are still **151 pass, 100 fail, 23 N/A** until Governance re-audits.

**Who does what next**
- B5 has run (Grok, read-only, ~02:08 UTC Nov 4). `Finished logrotate.service - Rotate log files.` at 00:00:47 UTC. `is-failed` printed `inactive` (exit 1). No `error:` line. The recorded next elapse was 00:23 UTC; that difference was not checked. Output is in `docs/cis-fix/batch-3.md` B5.
- The AIDE timer fires at 05:00 UTC Nov 4 (11:00 pm CT Nov 3).
- Trigger for the second pass: **AJ says go**, on the later Central morning of Nov 4. **[Assumption]** no clock time was named. The window lasts until 00:00 UTC Nov 5 (6:00 pm CT Nov 4).
- Timezone check first (Grok, read-only): `timedatectl show -p Timezone --value`. Confirmed 2026-11-04: `Etc/UTC`. `--since today` depends on it.
- AJ, shown first, sudo C9 lines 2, 6, 7, 11, 13, 15.
- Grok, no sudo: C8; C9 lines 1, 3, 5, 8–10; line 4 unless it returns permission denied (then AJ runs it with sudo); lines 12, 14, 16 once AJ's files exist; `journalctl -u dailyaidecheck.service --since today --no-pager | tail -5` (expect `Finished`); the 05:00 run's total, added, removed, and changed counts.
- Governance: re-audit 6.1.1.1.5, 6.1.2.7, 6.3.1, and 6.3.2.
- Batch 4 after those re-audits. Not started.

**Still open**
- Entry count: init 111497 + 1 added = 111498. C6's total line says 111499. Removed 0, changed 5. The added path, re-read by `aj` with no sudo, is `/run/systemd/journal/streams/10:47893`. The gap of 1 stays unreconciled. Not a stop.
- B5 also on 2026-11-08 and 2026-12-01.
- GR1 (after 00:10 UTC 2026-11-04) was not run this session.
- DMT Console `jwtKey` and admin password are still not rotated.

## Where it stands
- **Batch 1 (file modes) and Batch 2 (package removal) done.** Totals **151 pass, 100 fail, 23 N/A**. Records: `docs/cis-fix/batch-1.md`, `docs/cis-fix/batch-2.md` (rev 3, applied), `docs/findings/cis-batch-1-review.md`, `docs/findings/cis-batch-2-review.md`, handoff step 10 + Config changes + SBOM.
- Johnny rebooted at 06:17 UTC 2026-11-03 on the rebuilt initrd (unattended, TPM unlock worked). Kernel 7.0.0-42.
- **Recurring checks GR1–GR4** (handoff step 10). GR1 first due after 00:10 UTC 2026-11-04. After any `apt install`, also re-run the three CIS 2.1.13/2.2.4/2.2.6 audit lines (Batch 2 packages can come back).

## Lessons from Batch 2 (apply to every package change)
- **Read maintainer scripts and triggers, not just dependencies.** Removing `fuse3` rebuilt the only initrd (dracut). Before any package change, check `/var/lib/dpkg/info/<pkg>:*.{postinst,postrm,triggers}` for `update-initramfs`, and plan the baseline + copy + reboot proof.
- **Don't assume AJ has a console open.** The AMT KVM launch tool is not recorded in the repo. Ask AJ which tool they use before any step that needs the console, and record it in the handoff.
- Agents never run sudo, not even `sudo -n`.

## Batch 3 status (2026-11-03 ~01:15 CST): drafted, reviewed once, nothing run on Johnny
- **Done:** AJ ran `sudo apt update` (~06:45 UTC; lists fresh, all up to date). Governance vetted AIDE: `docs/findings/aide-vetting.md`, APPROVE WITH CONDITIONS. Platform drafted `docs/cis-fix/batch-3.md` **rev 3** (journald 6.1.1.1.5, logrotate 6.1.2.7, AIDE 6.3.1/6.3.2). Assurance reviewed rev 2: `docs/findings/cis-batch-3-review.md`, APPROVE WITH CHANGES (3 Medium, 7 Low, 2 Info, no High); Platform applied F1-F10 in rev 3.
- **Rev 3 spot-check done** (the Assurance agent, 2026-11-03): addendum in `docs/findings/cis-batch-3-review.md`. F1–F12 landed. Verdict APPROVE WITH CHANGES, one Low (S1, assumption 9). Grok applied S1. C3a was not run on Johnny. Claude did not do that spot-check. Claude reviewed `bca0b41`, `c34b4c5` and `e40584d` and approved each. AJ (2026-11-03): no extra pass over C1–C10, and no narrower pass over C1, C2 and C7.
- **`adeinit.still-running` is the package's spelling.** `/usr/sbin/aideinit` in aide-common 0.19.2-3 touches that name (lines 136 and 139). C3's `ls` stays. The `.deb` sha256 matches the SBOM row. The confirmation lives in `docs/cis-fix/batch-3.md`. The findings file keeps Assurance's own note and does not carry the writer's settlement.
- **AJ decided:** accept R-AIDE-1; install resolute aide/aide-common 0.19.2-3 with `--no-install-recommends` (no Postfix); multiple hashes cover only the null-byte bypass GHSA-6wc9-4w69-5jc5; the invalid-UTF-8 bypass GHSA-wq25-fm54-5q3q stays open until Ubuntu ships 0.19.5 for 26.04; `dailyaidecheck.timer` held until the DB is initialised, then 05:00 UTC.
- **Q6 is answered, not owed.** In `docs/cis-fix/batch-3.md` the open-question list, item 6 is marked answered (AJ, 2026-11-03): R-AIDE-1, option A (install 0.19.2-3 now, `--no-install-recommends`, multiple hashes, track Ubuntu for 0.19.5). An earlier Q6, "run `apt update`", was answered the same day and removed. That is why the owed list goes Q5 then Q7.
- **AJ decided (2026-11-03, all recs, Q1–Q5 and Q7–Q10).** Q1 keep `maxage 90`. Q2 run B2 (`rsyslog` and `ufw` to `rotate 13`). Q3 accept the conffile residual. Q4 keep the recorded journal caps, including `SystemMaxUse=1G`. Q5 run `journalctl --rotate` (A1b). Q7 `dpkg-statoverride` `dotlockfile` to 0755. Q8 read `/var/log/aide/aide.log` by hand. Q9 `RandomizedDelaySec=0` when C6 is under 50 minutes; at 50 or more, stop before C7. Q10 run C6 before C7. Q6 was already answered. Claude's review of `44efe85` says these recorded answers match AJ's, and the Q9 stop before C7 is in the draft. Nothing in Batch 3 has run.
- **Claude's review of `44efe85` (2026-11-03): approve with changes.** Scope Claude actually reviewed: C4 and A1b. C1–C10 were not reviewed beyond C4, per AJ. Two fixes, both applied by Grok in `docs/cis-fix/batch-3.md` rev 4. C4 (Medium): `--add root mail 0755` so the override changes the mode only; expected output is `755 root:mail` and `root mail 755`; the rollback `chmod 2755` then leaves group `mail`. A1b (Low): the block is below A2; it runs `journalctl -u systemd-journald -n 6 --no-pager` and `journalctl --disk-usage` after `journalctl --rotate`; the SIGUSR2 claim is dropped; the new file's `640` mode is **[Assumption]**. The rev 2 findings file still shows GC6 as `root root 755`. That line is not the current expected output. The writer does not edit the findings file.
- **Apply path (AJ, 2026-11-03).** Grok is local and drives the apply. Grok runs the read-only SSH checks. AJ runs every sudo block, and Grok shows that block first. Claude reviews the rev 4 commit before Group A, then reviews at the end of each group and at the C6 gate. Stop on any error and paste it. No console needed, no reboot. Re-run `apt-get -s` at apply time and stop if `postfix` appears. Commands one block at a time. Group A, then B, then C.
- **Files:** the rev 3 draft, AIDE vetting, and the rev 2 review were committed in `de05a74`. The rev 3 spot-check addendum and S1 are in `bca0b41` (handoff rev 23). The spelling confirmation in the draft is in `c34b4c5` (handoff rev 24). Handoff rev 25 takes the writer's sentence back out of the findings file. After install: record `_aide`, the 4 `.deb` hashes, R-AIDE-1 (accepted) in the SBOM, Config changes and risk register; re-run the three CIS 2.1.13/2.2.4/2.2.6 lines and GR1-GR4.
- **Johnny:** Batch 3 Groups A, B, and C are applied through the first C9. Claude's sign-off on `de0113e` is C4, A1b, and the checkpoints only. **Owners:** B5 has passed (Grok, read-only, 2026-11-04 00:00:47 UTC). The 05:00 UTC AIDE run is 11:00 pm CT that night. The second pass starts when AJ says go. AJ runs sudo C9 lines 2, 6, 7, 11, 13, and 15, shown first. Grok runs C8, the no-sudo C9 lines (1, 3, 5, 8–10, then 12, 14, 16), line 4 unless permission denied, and the `Finished` journal check. `--since today` covers that run until 00:00 UTC on 2026-11-05 (6:00 pm CT on 2026-11-04) while timezone stays `Etc/UTC`. Governance then re-audits 6.1.1.1.5, 6.1.2.7, 6.3.1, and 6.3.2. Batch 4 is after that. `aide.db.new` from C6 is left alone.
- **Open, not blocking:** rotate the exposed DMT Console `jwtKey` and admin password; test the console's power buttons on purpose; the 2026-11-01 KVM method is an assumption. KVM works via the Johnny KVM Desktop icon on rock-box (login username `standalone`, device "Johnny Mgmt.").
- **Token note (AJ, 2026-11-03):** usage credits are being spent; keep agent runs few and short, one spot-check at most per draft.

## Notes
- 1.6.2, 1.6.3, 1.6.12 (Batch 5) and 1.6.5 (Batch 8) are the remaining section 1.6 fails.
- Paperclip trial (handoff step 13): all 10 agents paused; nothing changed.
