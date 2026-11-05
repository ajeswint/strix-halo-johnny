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
