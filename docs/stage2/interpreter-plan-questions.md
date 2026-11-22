# Stage 2 Prep: Interpreter Handling Plan — Questions for AJ (DRAFT)

Rev 1, 2026-11-21 America/Chicago. Status: **DRAFT — QUESTIONS FOR AJ (NOT A FINALIZED DESIGN).** Presents options and stops for AJ's choice (`AGENTS.md:22`; `AGENTS.md:9`). Nothing is locked in this document.

---

## 1. Context: What AJ Already Decided vs. What Is Open

Already decided by AJ on 2026-11-14 and 2026-11-17 (`docs/architecture/architecture-rev2.md` §1.5 Fix 1, §2.1, §4 Stage 2, §7 O17/O21/O28):
- **O21 (K3 verdict model for Stage 2 processes):** Kleene three-state — `KnownGood (+1)`, `Unknown (0)`, `KnownBad (-1)`.
  - `Unknown` = executable's SHA-256 is on neither the signed allow list nor the deny list.
  - **No promotion via the parent process.**
  - **Interpreter gap (AJ-decided requirement):** *"Interpreters (`python3`, `bash`, etc.) are a known gap: acceptable while observe-only; a plan is required before enforcing."*
- **O17 (AJ-signed rule loosening):** minisign (Ed25519), verified in userspace before any BPF map write; private key kept on USB stick + Rock Box for now (password-protected, not `-W`; AJ creates keys himself; public key may be committed). AI may only tighten or suggest; loosening comes **only** from AJ-signed rules (Fix 1).
- **O28 = C (Rollout mode):** observe-only globally on Rock Box, except one enforcing test cgroup (after the Fast Path cgroup-scoping feasibility test confirms it; see `docs/stage2/cgroup-scoping-test-runbook.md`).

### Why interpreters break naive binary-hash K3
When a user or attacker runs `python3 /tmp/payload.py`, `bash -c 'curl ...'`, or `node evil.js`, the binary seen by `execve` / `lsm/bprm_check_security` is the **interpreter** (`/usr/bin/python3`, `/usr/bin/bash`, `/usr/bin/node`), not the script:
1. If `/usr/bin/python3` and `/usr/bin/bash` are on the signed `KnownGood` allow list, **any arbitrary untrusted script or one-liner runs as `KnownGood`** and completely bypasses `Unknown` network gating.
2. If `/usr/bin/python3` and `/usr/bin/bash` are left in `Unknown`, then **enforcing network gating on `Unknown` will disrupt normal Rock Box activity** (interactive shells, `apt`/package hooks, GNOME/systemd helpers, `ROCK-BOX-BOT`, Python dev tooling, `git`/`gh` scripts) unless scoped or exempted by AJ-signed rules.
3. Even if you hash a script file (`foo.py`), interpreters also accept inline code (`-c`, `-e`), stdin pipes (`curl ... | bash`), dynamic `import` / `source` / `eval`, environment hooks (`PYTHONPATH`, `PYTHONSTARTUP`, `BASH_ENV`, `LD_PRELOAD`), and indirect loaders (`/lib64/ld-linux-x86-64.so.2 /tmp/untrusted_elf`).

No single Linux mechanism solves all of these with zero friction. Below are the six architectural choices AJ needs to make before Stage 2 enforcement extends beyond a native-binary test cgroup.

---

## 2. Questions for AJ (with Honest Tradeoffs)

### Q1. When enforcing starts, what is the default K3 state of an interpreter binary itself?

| Option | Behavior | Pros | Cons / Bypasses | Rock Box breakage risk |
|---|---|---|---|---|
| **A. Always `Unknown` by default** | Interpreter binaries (`python3`, `bash`, `sh`, `node`, etc.) are **never** given a blanket `KnownGood` entry. They are network-gated (`Unknown`) unless matched by a narrower AJ-signed rule (Q5). | Closes the LOLBin / `python3 -c` / `curl \| bash` bypass cleanly; strictly honors O21 ("Unknown = not on allow list"). | High maintenance burden on a dev workstation; AJ must sign narrow exceptions for legitimate scripts/services or run them outside enforcing cgroups. | **High** if applied host-wide; **low** if scoped to one test cgroup first. |
| **B. Conditional `KnownGood`: interpreter hash + signed script hash** | Interpreter stays `Unknown` unless the executed script file is also on an AJ-signed script allow list (requires a Q2 script-identification mechanism). | Matches operator intuition ("allow *this* Python script, not *all* Python"). | Vulnerable to TOCTOU races if checked via `argv` path; bypassed by secondary imports (`import evil`), `-c`, `eval`, or `BASH_ENV` unless Q2/Q3 close them. | **Medium** (requires signing routine scripts and re-signing whenever a script is edited). |
| **C. Interpreter binary is `KnownGood`; accept the gap in Stage 2 and rely on behavior + Stage 3 AI** | Put system interpreter SHA-256s on the signed allow list; catch malicious scripts via `vfs_write` sampling, lineage telemetry, and Stage 3 async AI triage rather than blocking at `exec`. | Zero workstation breakage; simple to ship Stage 2 quickly. | **Major bypass:** any attacker using `python3` or `bash` bypasses Stage 2's `Unknown` network gate entirely (only post-hoc detection/tightening, never preventive gating). | **Very low.** |
| **D. Phased split (observe host-wide first; enforce in test cgroup)** | Keep host-wide Rock Box interpreters observe-only during Stage 2 while proving enforcement on (1) native binaries and then (2) Option A or B **inside the single enforcing test cgroup**, measuring real Rock Box interpreter traffic before choosing a host-wide rule. | Zero workstation disruption up front; collects real Rock Box telemetry so AJ's host-wide choice is backed by data rather than guesses. | Delays host-wide interpreter enforcement until after observe-only telemetry is reviewed. | **Low** during test-cgroup phase; host-wide risk deferred until Option A, B, or C is chosen. |

**AJ decides.**

---

### Q2. If Stage 2 tries to identify "which script is running", which technical mechanism is acceptable?

| Option | How it works | Honest strengths | Honest limits / unverified items |
|---|---|---|---|
| **A. Kernel `bprm_check_security` shebang + `argv` inspection** | For `./script.py` with `#!/usr/bin/python3`, kernel sees the script file in `bprm`; for `python3 script.py`, inspect `argv` to find a script path and hash it. | Works on stock Ubuntu interpreters with no interpreter patches. | **TOCTOU race:** hashing a path from `argv` before the interpreter opens it lets an attacker swap the file between check and open. Fragile against flag permutations (`python3 -u -I -B script.py`, `python3 -m pkg`), and blind to `-c`, stdin, and `import`/`source`. Exact `bprm_check_security` multi-pass behavior on shebang scripts on kernel `7.3.0-10-generic` is **UNVERIFIED**. |
| **B. Linux `AT_EXECVE_CHECK` (`execveat(2)` flag, Linux 6.14+) + securebits** | Kernel exposes `AT_EXECVE_CHECK` so cooperating interpreters ask the kernel's LSM ("would execution of this script/module fd be allowed?") before running it, paired with `SECBIT_EXEC_RESTRICT_FILE` / `SECBIT_EXEC_DENY_INTERACTIVE`. | Eliminates TOCTOU (operates on open fd) and covers imported/sourced files without guessing `argv`. | **Requires cooperating user-space interpreters.** Rock Box's `7.3.0-10-generic` kernel is newer than 6.14 (where `AT_EXECVE_CHECK` is built into core VFS with no dedicated core Kconfig gate), so the open question is whether stock Ubuntu 26.10 `python3`/`bash`/`node` binaries actually call `AT_EXECVE_CHECK` (**UNVERIFIED**, and unlikely to cover every interpreter on a workstation today). |
| **C. Kernel `file_open` / `mmap_file` hook for interpreter PIDs** | Track every file opened by a running interpreter PID and classify/hash opened scripts. | Sees the real open fd (reduces TOCTOU vs `argv`); catches `source` and `import`. | **High overhead** (Python opens hundreds of stdlib `.py`/`.so` files on startup); hard to separate code opens (`import evil.py`) from data opens (`open("report.txt")`); still blind to `-c` and stdin pipes. |
| **D. Do not attempt script hashing in Stage 2** | Classify solely by executable SHA-256 + cgroup/service context (fits Q1 Option A, C, or D). | Zero TOCTOU, minimal kernel complexity, no fragile `argv` parsing. | Cannot distinguish a trusted `python3` script from an untrusted `python3` script by script hash alone. |

**AJ decides.**

---

### Q3. How should interactive shells, inline execution (`-c` / `-e`), stdin pipes (`curl ... | bash`), and `eval` be handled?

1. **Option A — Always `Unknown` (network-gated when enforcing):**
   - *Pros:* Blocks the exact patterns most real-world Linux payloads use (`bash -c`, `python3 -c`, `curl ... | sh`).
   - *Cons:* Blocks AJ's own interactive shell commands (`curl`, `git`, `ssh`, `gh`, one-liners) unless AJ's interactive terminal/session has an explicit signed exception.
2. **Option B — Exempt AJ's interactive desktop/TTY session; enforce `Unknown` on non-interactive/background/headless invocations:**
   - *Pros:* Preserves workstation usability while still gating cron jobs, background daemons, and automated/test workloads.
   - *Cons:* Anything launched inside AJ's desktop session (for example, a compromised browser/IDE/CLI plugin spawning `bash -c` inside the user session) inherits the exemption unless isolated into a stricter cgroup.
3. **Option C — Observe-only for interactive/inline in Stage 2 (log full lineage + bounded `argv` for triage), enforce only inside the test cgroup:**
   - *Pros:* Zero false positives on Rock Box while building real baseline logs.
   - *Cons:* Does not prevent outbound network access from interactive/inline interpreter abuse outside the test cgroup during Stage 2.

**AJ decides.**

---

### Q4. What belongs in the interpreter / indirect-loader inventory, and how is it matched?

Beyond `python3` and `bash`, Linux has a long tail of execution vectors that bypass binary-only allow lists:
- **Shells & scripting runtimes:** `sh`/`dash`, `bash`, `zsh`, `python3`, `perl`, `ruby`, `node`, `awk`/`gawk`, `lua`, `php`, `tclsh`.
- **Developer/build runners present on Rock Box:** `cargo`, `rustc`, `make`, `env`, `xargs`, `find` (`-exec`).
- **Dynamic loader & memory-only execution:** invoking `/lib64/ld-linux-x86-64.so.2 /tmp/untrusted_elf` directly (executes an untrusted ELF while `execve` sees `ld-linux`), or executing from `memfd_create` / anonymous executable `mmap` (`PROT_EXEC`).

Questions for AJ:
1. **Inventory size for Stage 2:** Start with a small explicit starter set (e.g., `sh`/`dash`, `bash`, `python3`, `ld-linux`) or cover all installed scripting runtimes from day one?
2. **Matching key:** Key the interpreter list by **executable SHA-256** (defeats trivial `cp /usr/bin/python3 /tmp/foo` renaming, but requires updates when Ubuntu patches the binary) or by path + SHA-256?
3. **`memfd_create` / anonymous `PROT_EXEC`:** Treat fileless execution as immediately `Unknown` (or `KnownBad`)? Note: JIT engines (Chrome V8, Steam/Proton, some runtimes) use anonymous `PROT_EXEC` pages, so marking all `PROT_EXEC` as `KnownBad` will break Chrome/Steam on Rock Box; `memfd_create` exec (`bprm->file` backed by `memfd:`) is much narrower and safer to flag.

**AJ decides.**

---

### Q5. How should AJ-signed rules (O17 minisign) express interpreter exceptions, and how should routine `apt` upgrades be handled?

Remember **O17** (`docs/architecture/architecture-rev2.md` §7 O17): minisign (Ed25519), verified in userspace before any map write, private key on USB + Rock Box with password prompt (not `-W`).

| Option | Rule granularity | Operational tradeoff on Rock Box |
|---|---|---|
| **A. Pure SHA-256 allow/deny lists** | Only exact executable SHA-256 hashes. | Cleanest O21 semantics; **breaks after every Ubuntu security update** to `bash` or `python3` until AJ signs a refreshed rule bundle. |
| **B. Executable SHA-256 + cgroup / systemd-unit scope** | Example: allow `python3` (SHA-256 `H`) only inside `johnny-relay.service`, not globally. | Tightly bounds blast radius (compromised app in another slice cannot abuse the rule). Still requires AJ to re-sign after `python3` package updates. |
| **C. Executable SHA-256 + script SHA-256 tuple** | Example: allow `(python3_sha256, script_sha256)`. | Depends on Q2 (script identification); requires re-signing whenever either `python3` or the script changes. |
| **D. Allow-by-dpkg-package / path** | Trust binaries owned by verified Ubuntu packages. | Survives `apt upgrade` without re-signing, **but weakens strict O21 SHA-256 enforcement** and shifts trust to the local `dpkg` database (and root can already modify the host while lockdown is `none`, per O25). |

**AJ decides.**

---

### Q6. How should interpreter telemetry feed Stage 2's other hooks and Stage 3's async AI?

- Per **O21**, child processes **never** inherit `KnownGood` from a parent (no parent-process promotion).
- Per **Fix 3** (`docs/architecture/architecture-rev2.md` §1.5), 4 KB `vfs_write` sampling must be paired with lineage/behavior context.
- Per **Fix 1** and **MITRE ATLAS AML.T0051** (`docs/agent-team.md:83`), any `argv`, filename, or script path collected from an interpreter is **untrusted attacker-controlled data** and must be length-capped and delimited before ever reaching Stage 3's AI triage.

Question for AJ:
- Should Stage 2's observe-only exec telemetry record bounded `(pid, ppid, cgroup_id, exe_sha256, uid, truncated_argv)` for **all** execs on Rock Box (providing the exact dataset needed to pick Q1–Q5 host-wide), or only for processes inside selected cgroups / matching the Q4 interpreter list? (Privacy note: recording full `argv` host-wide can capture secrets passed on command lines, so logging truncated/redacted `argv` or restricting `argv` capture is a real tradeoff for AJ to call.)

**AJ decides.**

---

## 3. Summary Decision Matrix (Awaiting AJ)

| ID | Question | Depends on | Status |
|---|---|---|---|
| **Q1** | Default K3 state of interpreter binaries when enforcing (A: always `Unknown`, B: conditional on signed script, C: `KnownGood` + accept gap, D: phased — observe host-wide first, enforce in test cgroup) | O21, O28 C | **AJ decides.** |
| **Q2** | Script-identification mechanism (A: shebang + `argv`, B: `AT_EXECVE_CHECK`, C: `file_open` hook, D: none in Stage 2) | Q1 | **AJ decides.** |
| **Q3** | Interactive shells, `-c`/`-e`, stdin pipes, `eval` (A: always `Unknown`, B: exempt interactive TTY, C: observe-only outside test cgroup) | Q1 | **AJ decides.** |
| **Q4** | Interpreter & indirect-loader inventory (`sh`/`bash`/`python3`/`ld-linux`/`memfd`), matching key (SHA-256 vs path+SHA-256) | Q1, O21 | **AJ decides.** |
| **Q5** | Minisign (O17) rule granularity & `apt upgrade` re-signing workflow (A: SHA-256 only, B: SHA-256 + cgroup/unit, C: exe+script pair, D: dpkg/path) | O17, Q1, Q2 | **AJ decides.** |
| **Q6** | Exec telemetry scope & `argv` capture/privacy tradeoff feeding Fix 3 / Stage 3 | Fix 1, Fix 3, O21 | **AJ decides.** |

*Stopping here for AJ's architectural choices per `AGENTS.md:22`.*

---

## 4. Sources

- `docs/architecture/architecture-rev2.md` (§1.5 Fix 1 & Fix 3, §2.1 Decisions 3 & 4, §4 Stage 2, §7 O17/O21/O25/O28)
- `docs/architecture/architecture-pass.md` (Item F: K3 verdict model)
- `docs/stage2/cgroup-scoping-test-runbook.md` (O28 C feasibility test prerequisite)
- `docs/findings/stage2/2026-11-17-rockbox-fs-check.md` & `docs/findings/stage2/2026-11-17-rockbox-lockdown.md`
- Linux kernel docs, *LSM BPF Programs*: https://docs.kernel.org/bpf/bpf_lsm.html
- Linux kernel `AT_EXECVE_CHECK` (`execveat(2)` script execution check, introduced in Linux 6.14): https://docs.kernel.org/userspace-api/check_exec.html (stock Ubuntu 26.10 interpreter adoption is **UNVERIFIED**).
- MITRE ATLAS, *AML.T0051* (LLM Prompt Injection): https://atlas.mitre.org/techniques/AML.T0051
