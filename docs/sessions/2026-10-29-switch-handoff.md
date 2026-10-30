# Johnny switch handoff (2026-10-29, for Claude chat)

Base: `docs/sessions/2026-10-29-bench-handoff.md` (d9e3294) + `docs/os-handoff.md` rev 3. Same rules: "Johnny", never "Sentinel". Terse, one step at a time, exact commands, AJ enters all passwords, one-line "what this does" per step.

## Found this session (read-only, from rock-box)
- **rock-box**: `enp11s0`, MAC `9c:6b:00:d0:49:29` (ASRock), 192.168.50.223 DHCP. Runs **Ubuntu**. README said "Rocky workstation": fixed to "rock-box (Ubuntu workstation)" (uncommitted).
- **CRS309 = 192.168.50.221**, MAC `d0:ea:11:df:35:18` (OUI Routerboard.com). Only MikroTik found by a /24 ping sweep + ARP. CRS309 identity inferred, not confirmed.
- **Ports from rock-box:** 22 + 8291 (Winbox) open; 21/23/80/443/8080/8728/8729 closed. SSH accepts TCP, then closes before its banner (likely RouterOS service allowed-address limit; unverified). No MNDP (UDP 5678) heard in 70 s.
- **Inference: the switch runs RouterOS, not SwOS.** No web UI on 80/443; SSH + Winbox are RouterOS-only; `sfp-sfpplus7` is RouterOS naming. README and handoffs say SwOS: confirm, then fix docs.
- AJ manages the switch from a laptop on **ether1**. Chrome-extension reading from rock-box won't work for this.

## In progress
AJ is plugging the laptop into ether1. Step: find rock-box's switch port (expected SFP+5 per README, unverified).
- SwOS: **Hosts** tab → port for `9c:6b:00:d0:49:29`.
- RouterOS: **Bridge → Hosts** → "On Interface", or in a terminal:

```
/interface bridge host print where mac-address=9C:6B:00:D0:49:29
```

## Then (in order)
1. Confirm OS + version (RouterOS: `/system resource print`).
2. Isolate SFP+4 so it forwards only to rock-box's port. Method depends on OS (SwOS: Forwarding tab; RouterOS: not designed yet; research CRS3xx port isolation for that RouterOS version before proposing).
3. AJ plugs `eno4` (I226/AMT, `38:05:25:3a:a3:70`) → SFP+4.
4. rock-box needs 192.168.51.2/24 to reach AMT 192.168.51.10 (persistent or on demand; rock-box uses NetworkManager via netplan, connection `netplan-enp11s0`).
5. L1-2: `sfp-sfpplus7` out of the default bridge, then DACs. Still no DACs until then.
6. Rest of bench handoff "Next" (router .151 reservation, HDMI dummy, AMT power retest, thermal soak, tools/SBOM).
7. Session end: `docs/os-handoff.md` rev 4 (port rename, AMT, switch OS correction, README hardware table still says I226 = mgmt `eno3`), session CSV, commit, push.

## Open questions
- SwOS or RouterOS, and which version?
- `claude/L1 Handoff.md` (rev 5) holds the L1-2 / `sfp-sfpplus7` details. Not in `~/Documents/claude/` on rock-box or in the repo. Where is it?

## Uncommitted in repo
- `README.md:24` Rocky → rock-box fix.
- This file.
