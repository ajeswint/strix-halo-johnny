# apparmor-utils vetting: `apparmor-utils`, `python3-apparmor`, `python3-libapparmor` for CIS L1 1.3.1.1

Governance, 2026-11-04. Johnny was not touched (no SSH from this seat). Method: read the Ubuntu archive indexes over HTTP from the Governance workstation, downloaded the three `.deb` files and the `apparmor` `.dsc`, read their control data and file lists as text with `dpkg-deb -c/-R/-e` (nothing from the packages was run, nothing installed). Johnny-side facts that I could not read are listed in "Not verified" with exact commands. The live simulation on Johnny (2026-11-04, from the Brain's brief, not re-run here): `0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded`, the three packages only.

## Verdict: APPROVE WITH CONDITIONS

The three packages are the Ubuntu-built binaries of the same `apparmor` source package (5.0.2-0ubuntu1~26.04.1) that is already installed on Johnny. They have no maintainer script in `apparmor-utils`, only a Python byte-compile step in the other two, no trigger, no unit, no daemon, no listener, no setuid/setgid file, no kernel module, no initramfs hook. Installing them cannot change which AppArmor profiles load or how they are enforced. Conditions:

1. **Install exactly the simulated set, pinned.** `sudo apt-get install --no-install-recommends apparmor-utils=5.0.2-0ubuntu1~26.04.1 python3-apparmor=5.0.2-0ubuntu1~26.04.1 python3-libapparmor=5.0.2-0ubuntu1~26.04.1`. None of the three has a Recommends (read from control data), so `--no-install-recommends` changes nothing today; keep it as AJ chose. Abort if apt proposes anything beyond those three or any upgrade or removal. If `apt update` has since moved the candidate to a newer version, the pinned install fails safely: stop and re-vet.
2. **Check the `.deb` hashes** against section 1 before the install (read-only command in "Commands for Johnny" below).
3. **Guard the initrd anyway.** Nothing here calls `update-initramfs` or activates the dracut trigger (section 6), so no change is expected. AJ takes the initrd hash before and after. Any change is an incident, not noise.
4. **Take `aa-status` before and after** (sudo, AJ) and diff. Expect identical profile counts and modes (section 7).
5. **AIDE is already installed (SBOM, Batch 3).** New files under `/usr/sbin`, `/usr/bin`, `/etc/apparmor`, `/usr/lib/python3/dist-packages` (plus `__pycache__` from the byte-compile step) will show as changes in the next AIDE check if a baseline exists. Platform decides the order: install first, then baseline; or re-baseline after this install. Treat this install as the cause when the report lists exactly these paths.
6. **Re-audit CIS 1.3.1.1 after the install** (Governance edits the row in place; git keeps the audit verdict).
7. AJ's own rule of use (recommended, AJ decides): the `aa-*` tools are installed to satisfy the benchmark and for the later Level 2 "all profiles enforcing" work. No `aa-disable`, `aa-complain`, `aa-teardown`-style change to Johnny without AJ's approval and the fix gate.

## 1. Provenance

Candidate and pocket, read from the archive index (not from packages.ubuntu.com, which for resolute lists only the release-pocket version `5.0.0~beta1-0ubuntu7` and not the `-updates` version, so it is stale for this question: https://packages.ubuntu.com/resolute/apparmor-utils ).

| Binary | Version | Pocket / component | Source | Maintainer field | Arch | Size (bytes) | Installed-Size (KiB) | SHA256 of the `.deb` |
|---|---|---|---|---|---|---|---|---|
| `apparmor-utils` | 5.0.2-0ubuntu1~26.04.1 | resolute-updates / main | `apparmor` | Ubuntu Developers `<ubuntu-devel-discuss@lists.ubuntu.com>` | all | 51142 | 368 | `6d251b6ffefb54ccee50518bae414b5dd8abf0a55faf9687b550b153886e5d4c` |
| `python3-apparmor` | 5.0.2-0ubuntu1~26.04.1 | resolute-updates / main | `apparmor` | same | all | 101010 | 607 | `df67e000dcec6a8888c89dc0bdf15ad5e2d33b73601265a2a69579816ba6cdff` |
| `python3-libapparmor` | 5.0.2-0ubuntu1~26.04.1 | resolute-updates / main | `apparmor` | same | amd64 | 32420 | 163 | `fabb4c780038884b4b616a9568d90ed3113683c15f22fe9c44edf5540a844bda` |

Reference row (already installed on Johnny, not part of this install): `apparmor_5.0.2-0ubuntu1~26.04.1_amd64.deb` sha256 `8621170a44534ef32ab4f7e26a5cacabb2077a5a95bcb5236c0652f118032820`, resolute-updates / main, same source. All three new binaries come from the same source, version and pocket as the installed `apparmor`. Totals: download 184,572 bytes, installed about 1,138 KiB.

Hash chain (all read 2026-11-04):
- `http://archive.ubuntu.com/ubuntu/dists/resolute-updates/InRelease` (Release `Date: Wed, 04 Nov 2026 6:39:25 UTC`): `gpgv` against `/usr/share/keyrings/ubuntu-archive-keyring.gpg` on this workstation reported a good signature from "Ubuntu Archive Automatic Signing Key (2018)", key `F6ECB3762474EDA9D21B7022871920D1991BC93C`.
- `http://archive.ubuntu.com/ubuntu/dists/resolute-updates/main/binary-amd64/Packages.gz`: sha256 `13a062d023c23f15a96d603b166be1bfedbf6caa7489feb71df01537e8e7c467` equals the value listed in that Release file. The three `SHA256:` fields above are from this Packages file (arch `all` packages are carried in `binary-amd64`; the `binary-all` path returns 404).
- I downloaded each `.deb` from `http://archive.ubuntu.com/ubuntu/pool/main/a/apparmor/` and `sha256sum` matched the Packages value for all three (and for `apparmor`).
- Source: `http://archive.ubuntu.com/ubuntu/dists/resolute-updates/main/source/Sources.gz` (sha256 `a94707172b9fd436d10846d154462ef5059f94aa6fae560b43971d1e28ef9391`, equals the Release value) lists `apparmor_5.0.2.orig.tar.gz` sha256 `c02ff05f1831a42940d8a20194ed05128b9535db44afec13088b5aae57863327`, `apparmor_5.0.2-0ubuntu1~26.04.1.debian.tar.xz` sha256 `b41f819f7a06336fd1cc2de82016bbc4d3ba932c3c8444ed0f9878906199c599`, `.dsc` sha256 `a369a9e238fe5e48edc646f7be61c1a73d75a9dc28fdde37fbecfee0c0165bb3` (I downloaded the `.dsc` and its hash matches). I did not rebuild the package from source, so a binary-to-source build check is not done.
- The security pocket has no `apparmor` stanza: `resolute-security` main and universe `Packages.gz` contain no `apparmor`, `apparmor-utils`, `python3-apparmor` or `python3-libapparmor`. The version is an SRU (update), not a security update.

Publication (Launchpad, https://launchpad.net/ubuntu/+source/apparmor/+publishinghistory ):
- 2026-07-24 uploaded to `resolute-proposed` (later deleted from proposed on 2026-08-14 after release).
- 2026-08-05 published to `resolute-updates`, component `main`, status Published, "Created by Timo Aaltonen".
- Changelog entry (https://changelogs.ubuntu.com/changelogs/pool/main/a/apparmor/apparmor_5.0.2-0ubuntu1~26.04.1/changelog ): signed Ryan Lee `<ryan.lee@canonical.com>`, Mon, 13 Jul 2026 10:43:46 -0700, "New upstream release (SRU backport). (LP: #2161458)".
- SRU bug https://bugs.launchpad.net/ubuntu/+source/apparmor/+bug/2161458 : "[SRU] AppArmor 5.0.2 backport for 26.04", Fix Released for resolute 2026-08-05; QRT suite "Ran 64 tests ... OK (skipped=3)" reported 2026-07-28 on the proposed build; tag `verification-done-resolute`. The bug shows autopkgtest regressions on 2026-07-24 for adsys, libvirt-hwe, pollinate, snapd and sudo; the reporter said on 2026-07-29 they were resolved and had been believed spurious. I did not verify that independently.
- Archive history: the release pocket still carries `5.0.0~beta1-0ubuntu7` (auto-sync 2026-04-17). So the whole AppArmor userspace at 5.0.2 on 26.04 is a backport of the upstream release, not the release-day version.

## 2. Maintainer and upstream

- Package maintainer (all three): Ubuntu Developers. Original maintainer: Debian AppArmor Team `<pkg-apparmor-team@lists.alioth.debian.org>` (from the Packages stanza and `control`). The 26.04 upload is by a Canonical AppArmor developer (changelog signer above).
- Upstream: AppArmor project, https://apparmor.net/ , sources at https://gitlab.com/apparmor/apparmor . Origin: Ubuntu (Canonical-supported, component `main`).
- Assessment **[Assumption: judgment from the above]**: long-lived project, Canonical-maintained for Ubuntu, same maintainer path as the AppArmor parser and profiles already running on Johnny. No new trust relationship is added by installing these three.

## 3. Licensing

Read from `usr/share/doc/<pkg>/copyright` inside each `.deb` (the three files are byte-identical, 6065 bytes; DEP-5 format, shared by the whole source):
- `Files: *` GPL-2+ (Novell/SuSE/Immunix; Canonical 2008-2014). This covers the `utils/` code shipped in `apparmor-utils` and `python3-apparmor`.
- `libraries/libapparmor/*` and `parser/libapparmor_re/*`: LGPL-2.1+. The `python3-libapparmor` bindings are SWIG-generated from libapparmor **[Assumption: the bindings live under `libraries/libapparmor/` upstream and fall under that stanza; the copyright file has no separate stanza for them]**.
- `changehat/pam_apparmor/*` BSD-3-clause or GPL-2+; `changehat/mod_apparmor/*` LGPL-2.1+; sample profiles under `profiles/` GPL-2; `debian/*` GPL-2. The profile and PAM/Apache stanzas do not apply to these three binaries.
- SPDX summary: `apparmor-utils` GPL-2.0-or-later; `python3-apparmor` GPL-2.0-or-later; `python3-libapparmor` LGPL-2.1-or-later. No non-commercial, field-of-use or model-weight terms. Fine for Johnny.

## 4. Vulnerability status

Sources fetched 2026-11-04:
- Ubuntu CVE API, `https://ubuntu.com/security/cves.json?package=apparmor&version=resolute&limit=20` returned `total_results: 1`: **CVE-2016-1585** (mount rules widened when compiled), priority medium, resolute **not-affected** (fixed before 4.0.0~alpha2-0ubuntu5; noble and questing also not-affected, jammy released). The unfiltered query `https://ubuntu.com/security/cves.json?package=apparmor&limit=5` returned `total_results: 3`: the same CVE plus CVE-2017-6507 and CVE-2014-1424, which carry no status row for resolute. Browser page: https://ubuntu.com/security/cves?package=apparmor (it returned 504 several times; the JSON endpoint answered on retry).
- Ubuntu notices API, `https://ubuntu.com/security/notices.json?details=apparmor&release=resolute&limit=20`: 17 results, all kernel, kernel live-patch and snapd notices that mention AppArmor in their text. **No USN lists `apparmor`, `apparmor-utils`, `python3-apparmor` or `python3-libapparmor` as an updated package for resolute.** (Checked the `release_packages` fields of all 17 notices.)
- Debian tracker, https://security-tracker.debian.org/tracker/source-package/apparmor : only old items (CVE-2016-1585 fixed in trixie, forky and sid; CVE-2017-6507 and CVE-2014-1424 resolved).
- Open items for `apparmor` source in resolute: **none found.** Caveat: a search that returns nothing is weaker evidence than a positive entry. A new upstream issue may exist without a CVE ID yet (the aide vet found two). I found no upstream advisory text for 5.0.2 (the upstream release-notes wiki page, https://gitlab.com/apparmor/apparmor/-/wikis/Release_Notes_5.0.2 , fetched empty), and I did not check the upstream issue tracker.
- Adjacent, not a package item: 2026 kernel-side AppArmor LSM vulnerabilities disclosed by Qualys (for example https://ubuntu.com/security/CVE-2026-23268 , "unprivileged local user can do privileged policy management", priority high). The Ubuntu page lists the `linux` package on 26.04 resolute as **Not affected**. Those are kernel bugs; installing userspace utilities neither causes nor fixes them. Handed to `vuln-intake` to watch with the kernel SBOM row (Platform fixes). A web search also returned a mirror domain (`ap4ihba.duckdns.org`) for a related CVE page; I did not use it.
- SRU regression potential, from the SRU template in LP #2161458 (about the 5.0.2 backport as a whole): profile recompilation may give a one-time slower boot; abstraction changes "generally loosening confinement"; parser changes might cause compilation regressions; network interface mediation is opt-in. These describe the `apparmor` binary and profiles, which are already 5.0.2 on Johnny, so this install does not add them.

## 5. What gets installed

Dependencies (from `control`, matches the Packages stanzas):
- `apparmor-utils` Depends: `apparmor`, `python3-apparmor (= 5.0.2-0ubuntu1~26.04.1)`, `python3:any`. Recommends: none. Suggests: `vim-addon-manager` (skipped). Provides `apparmor-easyprof`; Breaks and Replaces `apparmor-easyprof (<< 3.0.3-4)` (not expected to be installed; the simulation shows 0 removals).
- `python3-apparmor` Depends: `python3-libapparmor (>= 5.0.2)`, `python3:any`. Recommends and Suggests: none.
- `python3-libapparmor` Depends: `python3 (>= 3.14~)`, `python3 (<< 3.15)`, `python3:any`, `libapparmor1 (>= 5.0.0~beta1)`, `libc6 (>= 2.4)`. Recommends and Suggests: none. The Python range matches the resolute interpreter (`python3.14` 3.14.4 in the archive); the simulation adds no Python package, so Johnny's `python3` already satisfies it.
- Everything else (`apparmor`, `libapparmor1`, `python3`) is already installed, consistent with the simulation.

File lists (`dpkg-deb -c`; man pages omitted):
- `apparmor-utils` (368 KiB): 13 scripts in `/usr/sbin` (`aa-audit aa-autodep aa-cleanprof aa-complain aa-decode aa-disable aa-enforce aa-genprof aa-logprof aa-mergeprof aa-show-usage aa-unconfined aa-update-browser`), `/usr/bin/aa-easyprof`, all `0755 root:root`; templates and policy groups under `/usr/share/apparmor/easyprof/`; a vim syntax file and `/usr/share/vim/registry/vim-apparmor.yaml` (used only if `vim-addon-manager` is installed); an empty directory `/var/log/apparmor/` (0755 root:root). Conffiles (3, new to the system): `/etc/apparmor/easyprof.conf`, `/etc/apparmor/logprof.conf`, `/etc/apparmor/severity.db`. These are settings for the tools (logprof and easyprof). The kernel and `apparmor.service` do not read them; profile loading uses `/etc/apparmor.d/` and `/etc/apparmor/parser.conf`, which belong to `apparmor`.
- `python3-apparmor` (607 KiB): pure Python modules under `/usr/lib/python3/dist-packages/apparmor/` and an `apparmor-5.0.2.egg-info/`. No executables.
- `python3-libapparmor` (163 KiB): `/usr/lib/python3/dist-packages/LibAppArmor.py`, `_LibAppArmor.cpython-314-x86_64-linux-gnu.so` (one compiled extension, 119,408 bytes, loaded only when a Python tool imports it) and an egg-info.
- Scripts use `#!/usr/bin/python3` (12 of 14), `#!/bin/sh` or `#!/bin/bash`.
- Not present in any of the three, checked by listing: systemd units or timers, daemon or init scripts, cron files, sockets or listeners, udev, D-Bus or sysctl files, `/etc/default` files, sudoers or profile.d snippets, `.ko` modules, files under `/etc/apparmor.d/`. **No setuid, setgid or sticky entry** in the three archives (checked the mode bits of every tar entry with `dpkg-deb --fsys-tarfile`).

## 6. Maintainer scripts and triggers

Read as text from `DEBIAN/` of each `.deb`:
- `apparmor-utils`: control members are `conffiles`, `control`, `md5sums` only. **No `preinst`, `postinst`, `prerm`, `postrm`, `triggers`.**
- `python3-apparmor` and `python3-libapparmor`: `control`, `md5sums`, `postinst`, `prerm`. No `triggers` member. The `postinst` is the stock debhelper `dh_python3` block: `py3compile -p <package> || true` (and `pypy3compile` if present). The `prerm` runs `py3clean`. Effect on install: writes `__pycache__/*.pyc` files under `/usr/lib/python3/dist-packages/`. No network, no service action.
- Therefore, for these three packages: **no `update-initramfs`, no dracut call, no `needrestart` call, no `systemctl`, no `apparmor_parser` run, no profile reload, no `aa-*` invocation.** Because `apparmor` is already at the same version and is not being upgraded (`0 upgraded`), its own `postinst` (which does run `apparmor_parser` helpers) is not executed by this install.
- A `triggers` member would be visible in the control archive; I read all three control archives, so the "no triggers declared" statement is verified for these packages, not assumed. Triggers declared by **other** installed packages can still fire on the files we add. From archives for the same release, read the same way:
  - `python3`, `python3-minimal`, `python3.14`, `python3.14-minimal` and `libpython3.14-stdlib` (resolute-updates 3.14.4-1ubuntu0.2, `python3` 3.14.3-0ubuntu2): no `triggers` member. No Python-level trigger on `dist-packages`.
  - `man-db` 2.13.1-1build1: `triggers` registers `interest-noawait` on `/usr/share/man` (and other man paths). If `man-db` is installed, dpkg will run its trigger after unpack (index cache update, harmless, no await, no network). The three packages put man pages under `/usr/share/man/man5` and `man8`.
  - `dracut` 110-11ubuntu0.1 (`triggers`: `interest-await update-initramfs`): this is a named trigger, activated only by something calling `dpkg-trigger update-initramfs` (kernel and dracut packages). Our files are not paths it watches and our scripts do not activate it. `dracut-core` and `initramfs-tools-core` carry no `triggers` member.
  - Other installed packages' trigger interests on Johnny's `/usr/sbin`, `/usr/bin`, `/etc/apparmor`, `/usr/lib/python3` are **[Assumption: none]**, because I cannot read Johnny's `/var/lib/dpkg`. Command in "Commands for Johnny" lists them.
- Noexec: the debs run maintainer scripts from `/var/lib/dpkg/info/` and unpack via `/var/lib/dpkg/`, not from `/tmp` or `/dev/shm`. **[Assumption: standard dpkg behavior, not tested under noexec here]** The byte-compile step runs `/usr/bin/py3compile` (an interpreter script on `/usr`) and writes into `/usr/lib/python3/dist-packages`. A noexec `/var` would break it, so the mount-options command is included below. This is the first apt install since `/tmp` and `/dev/shm` went noexec; a failure would show as a dpkg error, and the `|| true` guard turns a failed compile into a non-fatal no-op for the two Python packages.

## 7. Fit with CIS 1.3.1.1

- Rule: "Ensure apparmor packages are installed" (Level 1 Server). Current verdict in `docs/cis-26.04-l1-results.csv`: FAIL, evidence "apparmor installed; apparmor-utils not installed" (audit 2026-10-30). I did not re-read the benchmark text: the local CIS PDF and `docs/cis-local/` are not present in this checkout. **[Assumption: the audit checks that both `apparmor` and `apparmor-utils` are installed, inferred from the rule title and the recorded evidence.]** After the install both are installed, so the expected verdict is PASS. I will re-run CIS's own audit command from the local PDF (AJ or Governance with the PDF available) before editing the row.
- Plain `apt install apparmor-utils` would give the same three-package set as the simulation; the benchmark's remediation text is not changed by `--no-install-recommends`.
- Enforcement effect: none at install. The package ships tools and settings for them, loads nothing, and runs no tool at install time. Johnny's AppArmor state stays as audited: 1.3.1.2 PASS (apparmor.service enabled and active; 180 profiles loaded per the 2026-10-30 audit, taken with sudo by AJ) and 1.3.1.4 PASS (kernel.apparmor_restrict_unprivileged_unconfined). Install and enforcement are independent; `aa-status`, `aa-load`, `apparmor_parser` come from the already-installed `apparmor`, not from this install. The tools make later changes possible: `aa-complain` and `aa-disable` set profiles to complain mode or off, `aa-enforce` sets them to enforce. They act only when root runs them.
- Related later work, not part of this install: Level 2 recommendations on all profiles in enforce mode will use these tools (handoff step 10). Not in this batch.

## Risk register entry (for `docs/compliance/risk-register.md`; AJ accepts)

**R-AAU-1: `apparmor-utils` adds convenience tools that can weaken confinement, plus a small Python attack surface, on a box with root-only administration.**
- Risk: root can already change AppArmor state through `apparmor_parser` and securityfs, so the tools add no capability, but they make a mistake or abuse quicker and add Python code (about 1.1 MB, one compiled module) that parses logs and profiles when run as root. Rated low. No daemon, no listener, no setuid.
- Residual items AJ should accept: (1) SRU-class version (5.0.2 backport, not the release-day 5.0.0~beta1); (2) no `apparmor` source entry in the Ubuntu CVE or USN data now, but an absence of entries is not proof; (3) updates arrive from `-updates` unless Ubuntu issues a USN, so `unattended-upgrades` (security-only) will not move these; a USN would update all binaries of the source together; (4) AIDE baseline drift from the new files; (5) the autopkgtest regressions listed on LP #2161458 were reported as spurious by the uploader and not verified by me; (6) if the install runs `man-db` or other triggers, a harmless extra line appears in the dpkg log.
- Options: (A) install as vetted with the conditions above; (B) hold CIS 1.3.1.1 as a documented FAIL until a later benchmark review (leaves a Level 1 recommendation failing, no security gain since the tools are not needed for enforcement); (C) install the benchmark's package set and remove the tools after audit (breaks the benchmark's intent; the audit state would not stay PASS).
- Recommendation: **A**.
- AJ acceptance: pending.

## Commands for Johnny (read-only; AJ or Platform runs; no sudo unless marked)

Before the install:

```
apt-cache policy apparmor apparmor-utils python3-apparmor python3-libapparmor
```
Expect `Candidate: 5.0.2-0ubuntu1~26.04.1` from `resolute-updates/main` for each; `apparmor` Installed is the same version.

```
apt-cache show apparmor-utils=5.0.2-0ubuntu1~26.04.1 python3-apparmor=5.0.2-0ubuntu1~26.04.1 python3-libapparmor=5.0.2-0ubuntu1~26.04.1 | grep -E '^(Package|Version|Filename|Size|SHA256):'
```
Compare each `SHA256` with section 1. A mismatch is a stop.

```
findmnt -T /var/lib/dpkg -no TARGET,OPTIONS; findmnt -T /usr/lib/python3 -no TARGET,OPTIONS; findmnt -T /tmp -no TARGET,OPTIONS
```
Expect no `noexec` on the first two (the `/tmp` line is for the record).

```
grep -E 'python3|/usr/share/man|apparmor|/usr/sbin|/usr/bin' /var/lib/dpkg/triggers/File
```
Lists installed packages whose trigger interests touch the paths we add. Expect `man-db` (and nothing that rebuilds the initrd).

```
dpkg-query -W -f='${Package} ${Version} ${db:Status-Abbrev}\n' man-db needrestart apt-listchanges vim-addon-manager apparmor-utils python3-apparmor python3-libapparmor 2>&1
```

AJ, sudo, before and after (save to the existing audit directory):

```
mkdir -p ~/cis-audit && sudo aa-status > ~/cis-audit/aa-status-before-apparmor-utils.txt && sudo sha256sum /boot/initrd.img-* > ~/cis-audit/initrd-before-apparmor-utils.txt && head -4 ~/cis-audit/aa-status-before-apparmor-utils.txt
```

Install (AJ, sudo):

```
sudo apt-get install --no-install-recommends apparmor-utils=5.0.2-0ubuntu1~26.04.1 python3-apparmor=5.0.2-0ubuntu1~26.04.1 python3-libapparmor=5.0.2-0ubuntu1~26.04.1
```

After the install:

```
sudo aa-status > ~/cis-audit/aa-status-after-apparmor-utils.txt && diff ~/cis-audit/aa-status-before-apparmor-utils.txt ~/cis-audit/aa-status-after-apparmor-utils.txt && echo aa-status-identical
```

```
sudo sha256sum /boot/initrd.img-* > ~/cis-audit/initrd-after-apparmor-utils.txt && diff ~/cis-audit/initrd-before-apparmor-utils.txt ~/cis-audit/initrd-after-apparmor-utils.txt && echo initrd-identical
```

```
dpkg-query -W -f='${Package} ${Version} ${db:Status-Abbrev}\n' apparmor apparmor-utils python3-apparmor python3-libapparmor; sha256sum /var/cache/apt/archives/apparmor-utils_5.0.2-0ubuntu1~26.04.1_all.deb /var/cache/apt/archives/python3-apparmor_5.0.2-0ubuntu1~26.04.1_all.deb /var/cache/apt/archives/python3-libapparmor_5.0.2-0ubuntu1~26.04.1_amd64.deb
```
(the last part works only if apt kept the debs in its cache)

```
grep -E 'update-initramfs|dracut|apparmor_parser|Setting up (apparmor-utils|python3-apparmor|python3-libapparmor)' /var/log/apt/term.log | tail -20
```
Expect only the three "Setting up" lines; no `update-initramfs`, no dracut.

```
dpkg -V apparmor-utils python3-apparmor python3-libapparmor; dpkg-query -W -f='${Conffiles}\n' apparmor-utils
```

## Not verified (could not read from this seat)

- Johnny's own apt metadata and installed state (hash match of its Packages data, installed Python version, installed trigger interests, `man-db` and `needrestart` presence, mount options). Commands above.
- A source rebuild or binary reproducibility check (not done).
- The CIS benchmark audit text for 1.3.1.1 (PDF not in this checkout; rule behavior taken from the audit CSV).
- Upstream AppArmor 5.0.2 release notes and upstream security advisories (the wiki page fetched empty).
- That the autopkgtest regressions in the SRU bug were spurious (reporter's statement only).
- Ubuntu's CVE web page for `apparmor` (504 on every fetch; used the JSON API instead). The API's `version=resolute` filter returned one CVE; I did not confirm how the filter treats CVEs without a resolute status row.

## SBOM rows (Brain to paste into `docs/os-handoff.md`; not edited here)

| Package | Version | Source | License | `.deb` sha256 (verified against InRelease > Packages.gz > download) | Why | Date |
|---|---|---|---|---|---|---|
| apparmor-utils | 5.0.2-0ubuntu1~26.04.1 | Ubuntu 26.04 `resolute-updates/main`, source `apparmor` | GPL-2.0-or-later | `6d251b6ffefb54ccee50518bae414b5dd8abf0a55faf9687b550b153886e5d4c` | CIS 1.3.1.1 (AJ chose install with `--no-install-recommends`) | 2026-11-04 (vetted; install pending AJ) |
| python3-apparmor | 5.0.2-0ubuntu1~26.04.1 | Ubuntu 26.04 `resolute-updates/main`, source `apparmor` | GPL-2.0-or-later | `df67e000dcec6a8888c89dc0bdf15ad5e2d33b73601265a2a69579816ba6cdff` | dependency of `apparmor-utils` (pinned `=`) | 2026-11-04 (vetted; install pending AJ) |
| python3-libapparmor | 5.0.2-0ubuntu1~26.04.1 | Ubuntu 26.04 `resolute-updates/main`, source `apparmor` | LGPL-2.1-or-later | `fabb4c780038884b4b616a9568d90ed3113683c15f22fe9c44edf5540a844bda` | dependency of `python3-apparmor` (Python 3.14 bindings) | 2026-11-04 (vetted; install pending AJ) |

Handoff-style two-column form, if preferred (matches the existing SBOM table):

| apparmor-utils (CIS 1.3.1.1) | 5.0.2-0ubuntu1~26.04.1; `.deb` sha256 `6d251b6ffefb54ccee50518bae414b5dd8abf0a55faf9687b550b153886e5d4c` |
|---|---|
| python3-apparmor (dep of apparmor-utils) | 5.0.2-0ubuntu1~26.04.1; `.deb` sha256 `df67e000dcec6a8888c89dc0bdf15ad5e2d33b73601265a2a69579816ba6cdff` |
| python3-libapparmor (dep of python3-apparmor) | 5.0.2-0ubuntu1~26.04.1; `.deb` sha256 `fabb4c780038884b4b616a9568d90ed3113683c15f22fe9c44edf5540a844bda` |

Also record after the install: no new system user or group (none of the three creates one; sysusers not used), and the three conffiles under `/etc/apparmor/`.

## Handoffs

- Platform: pinned install command above with `--no-install-recommends`; initrd and `aa-status` before/after; decide AIDE baseline order; confirm `/var` and `/usr` are not noexec.
- Brain: paste the SBOM rows after AJ installs and the hashes are confirmed; record the three conffiles.
- Governance: after the install, re-run CIS 1.3.1.1 and edit the CSV row in place; `vuln-intake` watch for any `apparmor` USN in resolute and for kernel AppArmor LSM CVEs against the SBOM kernel row.

AJ acceptance: pending
