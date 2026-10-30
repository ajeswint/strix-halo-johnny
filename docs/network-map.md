# Johnny network map

Audited 2026-10-29 ~19:45 CT. Sources: CRS309 `/interface bridge host print`, `/interface ethernet monitor`, `/export terse` (pasted by AJ from the laptop on ether1); LAN ping sweep + ARP + IEEE OUI lookup from rock-box. **Physical cabling is the truth; docs follow it.**

## CRS309 ports (as cabled)
| Port | Link | Module | Learned MAC(s) | Device | In `bridge` |
|---|---|---|---|---|---|
| ether1 | up, 1G | built-in RJ45 | n/a (not bridged) | AJ's laptop: **OOB switch mgmt**, 192.168.88.1/24 | no (list `MGMT`) |
| SFP+1 | up, 1G | OEM `SFP-GE-T` (SFP-to-RJ45) | `A0:AD:9F:6B:E9:D0` + 7 LAN clients | **Uplink to RT-BE88U** (everything behind the router learned here) | yes |
| SFP+2 | up (inferred) | not yet read | `38:05:25:3A:A3:71` | **Johnny `eno3`** (RTL8127, host mgmt) | yes |
| SFP+3 | none (inferred) | not yet read | none | free | yes |
| SFP+4 | up (inferred) | not yet read | `9C:6B:00:D0:49:29` | **rock-box** | yes |
| SFP+5 | up (inferred) | not yet read | `9C:BF:0D:01:F9:5C` | **Framework** laptop (192.168.50.188) | yes |
| SFP+6 | none (inferred) | not yet read | none | free | yes |
| SFP+7 | none (inferred) | not yet read | none | free; L1-2 says remove from `bridge` before DACs | yes |
| SFP+8 | none (inferred) | not yet read | none | free | yes |

"Inferred" = from the bridge host table (a port with link gets a local `D0:EA:11:DF:35:1x` entry; SFP+3/6/7/8 have none). Module column for SFP+2..8 pending: monitor output was cut off at terminal width.

Johnny `eno4` (I226/AMT, `38:05:25:3a:a3:70`): **unplugged.** Port: TBD (AJ). Must forward only to SFP+4 (rock-box).

## CRS309 config (from `/export terse`)
- CRS309-1G-8S+ r3, serial HMP0B0AZEKG, RouterOS 7.23.8 (long-term channel), routerboard firmware 7.23.8 (current = upgrade).
- **Management:** ether1 only. 192.168.88.1/24 on ether1, not bridged. SSH + Winbox allowed from 192.168.88.0/24 only; www, api, api-ssl, telnet, ftp, reverse-proxy disabled; MAC server/MAC-Winbox and neighbor discovery on `MGMT` only. (Matches rock-box probe: 22/8291 accept then drop, 80/443 closed, no MNDP.)
- **LAN address:** DHCP client on `bridge` (comment "L1-2 uplink via ASUS") → 192.168.50.221. `ip-forward=no`. Pingable from the LAN, not manageable from it.
- **Bridge:** one default `bridge`, all 8 SFP+ ports (`defconf`). No VLAN filtering, no port isolation, **no port mirror** configured yet.
- **L1-2 not done:** `sfp-sfpplus7` still in `bridge`. DAC gate stays closed.
- NTP client → time.cloudflare.com, TZ America/Chicago. Boot setup key = Delete.
- IPv6: default ND entry only; rock-box gets no IPv6 route from it (checked).

## LAN hosts (192.168.50.0/24, ping sweep + ARP)
| IP | MAC | OUI vendor | Switch port | Likely device |
|---|---|---|---|---|
| .1 | a0:ad:9f:6b:e9:d0 | ASUSTek | SFP+1 | RT-BE88U router |
| .7 | fc:6d:77:b1:b9:35 | Intel | SFP+1 (behind router) | unknown PC/NIC |
| .92 | a8:b5:7c:4d:6f:d5 | Roku | SFP+1 (behind router) | Roku |
| .104 | 1a:b7:b1:20:9a:18 | randomized | SFP+1 (behind router) | phone/tablet |
| .133 | d4:ad:fc:96:3e:5d | Shenzhen Intellirocks | SFP+1 (behind router) | smart-home device (likely Govee) |
| .152 | 38:05:25:3a:a3:71 | IEEE RA (Minisforum) | SFP+2 | Johnny `eno3` |
| .184 | 64:db:a0:f6:2d:08 | Select Comfort | SFP+1 (behind router) | Sleep Number bed |
| .188 | 9c:bf:0d:01:f9:5c | Framework | SFP+5 | Framework laptop |
| .193 | 30:d1:6b:0e:d7:3a | Liteon | SFP+1 (behind router) | unknown (Wi-Fi card) |
| .221 | d0:ea:11:df:35:18 | Routerboard.com | (switch itself) | CRS309 |
| .223 | 9c:6b:00:d0:49:29 | ASRock | SFP+4 | rock-box |
| .233 | 84:a9:3e:cc:bf:43 | Hewlett Packard | SFP+1 (behind router) | HP (likely printer) |

No unknown MACs on the switch: every learned MAC maps to a host above.

## Plan vs. physical (2026-10-20 plan)
| Plan | Physical | Note |
|---|---|---|
| SFP+1 router 10G DAC | SFP+1 router, 1G RJ45 module | Role matches. LAN is 1G by design. |
| SFP+2 E810 mirror target (DAC) | Johnny `eno3` | Mirror target port: TBD. |
| SFP+3 Johnny mgmt | free | |
| SFP+4 vPro OOB | rock-box | |
| SFP+5 rock-box | Framework | |
| SFP+6 Framework/MAX | free | |
| ether1 spare | OOB switch mgmt (laptop) | |

Pattern (inference): Johnny, rock-box, and Framework are each one cage lower than planned, as if ether1 had been counted as port 1.

## Other doc drift found
- Johnny's mgmt IP is **192.168.50.152** (RTL8127 DHCP lease), not .151. `AGENTS.md`, `README.md`, and `docs/os-handoff.md` still say .151 until the router reservation (.151 → `38:05:25:3a:a3:71`) is made.
