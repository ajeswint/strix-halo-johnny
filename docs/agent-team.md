# Johnny agent team

Rev 5, 2026-10-31. Agreed by AJ and Grok. Rev 5: first skill file (`cis-audit`); skill folders owned by the agent that holds the skill; `docs/hosts/` → Architect (provisional). Wired: `.claude/agents/` holds one file per agent (9); the Brain is the main session and has no file. Rev 2 (AJ): the SLM has full function for now; architecture-logic questions deferred (§7). Rev 3: Grok review applied (quarantine cross-reference, `.gitignore` owner, Fast Path in PW.9). Rev 4: agent files created.

What this is: the roster that says which agent owns which job, so no two agents do the same work. Inputs: role list `docs/Enterprise Security Software Team Roles.md` (127 titles); control model `docs/Distributed Neural Networks and Control Systems in Cephalopods.md` §1, §4–5; architecture `docs/JOHNNY_ Executive Architectural Summary.md`.

## 1. Shape: brain, optic lobes, eight arms

| Octopus (cephalopod doc) | Johnny team |
|---|---|
| Central brain, <8% of neurons: picks *what*, never *how* | **Brain** = the main session. Picks the next step, routes it to one agent, writes the handoff. Thin on purpose. |
| Optic lobes: whole-scene analysis, relayed to the brain | **Architect**: whole-system view. Architecture, contracts between agents, threat model. Feeds the Brain; builds nothing. |
| 8 arms, >60% of neurons: semi-autonomous executors | **8 arm agents**, one domain each (§2). |
| ~128:1 afferent bottleneck: brain gets summaries, never raw feeds | Reports are capped (§6). Raw output stays in files; reports cite paths. |
| ~1:93 efferent expansion: brain sends a goal, the arm works out the motion | Directive = goal + constraints + done-when. The agent picks the method. |
| No somatotopic map in the brain | The Brain doesn't track *how* agents work. The ownership map (§4) replaces supervision. |

Outside the agent count:
- **AJ** designs and decides. Holds every authority title (§5). Runs anything needing sudo or credentials, and every switch/router change.
- **Overseer**: separate reviewer (README step 3). External.

Count: 9 agents (Architect + 8 arms), run by the Brain. Floor of 8 met.

## 2. Roster

| # | Agent | Owns | Never |
|---|---|---|---|
| — | Brain | sequence, routing, handoff, session logs | domain work |
| OL | Architect | how the parts fit: contracts, threat model, invariants, budgets | implementation code, threshold values, compliance verdicts |
| 1 | Fast Path | capture NIC → eBPF → ring buffer | user-space code, OS files |
| 2 | Daemon | Rust user space: consumer, verdicts, actuator, storage writes, CLI | model internals, detection content |
| 3 | SLM | the on-box small language model: runtime, runtime decisions, eval | daemon code, Suricata/Zeek content |
| 4 | Detection & Response | Suricata, Zeek, thresholds, schema, intel, asset inventory, playbooks | capture plumbing, DB server runtime |
| 5 | Platform | Johnny's OS from firmware up, and the build toolchain | switch, router, detection configs |
| 6 | Network | everything between Johnny's ports and the LAN | Johnny's own netplan |
| 7 | Assurance | tests, reviews, red team: proves it works, tries to break it | product code; checking its own work |
| 8 | Governance | standards, CIS audit, risk, privacy, supply chain, vuln intake | fixes (owners fix); risk acceptance (AJ) |

### Brain (main session)
Thin by design, 6 skills:
- `session-open`: read README → AGENTS → handoff; state of play in ≤10 lines.
- `route`: find the one owner in §4; write the directive (§6).
- `sequence`: keep handoff "Next steps" in order; one step at a time.
- `consolidate`: merge agent reports into `docs/os-handoff.md` (sole writer).
- `arbitrate`: ownership gap or clash → propose an owner, AJ decides, update §4.
- `session-close`: bump the handoff revision; write the session CSV.

### Architect (optic lobes)
- `threat-model`: STRIDE per trust boundary; MITRE ATT&CK for LAN adversaries, MITRE ATLAS for attacks on the SLM.
- `adr-record`: one Architecture Decision Record per decision: context, options, choice, consequences.
- `interface-contracts`: versioned `#[repr(C)]` types for kernel↔daemon, daemon↔SLM, daemon↔storage, daemon↔upstream. Owns `common/` (types only, no logic).
- `trust-boundaries`: data-flow diagrams; enforcement/decision point placement (NIST SP 800-207).
- `verdict-model`: verdict states and transitions. The summary's three-valued K3 model (Known-Bad −1, Unknown 0, Known-Good +1) is the starting draft, not locked (§7).
- `invariant-spec`: safety properties in LTL plus plain English, handed to Assurance to check.
- `resource-budget`: RAM, CPU, PCIe, disk per component on the MS-02 (32 GB single channel; E810 at Gen4 x4 ≈ 50 Gb/s), SLM included.
- `failure-modes`: fail-open vs fail-closed per component; passive now, inline later.

### 1. Fast Path
- `ebpf-programs`: libbpf/CO-RE C, BTF, maps; verifier-safe (bounded loops, no floating point).
- `xdp-capture`: native XDP / AF_XDP on `ice`; count at XDP (handoff step 11).
- `lsm-exec-hooks`: BPF-LSM (`bprm_check_security`), fentry/fexit, exec lineage. Host tier, if Module 1 includes it (§7, deferred).
- `fixed-point-math`: Q16.16 entropy lookup table and integer χ² over 4096-byte buffers (bound 4800), inside verifier limits.
- `ringbuf-producer`: `BPF_MAP_TYPE_RINGBUF` sizing, emit, drop counters.
- `e810-capture-tuning`: `ethtool` promisc, offloads, RSS/queues, rings, IRQ affinity, DDP package; which cores capture gets.
- `lockdown-compat`: what Secure Boot lockdown allows: no `bpf_probe_write_user`; out-of-tree modules need MOK signing.
- `packet-parsers`: EverParse 3D specs → verified zero-copy C parsers.

### 2. Daemon
- `rust-safe-core`: `#![forbid(unsafe_code)]` in user space; clippy clean; explicit errors.
- `ringbuf-consumer`: aya or libbpf-rs; reads events, writes kernel maps.
- `verdict-engine`: applies verdicts and threshold changes, from rules and from the SLM, to kernel maps.
- `openc2-actuator`: OpenC2 request/response (JSON/JADN); local enforcement point: contain, restore.
- `storage-writer`: batched writes to ClickHouse or Timescale; applies Detection's schema migrations.
- `upstream-client`: sends contract-shaped events over the LAN to the MAX.
- `service-hardening`: its systemd unit runs least-privilege: only the capabilities it needs, read-only filesystem view, syscall filter.
- `operator-cli`: local CLI/TUI: status, alerts, AJ's manual verdict override.

### 3. SLM
- `model-selection`: pick the model and quantization that fit the RAM budget; hand license and weight hashes to Governance.
- `inference-runtime`: local quantized inference in user space, sized to the Architect's resource budget, off the capture cores. Runtime choice is an ADR.
- `structured-output`: machine-readable output the Daemon can act on, in the Architect's schema.
- `input-isolation`: strings from traffic, filenames and command lines are data, never instructions: delimit, cap length, escape (MITRE ATLAS AML.T0051).
- `semantic-triage`: judge what rules can't: obfuscated command lines, living-off-the-land patterns, odd DNS/HTTP/TLS metadata.
- `runtime-control`: issue verdicts and adjust thresholds at runtime, tighter or looser (full function for now); the Daemon applies them.
- `telemetry-summarizer`: compress event clusters into compact JSON for storage and upstream.
- `model-eval`: labeled eval set; precision, recall, latency per model + quantization; regression gate before any swap.

### 4. Detection & Response
- `suricata-rules`: write and tune rules; EVE JSON output; thresholds and suppressions. Owns Suricata config.
- `zeek-scripts`: Zeek policy scripts, log selection, packages. Owns Zeek config.
- `attack-coverage`: map every detection to MITRE ATT&CK; list the gaps that matter on a home LAN.
- `telemetry-schema`: DB tables, partitions, TTL; metadata first; inside Governance's retention cap.
- `baseline-thresholds`: per-device baselines; base entropy/χ² thresholds; false-positive tuning with stats.
- `threat-intel`: STIX/TAXII 2.1 feeds and blocklists once Governance has vetted them; indicator aging.
- `asset-inventory`: devices keyed by MAC/IP, learned from traffic; the one list of what's on the LAN.
- `triage-response`: AJ's alert runbook; response playbooks (CACAO style): when to quarantine by MAC ACL/VLAN, never port shutdown.

### 5. Platform
- `ubuntu-2604-packages`: apt pins, holds, security-only unattended-upgrades, the pinned tool-install block (step 7). Every 26.04 claim cites a URL.
- `boot-chain`: Secure Boot db/dbx, PCR 7, LUKS2 + TPM2 enroll/re-enroll, dracut, kernel cmdline.
- `host-networking`: netplan on Johnny: `eno3` mgmt, `eno4` no IP, E810 links up with no addresses.
- `cis-remediation`: write fixes for Governance's failed CIS rules; honor the fix gate (working console first, second SSH session open).
- `data-services`: LVM log volume, XFS, CIS L2 partition split; DB server runtime and backups; journald, kdump.
- `oob-console`: AMT (ACM, TLS-only) settings; KVM/SOL via `rpc-go` or MeshCommander; HDMI dummy; BIOS and firmware, with a PCR 7 impact check before any change.
- `identity-recovery`: users, SSH keys, sudo; secrets inventory (names only, never values); recovery passphrase path, installer USB, config backups.
- `dev-toolchain`: build environment (Rust, clang/LLVM for BPF, bpftool); repo protection.

### 6. Network
- `routeros-crs309`: exact RouterOS 7 commands for AJ to paste on the laptop (ether1); read-back checks; `/export terse` snapshots.
- `span-design`: which ports mirror, what stays invisible (Wi-Fi behind the router), oversubscription (4 × 1G into a 10G target).
- `port-isolation`: `forwarding-override` one-way vs two-way; the AMT out-of-band path to rock-box.
- `quarantine-path`: MAC ACL / VLAN quarantine on the CRS309, and how an automated response would reach the switch (§7.6).
- `router-rtbe88u`: DHCP reservations, WireGuard placement, the Wi-Fi drop on Apply.
- `cabling-optics`: SFP/DAC inventory, link checks, wall drops. Physical cabling is the truth.
- `port-audit`: bridge host table ↔ port ↔ device, from AJ's pastes and rock-box ARP.
- `inline-and-wifi`: future inline on SFP+8 (fail-open); an AP on the CRS309 for Wi-Fi visibility.

### 7. Assurance
- `acceptance-gates`: pass/fail criteria per step and per release.
- `independent-review`: review other agents' designs and diffs. Never its own.
- `pcap-replay`: tcpreplay of public and lab pcaps at set rates; detection regression suite.
- `throughput-soak`: drop accounting NIC → XDP → ring buffer → daemon; iperf3, hping3; stress-ng + turbostat thermal soak (step 8).
- `fuzzing`: cargo-fuzz / libFuzzer on parsers, daemon inputs, the SLM input path.
- `formal-checks`: model-check the Architect's invariants (Z3 or TLA+); fixed-point vs floating-point reference.
- `adversary-emulation`: scripted ATT&CK scenarios from rock-box against AJ-owned lab hosts only; scores detections.
- `sensor-pentest`: attack Johnny itself: SSH, AMT TLS ports, malformed packets on the SPAN, evasion, prompt injection via traffic strings. Findings include root cause.

### 8. Governance
- `cis-audit`: CIS Ubuntu Linux 26.04 LTS 1.0.0, Level 1 – Server (then L2), with CIS's own audit commands; results CSV. USG / DISA STIG once Canonical ships 26.04 profiles. Status checked on the standards body's own page.
- `standards-map`: map controls to exact releases: SSDF v1.1, SP 800-207, CIS 26.04 1.0.0, MITRE ATLAS, NIST AI RMF.
- `risk-register`: risks, options, recommendation; AJ accepts (e.g. PCR-7-only binding).
- `capture-privacy`: household capture policy: metadata first, header-only snaplen, retention cap. Sets the limits Detection implements.
- `sbom-provenance`: SBOM (packages, crates, model weights), hashes, release records.
- `component-vetting`: vet packages, crates, upstream repos, model weights and intel feeds before first use: license, maintainer, CVE history.
- `vuln-intake`: CVE watch against the SBOM; triage; track to the fix by the owning agent.
- `licensing-procurement`: licenses (CIS non-commercial, model licenses), hardware buys (e.g. the ECC RAM quote), legal flags.

## 3. Zero overlap

**Overlap entropy.** For each responsibility *r* (a title, skill, path or SSDF practice), let *p_r(a)* be agent *a*'s share of it. *H(r) = −Σ p log₂ p*. One owner gives 0 bits; two equal owners give 1 bit. Target: every *H(r)* = 0. Titles, skills and practices are checked by script (§8).

Rules:
1. One writer per artifact (§4). Anyone else sends a request through the Brain.
2. Architect specifies, the owning arm builds, Assurance checks. Nobody checks its own work.
3. Governance sets limits (benchmark, retention, snaplen); the owner implements inside them.
4. Thresholds: Detection sets base values; the SLM changes them at runtime, either direction; the Daemon applies; Assurance measures the effect.
5. Unit tests live with their code. System, acceptance and adversarial tests live in `tests/` (Assurance).
6. Gap or clash → Brain proposes an owner → AJ decides → §4 updated.
7. Agents write files and run read-only checks. AJ runs sudo, credentials, switch and router changes.

Places that look shared, and the split:

| Looks shared | Split |
|---|---|
| Capture NIC | Platform: netplan (link up, no addresses). Fast Path: runtime tuning, XDP. |
| Database | Detection: schema. Daemon: writer code. Platform: server, volume, backups. |
| Thresholds | Detection: base values (config). SLM: runtime changes. Daemon: applies them. Assurance: measures. |
| Devices on the LAN | Detection: asset inventory (from traffic). Network: which port, which cable. |
| AMT | Platform: firmware settings, console. Network: the switch isolation path. |
| Quarantine | Detection: when. Daemon: the OpenC2 command. Network: the switch mechanism. Architect: the path design. |
| CIS | Governance: audit, verdict. Platform: fixes. |
| Model weights | SLM: choice, eval. Governance: license, hash, vetting. |
| Vulnerabilities | Governance: intake, tracking. Owning agent: fix. Assurance: root cause, regression test. |

## 4. Ownership map

`*` = planned, doesn't exist yet.

| Path | Owner |
|---|---|
| `README.md`, `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.claude/agents/`, `docs/os-handoff.md`, `docs/sessions/`, `docs/agent-team.md` | Brain |
| `docs/architecture/`\*, `common/`\*, `docs/hosts/` (hardware records; provisional, AJ to confirm) | Architect |
| `bpf/`\*, capture units `etc/systemd/system/johnny-capture.*`\* | Fast Path |
| `daemon/`\*, `etc/systemd/system/johnny-daemon.service`\* | Daemon |
| `slm/`\*, `etc/systemd/system/johnny-slm.service`\* | SLM |
| `detections/`\*, `db/schema/`\*, `etc/suricata/`\*, Zeek config\* (26.04 path unverified) | Detection |
| `etc/`, everything not listed above (today: all 15 files) | Platform |
| `docs/network-map.md`, `net/`\* (switch exports) | Network |
| `tests/`\*, `bench/`\*, `formal/`\*, `docs/findings/`\* | Assurance |
| `docs/cis-26.04-l1-results.csv`, `docs/compliance/`\*, local CIS PDF and `docs/cis-local/` | Governance |
| `.claude/skills/<skill>/` | the agent that holds the skill (today: `cis-audit` → Governance) |

Reference docs (everyone reads; one keeps them current):

| Doc | Keeper |
|---|---|
| Roles list; cephalopod, octopus predation and antipredator docs | Brain |
| Architecture summary; Security Software Architecture Overview (.md, .pdf); `BEGIN_Network_Security_Software_Enterprise.md` | Architect |
| `CRS309-1G-8SplusIN_200133.pdf`, `ASUS_RT-BE88U.pdf` | Network |
| `B0G39HV95T.pdf` (MS-02 Ultra manual) | Platform |

One exception: the SBOM and config-change tables live in `docs/os-handoff.md` (Brain writes; Governance and Platform supply). Proposal: move the SBOM to `docs/compliance/sbom.md` when the tool-install SBOM is built (step 7).

## 5. Title disposition

All 127 titles, each to exactly one place.

| Goes to | # | Titles |
|---|---|---|
| Brain | 9 | Program Manager (PM); Project Manager; Project Lead; Product Manager; Technical Product Manager; Software Development Manager; Development Lead; Security Team Lead; Future Maintainer |
| Architect | 17 | Chief Engineer; Enterprise Architect; Enterprise Security Architect (ESA); System Architect / Systems Architect; Software Architect; Software/Cloud Architect; Security Architect; Software Security Architect; Information Architect; Architect; Threat Modeller; System Security Engineer; Systems Engineer / System Engineer; Safety Engineer; Software Designer / Designer; Technical Lead; SME Security Lead |
| Fast Path | 3 | Expert Developer; Security Developer; Hardware Developer |
| Daemon | 10 | Product Designer; Product Designer User Interface (UI); Service Designer User Experience (UX); Senior Programmer; Software Developer / Developer; Full-Stack Developer; Programmer / Computer Programmer; Software Engineer; Builder; Software Security Engineer |
| SLM | 3 | Machine Learning (ML) Engineer; MLOps Engineer; AI Security Lead |
| Detection | 6 | Data Scientist; Data Engineer; Data Owner / Data Steward; Systems Security Analyst; Analyst; SOC (Security Operations Center) / Detection Engineer |
| Platform | 13 | Security Engineer; Identity Management Specialist; DevSecOps Specialist; Platform Engineer; Operations Engineer; Maintenance Engineer; IT Engineer; System Integrator; Enterprise Operator; System Administrator; Database Administrator; Administrator; Continuity Planner |
| Network | 1 | Network Administrator |
| Assurance | 12 | Software Assurance Lead / Software Assurance Staff; Application Security (AppSec) Engineer / Application Security Expert; Test Lead; Software Test & Evaluation Specialist; Software Quality Engineer; Quality/Test Engineer; Acceptance Engineer; Software Tester / Tester; Quality Assurance (QA) Personnel; External Penetration Tester / Penetration Tester; AI Pen Tester; Red Team Member |
| Governance | 19 | Information Security Manager; AI Governance / Risk Manager; Risk Manager / Risk Management Professional; Information Owner / Information Steward; Privacy Team Lead; Security Advisor (acting in Expert and Auditor sub-roles); Privacy Advisor / Team Privacy Advisor (acting in Expert and Auditor sub-roles); Primary Security and Privacy Contact; Security and Privacy Expert / Security Expert / Subject Matter Expert; Privacy Engineer; System Security Officer; Privacy Officer; Auditor / Internal Audit / Assurance Personnel; Product Security Incident Response Team (PSIRT) Member; Software Acquirer / Acquirer; Acquisition Official; Procurement Official / Procurement Officer; Cyber Supply Chain Risk Management Program Management Office (C-SCRM PMO) Staff; Legal and Corporate Affairs (LCA) Personnel |
| AJ | 16 | Chief Executive Officer (CEO); Chief Information Security Officer (CISO); Chief Technology Officer (CTO); Chief Information Officer (CIO); Authorizing Official (AO); Senior Information Security Officer; Senior Official for Privacy; Decision Authority (DA); Milestone Decision Authority (MDA); Program Sponsor; Steering Committee; Product Owner; Application Owner; Business Owner / Mission Owner; System Owner; End User / User / Customer |
| External | 2 | Vulnerability Reporter; Regulatory Assessor |
| Dropped | 10 | Defense Acquisition Executive; Component Acquisition Executive (CAE); Program Executive Officer (PEO); Line Manager; User Manager; Property Manager; Security Champion; Security Advocate; Contracting Officer; Human Resources (HR) Personnel |
| Not a role | 6 | Senior Management / Upper Management / Senior Managers; Executive Leaders / Executives; Code Owner; Cybersecurity Professional / Cybersecurity Staff / Security Staff; Operations Staff / Operations People; Technical Personnel / IT Personnel |

Why:
- **AJ (16):** authority titles. Agents propose; only AJ authorizes, accepts risk, owns the product.
- **External (2):** Regulatory Assessor → the Overseer review. Vulnerability Reporter is an outside party; reports land in Governance `vuln-intake`.
- **Dropped (10):** DoD acquisition chain (Defense Acquisition Executive, CAE, PEO) and contract or people admin (Contracting Officer, Line Manager, User Manager, Property Manager, HR): no function in a one-person lab. Security Champion and Security Advocate carry security into non-security teams; every agent here is a security agent, so either would duplicate all nine.
- **Not a role (6):** collective nouns, plus Code Owner, which is a mechanism (§4).
- Title counts aren't workload. The source list is governance-heavy and thin on kernel, network and ML: Network gets one title but runs separate devices with their own OS and management path.

## 6. Operating protocol

Directive (Brain → agent):
```
Goal:
Constraints:
Done when:
Owner paths:
Out of scope:
```

Report (agent → Brain), 12 lines max:
```
Result: done | blocked | needs AJ
Evidence: file paths (raw output stays there)
Commands for AJ: exact, copy-paste, no placeholders
Assumptions: marked
Handoffs: request to <agent>: what
Open: questions for AJ
```

Every agent inherits `AGENTS.md`: terse, one step at a time, show commands first, cite a URL for any 26.04 claim, never echo or store passwords, Johnny work only, stop after presenting options.

## 7. Source conflicts

Resolved (AJ, 2026-10-31):
1. **On-box LLM: yes.** README and AGENTS.md said "No LLM on the box" from the first repo commit (`4eef916`, 2026-10-29), credited to a 2026-10-20 planning session that isn't in the repo. The architecture summary puts an SLM in Tier 2. Rule removed.
2. **SLM limits: full function for now.** The BEGIN doc lets the SLM relax thresholds; the architecture summary §4 says tighten-only, schema-bound risk scores, never run commands. AJ: models have full function for now; any limits come with the architecture pass. README and AGENTS.md say so.

Deferred to the architecture pass (AJ: don't work the architecture logic yet):
3. **Tier 1** (global cloud, cross-tenant, MLS fleet keying). No agent until a fleet exists. Assumption: upstream stays the MAX over the LAN (README).
4. **Endpoint vs network.** The summary's Module 1 is host-side (BPF-LSM exec, `vfs_write` entropy, CoW rollback); Johnny's first job is a passive SPAN sensor, and README Module 1 is "eBPF fast path". Fast Path holds both XDP and LSM skills, so the roster works either way.
5. **CoW filesystem.** The summary's CoW example names a btrfs snapshot; Johnny's root is XFS (FICLONE works only within one filesystem).
6. **Automated quarantine path.** OpenC2 `contain` → MAC ACL/VLAN needs a way to reach the switch; the CRS309 is managed only from the laptop on ether1.
7. **Verdict model.** The K3 states and transitions are a draft (Architect `verdict-model`).

## 8. Review checklist

For the Overseer and Grok. Each line can be checked:
1. All 127 titles in the roles doc map to exactly one destination (§5).
2. 78 skills, no name repeated: 8 each for the Architect and every arm, 6 for the Brain.
3. All 19 SSDF v1.1 practices have an owner (table below). PW.5, PW.6, PW.9 split by path; no shared files.
4. Every repo path has one owner (§4).
5. No agent holds an authority title; AJ holds all 16.
6. Every place in §3 that looks shared has a split rule.
7. SSDF PO.2.1 Example 3's role list (cybersecurity staff, security champions, project managers and leads, senior management, developers, testers, software assurance leads and staff, product owners, operations and platform engineers) is covered in §5.

| SSDF v1.1 practice | Owner |
|---|---|
| PO.1 Define security requirements | Governance |
| PO.2 Implement roles and responsibilities | Brain (this doc) |
| PO.3 Implement supporting toolchains | Platform |
| PO.4 Define and use criteria for security checks | Assurance |
| PO.5 Secure development environments | Platform |
| PS.1 Protect code from tampering | Platform |
| PS.2 Verify release integrity | Governance |
| PS.3 Archive and protect releases (incl. SBOM) | Governance |
| PW.1 Design to meet security requirements | Architect |
| PW.2 Review the design | Assurance |
| PW.4 Reuse well-secured software | Governance |
| PW.5 Secure coding | by path: Fast Path `bpf/`, Daemon `daemon/`, SLM `slm/`, Architect `common/` |
| PW.6 Secure build configuration | same split as PW.5 |
| PW.7 Review code | Assurance |
| PW.8 Test executable code | Assurance |
| PW.9 Secure defaults | by path: Platform (OS), Daemon, SLM, Detection (sensor configs), Fast Path (`bpf/`, capture units) |
| RV.1 Identify vulnerabilities | Governance |
| RV.2 Assess, prioritize, remediate | Governance (fix: owning agent) |
| RV.3 Root-cause analysis | Assurance |

PW.3 was deleted in v1.1 (merged into PW.4). Source: [NIST SP 800-218, SSDF v1.1, Feb 2022](https://csrc.nist.gov/pubs/sp/800/218/final). SSDF v1.2 is still an initial public draft ([SP 800-218r1 ipd, 2025-12-17](https://csrc.nist.gov/pubs/sp/800/218/r1/ipd)); re-map when it goes final.

## 9. Next (not done)

1. ~~AJ and Grok agree on this roster.~~ Done 2026-10-31.
2. ~~Wire it: one `.claude/agents/<agent>.md` per agent (mission, owned paths, skills, report format).~~ Done 2026-10-31. Skills are lines in each agent file; a skill gets its own `SKILL.md` once its procedure is stable. First: `.claude/skills/cis-audit/` (done 2026-10-31, preloaded by Governance). Next candidates as the work arrives: `ubuntu-2604-packages` (step 7), `throughput-soak` (step 8), `e810-capture-tuning` (step 11).
3. Optional: a hook that blocks writes outside an agent's owned paths.
4. Architecture pass: the deferred items in §7.
