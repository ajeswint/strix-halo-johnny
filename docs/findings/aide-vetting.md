# AIDE vetting: `aide` and `aide-common` for CIS L1 6.3.1 / 6.3.2

Governance, 2026-11-03. Read-only: `apt-cache`/`apt-get -s` over SSH as `aj` (no sudo), `.deb` files downloaded with `apt-get download` as `aj`, copied to a scratch dir on rock-box and read as text (nothing from the packages was run). One side effect: `apt-get download` made `~/aide-scratch/` on Johnny, which I deleted after copying (assumption: nothing else touched).

## Verdict: APPROVE WITH CONDITIONS

The packages themselves are acceptable (GPL-2+, Debian/Ubuntu-maintained, upstream actively patching, no boot/PAM/SSH/sudo/initramfs side effects). Conditions:

1. **No MTA. Install with `--no-install-recommends`.** A plain `apt-get install aide aide-common` pulls in **postfix** (a mail daemon, listening on port 25 by default) plus `bsd-mailx`, `ssl-cert`, `libnsl2`. Johnny has no MTA now. Postfix is not approved and would reopen CIS 2.2.x (mail transfer agent) questions. Exact command to use: `apt-get install --no-install-recommends aide aide-common` (4 packages, below). Leave `figlet` and any mailer uninstalled; the daily check then logs "cannot send mail" to the journal and `/var/log/aide/` instead of mailing. Report delivery is a separate, later decision.
2. **Version 0.19.2-3 is behind two open upstream advisories (both moderate, CVSS 6.2, "AIDE detection bypass", fixed upstream in 0.19.5, no CVE ID yet, no Ubuntu fix for resolute yet).** AJ must accept this residual risk (entry R-AIDE-1 below). Mitigation for the null-byte hash one: the AIDE rules use several hash functions (CIS 6.3.3 is L2 and uses `sha512`; use the `H` group or at least `sha256+sha512`). No workaround exists for the invalid-UTF-8 filename one. Re-check when Ubuntu publishes a fix (`vuln-intake`).
3. **Install does not initialise a database** (debconf `aide/aideinit` default `false`, noninteractive). Platform runs `aideinit` (or `aide --init`) separately, as AJ approves, and moves `aide.db.new` to `aide.db`.
4. **Expect a failing first run at install.** `aide-common` postinst starts `dailyaidecheck.service` and `.timer` (and the buildcache service) on first install. With no database, that first check should end with "terminated because no AIDE database is present" (read from the script; inferred, not run). This is harmless but will show a failed unit and noise in the journal. Tell the reviewers so nobody treats it as an incident.
5. **Timer time is a Platform decision.** Package default is `OnCalendar=*-*-* 01:50:00` with `RandomizedDelaySec=2h`, `Persistent=true` (so 01:50 to ~03:50 UTC, host local time). The handoff plan says 05:00 UTC. That needs a drop-in (`/etc/systemd/system/dailyaidecheck.timer.d/`), written by Platform. CIS 6.3.2 only checks that the timer is enabled, active, and the service static/enabled; the time is site policy (CIS's text says "every day at 5am. Alter the frequency and time ... in compliance with site policy").
6. **After install re-run the CIS 2.1.13 / 2.2.4 / 2.2.6 audit lines** (Batch 2 packages) and GR1-GR4, per the batch 3 handoff. `postfix`/`bsd-mailx` must NOT be present afterwards (`dpkg -l postfix bsd-mailx`).
7. Snapshot the `_aide` account: install creates a system user `_aide` (nologin, home `/var/lib/aide`). Record it in the handoff Config changes and SBOM.

## 1. Candidates (read-only, Johnny, after AJ's `apt update` ~06:45 UTC)

```
$ apt-cache policy aide aide-common
aide:
  Installed: (none)
  Candidate: 0.19.2-3
  Version table:
     0.19.2-3 500
        500 http://us.archive.ubuntu.com/ubuntu resolute/main amd64 Packages
aide-common:
  Installed: (none)
  Candidate: 0.19.2-3
  Version table:
     0.19.2-3 500
        500 http://us.archive.ubuntu.com/ubuntu resolute/main amd64 Packages
```

- Component: **main** (Canonical-supported), pocket `resolute` (release); no `-updates` or `-security` version exists yet.
- Upstream: AIDE 0.19.2 (released 2025-08-13), packaged as Debian 0.19.2-3 (Debian changelog dated 2025-10-14), synced unchanged into Ubuntu. Latest upstream at 2026-11-03 is 0.19.5 (Debian sid 0.19.5-2, forky 0.19.5-1). So resolute is three upstream releases behind.
- Downloaded `.deb` hashes (sha256, for the SBOM; as served by the archive, not independently compared to the Release file):
  - `aide_0.19.2-3_amd64.deb` `4f07f5583859e6f43f1e2e975e59c67225fcdaa529ac15f56d639cb924a21bdd`
  - `aide-common_0.19.2-3_all.deb` `3ee74fa9a633c8d7a955d89caeb68c97b06b431142313a4c63d5d7e6d2c2bcec`
- Package pages: https://packages.ubuntu.com/resolute/aide , https://packages.ubuntu.com/resolute/aide-common (not fetched; control data read from the downloaded debs).

## 2. Maintainer and upstream

- Package maintainer field (both): Ubuntu Developers `<ubuntu-devel-discuss@lists.ubuntu.com>`; Debian maintainer Marc Haber (changelog and copyright).
- Upstream: AIDE, Hannes von Haugwitz; home https://aide.github.io , source https://github.com/aide/aide/releases . Security policy (`SECURITY.md` in the package): latest release supported; private disclosure by PGP email.
- Assessment (assumption: judgment from the above): long-lived project (1999 origin), active security handling, maintained in both distros.

## 3. License

`/usr/share/doc/aide/copyright` and `aide-common/copyright` (read from the debs): upstream `GPL-2+`; `debian/*` `GPL-2+`; `debian/aideinit` a permissive "bsd-like-1"; `fopen` files BSD-3-clause-like; `getopt.h` LGPL-2+; build scaffolding files "custom" (autotools). No non-commercial or field-of-use restrictions. Fine for Johnny. No model weights or data.

## 4. CVE history and open items

Sources fetched 2026-11-03:
- Ubuntu CVE list for aide: https://ubuntu.com/security/cves?package=aide
- https://ubuntu.com/security/CVE-2025-54389 , https://ubuntu.com/security/CVE-2025-54409
- Debian tracker: https://security-tracker.debian.org/tracker/source-package/aide
- Upstream advisories: https://github.com/aide/aide/security/advisories

| ID | Severity | Affects | Status for resolute 0.19.2-3 |
|---|---|---|---|
| CVE-2025-54389 (terminal escapes in file names hide add/remove from report) | Medium, 6.2 | before 0.19.2 | Fixed upstream in 0.19.2, so **included** in 0.19.2-3 (package `NEWS` confirms: "CVE-2025-54389: Escape control characters"). Ubuntu page has no resolute row (aide 0.19.2 already past the fix). |
| CVE-2025-54409 (NULL deref on xattr, local DoS) | Medium, 6.2 | 0.13 to 0.19.1 | Fixed upstream in 0.19.2, **included**. |
| CVE-2021-45417 (local root via crafted file, old) | Medium | before 0.17.4 | Not affected. |
| CVE-2005-1849, CVE-2005-2096 | Medium | zlib bundled copy in ancient versions | Not applicable (system zlib, `Depends: zlib1g`). |
| GHSA-6wc9-4w69-5jc5 (hash compare uses `strncmp`, stops at a NUL byte; detection bypass) | Moderate, 6.2 | 0.19.4 and earlier | **Open in resolute.** Fixed in 0.19.5. CVE requested, none yet. Published 2026-10-22. Workaround from upstream: use several hash functions per rule (e.g. the `H` group). |
| GHSA-wq25-fm54-5q3q (file names with invalid UTF-8 are never matched, so silently ignored; detection bypass) | Moderate, 6.2 | 0.16 to 0.19.4 | **Open in resolute.** Fixed in 0.19.5. CVE requested, none yet. No workaround. Published 2026-10-22. |
| GHSA-79g7-f8rv-jcxh, GHSA-522j-vvx9-gg28 | Moderate | to 0.19.1 | These are the two 2025 items above (same fixes in 0.19.2). |

Notes: Ubuntu's CVE tracker has no entry yet for the two October 2026 advisories (no CVE IDs), so "no open Ubuntu CVEs" is true but misleading. These need a local user able to create a file or alter one; they weaken AIDE as a detector but do not give an attacker new privilege. Johnny is a single-purpose box with one admin account, so exposure is limited.

## 5. What the packages install (from `dpkg-deb -c` on the downloaded debs)

`aide` (amd64): `/usr/bin/aide`, man pages (`aide.1`, `aide.conf.5`), docs. No config, no units.

`aide-common` (all):
- Config tree templates under `/usr/share/aide/config/` copied by postinst (via `ucf`) into `/etc/aide/aide.conf`, `/etc/aide/aide.conf.d/` (about 190 snippets, many are executable and are run by AIDE at config read time), `/etc/aide/aide.settings.d/`, `/etc/default/aide`, `/etc/cron.daily/dailyaidecheck`.
- `/usr/sbin/aideinit`; helpers `/usr/share/aide/bin/buildcache`, `/usr/share/aide/bin/dailyaidecheck`.
- systemd units in `/usr/lib/systemd/system/`: `dailyaidecheck.timer` (enabled by postinst), `dailyaidecheck.service` (Type=oneshot, `User=_aide`, `AmbientCapabilities=CAP_DAC_READ_SEARCH CAP_AUDIT_WRITE`, no sandboxing), `dailyaidecheck-buildcache.service` (required before the check).
- `/usr/lib/sysusers.d/aide-common.conf`: user `_aide` (home `/var/lib/aide`, shell `/usr/sbin/nologin`).
- `/usr/lib/tmpfiles.d/aide-common.conf`: `/run/aide` 0700 `_aide:root`; `/var/log/aide` 2755 `_aide:adm`; `/var/lib/aide` 0700 `_aide:root`.
- Database paths in `aide.conf`: in `/var/lib/aide/aide.db`, out/new `/var/lib/aide/aide.db.new`.
- Log-mode note: `/var/log/aide` is 2755 and group `adm`; files inside may be created 0644 and could trip CIS 6.1.3.1 (log files 0640 or tighter). Platform should check after the first run (Handoff).

## 6. Dry run on Johnny (read-only), exact output

### 6a. Default (recommends pulled in): `apt-get -s install aide aide-common`

```
NOTE: This is only a simulation!
      apt-get needs root privileges for real execution.
      Keep also in mind that locking is deactivated,
      so don't depend on the relevance to the real current situation!
Reading package lists...
Building dependency tree...
Reading state information...
Solving dependencies...
The following additional packages will be installed:
  bsd-mailx liblockfile-bin liblockfile1 libnsl2 postfix ssl-cert
Suggested packages:
  figlet postfix-cdb postfix-doc postfix-ldap postfix-lmdb
  postfix-mta-sts-resolver postfix-mongodb postfix-mysql postfix-pcre
  postfix-pgsql postfix-sqlite procmail sasl2-bin | dovecot-common
The following NEW packages will be installed:
  aide aide-common bsd-mailx liblockfile-bin liblockfile1 libnsl2 postfix
  ssl-cert
0 upgraded, 8 newly installed, 0 to remove and 0 not upgraded.
Inst libnsl2 (1.3.0-3build4 Ubuntu:26.04/resolute [amd64])
Inst postfix (3.10.6-4ubuntu2.2 Ubuntu:26.04/resolute-updates [amd64])
Inst aide (0.19.2-3 Ubuntu:26.04/resolute [amd64])
Inst liblockfile-bin (1.17-2build2 Ubuntu:26.04/resolute [amd64])
Inst liblockfile1 (1.17-2build2 Ubuntu:26.04/resolute [amd64])
Inst aide-common (0.19.2-3 Ubuntu:26.04/resolute [all])
Inst bsd-mailx (8.1.2-0.20220412cvs-1.1build1 Ubuntu:26.04/resolute [amd64])
Inst ssl-cert (1.1.3ubuntu2 Ubuntu:26.04/resolute [all])
Conf libnsl2 (1.3.0-3build4 Ubuntu:26.04/resolute [amd64])
Conf postfix (3.10.6-4ubuntu2.2 Ubuntu:26.04/resolute-updates [amd64])
Conf aide (0.19.2-3 Ubuntu:26.04/resolute [amd64])
Conf liblockfile-bin (1.17-2build2 Ubuntu:26.04/resolute [amd64])
Conf liblockfile1 (1.17-2build2 Ubuntu:26.04/resolute [amd64])
Conf aide-common (0.19.2-3 Ubuntu:26.04/resolute [all])
Conf bsd-mailx (8.1.2-0.20220412cvs-1.1build1 Ubuntu:26.04/resolute [amd64])
Conf ssl-cert (1.1.3ubuntu2 Ubuntu:26.04/resolute [all])
```

**REJECT this form.** The mail daemon comes from `aide-common` `Recommends: bsd-mailx | mailx | s-nail`, where `bsd-mailx` in turn depends on an MTA (`postfix` is the default provider).

### 6b. Approved form: `apt-get -s --no-install-recommends install aide aide-common`

```
NOTE: This is only a simulation!
      apt-get needs root privileges for real execution.
      Keep also in mind that locking is deactivated,
      so don't depend on the relevance to the real current situation!
Reading package lists...
Building dependency tree...
Reading state information...
Solving dependencies...
The following additional packages will be installed:
  liblockfile-bin liblockfile1
Suggested packages:
  figlet
Recommended packages:
  bsd-mailx | mailx | s-nail
The following NEW packages will be installed:
  aide aide-common liblockfile-bin liblockfile1
0 upgraded, 4 newly installed, 0 to remove and 0 not upgraded.
Inst aide (0.19.2-3 Ubuntu:26.04/resolute [amd64])
Inst liblockfile-bin (1.17-2build2 Ubuntu:26.04/resolute [amd64])
Inst liblockfile1 (1.17-2build2 Ubuntu:26.04/resolute [amd64])
Inst aide-common (0.19.2-3 Ubuntu:26.04/resolute [all])
Conf aide (0.19.2-3 Ubuntu:26.04/resolute [amd64])
Conf liblockfile-bin (1.17-2build2 Ubuntu:26.04/resolute [amd64])
Conf liblockfile1 (1.17-2build2 Ubuntu:26.04/resolute [amd64])
Conf aide-common (0.19.2-3 Ubuntu:26.04/resolute [all])
```

Dependency detail (`apt-cache depends`):
- `aide` Depends: libacl1, libaudit1, libc6, libcap2, libext2fs2t64, libnettle8t64, libpcre2-8-0, libselinux1, zlib1g (all already on Johnny); Recommends aide-common; Suggests figlet.
- `aide-common` Depends: aide, liblockfile1, ucf, debconf, one of systemd/sysusers providers (all present except liblockfile1); Recommends `bsd-mailx | mailx | s-nail` and `cron | cron-daemon`.
- Johnny already has `cron` 3.0pl1-200ubuntu1 (enabled), so the cron recommend is satisfied. No `/usr/sbin/sendmail` exists on Johnny now.
- New in 6b: `liblockfile-bin` (provides `dotlockfile`, possibly setgid mail helper; assumption: not read, small utility; check for new SUID/SGID binaries after install, CIS 7.1.x/SUID review) and `liblockfile1`.
- Only `resolute` release pocket is used for aide; postfix in 6a comes from `resolute-updates`.

## 7. Maintainer scripts and triggers (aide-common; `aide` has none)

Read as text from `DEBIAN/` in the extracted deb. Files: `config`, `preinst`, `postinst`, `prerm`, `postrm`, `templates`, `md5sums`, `control`. **No `triggers` file in either package.** (`aide` has only `control` and `md5sums`.)

- **initramfs / dracut / update-initramfs: none.** No call, no trigger. (The `31_aide_initramfs-tools` and `31_aide_grub-*` files are only AIDE exclusion rules, not actions.) Batch 2's rebuild-initrd lesson does not apply; no reboot proof needed for these packages.
- **Boot, GRUB, PAM, sudo, SSH: none.** The word "sudo" appears in postinst only as an `sha256sum`/`chmod` on `/etc/aide/aide.conf.d/31_aide_sudo` (an AIDE rule file). `31_aide_ssh-server`, `pam_motd` etc. are likewise rules, not changes.
- **Debconf prompt** `aide/aideinit` (boolean, default `false`). If true, postinst starts `/usr/sbin/aideinit -b` in the background via `start-stop-daemon`. Under `DEBIAN_FRONTEND=noninteractive` or default, nothing is initialised. Do not preseed it true without an approved plan: it is heavy I/O and writes the DB while other changes proceed.
- **postinst side effects**: ucf-merges the config into `/etc/aide/`, `/etc/default/aide`, `/etc/cron.daily/dailyaidecheck`; runs `systemd-sysusers aide-common.conf` and `systemd-tmpfiles --create aide-common.conf`; `dpkg-maintscript-helper mv_conffile` for an old cron name; `deb-systemd-helper enable dailyaidecheck.timer`; `systemctl daemon-reload`; `deb-systemd-invoke start` for `dailyaidecheck-buildcache.service`, `dailyaidecheck.service`, `dailyaidecheck.timer`. Removes `/var/tmp/aide.cron.daily*`.
- **cron vs timer**: `/etc/cron.daily/dailyaidecheck` is installed too but starts with "Skip if systemd is running" and exits when `/run/systemd/system` exists, so on Johnny only the systemd timer runs; no double run.
- **Mail**: `dailyaidecheck` sends report mail to `MAILTO` (default `root`) via `s-nail` or `mail` if present; otherwise prints a "mail or s-nail not installed" warning and exits cleanly. With 6b nothing is mailed and no MTA is touched.
- **prerm/postrm**: stop units on remove; purge removes `/var/lib/aide/aide.db*`, ucf-managed config, `/run/aide`, runs `db_purge`. Removal does not remove the `_aide` user or `/var/log/aide` (assumption: sysusers does not delete users).

## 8. Which CIS 6.3.2 mechanism the package provides

**systemd timer.** Local PDF (CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0, sha256 `4acce51f...4af8`), 6.3.2 at PDF pages 972-973 (printed "Page 973" follows the rule): audit is `systemctl list-unit-files | awk ... dailyaidecheck\.(timer|service)` expecting `dailyaidecheck.timer enabled` and the service `static`/`enabled`, then `systemctl is-active dailyaidecheck.timer` = `active`. 6.3.1: `dpkg-query -s aide` and `dpkg-query -s aide-common`, then remediation `apt install aide aide-common` plus `aideinit` and moving `aide.db.new` to `aide.db`. The 26.04 `aide-common` ships exactly `dailyaidecheck.timer` and `dailyaidecheck.service` (above), so the CIS audit units match the package; cron is only a fallback on non-systemd hosts.
- 6.3.1 / 6.3.2 are Level 1 Server; **6.3.3** (audit-tool integrity in `aide.conf`) is **Level 2** and is not part of this batch.
- Caveat: the 6.3.1 CIS remediation text is the plain `apt install aide aide-common`, which on Johnny would pull postfix. Deviation from CIS's command: add `--no-install-recommends`. The audit checks only that the two packages are installed, so the result is still PASS. Exact 26.04 release content only; I used no other-release SCAP.
- URL for the packaging: https://sources.debian.org/src/aide/0.19.2-3/ (assumption: the upstream Debian source for the deb read here, not fetched); upstream manual: https://aide.github.io

## Risk register entry (for `docs/compliance/risk-register.md`; AJ accepts)

**R-AIDE-1: AIDE 0.19.2-3 is exposed to two open upstream detection-bypass advisories.**
- Risk: a local user who can create or alter files could hide a change from AIDE (NUL-byte hash match; invalid-UTF-8 file names). Moderate, CVSS 6.2, integrity only, local only. No CVE ID, no Ubuntu fix yet.
- Options: (A) install 0.19.2-3 now, use multiple hash functions in rules, track Ubuntu for a fix; (B) wait for a resolute update (leaves CIS 6.3.1/6.3.2 failing, and no integrity monitoring); (C) build 0.19.5 from upstream source (out of the apt/SBOM chain, would need its own vetting, signed-source check, and breaks "no unpackaged software"; not recommended).
- Recommendation: **A**. Johnny is single-admin, rules still catch ordinary changes, and AIDE is a detective control, not a barrier. Re-check at each `apt update`; request a stable release update from Ubuntu if none appears within the vuln-intake window (Assumption: LP bug or `ubuntu-security` contact to be raised by AJ).
- AJ acceptance: pending.

## Handoffs

- Platform: install with `--no-install-recommends`; drop-in for the 05:00 UTC timer; `aideinit` plan; check `/var/log/aide` file modes against 6.1.3.1; post-install check for new SUID/SGID (liblockfile) and absence of postfix.
- Brain: record `_aide`, `liblockfile1`, `liblockfile-bin`, hashes above in SBOM/Config changes after install.
- Governance: vuln-intake watch for aide 0.19.5 in resolute-updates.
