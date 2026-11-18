# 2026-11-17 America/Chicago: Rock Box §3 filesystem + BPF LSM check recorded (Stage 2 prep, docs only)

- **What:** AJ ran the read-only `docs/architecture/architecture-rev2.md` §3 block on Rock Box at ~5:04 PM CT. No sudo, no writes, no ssh; Johnny not touched.
- **Review:** the block ran **unreviewed** (§3 said "not yet reviewed"; no adversarial review happened before AJ ran it). It is read-only, so there was no harm.
- **Raw output:** `docs/findings/stage2/2026-11-17-rockbox-fs-check.md` (all 8 sections, kernel `7.3.0-10-generic`, `ROCKBOX-FS-CHECK-DONE`).
- **Result:**
  - `/` and `/home`: one ext4 partition `/dev/nvme0n1p2` (`stat -f` prints `ext2/ext3` for ext4), no reflink → rollback needs a full-copy shadow (fix 2).
  - BPF LSM: `CONFIG_BPF_LSM=y`, `bpf` in the active list `lockdown,capability,landlock,yama,apparmor,bpf,ima,evm` → active; no kernel command-line change or reboot needed for it.
- **Docs updated:** `docs/architecture/architecture-rev2.md` (fix 2 status, §2.1 Decision 5 row, §3 review state, Stage 2 entry criteria 1-3, O28 wording, O22 and O28 entries), `docs/os-handoff.md` rev 120.
- **Stage 2 entry now:** 2 and 3 met; 1 open (O27: AJ declares Stage 1 exited, or decides to start Stage 2 alongside it); 4 open (O17, O21).
- **O22 addition:** full-copy store on the single ext4 `/` shares space with the OS, so the cap must protect free space on `/`; it may sit on another disk (`EXDEV` limits only clones).
- **O28:** observe-only vs enforcing from the start is AJ's choice; the doc no longer presents observe-only as a default.
- **Constraints kept:** docs only; no Johnny commands, no sudo, `main` untouched.
