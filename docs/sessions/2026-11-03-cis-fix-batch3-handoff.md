# Johnny handoff → new session: CIS L1 fix pass, Batch 3 onward (2026-11-03)

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 19 or later). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (for Grok) → Outline.

**Method, batch table, owed decisions, "every change" steps and the Don't list:** `docs/sessions/2026-10-31-cis-fix-handoff.md`. That brief still holds, except where this one and `2026-11-03-cis-fix-batch2-handoff.md` update it (re-check verdicts edited in place; mode-only changes as Config changes rows; log group `root adm` 0640).

## Where it stands
- **Batch 1 (file modes) and Batch 2 (package removal) done.** Totals **151 pass, 100 fail, 23 N/A**. Records: `docs/cis-fix/batch-1.md`, `docs/cis-fix/batch-2.md` (rev 3, applied), `docs/findings/cis-batch-1-review.md`, `docs/findings/cis-batch-2-review.md`, handoff step 10 + Config changes + SBOM.
- Johnny rebooted at 06:17 UTC 2026-11-03 on the rebuilt initrd (unattended, TPM unlock worked). Kernel 7.0.0-42.
- **Recurring checks GR1–GR4** (handoff step 10). GR1 first due after 00:10 UTC 2026-11-04. After any `apt install`, also re-run the three CIS 2.1.13/2.2.4/2.2.6 audit lines (Batch 2 packages can come back).

## Lessons from Batch 2 (apply to every package change)
- **Read maintainer scripts and triggers, not just dependencies.** Removing `fuse3` rebuilt the only initrd (dracut). Before any package change, check `/var/lib/dpkg/info/<pkg>:*.{postinst,postrm,triggers}` for `update-initramfs`, and plan the baseline + copy + reboot proof.
- **Don't assume AJ has a console open.** The AMT KVM launch tool is not recorded in the repo. Ask AJ which tool they use before any step that needs the console, and record it in the handoff.
- Agents never run sudo, not even `sudo -n`.

## Next: Batch 3 (logging), 4 rules
6.1.1.1.5, 6.1.2.7, 6.3.1, 6.3.2: journald drop-in, logrotate (weekly, rotate 13, maxage 90), AIDE install + init + daily 05:00 UTC timer. Lockout risk none.
- **AIDE and `aide-common` are package installs.** Governance vets them first (license, maintainer, CVE history; AJ approved AIDE once vetted). `apt-get -s` first, read every line, and check the new packages' scripts and triggers for initramfs or boot-path effects.
- Decisions owed for Batch 3: `apt update` before the install (lists age at apply time; Batch 2 chose no because nothing was installed); AIDE database location and init timing.
- Order: Platform drafts → Assurance reviews → AJ's decisions → commands one block at a time (Brain runs read-only checks over SSH; AJ runs sudo).
- Then Batch 4 (kernel params and modules, reboot) per the method brief.

## Notes
- 1.6.2, 1.6.3, 1.6.12 (Batch 5) and 1.6.5 (Batch 8) are the remaining section 1.6 fails.
- Paperclip trial (handoff step 13): all 10 agents paused; nothing changed.
