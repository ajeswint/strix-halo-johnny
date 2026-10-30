# Johnny switch handoff (2026-10-29, for Claude chat)

Current state: `docs/os-handoff.md` rev 4. Network: `docs/network-map.md`. Same rules: "Johnny", never "Sentinel". Terse, one step at a time, exact commands, AJ enters all passwords, one-line "what this does" per step.

## Settled (do not reopen)
- **Switch management = laptop on ether1 only. rock-box is a normal LAN client.** Do not raise the switch OS again.
- **Physical cabling is the truth.** Docs follow it; don't propose moving cables to fit an old plan.

## Ports (CRS309, verified 2026-10-29)
ether1 laptop (OOB mgmt) · SFP+1 router uplink · SFP+2 Johnny `eno3` · SFP+3 bedroom drop → unmanaged switch · SFP+4 rock-box · SFP+5 Framework · **SFP+6 Johnny `eno4` (AMT)** · SFP+7/8 E810 DACs (Johnny ends out).

## Done
- SFP+3 override removed; SFP+6 → SFP+4 (verified). `eno4` → SFP+6, link up 1000 full, no host IP.

## Then
1. rock-box 192.168.51.2/24 (persistent or on demand) → reach AMT 192.168.51.10:16993.
2. L1-2: SFP+7 and SFP+8 out of `bridge`, mirror config, then DAC Johnny ends.
3. Rest of `docs/os-handoff.md` rev 4 next steps.
