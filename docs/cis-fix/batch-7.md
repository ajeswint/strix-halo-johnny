# CIS L1 fix pass, Batch 7: IPv6 disable

**Status:** DRAFT rev 1 (Grok, 2026-11-04). Nothing in this batch has run on Johnny.

**Rules in scope (9):** 3.1.1 IPv6 status matches site policy (AJ, 2026-10-31: no IPv6). 3.3.2.1–3.3.2.8 become N/A once 3.1.1 reports IPv6 is not enabled. The local audit body is `docs/cis-local/cis-3-audit.sh`: "IPv6 is not enabled" if `/sys/module/ipv6/parameters/disable` is not `0`, or if both `net.ipv6.conf.all.disable_ipv6` and `net.ipv6.conf.default.disable_ipv6` are `1`.

**Not in this batch:** `ipv6.disable=1`, GRUB, initrd, and reboot. Wireless (3.1.2, 3.1.3). ufw enable, `IPV6=no`, and any `ufw reload`. SSH daemon settings (Batch 8). Per-NIC capture sysctl on `eno1np0` (step 11).

## Plan

The script AJ runs is [`batch-7.sh`](batch-7.sh). Copy it from the laptop, then run PASTE 1 from SSH. A second SSH session from `192.168.50.0/24` is already open before PASTE 1. PASTE 2 is typed at the KVM console only if PASTE 1 dropped IPv4 SSH. PASTE 2 sets both live `disable_ipv6` keys to `0` before it restores the johnny file from the backup. If that backup is missing it exits `STOP-no-backup` after the live undo.

```bash
# RUNS ON: LAPTOP
# RUNS IN: LAPTOP
scp docs/cis-fix/batch-7.sh aj@192.168.50.152:cis-audit/batch-7.sh
```

```bash
# RUNS ON: JOHNNY (SSH)
# RUNS IN: SSH
# PASTE 1
sudo bash ~/cis-audit/batch-7.sh
```

```bash
# RUNS ON: JOHNNY (KVM)
# RUNS IN: KVM
# PASTE 2
sudo bash ~/cis-audit/batch-7.sh 2
```

**No reboot. No GRUB edit. No `ipv6.disable=1`.** The CIS check passes on the two sysctl keys. Those keys apply immediately with `sysctl -w` and persist in `/etc/sysctl.d/60-johnny-cis-network.conf`, which `systemd-sysctl` reads at the next boot. The kernel cmdline is unchanged, so the initrd is unchanged.

Live read, 2026-11-04, no sudo: kernel `7.0.0-42-generic`. Cmdline has `pcie_aspm=off` and `crashkernel=…` and no `ipv6.disable`. `ss` shows TCP `0.0.0.0:22` and `[::]:22`. `ssh.socket` is `ListenStream=0.0.0.0:22`, `ListenStream=[::]:22`, `BindIPv6Only=ipv6-only`, so the IPv4 listener does not depend on the IPv6 socket. Three established SSH sessions were `192.168.50.152:22` from `192.168.50.223`. `eno3` is `192.168.50.152/24` via DHCP, default route `192.168.50.1`. IPv6 is link-local `fe80::/64` on `eno3` and `::1` on `lo`. No IPv6 default route. `disable_ipv6` is `0` on `all`, `default`, `lo`, `eno1np0`, `eno2np1`, `eno3`, and `eno4`. Other listeners are IPv4, plus chrony UDP `[::1]:323` beside `127.0.0.1:323`. `/etc/ufw/ufw.conf` is `ENABLED=yes` and `/etc/default/ufw` is `IPV6=yes`. This batch does not reload ufw. **[Assumption]** leaving `IPV6=yes` while `disable_ipv6=1` does not drop the existing IPv4 SSH sockets. Unverified until PASTE 1's verify block.

PASTE 1 is idempotent. It prints `STATE`, then:

1. Stops unless `eno3` has `192.168.50.152/24`, the default route is via `eno3`, at least one established SSH peer is in `192.168.50.0/24` on local `192.168.50.152:22`, and `0.0.0.0:22` is listening. Peers come from `ss -H -tn sport = :22` with awk `$1=="ESTAB"` and field 5. A state filter is not used: on this iproute2, `ss -H -tn state established` drops the State column, so the peer would be field 4 and field 5 would be empty. Confirmed on Johnny 2026-11-04: three ESTAB rows, peers `192.168.50.223`. A peer of `192.168.50.152` is `NOTE-ssh-self` and is not counted. Any established SSH peer outside `192.168.50.0/24` is `STOP-ssh-peer`.
2. Stops on an unexpected listener. Allowed: TCP/UDP `127.0.0.53:53` and `127.0.0.54:53`, UDP `192.168.50.152:68`, UDP `127.0.0.1:323`, UDP `[::1]:323`, TCP `0.0.0.0:22`, TCP `[::]:22`. `[::]:22` and `[::1]:323` are allowed only because those IPv4 twins exist. Anything else is `STOP-listener`.
3. Stops if the live netplan file contains `dhcp6: true`.
4. Writes `/etc/systemd/system/ssh.socket.d/60-johnny-cis-ipv4.conf` so a later boot or socket start listens on `0.0.0.0:22` only. It runs `systemctl daemon-reload` and does **not** restart `ssh.socket` or `ssh.service`. The current `[::]:22` socket stays until that unit is restarted. Do not restart it in this batch.
5. If both sysctl keys are already `1` in the johnny file and in the kernel, it prints `SKIP-disable-ipv6`. Otherwise it copies `/etc/sysctl.d/60-johnny-cis-network.conf` to `/root/60-johnny-cis-network.conf.pre-batch7` once and appends the two `disable_ipv6 = 1` lines if they are absent. A later run keeps that same backup. If the live file no longer matches it, the script prints `BACKUP-DIFFERS` and still does not overwrite the backup. Rollback restores that kept copy. A different value already in the file is `STOP-sysctl-file`. It then runs `sysctl -w` on those two keys only. It does not run `sysctl -p` on the johnny file.
6. Re-checks `192.168.50.152/24` on `eno3` and `0.0.0.0:22`. If either is gone, it sets both live keys back to `0` and exits `STOP-ipv4-ssh`. That message says to run the rollback block below: the two lines may still be in `60-johnny-cis-network.conf`, and a reboot would re-apply them. Then it checks `all`, `default`, and every interface under `/proc/sys/net/ipv6/conf` are `1`. The verify block runs `sysctl --system`, which re-applies every file under sysctl.d, not only the two IPv6 keys. That is intentional and harmless on this box. If a later file overrides either key, the script exits `STOP-sysctl-override` and leaves IPv6 as `sysctl --system` left it. There is no auto-revert on that path.
7. After `OK-batch-7`, the same commit that records the run mirrors `/etc/sysctl.d/60-johnny-cis-network.conf` into `etc/sysctl.d/60-johnny-cis-network.conf` and adds `etc/systemd/system/ssh.socket.d/60-johnny-cis-ipv4.conf`. Those copies are written after the run, when the live files exist.

`OK-batch-7` means the sysctl change is in effect now. The ssh.socket drop-in is on disk and is not the listening socket yet. No reboot is required for 3.1.1. The next boot applies the drop-in and the sysctl file together. Governance re-audits after AJ sends the output. Verdicts stay in the CSV until that re-audit.

## Rollback

Not part of the paste. Use PASTE 2 at the console if IPv4 SSH is already dead. If SSH still works, this is the undo:

```bash
sudo cp -a /root/60-johnny-cis-network.conf.pre-batch7 /etc/sysctl.d/60-johnny-cis-network.conf
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0
sudo rm -f /etc/systemd/system/ssh.socket.d/60-johnny-cis-ipv4.conf
sudo rmdir /etc/systemd/system/ssh.socket.d 2>/dev/null || true
sudo systemctl daemon-reload
```

Do not restart `ssh.socket` in the same step as the undo. `0.0.0.0:22` must still be listening before the session is closed.
