# Johnny handoff → Claude Code on the laptop (2026-10-30)

Repo: `ajeswint/strix-halo-johnny` (head `53dcd6d` or later; `git pull` first). Read `AGENTS.md`, `README.md`, `docs/os-handoff.md` (rev 4), `docs/network-map.md`. Project is "Johnny", never "Sentinel".

## How to work with AJ
- Terse. One step at a time. Exact copy-paste commands, no placeholders. One plain-English line per step saying what it does (AJ is new or rusty on many concepts).
- AJ runs anything needing sudo, passwords, or switch changes. Claude never types or stores passwords. `! cmd` in Claude Code has no TTY, so sudo prompts need a separate terminal.
- **Do not raise the switch OS.** The CRS309 is managed from this laptop on ether1, full stop.
- **Physical cabling is the truth.** Change docs to match; don't propose moving cables to fit an old plan.
- A port with a module but no link is not "free" (SFP+3 turned out to be a wall drop). Only empty cages are free.
- LAN is 1G by design; don't flag link speeds.
- After presenting options, stop and wait.

## Network reach from the laptop (assumption, verify)
On ether1 the laptop reaches only the switch (192.168.88.1; ether1 is not bridged, `ip-forward=no`). Johnny (`ssh aj@192.168.50.152`), rock-box, and GitHub need another path (e.g. laptop Wi-Fi). If none, Johnny-side checks run from rock-box.

## Current state (verified 2026-10-30)
| CRS309 port | Runs to |
|---|---|
| ether1 | this laptop, OOB switch mgmt |
| SFP+1 | RT-BE88U router |
| SFP+2 | Johnny `eno3` (RTL8127), 192.168.50.152 |
| SFP+3 | wall drop → primary bedroom → unmanaged switch |
| SFP+4 | rock-box, 192.168.50.223 + 192.168.51.2 |
| SFP+5 | Framework, 192.168.50.188 |
| SFP+6 | Johnny `eno4` (I226, AMT only) — isolated: forwards only to SFP+4 |
| SFP+7 / SFP+8 | 10G DACs, Johnny ends **out**; both still in default `bridge` |

AMT 192.168.51.10: reachable from rock-box, cert SHA-256 matches record, unreachable from SFP+2 (negative test passed). Johnny: closet, PCR 7 baseline, unattended boot.

## Now: apply L1-2 (design in `docs/network-map.md` § L1-2 design)
**Step 1, switch (AJ pastes in the CRS309 terminal):**
```
/interface bridge port remove [find interface=sfp-sfpplus7]
/interface bridge port remove [find interface=sfp-sfpplus8]
/interface ethernet disable sfp-sfpplus8
/interface ethernet switch port set sfp-sfpplus1 mirror-ingress=yes
/interface ethernet switch port set sfp-sfpplus3 mirror-ingress=yes
/interface ethernet switch port set sfp-sfpplus4 mirror-ingress=yes
/interface ethernet switch port set sfp-sfpplus5 mirror-ingress=yes
/interface ethernet switch set switch1 mirror-source=none mirror-target=sfp-sfpplus7
/export terse
```
What it does: takes both DAC ports out of the LAN bridge, switches SFP+8 off, and copies every frame entering SFP+1/3/4/5 to SFP+7.
Verify in the export: no `bridge port` lines for sfp7/sfp8; sfp8 disabled; four `mirror-ingress=yes`; `mirror-target=sfp-sfpplus7`. Nothing loses connectivity: mgmt is on ether1, and SFP+7/8 have no link today.

**Step 2, physical (AJ):** plug the **SFP+7** DAC's free end into Johnny's **left** E810 cage (`eno1np0`). No link → it's the SFP+8 DAC (disabled): swap. SFP+8's Johnny end stays out.

**Step 3, Claude (read-only, over SSH to Johnny):**
```
ssh -o BatchMode=yes aj@192.168.50.152 'ip -br link show eno1np0; ip -br addr show eno1np0; cat /sys/class/net/eno1np0/speed; ip -s link show eno1np0'
```
Expect: carrier up, 10000 (untested with this DAC), **no addresses**, rx counters climbing on a second run.

## After L1-2
- Record in `docs/network-map.md` (switch config + L1-2 applied), `docs/os-handoff.md` next step 3, and append rows to `docs/sessions/Johnny_Switch_Session_Log_2026-10-29.csv` (same columns). Commit + push.
- Then rev 4 next steps 4+ (router .151 reservation, HDMI dummy, AMT power retest, tool install with pinned SBOM, thermal soak, …).
- Session end: bump `docs/os-handoff.md` revision, add the session CSV.
