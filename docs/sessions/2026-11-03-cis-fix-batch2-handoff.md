# Johnny handoff → new session: CIS L1 fix pass, Batch 2 onward (2026-11-03)

Repo `ajeswint/strix-halo-johnny`; `git pull` first. Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 18 or later). The project is "Johnny", never "Sentinel". Reply to AJ as Detail → Relay (for Grok) → Outline.

**Method, batch table, owed decisions, "every change" steps and the Don't list:** `docs/sessions/2026-10-31-cis-fix-handoff.md`. That brief still holds, except where this one updates it.

## Where it stands
- **Gate met** (rev 16). SSH key login to Johnny works (`ssh aj@192.168.50.152`).
- **Batch 1 done** (file modes; applied 2026-11-03 05:05–05:30 UTC). Totals **147 pass, 104 fail, 23 N/A**. Record: `docs/cis-fix/batch-1.md` (rev 2), `docs/findings/cis-batch-1-review.md`, handoff step 10 + Config changes, `etc/` mirrors.
- **Decided (AJ, 2026-11-03), applies to later batches too:** re-check verdicts are **edited in place** in `docs/cis-26.04-l1-results.csv` (targeted line edits; git keeps the audit verdict); mode-only changes are recorded as Config changes rows (with `dpkg-statoverride --list`), content changes get `etc/` copies; short CIS command quotes may stay in tracked docs; log group for fixed logs is `root adm` 0640.
- **GR4 (reboot needed?):** the login no longer shows "System restart required" and Johnny never auto-reboots. Weekly and after unattended upgrades: `cat /run/reboot-required /run/reboot-required.pkgs` (no sudo) → "No such file" (it was, 2026-11-03 05:47 UTC, kernel 7.0.0-42). If present, plan a console reboot.
- **Recurring checks GR1–GR3** (handoff step 10). GR1 first due after 00:10 UTC 2026-11-04 (6:10 PM CT Nov 3): `find /var/log/sysstat -type f -perm /0137` → nothing.

## Next: Batch 2 (package removal)
- **AJ decided:** include `nftables` in the removal; keep the `nf_tables` kernel module (ufw needs it).
- **Platform draft:** `docs/cis-fix/batch-2.md` + `docs/cis-fix/batch-2-sim.txt` (live read 2026-11-03 05:37 UTC). Key points: mark 43 packages manual first, then one `apt-get remove` of the 9 (`ubuntu-standard ftp tnftp telnet inetutils-telnet rsync ntfs-3g fuse3 nftables`) removes 9 and installs 0; `ftp` alone would pull `ftp-ssl`; a careless `--autoremove` takes 38 packages incl. sysstat, tcpdump, mtr-tiny. rsync must be purged for 2.1.13 ([Assumption] in the draft). ufw → iptables, which only recommends nftables.
- **Not reviewed.** AJ stopped Assurance's review mid-run; no review file exists. **First step: Assurance reviews batch-2.md** (incl. its own `apt-get -s` on Johnny), then AJ's decisions, then commands.
- **AJ decisions owed for Batch 2:** `apt update` first (Platform rec no; re-check list age at apply time); remove the 2 orphan libs `libnftables1`, `libntfs-3g89t64` (Platform leans yes); purge leftover nftables/fuse3 configs (default keep); accept the 43 manual marks (rec yes).
- After apply: Governance re-audits 2.1.13, 2.2.4, 2.2.6, 7.1.13 (expect 13 SUID, 6 SGID); SBOM in the handoff lists the removed packages.

## Notes
- Agents never run sudo, not even `sudo -n` (a Platform read once included a `sudo -n true` probe; the permission check blocked it).
- Batch 3 (logging) is next after Batch 2. 1.6.2, 1.6.3, 1.6.12 (Batch 5) and 1.6.5 (Batch 8) are the remaining section 1.6 fails.
- Paperclip trial (handoff step 13): all 10 agents paused; nothing changed this session.
