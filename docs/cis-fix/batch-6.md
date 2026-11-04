# CIS L1 fix pass, Batch 6: firewall

**Status:** DRAFT rev 5 (Grok, 2026-11-04 16:45 CT). The fences are unchanged. Paste 1 is the fence Claude approved at `904f24b`. Paste 2 is the fence Claude approved at `f519e8b`. Neither has landed. Paste 2 waits on `OK-paste-1` and on AJ's go.

**Rules in scope (5):** 4.1.2 ufw service active with rules, 4.1.3 incoming default, 4.1.5 routed default, then 3.3.1.16 and 3.3.1.17 `log_martians`.

**Not in this batch:** 4.1.1 is already PASS. 4.1.4 outgoing deny is Level 2. IPv6 disable is Batch 7. SSH daemon settings are Batch 8. No `ufw enable` is in Paste 1.

## Decisions (AJ, 2026-11-04)

AJ said "go with recs, if feasible."

1. **SSH source.** (a) TCP 22 from `192.168.50.0/24` in on `eno3`. Feasible. The hosts that SSH to Johnny are in that subnet: laptop Wi-Fi `192.168.50.7`, Framework `192.168.50.188`, rock-box `192.168.50.223` (`docs/network-map.md`). A read at 16:31 CT showed one established peer, `192.168.50.223`. Switch management on ether1 is `192.168.88.0/24` and is not host SSH. AMT is `192.168.51.0/24` and is not host SSH.
2. **Incoming policy.** (a) Keep `DEFAULT_INPUT_POLICY="DROP"`. Feasible. That line is already in `/etc/default/ufw`. Paste 2 does not change it. ufw prints DROP as deny ([ufw(8), resolute](https://manpages.ubuntu.com/manpages/resolute/man8/ufw.8.html)).

Paste 1's go is the fence below. It matches `904f24b`. This revision does not change it. Paste 2 waits on Claude's review.

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

`/etc/ufw/sysctl.conf` is a `ufw` conffile. Read-only at 2026-11-04 16:12 CT: `dpkg-query -W -f='${Conffiles}\n' ufw | grep sysctl` printed ` /etc/ufw/sysctl.conf 7723079fc108eda8f57eddab3079c70a`, and `md5sum` of the live file printed the same hash. Paste 1 makes it a modified conffile. GR3 already watches conffile prompts. The johnny file is not a package conffile.

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
last=$(tail -c 1 /etc/sysctl.d/60-johnny-cis-network.conf | od -An -tu1 | tr -d '[:space:]')
if [ "$last" != 10 ]; then
  echo STOP-johnny-no-newline
  exit 1
fi
cp -a /etc/ufw/sysctl.conf /root/ufw.sysctl.conf.pre-batch6
cp -a /etc/sysctl.d/60-johnny-cis-network.conf /root/60-johnny-cis-network.conf.pre-batch6
echo COPIES-MADE
sed -i 's|^net/ipv4/conf/all/log_martians=0$|# net/ipv4/conf/all/log_martians=0|' /etc/ufw/sysctl.conf
sed -i 's|^net/ipv4/conf/default/log_martians=0$|# net/ipv4/conf/default/log_martians=0|' /etc/ufw/sysctl.conf
if grep -Eq '^[[:space:]]*([^#[:space:]].*)?log_martians' /etc/ufw/sysctl.conf; then
  diff -u /root/ufw.sysctl.conf.pre-batch6 /etc/ufw/sysctl.conf || true
  echo STOP-ufw-sysctl-active
  exit 1
fi
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
sha256sum /etc/ufw/sysctl.conf /etc/sysctl.d/60-johnny-cis-network.conf
echo OK-paste-1
EOF
```

`$(tail -c 1)` would drop a trailing newline, so the newline check reads that byte with `od`. `10` is the newline. `diff` exits 1 when the files differ, so the stop path uses `|| true`.

| Line | Meaning | What AJ does |
|---|---|---|
| `STOP-ufw-already-enabled` | `ENABLED` is not `no`. | Stop. No `COPIES-MADE`. |
| `STOP-ufw-sysctl-all` or `STOP-ufw-sysctl-default` | The live `log_martians=0` line is not the expected text. | Stop. No `COPIES-MADE`. |
| `STOP-johnny-log-martians-present` | The johnny file already has one of the keys. | Stop. No `COPIES-MADE`. Tell the Brain. |
| `STOP-johnny-no-newline` | The johnny file does not end in a newline. | Stop. No `COPIES-MADE`. Tell the Brain. |
| `COPIES-MADE` | Both backups exist. Edits start after this line. | If `OK-paste-1` is missing, rollback below. |
| `STOP-ufw-sysctl-active` | An uncommented `log_martians` line remains. The `diff` is above this line. | Stop. Rollback below. |
| `STOP-ufw-sysctl-comment` | A comment did not land. `COPIES-MADE` already printed. | Stop. Rollback below. |
| `STOP-sysctl-apply` | `sysctl -p` failed. `COPIES-MADE` already printed. | Stop. Rollback below. |
| `STOP-log-martians-running` | A running value is not 1. `COPIES-MADE` already printed. | Stop. Rollback below. |
| `STOP-ufw-enabled` | `ENABLED` changed during the script. | Stop. Rollback below. Tell the Brain. Do not continue. |
| `OK-paste-1` | Both running values are 1, ufw is still not enabled, and the two `sha256sum` lines are above this line. | Send the output. Do not start Paste 2. |

The 2026-11-05 05:00 UTC AIDE run may also list `/etc/ufw/sysctl.conf`, `/etc/sysctl.d/60-johnny-cis-network.conf`, `/root/ufw.sysctl.conf.pre-batch6`, and `/root/60-johnny-cis-network.conf.pre-batch6` if Paste 1 has run by then. It should not list the deleted initrd copy. Do not promote `aide.db.new`.

After `OK-paste-1`, Grok reads this with no sudo. `aj` is in group `adm`. A count of `0` is the quiet result. Any other count is a note for Paste 2, not a reason to roll Paste 1 back. Do not start Paste 2.

```bash
journalctl -k -b --since "-5 min" --no-pager | grep -c martian
```

Read-only at 2026-11-04 16:48 CT, before Paste 1 landed. `ENABLED=no`. `/etc/ufw/sysctl.conf` lines 29 and 30 were still `log_martians=0`. The johnny file still ended at `route_localnet = 0`, sha256 `e51dc93631673b952667ef5dc5fe34403cd33192ab4498825c24396b152d71e9`. Running values were `0` and `0`. `/etc/ufw/sysctl.conf` sha256 was `df05de02ea325b3c6d0d22c06c3dc7ebaf3a4e06e41fb98a0671b430b7da5b7f`. The martian command printed `0`. That `0` is the baseline from before the paste. It is not the count after `OK-paste-1`. No rollback. The `sed` had not run. If a paste stopped before the edit, a rerun copies the same bytes over any backup it already made. Ask AJ for any Paste 1 output before that rerun. No mirror commit until `OK-paste-1`.

After `OK-paste-1`, one commit does the mirrors and the Config rows. Not before. Grok reads both live files with no sudo and writes `etc/ufw/sysctl.conf` and `etc/sysctl.d/60-johnny-cis-network.conf`. The Config rows in `docs/os-handoff.md` use the paste's two `sha256sum` lines. The ufw row says modified conffile. The johnny row does not. The `/root` backups stay out of `etc/`.

Rollback when the paste printed `COPIES-MADE` and did not print `OK-paste-1`. Not part of the paste. A later run that stops with no `COPIES-MADE` does not change that: roll back the run that printed `COPIES-MADE` before running Paste 1 again.

```bash
sudo cp -a /root/ufw.sysctl.conf.pre-batch6 /etc/ufw/sysctl.conf
sudo cp -a /root/60-johnny-cis-network.conf.pre-batch6 /etc/sysctl.d/60-johnny-cis-network.conf
sudo sysctl -w net.ipv4.conf.all.log_martians=0
sudo sysctl -w net.ipv4.conf.default.log_martians=0
```

## Paste 2

Not run. Claude on `35f0697` approved the rev 4 fence with changes. This is rev 5. It waits until Paste 1 has printed `OK-paste-1`. It is not a go until Claude reviews this fence.

Before this paste: two SSH sessions from `192.168.50.0/24` are already established, and one of them is AJ's interactive shell. AMT KVM is open, and the LUKS passphrase is at hand. The script stops unless those two sessions are already connected. It cannot see which one is the interactive shell. That is AJ's to have open before the paste. Enabling ufw flushes its chains and can drop the session that runs it. The man page says to add the SSH rule first, and that `ufw enable` prompts over SSH, so the script uses `ufw --force enable` ([ufw(8), resolute](https://manpages.ubuntu.com/manpages/resolute/man8/ufw.8.html)). The same page's sample `ufw allow in on eth0 from 192.168.0.0/16` is one IPv4 rule. A generic `ufw allow 22/tcp` is the example that applies to IPv4 and IPv6. This rule names an IPv4 source, so it does not allow `[::]:22`. `IPV6=yes` stays. Incoming DROP then blocks new IPv6 SSH. Batch 7 is the IPv6 disable. This paste does not set `IPV6=no`.

After `OK-paste-2`, a new SSH login from a host in `192.168.50.0/24` has to reach a shell before anything else. If that login fails, from the session that was already open or from the KVM console:

```bash
sudo ufw disable
```

One block. `sudo -v` is the first line. A paste that does not print `OK-paste-2` is a stop.

```bash
sudo -v
sudo bash <<'EOF'
set -euo pipefail
if ! grep -qx 'ENABLED=no' /etc/ufw/ufw.conf; then
  echo STOP-ufw-already-enabled
  exit 1
fi
if ! grep -qx 'DEFAULT_INPUT_POLICY="DROP"' /etc/default/ufw; then
  echo STOP-input-policy
  exit 1
fi
if ! grep -qx 'DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
  echo STOP-forward-policy
  exit 1
fi
if grep -Eq '^[[:space:]]*([^#[:space:]].*)?log_martians' /etc/ufw/sysctl.conf; then
  echo STOP-ufw-sysctl-active
  exit 1
fi
a=$(sysctl -n net.ipv4.conf.all.log_martians)
d=$(sysctl -n net.ipv4.conf.default.log_martians)
if [ "$a" != 1 ] || [ "$d" != 1 ]; then
  echo STOP-log-martians-before
  exit 1
fi
if ! grep -qx -- '-A ufw-before-input -p udp --sport 67 --dport 68 -j ACCEPT' /etc/ufw/before.rules; then
  echo STOP-dhcp
  exit 1
fi
if ip -4 addr show dev eno1np0 | grep 'inet ' >/dev/null; then
  echo STOP-eno1np0-addr
  exit 1
fi
n=0
while read -r peer; do
  [ -n "$peer" ] || continue
  ip=${peer%:*}
  case "$ip" in
    192.168.50.*)
      n=$((n+1))
      echo "SSH-PEER $ip"
      ;;
    *)
      echo "STOP-ssh-peer $ip"
      exit 1
      ;;
  esac
done < <(ss -Htn state established '( sport = :22 )' | awk '{print $4}')
if [ "$n" -lt 2 ]; then
  echo STOP-ssh-peers-$n
  exit 1
fi
ufw allow in on eno3 from 192.168.50.0/24 to any port 22 proto tcp
echo RULE-ADDED
if ! ufw show added | grep -Fx 'ufw allow in on eno3 from 192.168.50.0/24 to any port 22 proto tcp' >/dev/null; then
  ufw show added || true
  echo STOP-ssh-rule
  exit 1
fi
ufw --force enable
if ! ufw status | grep -x 'Status: active' >/dev/null; then
  ufw disable
  echo STOP-ufw-not-active
  exit 1
fi
rule_line=$(ufw status | grep -F '192.168.50.0/24' || true)
if [[ "$rule_line" != *eno3* || "$rule_line" != *22* ]]; then
  ufw disable
  echo STOP-ssh-rule-missing
  exit 1
fi
v6=$(ufw status verbose | grep -F '(v6)' || true)
case "$v6" in
  *22*)
    ufw disable
    echo STOP-ipv6-ssh-allow
    exit 1
    ;;
esac
a=$(sysctl -n net.ipv4.conf.all.log_martians)
d=$(sysctl -n net.ipv4.conf.default.log_martians)
if [ "$a" != 1 ] || [ "$d" != 1 ]; then
  ufw disable
  echo STOP-log-martians-after-enable
  exit 1
fi
ip -br link show eno1np0
ip -br addr show eno1np0
ufw status verbose
echo BEGIN-user.rules
cat /etc/ufw/user.rules
echo END-user.rules
echo BEGIN-user6.rules
cat /etc/ufw/user6.rules
echo END-user6.rules
if ! sha256sum /etc/ufw/ufw.conf /etc/ufw/user.rules /etc/ufw/user6.rules; then
  ufw disable
  echo STOP-sha256
  exit 1
fi
echo OK-paste-2
EOF
```

| Line | Meaning | What AJ does |
|---|---|---|
| `STOP-ufw-already-enabled` | `ENABLED` is not `no`. | Stop. No rule was added by this run. |
| `STOP-input-policy` or `STOP-forward-policy` | A saved default is not DROP. | Stop. No rule was added. |
| `STOP-ufw-sysctl-active` or `STOP-log-martians-before` | Paste 1 is not in effect. | Stop. No rule was added. |
| `STOP-dhcp` | The DHCP client accept line is not the stock text. | Stop. No rule was added. Send the output. |
| `STOP-eno1np0-addr` | `eno1np0` has an IPv4 address. | Stop. No rule was added. |
| `STOP-ssh-peer` | An established SSH peer is outside `192.168.50.0/24`. | Stop. No rule was added. |
| `STOP-ssh-peers-N` | Fewer than two established SSH sessions from that subnet. | Open the interactive shell from `192.168.50.0/24` and run the paste again. One of the two peers has to be that shell. |
| `SSH-PEER` | One accepted peer. | Read it. The paste continues. |
| `RULE-ADDED` | The allow command ran. | If `OK-paste-2` is missing, rollback below. |
| `STOP-ssh-rule` | `ufw show added` did not print the expected line. `show added` is above this line. | Stop. Rollback below. |
| `STOP-ufw-not-active` | `ufw --force enable` did not leave status active. `RULE-ADDED` already printed. The script ran `ufw disable`. | Stop. Rollback below deletes the staged rule. |
| `STOP-ssh-rule-missing`, `STOP-ipv6-ssh-allow`, `STOP-log-martians-after-enable`, `STOP-sha256` | Enable ran and a later check failed. The script ran `ufw disable`. | Stop. Rollback below deletes the staged rule. |
| `OK-paste-2` | ufw is active, the IPv4 SSH rule is present, no IPv6 port-22 allow is present, and `log_martians` is still 1. | Send the output. Do the new login before anything else. |

**[Assumption]** `ufw show added` prints the rule as the single line `ufw allow in on eno3 from 192.168.50.0/24 to any port 22 proto tcp`. `get_show_added` in the installed `frontend.py` prints `ufw ` plus the command string. If the formatter uses another word order, the paste stops at `STOP-ssh-rule` before enable and prints `show added`. The piped `grep` checks do not use `-q`. Under `pipefail`, `-q` can take SIGPIPE and look like a failed match.

`/etc/ufw/user.rules` and `/etc/ufw/user6.rules` are mode `0640` in upstream ufw 0.36.2 ([setup.py](https://git.launchpad.net/ufw/plain/setup.py?h=0.36.2), the `0o640` loop that includes both names). `ufw.conf` is not in that loop. The paste prints the two rules files between the `BEGIN` and `END` lines. Grok's SSH login cannot read mode `0640`. The mirror is built from those printed bodies. `ufw.conf` is read directly.

After the new login works, Grok reads this with no sudo, AJ sends 1000 pings from rock-box to the Framework at `192.168.50.188`, and Grok reads the same command again:

```bash
ethtool -S eno1np0 | grep -E '^ +rx_(unicast|dropped)\.nic'
```

```bash
ping -c 1000 -i 0.005 192.168.50.188
```

The ping runs on rock-box. **[Assumption]** `-i 0.005` is how 1000 pings fit the recorded ~5 s. `docs/network-map.md` records the count and the time, not the flags. A rise in `rx_unicast.nic` shows the mirror still reaches the port. It does not show capture after the filter. `eno1np0` is not promiscuous, so kernel `rx_packets` stays flat for mirrored unicast that is not addressed to this NIC (same network-map result, 2026-10-30). A flat `rx_unicast.nic` is a Detection note. It is not by itself a reason to disable ufw.

Governance then re-audits 4.1.2, 4.1.3, 4.1.5, 3.3.1.16, and 3.3.1.17. 4.1.5 stays a manual judge on `DEFAULT_FORWARD_POLICY="DROP"`. The verdicts are Governance's. After those verdicts, one commit mirrors `/etc/ufw/ufw.conf`, `/etc/ufw/user.rules`, and `/etc/ufw/user6.rules` into `etc/` and adds their Config rows. The written files' hashes must equal the paste's `sha256sum` lines. The two rules files come from the printed bodies. That commit is not the Paste 1 mirror commit.

Rollback when the paste printed `RULE-ADDED` and did not print `OK-paste-2`. Not part of the paste. `ufw disable` while already inactive prints a skipping line. That is expected when enable did not happen.

```bash
sudo ufw disable
sudo ufw delete allow in on eno3 from 192.168.50.0/24 to any port 22 proto tcp
```
