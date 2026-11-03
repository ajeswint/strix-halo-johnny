# Johnny handoff → new session: CIS L1 fix pass, Batch 3 onward (2026-11-03)

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 23 or later). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (Grok writes it, Claude reads it) → Outline.

**Model seats (AJ, 2026-11-03):** Grok writes. Claude reviews and does not edit the draft. `docs/cis-fix/batch-3.md` rev 3 was written before this rule. Further edits are Grok's. The rev 3 spot-check is Claude's review.

**Method, batch table, owed decisions, "every change" steps and the Don't list:** `docs/sessions/2026-10-31-cis-fix-handoff.md`. That brief still holds, except where this one and `2026-11-03-cis-fix-batch2-handoff.md` update it (re-check verdicts edited in place; mode-only changes as Config changes rows; log group `root adm` 0640).

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
- **Rev 3 spot-check done** (Assurance, 2026-11-03): addendum in `docs/findings/cis-batch-3-review.md`. F1–F12 landed. Verdict APPROVE WITH CHANGES, one Low (S1, assumption 9). Grok applied S1. No re-review. C3a was not run on Johnny.
- **AJ decided:** accept R-AIDE-1; install resolute aide/aide-common 0.19.2-3 with `--no-install-recommends` (no Postfix); multiple hashes cover only the null-byte bypass GHSA-6wc9-4w69-5jc5; the invalid-UTF-8 bypass GHSA-wq25-fm54-5q3q stays open until Ubuntu ships 0.19.5 for 26.04; `dailyaidecheck.timer` held until the DB is initialised, then 05:00 UTC.
- **Q6 is answered, not owed.** In `docs/cis-fix/batch-3.md` the open-question list, item 6 is marked answered (AJ, 2026-11-03): R-AIDE-1, option A (install 0.19.2-3 now, `--no-install-recommends`, multiple hashes, track Ubuntu for 0.19.5). An earlier Q6, "run `apt update`", was answered the same day and removed. That is why the owed list goes Q5 then Q7.
- **AJ decisions still owed (Brain recs in brackets):** Q1 global `maxage 90` [keep]; Q2 edit `rsyslog` and `ufw` stanzas to `rotate 13` [yes]; Q3 accept the conffile residual [accept]; Q4 journal cap `SystemMaxUse=1G` [keep recorded values]; Q5 optional `journalctl --rotate` proof [yes]; Q7 `dotlockfile` SGID (7.1.13 would go 13/6 to 13/7): `dpkg-statoverride` to 0755 or approve as a 7th SGID [override]; Q8 accept reading `/var/log/aide/aide.log` by hand (exit 0 on changes, no mail) [accept]; Q9 `RandomizedDelaySec=0` [yes if the first scan is under 50 min]; Q10 first manual check before enabling the timer [yes]. AJ may answer "all recs".
- **Order:** AJ's answers, then commands one block at a time (read-only checks over SSH from a host on the LAN; AJ runs sudo). No console needed, no reboot. Re-run `apt-get -s` at apply time and stop if `postfix` appears.
- **Files:** the rev 3 draft, AIDE vetting, and the rev 2 review were committed in `de05a74`. The rev 3 spot-check addendum and S1 are in the handoff rev 23 commit. After install: record `_aide`, the 4 `.deb` hashes, R-AIDE-1 (accepted) in the SBOM, Config changes and risk register; re-run the three CIS 2.1.13/2.2.4/2.2.6 lines and GR1-GR4.
- **Johnny:** unchanged by Batch 3 (only `apt update` ran). Batch 2 is the last change.
- **Open, not blocking:** rotate the exposed DMT Console `jwtKey` and admin password; test the console's power buttons on purpose; the 2026-11-01 KVM method is an assumption. KVM works via the Johnny KVM Desktop icon on rock-box (login username `standalone`, device "Johnny Mgmt.").
- **Token note (AJ, 2026-11-03):** usage credits are being spent; keep agent runs few and short, one spot-check at most per draft.

## Notes
- 1.6.2, 1.6.3, 1.6.12 (Batch 5) and 1.6.5 (Batch 8) are the remaining section 1.6 fails.
- Paperclip trial (handoff step 13): all 10 agents paused; nothing changed.
