# Step 11 — E810 capture config (applied 2026-11-05 ~08:26 CT)

Rev 2, 2026-11-05 ~08:26 CT. Applied on Johnny. AJ's paste printed `STEP11-DONE`. Grok 4.7 recorded the closeout. The paste below is the one that ran (PR #4, merged). After `STEP11-DONE`, leave it unless a rollback to the first-run netplan backup is acceptable.

Live result (AJ, 2026-11-05 ~08:26 America/Chicago):

- `CAPTURE-CPUS 1 2 3 4`
- `XDP-OK` (mode `driver`; the counter rose). The script detaches and checks the program is gone before it prints `XDP-OK`.
- `OK-promisc`, `OK-eno2`, `OK-eno3`, `OK-eno1`, `OK-tuning`, `CPU0-UNCHANGED`, `VERIFY-TUNED` 1–4
- `MARTIAN-BEFORE 2475` / `MARTIAN-AFTER 2477` (delta 2; a note)
- `STEP11-DONE`; log `/root/step11-apply.log`
- Post-apply: `eno1np0` UP with `PROMISC`+`NOARP`; `eno2np1` DOWN (no admin UP); `eno3` still `192.168.50.152/24`; `johnny-capture-tuning.service` active and enabled

Live sha256 from Johnny matches the table below, including `etc/johnny/capture-cores`. `etc/johnny/capture-tuning.sh` was already `1aa19b9f…` and was left as-is.

Rev 1, 2026-11-04 23:55 CT, was the draft. Grok 4.7 wrote it. Claude Code reviewed it.

Ownership for this one paste: Platform owns Johnny's netplan and the helper under `etc/johnny/`. Fast Path owns `etc/systemd/system/johnny-capture-tuning.service` (the capture-unit path in `docs/agent-team.md` §4). The step is one recoverable script, so the writer put both in the same paste.

## What it does

1. `eno1np0` (SFP+7 mirror target): promiscuous on, ARP off, link stays up, no addresses. Persisted with a networkd drop-in on netplan's generated unit, not a second `.network` file (a second file would win the whole match and drop the netplan stanza).
2. `eno2np1` (SFP+8 end is out, switch port disabled): `activation-mode: off` in the existing netplan file. Netplan 1.2 turns that into `ActivationPolicy=always-down`. The script stops if the generated line is anything else.
3. Native XDP on `ice`: load a prebuilt pass-counter with `bpftool` (already installed, step 7) in `xdpdrv` only, require the attachment mode `driver`, require the counter to rise, then detach and unpin. No generic-XDP fallback.
4. Capture cores: discover four performance CPUs, set EPP to `performance`, and disable every cpuidle state except `POLL` and shallow C1 (`C1` or `C1_ACPI`). A systemd oneshot re-applies that on boot. The previous values are saved and the revert script writes them back.
5. Prints `journalctl -k | grep -c martian` before and after the XDP window. The count is a note. It does not pass or fail the step.

## What it does not do

- No reboot, no apt, no GRUB, no sudoers, no `NOPASSWD`.
- Does not edit the `eno3` or `eno4` netplan stanzas. `eno3` stays DHCP.
- Does not write a per-interface `disable_ipv6` sysctl. Does not change `rp_filter` or `log_martians`.
- Does not pin `ice` IRQs, change queues, rings, or offloads, or load a DDP package.
- Does not leave an XDP program attached. AF_XDP is not opened.
- Does not start or stop `suricata`.
- Does not change the cpufreq governor and does not set a kernel cmdline (`intel_idle.max_cstate` is global and needs a reboot; this step does not use it).

## Why

`eno1np0` is the mirror target and is already up at 10000 with no addresses (2026-11-04). It is not promiscuous, so the NIC drops mirrored unicast that is not addressed to its own MAC (`docs/network-map.md`, 2026-10-30). Promiscuous mode is what lets the capture path see that unicast. ARP off keeps the port from answering ARP. It has no address either way.

`eno2np1` is operationally down (no carrier) but still administratively up (`MULTICAST,UP`). `activation-mode: off` is how netplan tells networkd to hold it down. The SFP+8 DAC stays out and the switch port stays disabled; this step does not touch the switch.

The XDP check is the step 11 "count with XDP" on the in-tree `ice` driver. A permanent capture program is Module 1.

The four cores are held out of deep idle so a later IRQ pin has somewhere to land. This paste does not move IRQs, so those cores are reserved by power policy only. The other performance cores stay available for the host and the later on-box SLM.

## CIS interactions

IPv6 is already off system-wide in `etc/sysctl.d/60-johnny-cis-network.conf` (`net.ipv6.conf.all.disable_ipv6 = 1` and `default`). The handoff's per-interface `disable_ipv6=1` on `eno1np0` is redundant. The script reads `net.ipv6.conf.all.disable_ipv6` and `net.ipv6.conf.eno1np0.disable_ipv6` and stops if either is not `1`. It does not write a sysctl.

`net.ipv4.conf.all.rp_filter` and `default` are `1`. `log_martians` on `all` and `default` is `1`. AJ left the per-NIC wildcard at `2` (batch 4). The kernel uses the max of `all` and the interface, so `eno1np0` is still loose while its own value stays `2` (`docs/os-handoff.md`, batch 4 close). This paste does not change that.

Martians: batch 6 already logged broadcasts on `eno1np0`. **[Assumption]** `PACKET_OTHERHOST` unicast is dropped in `ip_rcv` before `rp_filter`, same as the batch 4 note for this kernel (7.0.0-42). Promiscuous mode is what XDP and AF_PACKET need; it is not by itself a reason to expect a martian flood of mirrored unicast. The script still records the count the handoff asked for:

```bash
journalctl -k | grep -c martian
```

It prints `MARTIAN-BEFORE` and `MARTIAN-AFTER`. A non-zero delta is a note for the next session, not a rollback.

ufw is not enabled by this paste. `eno1np0` has no address. Detection's later check that a ufw deny does not hide SPAN frames is unchanged and still open.

Kernel lockdown stays as it is. Root loading a BPF program is the expected integrity-lockdown path. If the kernel refuses the load, the script stops and rolls back. It does not weaken lockdown.

## Capture cores

The script does not hardcode CPU numbers.

1. Read `/sys/devices/cpu_core/cpus` and `/sys/devices/cpu_atom/cpus`. Both must exist, parse as a CPU list, and be disjoint. Those are the hybrid PMU cpumasks (performance / "atom"). **[Assumption]** kernel 7.0.0-42 on the 285HX still exports them. If either file is missing, the script prints `STOP-no-hybrid-pmu` and does not guess from `cpuinfo_max_freq`.
2. Read `/sys/devices/system/cpu/cpu0/topology/core_cpus_list` and drop that set (CPU 0 and any SMT sibling). CPU 0 stays on housekeeping.
3. Take the lowest four remaining IDs from `cpu_core`.

**[Assumption, illustration only]** If `cpu_core` is `0-7` and CPU 0's sibling list is `0` (Arrow Lake has no hyperthread), the set is `1 2 3 4`. The script prints `CAPTURE-CPUS` from the live files. A different list is the list that gets written. Fewer than four IDs is `STOP-capture-cpu-count`.

Four is the step 11 choice: the mirror is four 1G ingress ports into one 10G target, and the other performance cores stay free. It is not a measurement. Changing the count is a one-line edit (`-eq 4` in `pick_capture_cpus`) before AJ runs, not a second paste.

On those four CPUs only:

- `energy_performance_preference` is set to `performance`. The governor is printed and not changed. **[Assumption]** `intel_pstate` is the scaling driver (Ubuntu's default when HWP is available). Anything else is `STOP-not-intel-pstate`.
- Every cpuidle state that is not `POLL` and not shallow C1 is disabled. Shallow C1 is `C1` or `C1_ACPI`. `C1E`, `C2_ACPI`, and `C3_ACPI` are deep. Johnny's live names (2026-11-05) are `POLL`, `C1_ACPI`, `C2_ACPI`, `C3_ACPI` (ACPI idle, not `intel_idle`'s bare `C1`/`C1E`). If a chosen CPU has no shallow C1, or no deeper state, the script stops.
- CPU 0's EPP, and the disable bit of its first deep idle state, are compared after the write and must be unchanged.

The previous EPP and disable bits are saved to `/var/lib/johnny/capture-tuning-before.tsv` before the first write. `johnny-capture-tuning.service` re-applies on boot. `systemctl disable --now johnny-capture-tuning.service` runs the revert action. The saved file is kept so a later apply still restores the original values.

IRQ affinity, RSS, and RPS are not changed. Fast Path pins those when a capture program stays loaded.

## Native XDP

`bpftool` 7.7.0 is already on Johnny (step 7). No extra package.

The object is `docs/tool-install/xdp-pass-count.o`, built here with Ubuntu clang 18.1.3:

```bash
clang -O2 -g -Wall -Wextra -target bpf -mcpu=v3 \
  -c docs/tool-install/xdp_pass_count.c \
  -o docs/tool-install/xdp-pass-count.o
```

sha256 `2fe90f6c84c4ca5b07e34f4dd319e443a7609ff538587327aaebcfa1fccf0398`. The script refuses any other hash. Do not rebuild it on Johnny (clang is not installed there, and a rebuild would not match the hash).

`llvm-objdump -d` on that object: `call 0x1` (`bpf_map_lookup_elem`), `lock *(u64 *)(r0 + 0x0) += r1`, `w0 = 0x2` (`XDP_PASS`), `exit`. Section `xdp`, license `GPL`, one array map. Local check: `bash docs/tool-install/step-11-self-test.sh` (does not touch a NIC).

Attach is only `bpftool net attach xdpdrv`. `xdp` (the mode that falls back to generic) is not used. The script requires the JSON mode string `driver`. It sleeps 5 seconds, and another 10 if the counter has not moved, then detaches and deletes `/sys/fs/bpf/johnny_xdp_count`.

- Counter increased: `XDP-OK`.
- NIC `rx_unicast.nic` increased but the map did not: `STOP-xdp-no-count`.
- Neither increased: `STOP-xdp-no-traffic` (mirror quiet, or the port is not delivering). Run it while the SPAN is up.
- Attach failed: `STOP-xdp-attach`, plus the last ice/XDP/DDP kernel lines and the GRO/LRO offload lines. Offloads are not changed.

**[Assumption]** `rx_unicast.nic` is still the ethtool counter name from 2026-10-30. If that line is absent, the script counts `/sys/class/net/eno1np0/statistics/rx_packets` and prints `NOTE-nic-counter-fallback`.

ice blocks XDP for frames larger than 3KB ([kernel ice doc](https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html)). The script stops if the MTU is over 3000. It does not change the MTU. **[Assumption]** the live MTU is still 1500.

A missing DDP package puts the PF in safe mode and native XDP is refused (same kernel doc). The handoff already records DDP "ICE OS Default" 1.3.43.0 loaded. This paste does not load another package. A safe-mode failure is a stop, not a cue to download COMMS.

AF_XDP zero-copy is supported by `ice` on this kernel series (same doc). It needs a userspace socket. That is Module 1, not this verify.

## DDP COMMS (optional, not in the paste)

The in-tree default package is what enables the pipeline features, including native XDP. A COMMS profile (extra tunnel parsers) is an Intel download, not an Ubuntu package and not in this repo. Loading a different package means unloading every `ice` PF ([kernel ice doc](https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html)). The home SPAN does not need it. Leave "ICE OS Default" loaded.

## Files the paste writes

| Path on Johnny | Repo mirror | sha256 |
|---|---|---|
| `/etc/netplan/00-installer-config.yaml` | `etc/netplan/00-installer-config.yaml` | `83a6b8bedce740a2559e0d2c6e611337d529f2d505457ea19a6da9819ce0e185` |
| `/etc/systemd/network/10-netplan-eno1np0.network.d/60-johnny-capture.conf` | same under `etc/` | `78939fd5bbb8b0dc7336661ca748de9d6342260beab32a4f4da843330c9c0b1a` |
| `/etc/johnny/capture-tuning.sh` | `etc/johnny/capture-tuning.sh` | `1aa19b9f20dc713aa7556e7ef0bb95a3c377a76b805442f6f36b5874dbb264a6` |
| `/etc/systemd/system/johnny-capture-tuning.service` | same under `etc/` | `64b3045cf4d9c487265a76c3338253d5b73ad137514ee9868a70389b7b800730` |
| `/etc/johnny/capture-cores` | `etc/johnny/capture-cores` | `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b` |
| `/var/lib/johnny/capture-tuning-before.tsv` | not mirrored (pre-change values) | written on first apply |
| `/root/step11-revert.sh` | `docs/tool-install/step-11-revert.sh` | `16016830c2c288ce80024335c2bd37f00d00c5d1a995718861c6de08e5de8a92` |
| `/root/00-installer-config.yaml.pre-step11` | the pre-step11 yaml, kept on Johnny | first run only |
| `/root/step11-apply.log` | the apply transcript | this run |

The netplan mirror adds only this, under `eno2np1`:

```yaml
      # step 11: keep this port admin-down (SFP+8 end is out)
      activation-mode: off
```

`eno3`, `eno1np0`, and `eno4` are byte-for-byte the previous stanzas. Mode of the live yaml is preserved (`cp -a` / `fchmod`).

No new sysctl, udev, or GRUB file.

## Preconditions

- Second SSH session already open, and AMT KVM available. `netplan apply` reloads networkd. The `eno3` generated file is checked identical before apply, and `.152` plus the default route via `eno3` are checked after. If SSH drops, the KVM console runs the rollback below.
- This branch checked out at `/home/aj/Projects/strix-halo-johnny`. **[Assumption]** that is still the rock-box checkout from `docs/agent-team.md`.
- SPAN up (SFP+7 → `eno1np0` at 10000) so the counter can move.
- `aj` has no passwordless sudo. The script has no sudoers change.

## Paste

One block, from the rock-box checkout of this branch. First line refreshes sudo on the machine you paste it on. The script itself runs as root on Johnny.

```bash
sudo -v
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-11-e810-capture.sh aj@192.168.50.152:/home/aj/cis-audit/step-11-e810-capture.sh
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/xdp-pass-count.o aj@192.168.50.152:/home/aj/cis-audit/xdp-pass-count.o
ssh -t aj@192.168.50.152 'sudo bash /home/aj/cis-audit/step-11-e810-capture.sh'
```

Success ends with `STEP11-DONE` and `XDP-OK`. The transcript is `/root/step11-apply.log`.

A failure after a change from this run prints `REVERTING` and runs the rollback. A rerun that changes nothing and then fails prints `CONFIG-KEPT` and leaves the previous config. A rerun that has to apply again (the port was not actually down, or a file was missing) is treated as a change: a later failure rolls back to the first-run netplan backup. After `STEP11-DONE`, do not rerun unless that rollback is acceptable.

## Verify

The script's own checks are the gate: `OK-promisc`, `OK-eno2`, `OK-eno3`, `OK-eno1`, `XDP-OK`, `OK-tuning`, `CPU0-UNCHANGED`, `STEP11-DONE`.

After a successful run, read-only:

```bash
ssh aj@192.168.50.152 'ip -br link show eno1np0 eno2np1 eno3; ip -br addr show eno1np0 eno2np1 eno3; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.eno1np0.disable_ipv6 net.ipv4.conf.all.rp_filter net.ipv4.conf.eno1np0.rp_filter net.ipv4.conf.all.log_martians; journalctl -k | grep -c martian; systemctl is-active johnny-capture-tuning.service; systemctl is-enabled johnny-capture-tuning.service'
```

Expect `eno1np0` UP at 10000 with `PROMISC` and `NOARP` and no address line; `eno2np1` without the admin `UP` flag; `eno3` still `192.168.50.152`; both IPv6 sysctls `1`; `all.rp_filter` `1` (the per-NIC value may still be `2`); the tuning unit `active` and `enabled`.

The preflight link gate reads sysfs `flags` as hex or decimal (`0x1003` on this kernel). It does not require `IFF_LOWER_UP`: that bit stays clear here even when `carrier` is 1 and `operstate` is `up`. Link-up is speed `10000`, `carrier` 1 or `operstate` `up`, and `IFF_UP`.

Copied back in the closeout commit: `etc/johnny/capture-cores` (`1` through `4`, sha256 `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b`). AJ's live hashes for the yaml, the drop-in, `capture-tuning.sh`, and the unit match the table. The tuning script in the repo was already that hash.

## Rollback

From SSH or the KVM console:

```bash
sudo bash /root/step11-revert.sh
```

That script is installed before any change. It detaches the XDP program if one is still pinned, restores EPP and cpuidle from the save file, disables the unit, deletes the drop-in and the tuning files, restores `/root/00-installer-config.yaml.pre-step11` if the live yaml differs, and runs `netplan apply` only in that case. If the yaml is unchanged, it runs `networkctl reload` so networkd drops `Promiscuous=` and `ARP=` from the live config. It then clears promisc and turns ARP back on for `eno1np0`. The apply script ignores SIGHUP and SIGPIPE, and any nonzero exit after a change from this run still starts this rollback. Safe to run twice. It prints `REVERTED`.

The first-run yaml backup is not overwritten on a later run (`BACKUP-KEPT`).

## Sources

- Netplan 1.2 `activation-mode`: `off` forces the link down on the networkd backend. <https://netplan.readthedocs.io/en/1.2/netplan-yaml/>
- **[Assumption]** netplan.io 1.2-1ubuntu5.1 still emits `ActivationPolicy=always-down` for `activation-mode: off`, as in the generator test. The script requires that exact line. <https://github.com/canonical/netplan/blob/main/tests/generator/test_common.py>
- `Promiscuous=`, `ARP=`, and `.network.d` drop-ins: <https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html>
- ice XDP, the 3KB frame limit, and DDP safe mode: <https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html>
- `bpftool net attach xdpdrv`: <https://man.archlinux.org/man/bpftool-net.8.en>
- EPP per CPU: <https://docs.kernel.org/admin-guide/pm/intel_pstate.html> and <https://ubuntu.com/server/docs/explanation/performance/perf-p-states/>
- Per-CPU cpuidle `disable`: <https://www.kernel.org/doc/Documentation/cpuidle/sysfs.txt>
- Hybrid PMU cpumasks `/sys/devices/cpu_core/cpus` and `/sys/devices/cpu_atom/cpus`: <https://lists.openwall.net/linux-kernel/2021/03/29/237>. **[Assumption]** those paths still exist on 7.0.0-42. The script stops if they do not.

## Closeout

Applied 2026-11-05 ~08:26 CT. PR #4 was the paste. This revision records the result and adds `etc/johnny/capture-cores`. Live sha256 values match the table. IRQ affinity stays later.
