# 2026-11-06 UTC (2026-11-05 evening to 2026-11-06 America/Chicago): Module 1 slice 1 started (draft)

Seat: code-writer (Sonnet, effort high). Branch `claude/module1-span-xdp-slice1`, from `claude/practical-ritchie-4c6vvf` tip `17633cc` (handoff rev 95, PR #21 merged). Docs, one read-only probe script, one self-test. **No sudo, no apt, no SSH, no Johnny contact.** Nothing applied. Not yet reviewed.

**Trigger.** AJ said **go** on Module 1 (2026-11-05 evening America/Chicago). OS gate APPROVED (`docs/findings/overseer-review-os-gate.md` §8).

**Scope (AJ, §8).** First slice only: the passive SPAN / XDP path on `eno1np0`. Host LSM, idle-memory investigation, Suricata config, inline, quarantine, Wi-Fi: not started. Lab UKI option A unchanged.

**What was written.**
- `docs/tool-install/module1-slice1-span-xdp.md`: runbook. Path decision, constraints, a fact-to-decision table, two pastes, a STOP table, the sketch of the next paste (marked not drafted).
- `docs/tool-install/module1-slice1-probe.sh`: read-only capability probe. `user` mode (as `aj`, no sudo) and `root` mode (`bpftool` only). Tokens `M1S1-PROBE-DONE`, `M1S1-PROBE-ROOT-DONE`. Every Johnny-state command goes through `ro()`, which refuses anything off the allowlist and exits 97. STOPs are collected, not fail-fast.
- `docs/tool-install/module1-slice1-self-test.sh`: rock-box. Allowlist positive and negative cases, `ro` against command shims, parser fixtures, an end-to-end run of both modes against a fake `/sys` and `/proc` plus shims, static checks (every `ro`/`save` call passes the allowlist; no forbidden text), runbook cross-checks (hash, tokens, paste shape, STOP table). `SELF-TEST-OK`.
- `docs/os-handoff.md` rev 96; `README.md` Sequence 4.

**Path choice (a draft recommendation, not AJ's decision).** The task asked the seat to choose and justify. Choice: permanent native-XDP observer (`xdpdrv` only, always `XDP_PASS`, header-only metadata in BPF maps). AF_XDP zero-copy deferred. AF_PACKET kept as the cross-check. The handoff and the runbook say AJ and the reviewer confirm it before any attach paste. AGENTS.md says to stop and wait for AJ's choice after presenting options; the choice here is bounded to a read-only probe that works under any of the three outcomes.

**Why a probe first.** The repo has no recorded `ethtool -k/-l/-g/-x`, memlock limits, huge pages, `XDP_SOCKETS`/`XDP_SOCKETS_DIAG` config, `xsk` sockets, or toolchain facts for `eno1np0`, and step 11 attached before step 13 pinned the IRQs, so the two have never run together.

**Self-test evidence (rock-box, 2026-11-06 ~06:35Z).** `SELF-TEST-OK`, `E2E-OK`, `STATIC-INVOCATIONS-OK 25`. Mutation checks (temporary edits, restored): an `ethtool -K` call through `ro`, a bare `ip link set`, an allowlist that permits `-K`, `systemctl start`, `journalctl --vacuum`, a missing STOP row in the runbook, `sudo` in Paste 1, `stop()` that no longer counts, an IRQ-outside-cores check downgraded to a NOTE, and a wrong sample-seconds divisor: all made the self-test fail. One earlier full run printed `e2e user rc: got [1] want [0]` once, right after the harness moved a long command to the background. **[Resolved in the fix round below]**: that was B1, not a harness effect. `cpu_in_list` piped into `grep -qx` under `set -o pipefail` and lost the race to SIGPIPE on some runs (deterministic with a long list). The self-test prints the probe output on any rc mismatch.

**Assumptions and unverified (all in the runbook).** MTU 1500 (probe measures). A first XDP attach on `ice` may move the IRQ pins (tested in the attach paste, not here). UMEM accounting (memlock vs cgroup) on this kernel. `bpftool -j feature probe kernel` JSON key names are from memory; fixtures in the self-test are illustrative, not live captures. LRO and VLAN-offload effects on XDP are not read from source. `ethtool -S/-x/-n/--show-priv-flags` and `ss -f xdp` as `aj`. Apt candidates come from cached lists. The Ubuntu `stonking` bpftool man pages are not the `resolute` pages. The January 2023 `ice` XDP multi-buffer patch is cited from its posting; the merging kernel release was not confirmed.

**Known limitation, same as step 11.** Paste 2 runs the script as root from `/home/aj/cis-audit/` after a hash check. There is no root-owned copy, so a process running as `aj` could swap the file between the check and the run.

**Not touched.** `docs/agent-team.md` (Brain's), `etc/` (no Johnny file changes), `.claude/agents/`, soft nits N1–N5 from PR #20, any CIS or OS paste. No Suricata config. No sudoers change.

**Johnny paste.** Drafted, not run: Paste 1 (no sudo) and Paste 2 (optional, sudo) in the runbook.

## Fix round (same day, REQUEST-CHANGES B1 and B2 on `b5d71e1`)

Seat: code-writer (Sonnet, effort high). Branch `claude/module1-span-xdp-slice1`, PR #22 stays open. No sudo, no SSH, no Johnny contact. Still a draft, not applied, not re-reviewed.

- **B1 `cpu_in_list`.** Reproduced on the old code first: `cpu_in_list 0 0-30000` returned 1 three times out of three under `set -euo pipefail`. Fix: capture `cpulist_expand` output, match with `case`; also reject a non-numeric CPU and normalize leading zeros. Self-test: `0-30000` first, last, one past the end, ten repeats, leading zero, empty and non-numeric CPU, and substring cases (`1` in `10-12`, `12` in `1-2`).
- **B2 empty `per_core`.** Fix: `IRQ-PER-CORE` loop runs only when the array is non-empty, skips an empty `n`, uses `:-0`; when empty it prints `IRQ-PER-CORE none-inside-capture-cores`. Self-test: all 12 queue IRQs on CPU 9 with cores `1-4` prints `STOP-irq-baseline-outside-capture-cores count=12`, `ZC-QUEUES queues=12 cores=4`, `M1S1-PROBE-STOPS`, no `M1S1-PROBE-DONE`, no `bad array subscript`, and later sections (`KCONFIG`, `UNIT`) still print. A restore step then checks the happy path again (`IRQ-PER-CORE cpu1=3`).
- **N1.** `ro()` exits 97 inside `save()`'s `2>` redirect, so the refusal message went into the `.err` file. My first attempt (printing the `.err` file in the 97 branch) was dead code because `ro()` exits the shell before the branch; the test caught it. Final fix: `save()` calls `ro_allowed "$@" || ro "$@"` before the redirect. Self-test: `save` of a refused command prints `STOP-not-readonly` on stderr and exits 97.
- **N2.** Paste 2 drops the rock-box `sudo -v`. `sudo -v &&` is first inside the `ssh -t` command that runs on Johnny, so the one password prompt is Johnny's and the sudo timestamp is in the same pty as the later `sudo bash`. This differs from the repo rule "`sudo -v` is the block's first line" in letter only: the block's first sudo is `sudo -v`, and it runs where the sudo does. The self-test now rejects any `sudo` outside that line.
- **Mutation checks (each fix reverted alone, then restored):** B1 reverted fails with `cpu_in_list 0 0-30000 must succeed under pipefail`; B2 reverted fails the all-outside e2e (`STOP-irq-baseline-outside-capture-cores count=12` missing, `bad array subscript` in the probe); N1 reverted fails the save test; a bare rock-box `sudo -v` put back into Paste 2 fails the paste-shape check.
- **Result.** New probe sha256 `93d6253720dab71f1b7cc63704f844068daa2c54f7ad78922c9751ebf44fba47`. `SELF-TEST-OK`, `E2E-OK`, `STATIC-INVOCATIONS-OK 25`, `shellcheck` clean. Run several times idle, seven times with 24 CPU-bound loops on 24 cores (one with stdin closed), all `SELF-TEST-OK`.
- N3 to N6 not touched.
