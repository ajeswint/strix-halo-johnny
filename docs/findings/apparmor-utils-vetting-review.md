# Review of `docs/compliance/apparmor-utils-vetting.md`

Grok, 2026-11-04. The record is `7d71a4e` on `claude/busy-hawking-3pehd8` (`7d71a4e3a0cb6d0304c3755a45ce6a37a5db2217`), copied here unchanged. AJ chose that file. A Claude-seat agent wrote it. This review is the other seat. The stopped Governance run wrote nothing and is not this file.

**Verdict of the review: the APPROVE WITH CONDITIONS stands.** The install stays gated on AJ accepting R-AAU-1, option A.

## Closed on Johnny (read-only SSH, 2026-11-04, no sudo)

The "Commands for Johnny" before the install, and what they printed:

- `apt-cache policy`: `apparmor` is installed at `5.0.2-0ubuntu1~26.04.1`. The three candidates are that same version, from `https://us.archive.ubuntu.com/ubuntu resolute-updates/main`. The release pocket still lists `5.0.0~beta1-0ubuntu7`.
- `apt-cache show` SHA256 and Size match section 1 of the vet exactly: `apparmor-utils` `6d251b6ffefb54ccee50518bae414b5dd8abf0a55faf9687b550b153886e5d4c` / 51142, `python3-apparmor` `df67e000dcec6a8888c89dc0bdf15ad5e2d33b73601265a2a69579816ba6cdff` / 101010, `python3-libapparmor` `fabb4c780038884b4b616a9568d90ed3113683c15f22fe9c44edf5540a844bda` / 32420. Johnny's index is the https `us.archive` mirror. The vet hashed downloads from `http://archive.ubuntu.com`. The two views agree.
- `findmnt -T` for `/var/lib/dpkg` and `/usr/lib/python3` is `/`, XFS, no `noexec`. `/tmp` is `noexec`. `/var` and `/usr` are the same `/`. The py3compile path is not on a noexec mount.
- `grep` of `/var/lib/dpkg/triggers/File` for `python3`, `/usr/share/man`, `apparmor`, `/usr/sbin`, and `/usr/bin` printed one line: `/usr/share/man man-db/noawait`. No initrd trigger interest on those paths. The vet's "none" assumption for the other paths is closed.
- `dpkg-query`: `man-db` 2.13.1-1build1 installed, `needrestart` 3.11-1ubuntu2 installed, `apt-listchanges` absent, `vim-addon-manager` absent, the three new packages absent. `python3 --version` is 3.14.4, which matches the vet's Python 3.14 note.

## Still open, and not closed by this review

Source rebuild, the CIS PDF text for 1.3.1.1, upstream release notes, the SRU autopkgtest claim, and the Ubuntu CVE web page. The vet already labels those. They do not change the pinned three-package install. `aa-status` and the initrd hash are still before-and-after checks for the install paste, not for this review.

R-AAU-1 is accepted, option A (AJ, 2026-11-04). No `aa-disable`, `aa-complain`, or `aa-teardown` without a separate decision. Governance re-audits the eight Batch 5 rules after the install.
