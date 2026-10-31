# Johnny handoff → Grok: agent team review (2026-10-31)

> **Historical.** Review done: Grok confirmed `7a2409b` and `c215237`. Current state: `docs/os-handoff.md` (latest rev) and `docs/agent-team.md`.

From Claude (Opus 5.5) to Grok (4.7). Repo `ajeswint/strix-halo-johnny`. The project is "Johnny", never "Sentinel". Read `AGENTS.md` first; its rules bind you too.

## The ask
Review `docs/agent-team.md` (rev 2). AJ wants both models to agree on it. Return:
- **Agree** or **Disagree** per section (§1–§9), with reasons.
- Any title, skill, path or SSDF practice with two owners or none. Run the §8 checklist.
- Proposed changes as exact edits to `docs/agent-team.md`, one-line reason each.

Out of bounds: the architecture logic (AJ deferred it) and SLM limits (full function for now). Don't reopen them.

## Johnny in five lines
- Defensive network-security platform. First deployment: a 24/7 passive sensor on the home LAN (CRS309 port mirror → Intel E810 in a Minisforum MS-02 Ultra).
- Ubuntu Server 26.04.1, Secure Boot, TPM-unlocked LUKS, headless in a closet. AJ designs; agents build. AJ runs anything needing sudo or credentials.
- Stage: OS hardening. CIS Ubuntu Linux 26.04 LTS 1.0.0 Level 1 audit, section 1 of 7 done. Tool install (Suricata, Zeek, …) comes after the baseline.
- Then Module 1 (eBPF fast path). Planned stack: Suricata + Zeek + own Rust daemon + ClickHouse or Timescale, plus an on-box SLM.
- Current state: `docs/os-handoff.md` (rev 8). Ports and cabling: `docs/network-map.md`.

## AJ's calls this session
1. Prune the 127-title role list (`docs/Enterprise Security Software Team Roles.md`) to at least 8 agents, no overlap, a healthy set of skills each.
2. The on-box LLM is part of the architecture. "No LLM on the box" (first repo commit, no recorded source) is gone from README and AGENTS.md.
3. Don't work the architecture logic yet. Models have full function for now.

## The roster
Octopus control model (`docs/Distributed Neural Networks and Control Systems in Cephalopods.md` §4–5): the brain picks *what*, arms work out *how*, and arms report summaries, not raw feeds.

- **Brain** = the main session. Routes each step to one owner; sole writer of the handoff.
- **Architect** = optic lobes. Whole-system view; builds nothing.
- **8 arms**, one domain each.

9 agents in all (floor was 8).

| Agent | Owns | Skills |
|---|---|---|
| Brain | sequence, routing, handoff, session logs | session-open, route, sequence, consolidate, arbitrate, session-close |
| Architect | contracts, threat model, invariants, budgets | threat-model, adr-record, interface-contracts, trust-boundaries, verdict-model, invariant-spec, resource-budget, failure-modes |
| 1 Fast Path | capture NIC → eBPF → ring buffer | ebpf-programs, xdp-capture, lsm-exec-hooks, fixed-point-math, ringbuf-producer, e810-capture-tuning, lockdown-compat, packet-parsers |
| 2 Daemon | Rust user space | rust-safe-core, ringbuf-consumer, verdict-engine, openc2-actuator, storage-writer, upstream-client, service-hardening, operator-cli |
| 3 SLM | the on-box model | model-selection, inference-runtime, structured-output, input-isolation, semantic-triage, runtime-control, telemetry-summarizer, model-eval |
| 4 Detection & Response | Suricata, Zeek, thresholds, schema, inventory, playbooks | suricata-rules, zeek-scripts, attack-coverage, telemetry-schema, baseline-thresholds, threat-intel, asset-inventory, triage-response |
| 5 Platform | Johnny's OS from firmware up; build toolchain | ubuntu-2604-packages, boot-chain, host-networking, cis-remediation, data-services, oob-console, identity-recovery, dev-toolchain |
| 6 Network | switch, router, optics, mirror, isolation | routeros-crs309, span-design, port-isolation, quarantine-path, router-rtbe88u, cabling-optics, port-audit, inline-and-wifi |
| 7 Assurance | tests, independent review, red team | acceptance-gates, independent-review, pcap-replay, throughput-soak, fuzzing, formal-checks, adversary-emulation, sensor-pentest |
| 8 Governance | CIS audit, risk, privacy, supply chain, vuln intake | cis-audit, standards-map, risk-register, capture-privacy, sbom-provenance, component-vetting, vuln-intake, licensing-procurement |

One-line meaning of every skill: `docs/agent-team.md` §2.

## How "no overlap" is enforced
- One writer per file (ownership map, §4). Others request through the Brain.
- Architect specifies → owner builds → Assurance checks. Nobody checks its own work.
- Governance sets limits; owners implement inside them.
- AJ holds all 16 authority titles and runs sudo, credentials, switch and router changes.
- Overlap entropy *H = −Σ p log₂ p* per title, skill, path and practice; target 0 bits. Script-checked: 127/127 titles mapped once, 78 skill names unique, 19/19 SSDF v1.1 practices owned (PW.5/6/9 split by path).
- Titles: Brain 9, Architect 17, Fast Path 3, Daemon 10, SLM 3, Detection 6, Platform 13, Network 1, Assurance 12, Governance 19, AJ 16, External 2, Dropped 10, Not a role 6. Counts aren't workload: the source list is governance-heavy and thin on kernel, network and ML.

## Deferred (not for this review)
Tier 1 cloud; Module 1 host-side vs network-side; btrfs vs XFS for CoW; automated quarantine path to the switch; the verdict model (K3 draft). Listed in `docs/agent-team.md` §7.

## Standards
SSDF v1.1 (NIST SP 800-218, Feb 2022) is the current final; v1.2 is an initial public draft (2025-12-17). Checked on csrc.nist.gov 2026-10-31. Cite primary pages, not search summaries.

## Files this session
`docs/agent-team.md` (new), `README.md`, `AGENTS.md`, `docs/os-handoff.md` (rev 8), this file, `docs/sessions/Johnny_AgentTeam_Session_Log_2026-10-31.csv`. No change on Johnny.
