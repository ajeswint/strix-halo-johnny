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

**Self-test evidence (rock-box, 2026-11-06 ~06:35Z).** `SELF-TEST-OK`, `E2E-OK`, `STATIC-INVOCATIONS-OK 25`. Mutation checks (temporary edits, restored): an `ethtool -K` call through `ro`, a bare `ip link set`, an allowlist that permits `-K`, `systemctl start`, `journalctl --vacuum`, a missing STOP row in the runbook, `sudo` in Paste 1, `stop()` that no longer counts, an IRQ-outside-cores check downgraded to a NOTE, and a wrong sample-seconds divisor: all made the self-test fail. One earlier full run printed `e2e user rc: got [1] want [0]` once, right after the harness moved a long command to the background; I could not reproduce it (five clean loops afterwards, and with stdin as `/dev/null` and closed). The self-test now prints the probe output on any rc mismatch, so a recurrence is diagnosable. **[Unexplained]**, not claimed fixed.

**Assumptions and unverified (all in the runbook).** MTU 1500 (probe measures). A first XDP attach on `ice` may move the IRQ pins (tested in the attach paste, not here). UMEM accounting (memlock vs cgroup) on this kernel. `bpftool -j feature probe kernel` JSON key names are from memory; fixtures in the self-test are illustrative, not live captures. LRO and VLAN-offload effects on XDP are not read from source. `ethtool -S/-x/-n/--show-priv-flags` and `ss -f xdp` as `aj`. Apt candidates come from cached lists. The Ubuntu `stonking` bpftool man pages are not the `resolute` pages. The January 2023 `ice` XDP multi-buffer patch is cited from its posting; the merging kernel release was not confirmed.

**Known limitation, same as step 11.** Paste 2 runs the script as root from `/home/aj/cis-audit/` after a hash check. There is no root-owned copy, so a process running as `aj` could swap the file between the check and the run.

**Not touched.** `docs/agent-team.md` (Brain's), `etc/` (no Johnny file changes), `.claude/agents/`, soft nits N1–N5 from PR #20, any CIS or OS paste. No Suricata config. No sudoers change.

**Johnny paste.** Drafted, not run: Paste 1 (no sudo) and Paste 2 (optional, sudo) in the runbook.
