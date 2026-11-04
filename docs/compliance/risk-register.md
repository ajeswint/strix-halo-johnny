# Johnny risk register

Three entries. An entry is accepted only when AJ has said so. `docs/findings/aide-vetting.md` still says R-AIDE-1 is pending; the acceptance is Batch 3, not that line.

## R-AIDE-1

**Status:** accepted, option A (AJ, 2026-11-03). Cite: `docs/cis-fix/batch-3.md` line 657.

AIDE 0.19.2-3 has two open upstream detection-bypass advisories (NUL-byte hash match; invalid-UTF-8 file names). Moderate, CVSS 6.2, integrity only, local only. No CVE ID and no Ubuntu fix yet. The invalid-UTF-8 bypass stays open until a fix lands.

Option A, the one AJ accepted: install 0.19.2-3 with `--no-install-recommends`, use multiple hashes, and track Ubuntu for 0.19.5. Option B was to wait. Option C was to build 0.19.5 from upstream. C was not recommended.

## PCR 7 binding

**Status:** accepted for the lab (option A). Cite: `docs/os-handoff.md`, Known gaps, "PCR-7-only binding (option A, chosen)."

The TPM unlock uses PCR 7 only. The passphrase stays as recovery. `/boot` is plaintext and the initrd is unsigned and unmeasured in PCR 7. A physical attacker who can edit the initrd, or boot other media from the boot menu, can receive the key. There is no GRUB password yet (CIS 1.4.1), so a kernel command line such as `init=` at the GRUB menu does not touch PCR 7. That path is understood and untested.

Fleet option D (signed UKI and a signed PCR 11 policy) is research, not a lab acceptance. Options B (PIN) and C (PCR 7+9) were rejected.

## ksmbd

**Status:** pending. Not accepted.

`ksmbd` stays loadable. `modprobe.d(5)` gives its built-in softdep precedence over `install /bin/false`, so the blacklist and install lines were removed rather than left as a block the dry-run disproves. `modprobe -n` still inserts `ksmbd.ko.zst`. The CIS 1.1.1.11 script does not list it, because the file is under `kernel/fs/smb/server/`.

Read-only checks, 2026-11-04T07:26:18Z, before this entry is finalized: `dpkg-query -W ksmbd-tools` found no package. `ss` found no listener on 139 or 445. Those facts are also in the 1.1.1.11 row of `docs/cis-26.04-l1-results.csv`. The manual pass records the keep set and this exception. It is not an acceptance of this entry.

- Options: (A) leave `ksmbd` loadable, as it is now; (B) divert or remove `ksmbd.ko.zst`, which is a package file and can return on a kernel upgrade; (C) put `install ksmbd /bin/false` back. C is not a block: the softdep still wins, and showconfig would claim a block the dry-run disproves.
- Recommendation: **A**. Nothing listens on 139 or 445, and `ksmbd-tools` is not installed. B fights the kernel package. C is a false block.
- AJ acceptance: pending.
