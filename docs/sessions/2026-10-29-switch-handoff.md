# Johnny switch handoff (2026-10-29, for Claude chat)

Base: `docs/sessions/2026-10-29-bench-handoff.md` (d9e3294) + `docs/os-handoff.md` rev 3. Same rules: "Johnny", never "Sentinel". Terse, one step at a time, exact commands, AJ enters all passwords, one-line "what this does" per step.

## Found this session (read-only, from rock-box)
- **rock-box**: `enp11s0`, MAC `9c:6b:00:d0:49:29` (ASRock), 192.168.50.223 DHCP. Runs **Ubuntu**. README said "Rocky workstation": fixed to "rock-box (Ubuntu workstation)" (f68f729).
- **CRS309 = 192.168.50.221**, MAC `d0:ea:11:df:35:18` (OUI Routerboard.com). Only MikroTik found by a /24 ping sweep + ARP. CRS309 identity inferred, not confirmed.
- **rock-box is on `sfp-sfpplus4`** (switch hosts table, flags DE, bridge `bridge`). Docs followed the physical setup: **AMT (`eno4`) goes to SFP+5**, isolated to SFP+4. Johnny `eno3` on SFP+3 not yet re-verified.
- **Switch management = laptop on ether1 only. rock-box is a normal LAN client.** Settled by AJ; do not raise the switch OS again.

## In progress
AJ is on the laptop via ether1. rock-box port found (SFP+4). Next: isolate SFP+5.

## Then (in order)
1. Isolate SFP+5 so it forwards only to SFP+4 (rock-box) (AJ makes the change from the laptop).
2. AJ plugs `eno4` (I226/AMT, `38:05:25:3a:a3:70`) → SFP+5.
3. rock-box needs 192.168.51.2/24 to reach AMT 192.168.51.10 (persistent or on demand; rock-box uses NetworkManager via netplan, connection `netplan-enp11s0`).
4. L1-2: `sfp-sfpplus7` out of the default bridge, then DACs. Still no DACs until then.
5. Rest of bench handoff "Next" (router .151 reservation, HDMI dummy, AMT power retest, thermal soak, tools/SBOM).
6. Session end: `docs/os-handoff.md` rev 4 (port rename, AMT, README hardware table still says I226 = mgmt `eno3`), session CSV, commit, push.

## Open questions
- `claude/L1 Handoff.md` (rev 5) holds the L1-2 / `sfp-sfpplus7` details. Not in `~/Documents/claude/` on rock-box or in the repo. Where is it?

