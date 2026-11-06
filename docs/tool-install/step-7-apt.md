# Step 7 — tool install (2026-11-04)

AJ chose **C**: core tools + Suricata, dumpcap usable by `aj` (wireshark group).

Zeek is **not** in Ubuntu 26.04 apt (only `zkg`). Skip for now.

Already on Johnny: `tcpdump`, `mtr-tiny`, `ethtool`, `bind9-dnsutils`, `bpftool`, `bpftrace`.

## Paste on Johnny (SSH, your sudo password)

One recoverable block. Does not enable Suricata as an IDS; packages only.

```bash
export DEBIAN_FRONTEND=noninteractive
sudo -v

# Allow non-root capture via dumpcap + wireshark group
echo 'wireshark-common wireshark-common/install-setuid boolean true' | sudo debconf-set-selections

sudo apt-get install -y --no-install-recommends \
  tshark wireshark-common \
  nmap masscan \
  iperf3 hping3 tcpreplay netsniff-ng \
  bpfcc-tools stress-ng \
  suricata

sudo usermod -aG wireshark aj

# Record versions for SBOM
dpkg-query -W -f='${Package}\t${Version}\n' \
  tshark wireshark-common tcpdump suricata nmap masscan iperf3 hping3 \
  tcpreplay netsniff-ng bpftrace bpftool bpfcc-tools mtr-tiny ethtool \
  bind9-dnsutils stress-ng | tee ~/cis-audit/step-7-versions.txt

echo STEP7-APT-DONE
echo "Log out/in (or newgrp wireshark) before non-root tshark/dumpcap."
```

## After install (rock-box)

```bash
scp aj@192.168.50.152:~/cis-audit/step-7-versions.txt /tmp/
# then: verify dumpcap cap, update docs/os-handoff.md SBOM, commit
```

## Verify on Johnny (after re-login)

```bash
groups | grep -q wireshark && echo WIRESHARK-GROUP-OK
getcap $(command -v dumpcap)
tshark -D | head
suricata --build-info | head -5
nmap --version | head -1
```

## Applied (2026-11-04 ~23:12 CT)

`STEP7-APT-DONE`. iperf3 daemon left **disabled**. `aj` is in group `wireshark` (108). `dumpcap` has `cap_net_admin,cap_net_raw=eip`.

Suricata package installed but the unit came up **enabled** and **failed** (no capture config yet). Disable it until E810/capture setup (this was the instruction at install time; **now disabled and inactive, see Re-verified below**; who ran it is not recorded):

```bash
sudo systemctl disable --now suricata
```

Versions:

| Package | Version |
|---|---|
| `bind9-dnsutils` | 1:9.20.24-1ubuntu0.4 (install-time; now `.0.5`, see Re-verified) |
| `bpfcc-tools` | 0.35.0+ds-1ubuntu2 |
| `bpftool` | 7.7.0+7.0.0-42.42 |
| `bpftrace` | 0.25.0-1ubuntu1 |
| `ethtool` | 1:6.19-1 |
| `hping3` | 3.a2.ds2-10.1build1 |
| `iperf3` | 3.20-2 |
| `masscan` | 2:1.3.2+ds1-2build1 |
| `mtr-tiny` | 0.95-1.1ubuntu2 |
| `netsniff-ng` | 0.6.9-2 |
| `nmap` | 7.98+dfsg-1 |
| `stress-ng` | 0.20.01-1 |
| `suricata` | 1:8.0.3-1 |
| `tcpdump` | 4.99.6-1 |
| `tcpreplay` | 4.5.2-1build1 |
| `tshark` | 4.6.4-1 |
| `wireshark-common` | 4.6.4-1 |

## Re-verified (2026-11-06 ~02:03Z, read-only SSH as `aj`; token `STEP7-VERIFY-DONE`)

No sudo, apt, or config change. Commands: `dpkg-query -W` on the 17 packages above, `id -nG aj`, `getent group wireshark`, `getcap` and a `security.capability` xattr read on `/usr/bin/dumpcap`, `systemctl show` for `suricata` and `iperf3`, `apt-mark showhold`, `apt list --upgradable`, and `/var/log/dpkg.log*` / `unattended-upgrades.log`.

| Check | Result |
|---|---|
| Versions vs table above | 16 of 17 identical. **Drift:** `bind9-dnsutils` is `1:9.20.24-1ubuntu0.5` (upgraded `2026-11-05 06:48:18` UTC with `bind9-host` and `bind9-libs`; same run also upgraded `libmspack0t64` and `libpcre2-8-0`; `unattended-upgrades.log` names the run). All 17 are `ii` |
| `aj` in `wireshark` | yes, `wireshark:x:108:aj`; the live session shows the group |
| `dumpcap` | `cap_net_admin,cap_net_raw=eip`, mode `-rwxr-xr--` `root:wireshark`; owned by `wireshark-common`. The `+` in `ls -l` is the capability xattr (the only xattr; no ACL). `getfacl` is not installed, so this was read with `os.getxattr` |
| `suricata` | `UnitFileState=disabled`, `ActiveState=inactive`, `SubState=dead`, `Result=success`. Not enabled by this check. The live state is verified; **who ran `systemctl disable --now suricata`, and when, is not recorded** (the Applied section only lists it as the instruction) |
| `iperf3` | `UnitFileState=disabled`, `ActiveState=inactive` |
| Holds | `secureboot-db`, `shim-signed` (unchanged) |
| Pending upgrades for these packages | none listed. **[Assumption]** from the cached apt lists; `apt update` was not run by this check. The lists are about a day old: sampled list files carry server timestamps 2026-11-04 19:59Z to 2026-11-05 05:11Z, and `/var/lib/apt/periodic/update-success-stamp` is 2026-11-05 06:48:26Z. Not re-checked after the unattended run |

`tshark -D`, `suricata --build-info`, and `nmap --version` from the Verify block above were not re-run. Package versions and `dumpcap` caps are the evidence. `apt list --upgradable` output was not captured; the "none listed" row is an assumption, not a saved result.
