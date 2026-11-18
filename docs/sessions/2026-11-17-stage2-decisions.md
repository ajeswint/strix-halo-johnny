# 2026-11-17 America/Chicago: Stage 2 decisions recorded (O17, O21, O27, O28) + Rock Box lockdown check (docs only)

- **AJ decision:** at 7:59 PM CT AJ said "follow claude recs", accepting Claude's leanings as his decisions. Recorded as **AJ-DECIDED 2026-11-17** in `docs/architecture/architecture-rev2.md` (Stage 2 entry criteria 1 and 4, the Stage 2 observe-only line, §1.5 fix 1 signature note, §2.1 Decision 4 row, §7 O17/O21/O27/O28).
  - **O27 = B:** Stage 1 and Stage 2 overlap; Stage 2 may start now; Stage 1 exits after a longer zero-drop window set by AJ (length **PENDING AJ**).
  - **O28 = C:** observe-only, except one enforcing test cgroup; BPF LSM cgroup scoping is **UNVERIFIED** until a Fast Path test confirms it, before any enforcement.
  - **O17:** Ed25519, verified in userspace before any map write; private key not a plain file on Rock Box; FIDO2 `ssh-keygen -Y` if AJ owns one, else minisign (**PENDING AJ**).
  - **O21:** K3 three-state; Unknown = executable SHA-256 on neither the signed allow list nor the deny list; no parent-process promotion; interpreters are a known gap, acceptable while observe-only, plan required before enforcing.
- **Lockdown check:** AJ ran `cat /sys/kernel/security/lockdown` on Rock Box ~7:58 PM CT → `[none] integrity confidentiality` (`docs/findings/stage2/2026-11-17-rockbox-lockdown.md`). Fast Path item, not a gate.
- **Branch note:** PRs #38–#45 and this one merged into `claude/practical-ritchie-4c6vvf`, not `main`; `origin/main` is at handoff rev 52 (2026-11-04); merging to `main` is AJ's call.
- **Still PENDING AJ (from these decisions):** Stage 1 exit zero-drop window length (O27); FIDO2 vs minisign (O17); a cgroup-scoping Fast Path test result before any enforcement (O28); an interpreter plan before enforcing (O21).
- **Handoff:** `docs/os-handoff.md` rev 121. Docs only; no Johnny commands, no sudo, `main` untouched, no Stage 2 writer started.
