# strix-halo-johnny

Johnny: defensive network-security platform (monitoring, threat detection, response). First deployment is a 24/7 sensor watching the home LAN. AJ designs, Claude builds.

## Hardware
| Item | Detail |
|---|---|
| Sensor | Minisforum MS-02 Ultra: Core Ultra 9 285HX, 1× 32GB DDR5 non-ECC (single channel, 4800), Crucial P310 1TB |
| Capture NIC | Intel E810-XXV dual 25G SFP28 on riser, PCIe 4.0 x16 slot (runs Gen4 x4) |
| Onboard | RTL8127 (`eno3`, host mgmt); I226-LM 2.5G (`eno4`, AMT only); vPro/AMT activated (ACM, TLS-only) |
| Switch | MikroTik CRS309-1G-8S+IN on SwOS, hardware port mirror (SPAN) |
| Optics | 4× 1G SFP-to-RJ45, 2× 3m passive 10G DAC |

Host `johnny`, 192.168.50.152 (DHCP on `eno3`; .151 reservation pending), Ubuntu Server 26.04.1. Access: `ssh aj@192.168.50.152` (key only).

## Sequence
1. L1 lab: done
2. **OS: in progress.** Boot, firmware and TPM are done; tool install and capture config are next. State: [docs/os-handoff.md](docs/os-handoff.md)
3. Overseer review
4. Module 1: eBPF fast path

## Design decisions (from planning, 2026-10-20)
- Passive (SPAN) first, inline later. Sensor sits LAN-side of the RT-BE88U (WireGuard encrypts at the router, which can't mirror).
- CRS309 ports, as cabled (audit 2026-10-29, [docs/network-map.md](docs/network-map.md)): ether1 OOB switch mgmt (laptop only), SFP+1 uplink to RT-BE88U, SFP+2 Johnny `eno3`, SFP+3 free, SFP+4 rock-box (Ubuntu workstation), SFP+5 Framework, SFP+6–8 free. Still to place: vPro/AMT `eno4` OOB (isolated to SFP+4, never quarantinable) and the E810 mirror target (DAC).
- Stack fits 32 GB: Suricata + Zeek + own daemon + ClickHouse or Postgres/Timescale. No Elastic/OpenSearch.
- No LLM on the box. Johnny keeps deterministic detection; LLM triage goes over the LAN to the MAX.
- Logs on their own LVM volume. TLC NVMe only when full PCAP starts.
- Devices keyed by MAC/IP; quarantine by MAC ACL/VLAN, not port shutdown.
- Open: Wi-Fi clients are invisible unless an AP hangs off the CRS309.

## Layout
- `docs/os-handoff.md`: current state, config changes, gaps, next steps, SBOM. Revision number in its header.
- `docs/sessions/`: per-session CSV logs (who ran what, result).
- `etc/`: copies of Johnny's live config files, mirroring their real paths.

## Legal
Anyone else on this network gets captured. Lab default: metadata first, header-only snaplen, short retention.
