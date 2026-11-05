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

Suricata package installed but the unit came up **enabled** and **failed** (no capture config yet). Disable it until E810/capture setup:

```bash
sudo systemctl disable --now suricata
```

Versions:

| Package | Version |
|---|---|
| `bind9-dnsutils` | 1:9.20.24-1ubuntu0.4 |
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
