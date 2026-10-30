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
| SFP+7 | no link | **10G DAC** OEM `SFP-H10GB-CU3M` | none | E810 (Johnny end unplugged) | yes | none |
| SFP+8 | no link | **10G DAC** OEM `SFP-H10GB-CU3M` | none | E810 (Johnny end unplugged) | yes | none |

**DAC gate:** both DACs' switch ends sit in SFP+7/8, which are default-`bridge` ports. Their Johnny ends stay out until both ports are out of `bridge` (L1-2; the old note named only SFP+7). Johnny cage map (facing back): left = `eno1np0`, right = `eno2np1`.

## CRS309 config (from `/export terse`)
- CRS309-1G-8S+ r3, serial HMP0B0AZEKG, RouterOS 7.23.8 (long-term channel), routerboard firmware 7.23.8 (current = upgrade).
- **Management:** ether1 only. 192.168.88.1/24 on ether1, not bridged. SSH + Winbox allowed from 192.168.88.0/24 only; www, api, api-ssl, telnet, ftp, reverse-proxy disabled; MAC server/MAC-Winbox and neighbor discovery on `MGMT` only. (Matches the rock-box probe: 22/8291 accept then drop, 80/443 closed, no MNDP.)
- **LAN address:** DHCP client on `bridge` (comment "L1-2 uplink via ASUS") → 192.168.50.221. `ip-forward=no`. Pingable from the LAN, not manageable from it.
- **Bridge:** one default `bridge`, all 8 SFP+ ports (`defconf`), hardware offloaded (host flags E). No VLAN filtering, **no port mirror** yet.
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

**AMT subnet (separate L3, same switch):** 192.168.51.0/24. AMT = 192.168.51.10 (static, on `eno4`). rock-box needs 192.168.51.2/24 on `enp11s0` to reach it (not yet configured).

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

Mirror target port for E810 capture: TBD (L1-2).
