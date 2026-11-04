# Johnny handoff → Batch 6 (2026-11-04 15:57 CT)

Repo `ajeswint/strix-halo-johnny`, branch `claude/practical-ritchie-4c6vvf`. Read `AGENTS.md`, `README.md`, then `docs/os-handoff.md`. The project is Johnny. Reply as Detail, Relay, Outline.

## Where it stands

Batch 5 is closed. HEAD when this brief was written was `4d2d66e`, handoff rev 64, totals **195 pass, 56 fail, 23 N/A**. Claude confirmed that commit on the remote. `main` was still at `b47bf86` (rev 52) in Claude's session. Revs 53–64 are on `claude/practical-ritchie-4c6vvf`. Do not merge to `main` unless AJ says so.

1.5.10 is PASS. The divert is `/root/10-coredump-debian.conf.distrib`. The `.pre-batch4` initrd copy is already deleted. The Batch 5 initrd copy is already deleted. The live initrd remains `42618411` bytes, mtime `2026-11-03 06:13:32.840646209 +0000`.

## Batch 6

Draft: `docs/cis-fix/batch-6.md` rev 2. Nothing has run. ufw is installed, the unit is active, and `ENABLED=no`. Input policy on disk is already DROP. `nftables` is `rc`.

Two decisions are open. Recommended answers: (a) SSH from `192.168.50.0/24` in on `eno3` to TCP 22, and (a) keep deny (DROP). Paste 1 only comments the two `log_martians=0` lines in `/etc/ufw/sysctl.conf` and sets those keys to 1 in `60-johnny-cis-network.conf`. It does not enable ufw. Paste 2 is the enable and is not written until AJ answers.

Before Paste 2: a second SSH session, AMT KVM open, and the LUKS passphrase at hand. If the new session cannot log in, `ufw disable` from the KVM console. Detection checks `eno1np0` after enable. That NIC has no address. This draft does not claim the mirror survives the filter table.

AIDE at 2026-11-05 05:00 UTC may list the Batch 5 files. It should not list the deleted initrd copy. Do not promote `aide.db.new`.

## Do not

- Run Paste 1 until AJ says go, after the review.
- Run `ufw enable` from this brief.
- Recreate either initrd copy.
- Run `aa-disable`, `aa-complain`, or `aa-teardown`.
- Start Batch 7.
