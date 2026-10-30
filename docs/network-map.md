# Johnny network map

Audited 2026-10-29 19:45–20:05 CT. Sources: CRS309 `/interface bridge host print`, `/interface ethernet monitor` loop, `/export terse`, `/interface ethernet switch port-isolation print` (pasted by AJ from the laptop on ether1); LAN ping sweep + ARP + IEEE OUI lookup from rock-box; AJ for where each cable runs. **Physical cabling is the truth; docs follow it.**

## CRS309 ports (as cabled)
| Port | Link | Module | Learned MAC(s) | Runs to | In `bridge` | Isolation |
|---|---|---|---|---|---|---|
| ether1 | up, 1G | built-in RJ45 | n/a (not bridged) | AJ's laptop: **OOB switch mgmt**, switch side 192.168.88.1/24 | no (list `MGMT`) | n/a |
| SFP+1 | up, 1G | OEM `SFP-GE-T` (SFP-to-RJ45) | `A0:AD:9F:6B:E9:D0` + 7 LAN clients | **RT-BE88U router** (everything behind the router is learned here) | yes | none |
| SFP+2 | up, 1G | OEM `SFP-GE-T` | `38:05:25:3A:A3:71` | **Johnny `eno3`** (RTL8127, host mgmt) | yes | none |
| SFP+3 | no link | OEM `SFP-GE-T` | none | **Wall drop → primary bedroom → unmanaged switch** (nothing up on it at audit) | yes | none (mistaken override removed 2026-10-29) |
| SFP+4 | up, 1G | OEM `SFP-GE-T` | `9C:6B:00:D0:49:29` | **rock-box** | yes | none (full LAN) |
| SFP+5 | up, 1G | OEM `SFP-GE-T` | `9C:BF:0D:01:F9:5C` | **Framework** laptop (192.168.50.188) | yes | none |
| SFP+6 | up, 1G (Johnny side: 1000 full, 01:06 UTC) | OEM `SFP-GE-T` | not checked | **Johnny `eno4`** (I226-LM, AMT only, `38:05:25:3a:a3:70`) | yes | **forwards only to SFP+4** (verified) |
| SFP+7 | up, 10G (Johnny side: 10000, 2026-10-30) | **10G DAC** OEM `SFP-H10GB-CU3M` | n/a (mirror target) | **Johnny `eno1np0`** (E810 left cage): **mirror target** | no (removed L1-2) | none |
| SFP+8 | **disabled** | **10G DAC** OEM `SFP-H10GB-CU3M` | none | E810 right cage (Johnny end **out**; reserved for inline) | no (removed L1-2) | none |

**DAC gate (closed 2026-10-30):** SFP+7/8 removed from `bridge` and SFP+8 disabled before the SFP+7 DAC went into Johnny. SFP+8's Johnny end stays out. Johnny cage map (facing back): left = `eno1np0`, right = `eno2np1`.

## CRS309 config (from `/export terse`)
- CRS309-1G-8S+ r3, serial HMP0B0AZEKG, RouterOS 7.23.8 (long-term channel), routerboard firmware 7.23.8 (current = upgrade).
- **Management:** ether1 only. 192.168.88.1/24 on ether1, not bridged. SSH + Winbox allowed from 192.168.88.0/24 only; www, api, api-ssl, telnet, ftp, reverse-proxy disabled; MAC server/MAC-Winbox and neighbor discovery on `MGMT` only. (Matches the rock-box probe: 22/8291 accept then drop, 80/443 closed, no MNDP.)
- **LAN address:** DHCP client on `bridge` (comment "L1-2 uplink via ASUS") → 192.168.50.221. `ip-forward=no`. Pingable from the LAN, not manageable from it.
- **Bridge:** one default `bridge`, SFP+1–6 (`defconf`), hardware offloaded (host flags E). No VLAN filtering. SFP+7/8 removed (L1-2); `sfp-sfpplus8` disabled.
- **Port mirror (L1-2, 2026-10-30):** `mirror-ingress=yes` on SFP+1/3/4/5; `switch1` `mirror-target=sfp-sfpplus7` (check: `:put [/interface ethernet switch get switch1 mirror-target]`; plain `print` doesn't show it).
- **Port isolation:** `/interface ethernet switch port-isolation`, per-port `forwarding-override` (one-way: frames entering the port may leave only via the listed ports). Verified 2026-10-29 with `print`: SFP+6 → SFP+4; every other port, incl. `switch1-cpu`, unset; no invalid flag. Two-way isolation (other ports excluding SFP+6) not applied; effect on `switch1-cpu` / .221 unverified.
- NTP client → time.cloudflare.com, TZ America/Chicago. Boot setup key = Delete.
- IPv6: default ND entry only; rock-box gets no IPv6 route from it (checked).

### Isolation commands (AJ, laptop on ether1)
```
/interface ethernet switch port-isolation unset sfp-sfpplus3 forwarding-override
/interface ethernet switch port-isolation set sfp-sfpplus6 forwarding-override=sfp-sfpplus4
/interface ethernet switch port-isolation print
```
History: 2026-10-29, SFP+3 → SFP+4 was applied and verified, then SFP+3 turned out to be the bedroom drop; moved to SFP+6. `eno4` was cabled ~minutes before the SFP+6 override went in (no host IP on `eno4`; AMT TLS-only).

## LAN hosts (192.168.50.0/24, ping sweep + ARP)
| IP | MAC | OUI vendor | Switch port | Likely device |
|---|---|---|---|---|
| .1 | a0:ad:9f:6b:e9:d0 | ASUSTek | SFP+1 | RT-BE88U router |
| .7 | fc:6d:77:b1:b9:35 | Intel | SFP+1 (behind router) | AJ's laptop (aj-Thin-15-B13VE) `wlo1` Wi-Fi |
| .92 | a8:b5:7c:4d:6f:d5 | Roku | SFP+1 (behind router) | Roku |
| .104 | 1a:b7:b1:20:9a:18 | randomized | SFP+1 (behind router) | Pixel 8 Pro (router reservation name) |
| .133 | d4:ad:fc:96:3e:5d | Shenzhen Intellirocks | SFP+1 (behind router) | smart-home device (likely Govee) |
| .152 | 38:05:25:3a:a3:71 | IEEE RA (Minisforum) | SFP+2 | Johnny `eno3` |
| .184 | 64:db:a0:f6:2d:08 | Select Comfort | SFP+1 (behind router) | Sleep Number bed |
| .188 | 9c:bf:0d:01:f9:5c | Framework | SFP+5 | Framework laptop |
| .193 | 30:d1:6b:0e:d7:3a | Liteon | SFP+1 (behind router) | Hisense Roku TV (router reservation name `60HisenseRokuTV`) |
| .221 | d0:ea:11:df:35:18 | Routerboard.com | (switch itself) | CRS309 |
| .223 | 9c:6b:00:d0:49:29 | ASRock | SFP+4 | rock-box |
| .233 | 84:a9:3e:cc:bf:43 | Hewlett Packard | SFP+1 (behind router) | HP (likely printer) |

No unknown MACs on the switch: every learned MAC maps to a host above.

### Router DHCP (RT-BE88U, LAN → DHCP Server, checked 2026-10-30)
Pool 192.168.50.2–.254, lease 86400 s. **Enable Manual Assignment was No** (listed entries were inactive; rock-box's .223 was a sticky lease). Turned on 2026-10-30 (Claude via Chrome extension, AJ approved Apply); verified on reload. Each entry matched the host's current address, so no host moved. **Apply on this page restarts the router's Wi-Fi** (~40 s: laptop `wlo1` disconnected 20:52:15 CT, `ssid-not-found` 20:52:30, back 20:52:58); Wi-Fi clients, incl. a browser driving the UI, drop.

| Name (router) | MAC | IP |
|---|---|---|
| Pixel-8-Pro | 1A:B7:B1:20:9A:18 | .104 |
| johnny (added) | 38:05:25:3A:A3:71 | .152 |
| 60HisenseRokuTV | 30:D1:6B:0E:D7:3A | .193 |
| "IEEE Registration Authority" | 34:46:63:20:98:D1 | .197 (unknown device; not seen in the sweep) |
| aj-rock-box | 9C:6B:00:D0:49:29 | .223 |

**AMT subnet (separate L3, same switch):** 192.168.51.0/24. AMT = 192.168.51.10 (static, on `eno4`, MAC `38:05:25:3a:a3:70`). rock-box = 192.168.51.2/24 on `enp11s0`, persistent, alongside DHCP .223.

rock-box `/etc/netplan/60-johnny-amt-oob.yaml` (root 600; rock-box file, not mirrored under `etc/`):
```
network:
  version: 2
  ethernets:
    enp11s0:
      addresses:
        - 192.168.51.2/24
```
`netplan get ethernets.enp11s0` after install: MAC match + `dhcp4: true` + `dhcp6: true` + `192.168.51.2/24` (merged). `netplan apply` printed "Failed to connect to network service /run/systemd/netif/io.systemd.Network … hard restart of systemd-networkd" (networkd is not the renderer; now running, manages no links, disabled at boot).

**AMT test from rock-box (2026-10-30 ~01:25 UTC):** ping OK; ARP 192.168.51.10 → `38:05:25:3a:a3:70`. TCP 16993 open, 16995 open, 664 open; 16992, 16994, 623, 5900 closed. TLS cert SHA-256 `8C:D6:65:E9:E5:0C:49:00:65:D3:D9:D3:13:5B:66:97:5C:E3:89:4F:F5:04:48:B0:75:BC:44:5C:47:35:3D:0A` = recorded; Intel AMT self-signed, notAfter 2037-12-31. 

**Negative test (2026-10-30):** temporary 192.168.51.3/24 on Johnny `eno3` (SFP+2): ping 0/3, ARP for 192.168.51.10 INCOMPLETE → FAILED, TCP 16993/16995/664 no answer. One-way isolation holds: AMT's replies cannot leave SFP+6 except to SFP+4. Temp address removed, verified.

## Plan (2026-10-20) vs. physical
| Plan | Physical |
|---|---|
| SFP+1 router 10G DAC | SFP+1 router, 1G `SFP-GE-T` (LAN is 1G by design) |
| SFP+2 E810 mirror target (DAC) | Johnny `eno3` |
| SFP+3 Johnny mgmt | bedroom drop |
| SFP+4 vPro OOB | rock-box |
| SFP+5 rock-box | Framework |
| SFP+6 Framework/MAX | AMT `eno4` |
| (unplanned) | SFP+7/8 E810 DACs |
| ether1 spare | OOB switch mgmt |

Mirror target port for E810 capture: SFP+7 (L1-2, applied 2026-10-30).

## L1-2 design (proposed and applied 2026-10-30, from the physical layout)
Goal: hardware port mirror (SPAN) of the LAN into one E810 port, with both DAC ports out of the default `bridge` so the E810 never joins the LAN.

| Item | Design | Why |
|---|---|---|
| Mirror target | **SFP+7**, standalone (removed from `bridge`) | DAC already in it. A standalone target carries only mirrored copies, never LAN forwarding or floods. |
| SFP+8 | Removed from `bridge` **and disabled** | Second DAC, reserved (inline later). Disabled = can't link even if its Johnny end goes in. Matches "second E810 port admin-down". |
| Mirror sources | **Ingress** on SFP+1 (router), SFP+3 (bedroom), SFP+4 (rock-box), SFP+5 (Framework) | Ingress-only on every LAN-facing port mirrors each frame once, at the port it entered: north-south and east-west, no duplicates. |
| Not mirrored | SFP+2 (Johnny `eno3`), SFP+6 (AMT) | Sensor doesn't mirror its own outbound mgmt; AMT's outbound only goes to rock-box. Their inbound halves are still seen at the sender's ingress (e.g. rock-box → Johnny at SFP+4). |
| Johnny capture port | SFP+7 DAC → **left cage = `eno1np0`** | Netplan already: no addressing, `optional: true`. Capture tuning (promisc, `arp off`, XDP) stays OS next step 11. |
| Bandwidth | ≤ 4 × 1G ingress = 4 Gb/s into a 10G DAC | No oversubscription. |

Not covered: Wi-Fi-to-internet traffic stays inside the RT-BE88U and never crosses the CRS309 (README "Open" item). Capture itself starts only with the tool install; the mirror alone records nothing (README Legal defaults apply then).

E810-XXV link with the 10G passive DAC (`SFP-H10GB-CU3M`): 10000, tested 2026-10-30.

### Switch commands (AJ, laptop on ether1)
```
/interface bridge port remove [find interface=sfp-sfpplus7]
/interface bridge port remove [find interface=sfp-sfpplus8]
/interface ethernet disable sfp-sfpplus8
/interface ethernet switch port set sfp-sfpplus1 mirror-ingress=yes
/interface ethernet switch port set sfp-sfpplus3 mirror-ingress=yes
/interface ethernet switch port set sfp-sfpplus4 mirror-ingress=yes
/interface ethernet switch port set sfp-sfpplus5 mirror-ingress=yes
/interface ethernet switch set switch1 mirror-target=sfp-sfpplus7
/export terse
:put [/interface ethernet switch get switch1 mirror-target]
```
Verify in the export: no `bridge port` lines for sfp7/sfp8; sfp8 disabled; four `mirror-ingress=yes`. `mirror-target` isn't in the export or plain `print`; the `:put` prints `sfp-sfpplus7`.

Correction: the design's original last line, `... set switch1 mirror-source=none mirror-target=sfp-sfpplus7`, fails on 7.23.8 (`bad parameter mirror-source`). `mirror-source` is pre-7.15; since 7.15 sources are per-port `mirror-ingress`/`mirror-egress` and the switch menu sets only `mirror-target`.

### Then (physical + Johnny)
1. AJ plugs the **SFP+7** DAC's free end into Johnny's **left** E810 cage. If no link comes up, it's the SFP+8 DAC (disabled): swap.
2. Claude checks over SSH (read-only): `eno1np0` carrier + speed, still no addresses, rx counters climbing.
3. SFP+8 DAC's Johnny end stays out.

**Result (2026-10-30, ~01:40 UTC):** first DAC tried was SFP+7. `eno1np0` UP, LOWER_UP, 10000, no addresses. `ethtool -S` port counters minutes after link: `rx_bytes.nic` 828118, `rx_unicast.nic` 3649, `rx_multicast.nic` 37, `rx_broadcast.nic` 7, `rx_dropped.nic` 0, `tx_bytes.nic` 0. Kernel saw 19 packets: not promisc, so the NIC filters mirrored unicast for other MACs (promisc is OS next step 11). `eno2np1` DOWN, no carrier.

Sources: MikroTik CRS3xx switch chip features, Mirroring (port-based multiple sources since 7.15; target may be standalone): https://help.mikrotik.com/docs/spaces/ROS/pages/30474317/CRS3xx+CRS5xx+CCR2116+CCR2216+switch+chip+features
