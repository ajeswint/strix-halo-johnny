# CIS L1 fix pass, Batch 6: firewall

**Status:** DRAFT rev 2 (Grok, 2026-11-04 16:04 CT). Nothing in this file has run. `ufw` stays inactive until AJ answers Q1 and Q2 and a later paste is reviewed. Rev 2 adds a stop line when `sysctl -p` fails, checks that the two comments landed, and says when to roll back.

**Rules in scope (5):** 4.1.2 ufw service active with rules, 4.1.3 incoming default, 4.1.5 routed default, then 3.3.1.16 and 3.3.1.17 `log_martians`.

**Not in this batch:** 4.1.1 is already PASS. 4.1.4 outgoing deny is Level 2. IPv6 disable is Batch 7. SSH daemon settings are Batch 8. No `ufw enable` is in Paste 1.

## Decisions still open

1. **SSH source.** (a) Recommended: allow TCP 22 only from `192.168.50.0/24` in on `eno3`. (b) Allow TCP 22 from anywhere. (c) Name one host. The live address is `192.168.50.152/24` on `eno3` only.
2. **Incoming policy.** (a) Recommended: keep `DEFAULT_INPUT_POLICY="DROP"`. ufw prints that as deny ([ufw(8), resolute](https://manpages.ubuntu.com/manpages/resolute/man8/ufw.8.html)). (b) Change incoming to reject.

Paste 2 is not written until those two answers are in. Enabling ufw flushes its chains and can drop the SSH session that runs it. The man page says to add the SSH rule first, and that `ufw enable` prompts when run over SSH. A script would need `ufw --force enable`. Recovery if the new session fails is AMT KVM, then `ufw disable`.

## Live state (read-only SSH, 2026-11-04 21:57 UTC)

`ufw` `0.36.2-9build1` is `ii`. `iptables` `1.8.11-2ubuntu3` is `ii`. `nftables` is `rc` `1.1.6-1` (removed in Batch 2; the kernel `nf_tables` module stays). `ufw.service` is enabled and active. `/etc/ufw/ufw.conf` is `ENABLED=no`. Saved policy in `/etc/default/ufw`: `IPV6=yes`, input DROP, output ACCEPT, forward DROP.

Listeners: TCP 22 on `0.0.0.0` and `[::]`; DNS stub on `127.0.0.53` and `127.0.0.54`; chrony command port `323` on localhost; DHCP client UDP 68 on `192.168.50.152%eno3`. Default route is via `192.168.50.1` on `eno3`.

`eno1np0` is UP with no address. RX at this read: 1874366 bytes, 8352 packets, TX 0. `eno4` is UP with no address. `eno2np1` is DOWN.

`log_martians` is 0 for `all` and `default`. The only matching lines are `/etc/ufw/sysctl.conf` lines 29 and 30:

```
net/ipv4/conf/all/log_martians=0
net/ipv4/conf/default/log_martians=0
```

`/etc/ufw/before.rules` is mode-restricted. This read could not confirm the DHCP line on Johnny. The resolute man page says the stock ruleset accepts DHCP client traffic on INPUT. Paste 2 must `grep` that line as root and stop if it is absent. Upstream stock text is `-A ufw-before-input -p udp --sport 67 --dport 68 -j ACCEPT` (https://git.launchpad.net/ufw/tree/conf/before.rules). **[Assumption]** Johnny's packaged file still has that line. Unverified here.

`ufw` reads `/etc/ufw/sysctl.conf` when it is enabled, and that file overrides the system sysctl settings ([ufw-framework(8), resolute](https://manpages.ubuntu.com/manpages/resolute/man8/ufw-framework.8.html)). Leaving `log_martians=0` active in that file would undo 3.3.1.16 and 3.3.1.17 at enable time. Paste 1 comments those two lines and sets `1` in `60-johnny-cis-network.conf`. It does not enable ufw.

`rp_filter` stays as Batch 4 left it: `all` and `default` are 1, and `eno1np0`, `eno3`, and `eno4` are 2 because `/usr/lib/sysctl.d/50-default.conf` sets `net.ipv4.conf.*.rp_filter = 2`. Effective mode on those NICs is loose. This batch does not change that.

**[Assumption]** Frames on `eno1np0` are not local (no address on that NIC), and AF_PACKET sees them before the filter table. Detection still has to confirm the mirror after Paste 2. This draft does not claim that.

Mirror of the network file before Paste 1: `etc/sysctl.d/60-johnny-cis-network.conf` sha256 `e51dc93631673b952667ef5dc5fe34403cd33192ab4498825c24396b152d71e9`. `/etc/ufw/` is not in `etc/` yet. Paste 1's backups are `/root/ufw.sysctl.conf.pre-batch6` and `/root/60-johnny-cis-network.conf.pre-batch6`.

Re-read at 2026-11-04 16:04 CT, no sudo. Same two `log_martians=0` lines, `ENABLED=no` on line 6, no `log_martians` key in the johnny file, running values `0` and `0`. The johnny file ends with `0` and a newline. All four of `ufw.conf`, `sysctl.conf`, the johnny file, and `/etc/default/ufw` are `644 root:root`. Policies are still input DROP, output ACCEPT, forward DROP, `IPV6=yes`. `ufw.service` is enabled and active.

`sysctl -p` on the johnny file writes `net.ipv4.ip_forward = 0` again. The kernel resets the other IPv4 settings only when that value changes ([ip-sysctl.rst](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/Documentation/networking/ip-sysctl.rst); the handler calls `inet_forward_change` only when `*valp != val`, [devinet.c](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/net/ipv4/devinet.c)). It is already 0. **[Assumption]** `7.0.0-42-generic` still has that comparison. The same `sysctl -p` writes every later key in the file, including the two new lines, so a reset would be put back by this paste. Setting `all.log_martians` to 1 turns the log on for every interface: the interface value is used if either `all` or the interface is 1 (same ip-sysctl page). Effective `rp_filter` stays loose, because the max of `all` 1 and the interface 2 is 2 (same page). **[Assumption]** a mirrored LAN or internet source that has a route via `eno3` is not a loose-mode failure, so this does not flood the kernel log. The read after `OK-paste-1` checks that.

## Paste 1

One block. `sudo -v` is the first line. It comments two lines and appends two keys. It does not run `ufw`. A paste that does not print `OK-paste-1` is a stop.

```bash
sudo -v
sudo bash <<'EOF'
set -euo pipefail
if ! grep -qx 'ENABLED=no' /etc/ufw/ufw.conf; then
  echo STOP-ufw-already-enabled
  exit 1
fi
if ! grep -qx 'net/ipv4/conf/all/log_martians=0' /etc/ufw/sysctl.conf; then
  echo STOP-ufw-sysctl-all
  exit 1
fi
if ! grep -qx 'net/ipv4/conf/default/log_martians=0' /etc/ufw/sysctl.conf; then
  echo STOP-ufw-sysctl-default
  exit 1
fi
if grep -q '^net.ipv4.conf.all.log_martians' /etc/sysctl.d/60-johnny-cis-network.conf \
   || grep -q '^net.ipv4.conf.default.log_martians' /etc/sysctl.d/60-johnny-cis-network.conf; then
  echo STOP-johnny-log-martians-present
  exit 1
fi
cp -a /etc/ufw/sysctl.conf /root/ufw.sysctl.conf.pre-batch6
cp -a /etc/sysctl.d/60-johnny-cis-network.conf /root/60-johnny-cis-network.conf.pre-batch6
sed -i 's|^net/ipv4/conf/all/log_martians=0$|# net/ipv4/conf/all/log_martians=0|' /etc/ufw/sysctl.conf
sed -i 's|^net/ipv4/conf/default/log_martians=0$|# net/ipv4/conf/default/log_martians=0|' /etc/ufw/sysctl.conf
if ! grep -qx '# net/ipv4/conf/all/log_martians=0' /etc/ufw/sysctl.conf \
   || ! grep -qx '# net/ipv4/conf/default/log_martians=0' /etc/ufw/sysctl.conf; then
  echo STOP-ufw-sysctl-comment
  exit 1
fi
printf '%s\n' '# 3.3.1.16 and 3.3.1.17. The matching lines in /etc/ufw/sysctl.conf are commented so ufw enable does not force 0.' 'net.ipv4.conf.all.log_martians = 1' 'net.ipv4.conf.default.log_martians = 1' >> /etc/sysctl.d/60-johnny-cis-network.conf
if ! sysctl -p /etc/sysctl.d/60-johnny-cis-network.conf >/dev/null; then
  echo STOP-sysctl-apply
  exit 1
fi
a=$(sysctl -n net.ipv4.conf.all.log_martians)
d=$(sysctl -n net.ipv4.conf.default.log_martians)
if [ "$a" != 1 ] || [ "$d" != 1 ]; then
  echo STOP-log-martians-running
  exit 1
fi
if ! grep -qx 'ENABLED=no' /etc/ufw/ufw.conf; then
  echo STOP-ufw-enabled
  exit 1
fi
echo OK-paste-1
EOF
```

| Line | Meaning | What AJ does |
|---|---|---|
| `STOP-ufw-already-enabled` | `ENABLED` is not `no`. | Stop. No copy was made. |
| `STOP-ufw-sysctl-all` or `STOP-ufw-sysctl-default` | The live `log_martians=0` line is not the expected text. | Stop. No copy was made. |
| `STOP-johnny-log-martians-present` | The johnny file already has one of the keys. | Stop. No copy was made. Tell the Brain. |
| `STOP-ufw-sysctl-comment` | The copies exist and a comment did not land. | Stop. Rollback below. |
| `STOP-sysctl-apply` | The copies exist and `sysctl -p` failed. | Stop. Rollback below. |
| `STOP-log-martians-running` | The files were edited and a running value is not 1. | Stop. Rollback below. |
| `STOP-ufw-enabled` | `ENABLED` changed during the script. | Stop. Rollback below. Tell the Brain. Do not continue. |
| `OK-paste-1` | Both running values are 1 and ufw is still not enabled. | Send the output. Do not start Paste 2. |

The 2026-11-05 05:00 UTC AIDE run may also list `/etc/ufw/sysctl.conf`, `/etc/sysctl.d/60-johnny-cis-network.conf`, `/root/ufw.sysctl.conf.pre-batch6`, and `/root/60-johnny-cis-network.conf.pre-batch6` if Paste 1 has run by then. It should not list the deleted initrd copy. Do not promote `aide.db.new`.

After `OK-paste-1`, Grok reads this with no sudo. `aj` is in group `adm`. A count of `0` is the quiet result. Any other count is a note for Paste 2, not a reason to roll Paste 1 back. Do not start Paste 2.

```bash
journalctl -k -b --since "-5 min" --no-pager | grep -c martian
```

Rollback when the paste printed `STOP-ufw-sysctl-comment`, `STOP-sysctl-apply`, `STOP-log-martians-running`, or `STOP-ufw-enabled`, or it ended with no `OK-paste-1` after the copies existed. Do not run it for `STOP-ufw-already-enabled`, `STOP-ufw-sysctl-all`, `STOP-ufw-sysctl-default`, or `STOP-johnny-log-martians-present`. Not part of the paste.

```bash
sudo cp -a /root/ufw.sysctl.conf.pre-batch6 /etc/ufw/sysctl.conf
sudo cp -a /root/60-johnny-cis-network.conf.pre-batch6 /etc/sysctl.d/60-johnny-cis-network.conf
sudo sysctl -w net.ipv4.conf.all.log_martians=0
sudo sysctl -w net.ipv4.conf.default.log_martians=0
```

## Paste 2

Not written. It waits on Q1 and Q2. It will be its own paste: confirm the DHCP line, add the SSH allow, then `ufw --force enable`, then a second SSH session must log in before anything else. AMT KVM stays the way back.
