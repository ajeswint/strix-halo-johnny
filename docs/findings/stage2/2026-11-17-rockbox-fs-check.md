# 2026-11-17 Rock Box filesystem + BPF LSM check (architecture-rev2 §3) — raw output

- **Run by:** AJ, on Rock Box, normal terminal, ~5:04 PM CT 2026-11-17. No sudo, no writes, no ssh. Johnny not touched.
- **Block:** the nine read-only lines in `docs/architecture/architecture-rev2.md` §3, unchanged.
- **Review state:** ran **unreviewed**. §3 said "not yet reviewed" and no adversarial review of the block happened before AJ ran it. The block is read-only, so there was no harm.

## Commands (as in §3)

```bash
echo "== kernel"; uname -r
echo "== mount holding /"; findmnt -no SOURCE,FSTYPE,OPTIONS --target /
echo "== mount holding /home"; findmnt -no SOURCE,FSTYPE,OPTIONS --target /home
echo "== filesystem type of / and /home"; stat -f -c '%n %T' / /home
echo "== xfs reflink on /"; xfs_info / 2>/dev/null | grep -o 'reflink=[01]' || echo not-xfs-or-no-access
echo "== xfs reflink on /home"; xfs_info /home 2>/dev/null | grep -o 'reflink=[01]' || echo not-xfs-or-no-access
echo "== active LSM list"; cat /sys/kernel/security/lsm; echo
echo "== kernel config"; grep -E '^CONFIG_BPF_LSM=|^CONFIG_LSM=' "/boot/config-$(uname -r)" || echo CONFIG_BPF_LSM-not-found
echo ROCKBOX-FS-CHECK-DONE
```

## Raw output (verbatim)

```text
== kernel
7.3.0-10-generic
== mount holding /
/dev/nvme0n1p2 ext4 rw,relatime
== mount holding /home
/dev/nvme0n1p2 ext4 rw,relatime
== filesystem type of / and /home
/ ext2/ext3
/home ext2/ext3
== xfs reflink on /
not-xfs-or-no-access
== xfs reflink on /home
not-xfs-or-no-access
== active LSM list
lockdown,capability,landlock,yama,apparmor,bpf,ima,evm
== kernel config
CONFIG_BPF_LSM=y
CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor,bpf"
ROCKBOX-FS-CHECK-DONE
```

## Reading (per the §3 result tables)

- **Filesystem (fix 2):** `/` and `/home` are the same filesystem, one ext4 partition (`/dev/nvme0n1p2`). `stat -f` prints `ext2/ext3` for ext4, as §3 expected. Not XFS, not btrfs, so no reflink / FICLONE. Rollback on Rock Box needs a **full-copy shadow** (AJ's fix 2 ext4 row).
- **Consequences for O22:** a full-copy store on `/` shares space with the OS, so its disk cap must protect free space on `/`. A full-copy store may sit on another disk; the `EXDEV` same-filesystem limit applies only to clones, not to full copies.
- **BPF LSM (Stage 2 entry 3):** `CONFIG_BPF_LSM=y` and `bpf` is in the active LSM list. BPF LSM programs can attach on Rock Box. No kernel command-line change and no reboot are needed for BPF LSM.
