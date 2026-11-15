# strix-halo-johnny

Johnny: defensive network-security platform (monitoring, threat detection, response). First deployment is a 24/7 sensor watching the home LAN. AJ designs, Grok builds, Claude reviews.

## Hardware
| Item | Detail |
|---|---|
| Sensor | Minisforum MS-02 Ultra: Core Ultra 9 285HX, 1× 32GB DDR5 non-ECC (single channel, 4800), Crucial P310 1TB |
| Capture NIC | Intel E810-XXV dual 25G SFP28 on riser, PCIe 4.0 x16 slot (runs Gen4 x4) |
| Onboard | RTL8127 (`eno3`, host mgmt); I226-LM 2.5G (`eno4`, AMT only); vPro/AMT activated (ACM, TLS-only) |
| Switch | MikroTik CRS309-1G-8S+IN, RouterOS 7.23.8; managed only from a laptop on ether1. Hardware port mirror (SPAN): ingress on SFP+1/3/4/5 → SFP+7. Port map: [docs/network-map.md](docs/network-map.md) |
| Optics | 1G SFP-to-RJ45 (OEM `SFP-GE-T`) in SFP+1–6; 2× 3m passive 10G DAC (OEM `SFP-H10GB-CU3M`) in SFP+7–8: SFP+7 → Johnny `eno1np0` (mirror target), SFP+8 disabled, Johnny end out |

Host `johnny`, 192.168.50.152 (DHCP on `eno3`, reserved on the router), Ubuntu Server 26.04.1. Access: `ssh aj@192.168.50.152` (key only).

## Sequence
1. L1 lab: done
2. OS: **done and closed** (Overseer gate signed APPROVE by AJ, 2026-11-05 America/Chicago). Boot, firmware, TPM, closet move, AMT (cabled + isolated), the L1-2 port mirror, tool install, the AMT power retest (step 6, 2026-11-05; Soft-reset don't-use), and the E810 capture config (step 11, `STEP11-DONE` 2026-11-05) are done. The thermal soak (step 8, 2026-11-05, `STEP8-DONE`, `NOTE-throttled`) is applied ([docs/tool-install/step-8-thermal-soak.md](docs/tool-install/step-8-thermal-soak.md)). EDAC (step 9, 2026-11-05, `STEP9-DONE`, `LOGS-DONE`, host bridge `0x7d1c`, `NOTE-no-mc`) is applied. `ECC-UNAVAILABLE` restates the non-ECC DIMM record ([docs/tool-install/step-9-edac.md](docs/tool-install/step-9-edac.md)). Step 12 signed UKI research inventory is done (`STEP12-RESEARCH-DONE`, `SLOTS-DONE`, [docs/tool-install/step-12-signed-uki.md](docs/tool-install/step-12-signed-uki.md)). Lab TPM unlock stays PCR 7 only. Option D is not applied. IRQ affinity (step 13, `STEP13-IRQ-DONE` 2026-11-05, paste tip `c765e01`) is applied. Every recorded `eno1np0` IRQ landed on CPU 1 at that paste; steps 13b–13f later spread the twelve TxRx queues over CPUs 1–4 and survive a cold boot ([docs/tool-install/step-13-irq-affinity.md](docs/tool-install/step-13-irq-affinity.md)). State: [docs/os-handoff.md](docs/os-handoff.md)
3. Overseer review: **signed, APPROVE** (AJ, 2026-11-05 America/Chicago). Record: [docs/findings/overseer-review-os-gate.md](docs/findings/overseer-review-os-gate.md) §8
4. Module 1: eBPF fast path — **port-mirror sniffing COMPLETE** (AJ go, 2026-11-05; slice 1 read-only probe applied 2026-11-06; slice 1b passive observe-only native-XDP attach applied 2026-11-06; slice 1c boot persistence unit applied 2026-11-08; slice 2 header-only ringbuf records trial applied and closed 2026-11-11; slice 2b boot-time `j_xdp_records` and persistent rotating reader `johnny-m1s2b-reader.service` APPLIED 2026-11-12T04:05Z, VERIFIED with verify-fix PR #34, and COLD-BOOT PROVEN 2026-11-12 ~05:54Z with `prog_id=78`, `M1S2B-COLD-BOOT-VERIFY-DONE`, [docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md](docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md), [docs/tool-install/module1-slice2b-boot-unit.md](docs/tool-install/module1-slice2b-boot-unit.md); slice 1c disabled/inactive; retention applied 2026-11-14 19:18Z; rate cap raised to cfg 1000000/100000 applied 2026-11-14 21:32Z; week test running to 2026-11-21 15:33 CT; optional future add-ons not started: symmetric RSS, AF_XDP; host LSM deferred to the architecture pass)

## Design decisions (from planning, 2026-10-20)
- Passive (SPAN) first, inline later. Sensor sits LAN-side of the RT-BE88U (WireGuard encrypts at the router, which can't mirror).
- CRS309 ports, as cabled (audit 2026-10-29, [docs/network-map.md](docs/network-map.md)): ether1 OOB switch mgmt (laptop only), SFP+1 uplink to RT-BE88U, SFP+2 Johnny `eno3`, SFP+3 bedroom drop (unmanaged switch), SFP+4 rock-box (Ubuntu workstation), SFP+5 Framework, SFP+6 vPro/AMT `eno4` OOB (isolated to SFP+4, never quarantinable), SFP+7 E810 DAC to `eno1np0` (mirror target), SFP+8 E810 DAC (disabled, Johnny end out). The 2026-10-20 port plan was superseded by the physical layout.
- Stack fits 32 GB: Suricata + Zeek + own daemon + ClickHouse or Postgres/Timescale. No Elastic/OpenSearch. On-box SLM not yet budgeted.
- On-box SLM: yes (AJ, 2026-10-31; replaces "No LLM on the box", whose 2026-10-20 planning source isn't in the repo). AJ decision 2026-11-14: the AI only tightens or suggests; loosening only via AJ-signed rules ([docs/architecture/architecture-rev2.md](docs/architecture/architecture-rev2.md)). This replaces "full function for now" (AJ, 2026-10-31). LLM triage over the LAN to the MAX: unchanged.
- Logs on their own LVM volume. TLC NVMe only when full PCAP starts.
- Devices keyed by MAC/IP; quarantine by MAC ACL/VLAN, not port shutdown.
- Open: Wi-Fi clients are invisible unless an AP hangs off the CRS309.

## Layout
- `docs/os-handoff.md`: current state, config changes, gaps, next steps, SBOM. Revision number in its header.
- `docs/sessions/`: per-session CSV logs (who ran what, result).
- `docs/agent-team.md`: agent roster, skills, file ownership (agreed by AJ and Grok).
- `.claude/agents/`: one file per agent (Claude Code subagents). The main session is the Brain.
- `.claude/skills/`: skill procedures, each owned by the agent that holds it (first: `cis-audit`, Governance).
- `docs/cis-26.04-l1-results.csv`: CIS Ubuntu 26.04 1.0.0 Level 1 – Server audit results (rule, result, evidence). Benchmark PDF and audit scripts stay local (gitignored).
- `etc/`: copies of Johnny's live config files, mirroring their real paths.

## Legal
Anyone else on this network gets captured. Lab default: metadata first, header-only snaplen, short retention.
