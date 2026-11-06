# Johnny risk register

Five entries. An entry is accepted only when AJ has said so. `docs/findings/aide-vetting.md` still says R-AIDE-1 is pending; the acceptance is Batch 3, not that line.

## R-AIDE-1

**Status:** accepted, option A (AJ, 2026-11-03). Cite: `docs/cis-fix/batch-3.md` line 657.

AIDE 0.19.2-3 has two open upstream detection-bypass advisories (NUL-byte hash match; invalid-UTF-8 file names). Moderate, CVSS 6.2, integrity only, local only. No CVE ID and no Ubuntu fix yet. The invalid-UTF-8 bypass stays open until a fix lands.

Option A, the one AJ accepted: install 0.19.2-3 with `--no-install-recommends`, use multiple hashes, and track Ubuntu for 0.19.5. Option B was to wait. Option C was to build 0.19.5 from upstream. C was not recommended.

## PCR 7 binding

**Status:** accepted for the lab (option A). Cite: `docs/os-handoff.md`, Known gaps, "PCR-7-only binding (option A, chosen)."

The TPM unlock uses PCR 7 only. The passphrase stays as recovery. `/boot` is plaintext and the initrd is unsigned and unmeasured in PCR 7. A physical attacker who can edit the initrd, or boot other media from the boot menu, can receive the key. There is no GRUB password yet (CIS 1.4.1), so a kernel command line such as `init=` at the GRUB menu does not touch PCR 7. That path is understood and untested.

Fleet option D (signed UKI and a signed PCR 11 policy) is research, not a lab acceptance. The 2026-11-05 inventory is done (`STEP12-RESEARCH-DONE`, `SLOTS-DONE`). Option D is not applied. Options B (PIN) and C (PCR 7+9) were rejected.

**Text note (2026-11-05, flag only; the entry above is unchanged).** AJ chose "refresh when convenient, not a hold" at the OS gate (`docs/findings/overseer-review-os-gate.md` §8). The sentence "There is no GRUB password yet (CIS 1.4.1)" is stale: `docs/cis-26.04-l1-results.csv` records 1.4.1 PASS from batch 10 (2026-11-04: `password_pbkdf2` and `set superusers` in `grub.cfg`, `--unrestricted` on the first menu entry). Whether `init=` at the GRUB menu is still open under that setup is **untested**. The refresh should say that, not claim it is closed.

## ksmbd

**Status:** accepted. AJ accepted option A on 2026-11-04 America/Chicago: leave `ksmbd` loadable. B and C were not chosen.

`ksmbd` stays loadable. `modprobe.d(5)` gives its built-in softdep precedence over `install /bin/false`, so the blacklist and install lines were removed rather than left as a block the dry-run disproves. `modprobe -n` still inserts `ksmbd.ko.zst`. The CIS 1.1.1.11 script does not list it, because the file is under `kernel/fs/smb/server/`.

Read-only checks, 2026-11-04T07:26:18Z, before AJ accepted this entry: `dpkg-query -W ksmbd-tools` found no package. `ss` found no listener on 139 or 445. Those facts are also in the 1.1.1.11 row of `docs/cis-26.04-l1-results.csv`. The manual pass records the keep set and this exception. That pass is not the acceptance.

- Options: (A) leave `ksmbd` loadable, as it is now; (B) divert or remove `ksmbd.ko.zst`, which is a package file and can return on a kernel upgrade; (C) put `install ksmbd /bin/false` back. C is not a block: the softdep still wins, and showconfig would claim a block the dry-run disproves.
- Recommendation: **A**. Nothing listens on 139 or 445, and `ksmbd-tools` is not installed. B fights the kernel package. C is a false block.
- AJ acceptance: option A on 2026-11-04 America/Chicago: leave `ksmbd` loadable. B and C were not chosen.

## R-AAU-1

**Status:** accepted, option A (AJ, 2026-11-04). Cite: `docs/compliance/apparmor-utils-vetting.md`.

`apparmor-utils` and its two dependencies add root-only tools that can put a profile in complain mode or turn it off. Root can already do that with `apparmor_parser`. The tools make that quicker, and they add Python code that parses logs and profiles when root runs it. No daemon, no listener, no setuid file.

AJ also accepted the rule that `aa-disable`, `aa-complain`, and `aa-teardown` are not run without a separate decision. Governance re-audits the eight Batch 5 rules after the install.

## Step 8 thermal soak (92 °C, `NOTE-throttled`)

**Status:** recorded as a finding at AJ's direction, 2026-11-05 America/Chicago (Overseer gate, `docs/findings/overseer-review-os-gate.md` §8). No temperature or watt limit is set. The soak is **not** re-run. Cite: `docs/tool-install/step-8-thermal-soak.md` (`STEP8-DONE`); handoff Next steps item 8.

`stress-ng --cpu 0 --timeout 30m` as `aj` (24 hogs, exit 0, 1800 s), `turbostat` every 10 s. Idle max CoreTmp and PkgTmp 44 °C, PkgWatt 9.23. Soak max CoreTmp and PkgTmp 92 °C, PkgWatt 121.06, CoreThr 4484, PKG_% 6.76. The run logged `NOTE-throttled` and `NOTE-throttle-sysfs-changed` (no throttle journal lines). `thermald` `2.5.11-0ubuntu1.1` is active and enabled, record only. Raw logs stay on Johnny.

Risk: under sustained all-core load the CPU reaches 92 °C and the throttle counters move, so a heavy Module 1 or SLM workload may run throttled in the closet. Nothing alarms or limits it today.

**[Assumption]** `CoreThr` is the maximum over the summary and per-CPU rows, so it may be one interval's sum across CPUs, not 4484 events on one core (runbook note). The `stress-ng` load is far heavier than the passive sensor load the box carries now; sensor-load temperature has not been measured.

Not decided here: a temperature limit, a fan or BIOS change, or a Module 1 power budget. Those wait for Module 1 sizing.
