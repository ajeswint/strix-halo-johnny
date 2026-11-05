# Step 13 — IRQ affinity (draft, not applied)

Rev 1, 2026-11-05 ~13:51 CT. Draft only. Grok 4.7 wrote it. Nothing in this file has been run on Johnny, on rock-box, or on ABLETON_BOX. `STEP13-IRQ-DONE` is not a result yet.

This is the tool-install step that replaces the open item "IRQ affinity later" from step 11. Handoff Next steps item 13 stays the finished Agent team note. That bullet is not this step. There is no `docs/tool-install/step-13-*.md` before this draft, and the tool-install sequence after step 12 is 13.

Ownership: Fast Path owns the capture-unit path `etc/systemd/system/johnny-capture.*` (`docs/agent-team.md` §4). `johnny-capture-irq.service` is that path. The policyscript and the one-line `IRQBALANCE_ARGS` edit are the smallest host change that keeps the pin from being undone. They are in the same paste, the same way step 11 put netplan and the tuning unit in one script. This draft does not change `docs/agent-team.md`.

## Machines

| Machine | What this step does there |
|---|---|
| Johnny | The script runs as root. Hostname gate `johnny`. Kernel gate `7.0.0-42-generic`. |
| rock-box | Where the paste is typed. `sudo -v`, then `scp`, then `ssh -t`. **[Assumption]** the checkout is still `/home/aj/Projects/strix-halo-johnny`, as in step 11 and `docs/agent-team.md`. |
| ABLETON_BOX | No command. Do not SSH. Do not touch the syslog collector. |

## Goal

Pin every MSI-X IRQ of the capture NIC `eno1np0` onto the CPUs listed in `/etc/johnny/capture-cores`, one CPU per IRQ, and make that pin survive `irqbalance` and a reboot. CPU 0 stays out of those masks. `eno3` stays `192.168.50.152/24` with its default route. The paste prints `STEP13-IRQ-DONE` only after that pin is in place and the checks below have passed. A draft, a stopped run, or a revert does not print it.

## Pass

All of these, from the script's own output:

- `CAPTURE-CPUS 1 2 3 4`
- `OK-tuning`
- `CPU0-CLEAR`
- `ENO2-IRQ-UNCHANGED`
- `ENO3-OK`
- `LOCKDOWN-UNCHANGED` (or `NOTE-no-lockdown` if that file cannot be read)
- `STEP13-IRQ-DONE`

When `irqbalance` is active, the script also prints `IRQ-HELD` after a 12 second wait. When it is not installed, `NOTE-no-irqbalance` is a pass, not a failure. `ALREADY-APPLIED` together with `STEP13-IRQ-DONE` means a second run found the pin already in place.

## What it does

1. Reads `/etc/johnny/capture-cores`. The sha256 must be `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b` (CPUs 1, 2, 3, 4, one per line). CPU 0 in that file is `STOP-cpu0-in-set`. The script does not rewrite the file and does not pick a new set.
2. Requires `johnny-capture-tuning.service` active and enabled, and `energy_performance_preference` `performance` on those four CPUs. It does not start the service and does not write EPP or idle bits.
3. Requires the step 11 link shape: `eno1np0` driver `ice`, speed `10000`, admin up, promiscuous, no ARP, no address; `eno2np1` driver `ice`, admin down, no address, and a different PCI device from `eno1np0`; `eno3` still `192.168.50.152/` with the default route out `eno3`.
4. Refuses to run if an XDP program is attached to `eno1np0`. It does not detach one.
5. Installs `/root/step13-revert.sh` before it records IRQ masks and before it edits `irqbalance`.
6. Saves the current `smp_affinity_list` of each `eno1np0` and `eno2np1` MSI-X IRQ to `/var/lib/johnny/irq-affinity-before.tsv` once, before any `irqbalance` restart. A later run prints `BACKUP-KEPT` and does not overwrite that file. Revert writes both sets back. The paste still does not choose new CPUs for `eno2np1`.
7. Writes one capture CPU into each `eno1np0` IRQ's `smp_affinity_list`. Queue IRQs whose `/proc/interrupts` name matches `eno1np0-TxRx-N`, `eno1np0-rx-N`, or `eno1np0-tx-N` use CPU `capture[N modulo 4]`. Every other MSI-X IRQ of that PCI device (misc, `ll_ts`, or a name this draft has not seen) uses the lowest capture CPU, which is CPU 1 for the current file. The script prints `NOTE-irq-name` for a name that is neither `eno1np0…` nor `ice-…`, and still pins it. A name that mentions `eno2np1`, `eno3`, or `eno4` is `STOP-irq-foreign` before the write.
8. If `irqbalance.service` exists, bans both ice PFs from balancing so the restart cannot move `eno2np1`, and so later intervals cannot undo the `eno1np0` pin. It does not stop or mask `irqbalance`. It does not set `IRQBALANCE_BANNED_CPUS` or `IRQBALANCE_BANNED_CPULIST`.
9. Enables `johnny-capture-irq.service` so a boot runs `/etc/johnny/irq-affinity.sh apply` again. The unit has no `ExecStop`. Disabling it does not restore masks. The revert script does.

## What it does not do

- No reboot, no `apt`, no GRUB, no `update-initramfs`, no sudoers, no `NOPASSWD`.
- Does not edit netplan, the `eno1np0` promiscuous drop-in, or `eno2np1`'s `activation-mode`.
- Does not write `eno2np1` IRQ masks. See the decision below.
- Does not write `eno3` or `eno4` sysfs, and does not ban `eno3` in the policyscript.
- Does not change RSS, the queue count, ring sizes, offloads, or coalescing. No `ethtool -L`, `-G`, `-K`, `-X`, or `-C`.
- Does not write `rps_cpus` or `xps_cpus`. The script records `rx-0` `rps_cpus`, `tx-0` `xps_cpus`, and the queue counts, and stops if those strings change.
- Does not load a DDP package, attach an XDP program, or leave one attached.
- Does not change the cpufreq governor, EPP, or idle states.
- Does not weaken kernel lockdown. It reads `/sys/kernel/security/lockdown` and stops if that string changes.
- Does not set `isolcpus`, `irqaffinity=`, or any other kernel command line.

## Decisions

### `eno2np1` is not pinned

`eno2np1` is admin-down (`activation-mode: off` from step 11). The SFP+8 DAC is out and the switch port is disabled. Moving its IRQs onto CPUs 1–4 would share the capture CPUs with a port that has no frames. The script records every `eno2np1` MSI-X `smp_affinity_list` before it changes anything else, and `ENO2-IRQ-UNCHANGED` means those strings are the same after the pin and, when `irqbalance` is active, after the 12 second wait.

The policyscript still returns `ban=true` for the `eno2np1` PCI device. That is not a pin. It stops `irqbalance`, if it is restarted, from moving those vectors as a side effect. CPU 0 may remain in the `eno2np1` mask. That is accepted. Those vectors are not the mirror path. An admin-up `eno2np1` is `STOP-eno2-up`. The script does not bring the port down. The same PCI device for both ports is `STOP-eno2-same-pci`.

**[Assumption]** An admin-down ice PF still has an `msi_irqs` directory, because the driver probed the function. If that directory is missing, the script stops with `STOP-no-msi eno2np1` before it writes an `eno1np0` mask.

### CPU 0 stays free of capture IRQs

`/etc/johnny/capture-cores` is the set. The hash gate is the membership test. Each `eno1np0` IRQ is given exactly one CPU from that set. After the write, `smp_affinity_list` must expand to that one CPU. If `effective_affinity_list` exists and is non-empty, it must be the same CPU. Empty or absent effective affinity prints `NOTE-effective-empty` or `NOTE-no-effective` and is not a failure. A non-empty effective mask that names any other CPU, including CPU 0, is `STOP-effective` and the run reverts.

Housekeeping IRQs, including `eno3`, are not moved by this script. `irqbalance` may still place them on CPUs 1–4. This step does not ban those CPUs. Banning CPUs 1–4 would push `eno3` and the disk toward CPU 0, which is the opposite of keeping CPU 0 free for the host.

### RPS, XPS, and RSS stay deferred

Step 11 left IRQ affinity, RSS, and RPS for the point where a capture program stays loaded. This step is only the IRQ pin.

RPS (`/sys/class/net/eno1np0/queues/rx-*/rps_cpus`) steers skbs in software after the driver. Native XDP runs in NAPI on the IRQ's CPU. RPS does not move that. XPS (`xps_cpus`) places transmit queues. `eno1np0` has no address and ARP is off, so it should not transmit. RSS already chooses a queue in hardware. Pinning the queue's IRQ chooses the CPU. Changing the indirection table or the queue count is a different step. The kernel scaling doc is the split used here: RSS is the hardware queue, the IRQ affinity is which CPU that queue's interrupt may use, and RPS is a separate software map ([scaling](https://docs.kernel.org/networking/scaling.html)).

The paste does not call `ethtool -X` or `-L`. It stops if the recorded RPS or XPS string, or the queue-directory count, changes during the run.

### `irqbalance` is not stopped

The ice driver doc's aRFS example says to stop `irqbalance` until the next reboot ([ice](https://docs.kernel.org/networking/device_drivers/ethernet/intel/ice.html)). This step does not do that. A stop would leave every other IRQ, including `eno3`, wherever it last sat, and a mask would do the same across reboot. The paste bans only the two ice PF devices.

Ubuntu 26.04 publishes `irqbalance` `1.9.4-3` ([source package](https://packages.ubuntu.com/source/resolute/irqbalance)). Debian's build of that version installs the env file as `/etc/default/irqbalance` and points the unit's `EnvironmentFile` at that path ([debian/rules](https://sources.debian.org/src/irqbalance/1.9.4-3/debian/rules/), [debian/irqbalance.install](https://sources.debian.org/data/main/i/irqbalance/1.9.4-3/debian/irqbalance.install)). **[Assumption]** Johnny's unit, if installed, matches that. The script reads `systemctl cat irqbalance.service` and stops with `STOP-irqbalance-env` unless the last `EnvironmentFile` is `/etc/default/irqbalance`. An `Environment=` line that sets `IRQBALANCE_*` is the same stop. This draft has not seen Johnny's unit. `irqbalance` is not in the handoff SBOM. Absence is `NOTE-no-irqbalance`. A process named `irqbalance` without the unit is `STOP-irqbalance-unknown`. The script does not install the package.

The env file is edited only when every uncommented `IRQBALANCE_ARGS` is missing, empty, or already `--policyscript=/etc/johnny/irqbalance-policy.sh`. Any other value is `STOP-irqbalance-args` before a write. An uncommented non-empty `IRQBALANCE_BANNED_CPUS` or `IRQBALANCE_BANNED_CPULIST` is `STOP-irqbalance-banned` before a write. The first-run file is copied to `/var/lib/johnny/irqbalance.default.pre-step13` and not overwritten later.

irqbalance 1.9.4 runs the policyscript as `exec <script> <pci-sysfs-dir> <irq>` ([classify.c at v1.9.4](https://github.com/Irqbalance/irqbalance/blob/v1.9.4/classify.c)). The PCI directory is `/sys/bus/pci/devices/<bdf>`. The script prints `ban=true` when that directory is `eno1np0`'s device or `eno2np1`'s device, and prints nothing otherwise. Exit is 0. The man page describes the same `ban=true` key ([irqbalance.1 at v1.9.4](https://github.com/Irqbalance/irqbalance/blob/v1.9.4/irqbalance.1)).

If `irqbalance` is `active`, and its command line does not already contain that policyscript argument, the paste restarts the unit and then requires the argument on the main PID's command line (`STOP-irqbalance-cmd` if it never appears). It then waits 12 seconds. The default sample interval is 10 seconds ([same man page](https://github.com/Irqbalance/irqbalance/blob/v1.9.4/irqbalance.1)). **[Assumption]** Johnny is on that default, because a custom `IRQBALANCE_ARGS` would already have stopped the paste. After the wait the pin, the `eno2np1` masks, `eno3`, and the RPS/XPS strings are checked again. `IRQ-HELD` means they held. `inactive` or `failed` is left that way (`NOTE-irqbalance-inactive`). The paste does not start `irqbalance`. `activating` or `deactivating` is `STOP-irqbalance-state` before a change.

1.9.4-3 dropped `ProtectKernelTunables=yes` ([changelog](https://sources.debian.org/data/main/i/irqbalance/1.9.4-3/debian/changelog)). **[Assumption]** the policyscript can read `/sys/class/net` from inside the service. If it cannot, `irqbalance` will not ban the ice IRQs, the 12 second check will fail, and the paste reverts.

### Names and managed IRQs

**[Assumption]** Ubuntu `7.0.0-42-generic` matches mainline `v7.0` ice IRQ names closely enough for the round-robin above. In that tree, combined queues are named `<ifname>-TxRx-<n>` and the non-queue vector is `ice-<driver-device>:misc` ([ice_main.c at v7.0](https://github.com/torvalds/linux/blob/v7.0/drivers/net/ethernet/intel/ice/ice_main.c)). The same file calls `netif_set_affinity_auto()`, which spreads queue affinity with `cpumask_local_spread` across the node, including CPU 0, until userspace writes a mask ([net/core/dev.c at v7.0](https://github.com/torvalds/linux/blob/v7.0/net/core/dev.c)). The Launchpad tree for `Ubuntu-7.0.0-42.42` did not answer from this draft, so the script does not require those strings. It pins the MSI-X set from `/sys/class/net/eno1np0/device/msi_irqs`. An `eno1np0` name in `/proc/interrupts` whose IRQ is not in that set is `STOP-irq-outside-msi`.

Writes go to `/proc/irq/N/smp_affinity_list`, which is the CPU-list form of the allowed mask ([IRQ affinity](https://docs.kernel.org/core-api/irq/irq-affinity.html)). If that file is not writable, the paste stops with `STOP-affinity-ro` before it saves masks, installs the unit, or edits `irqbalance`. Managed interrupts are not movable from `/proc` ([managed IRQs](https://docs.kernel.org/core-api/irq/managed_irq.html)). This step does not set `isolcpus=managed_irq` and does not touch GRUB. A failed write is `STOP-affinity-write` and reverts.

**[Inference]** A userspace write updates the NAPI affinity notifier's stored mask, so a later `irq_set_affinity()` from `napi_restore_config` keeps the pin. That inference is from `netif_napi_irq_notify` in the `v7.0` file above. The paste does not bounce the link to test it. The boot unit re-applies the pin after `network-online.target`.

## Files the paste writes

These repo files are the bytes the paste installs. They are not on Johnny until `STEP13-IRQ-DONE`.

| Path on Johnny | Repo mirror | Mode | sha256 |
|---|---|---|---|
| `/etc/johnny/irq-affinity.sh` | `etc/johnny/irq-affinity.sh` | 0755 | `376732d65270d5f1f35247c319a1b535f05b6a931bde7e7bbe1d976aa1e0dcdc` |
| `/etc/johnny/irqbalance-policy.sh` | `etc/johnny/irqbalance-policy.sh` | 0755 | `7a3eeb944be0ee60ba94099b3ae4da3c905c941003c5c50221921032a9ffb0a8` |
| `/etc/systemd/system/johnny-capture-irq.service` | `etc/systemd/system/johnny-capture-irq.service` | 0644 | `9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355` |
| `/root/step13-revert.sh` | `docs/tool-install/step-13-revert.sh` | 0755 | `3e3f995358c5f33303728db827861f9c6f629f43db41405e2df0ccfc70a3718e` |
| `/home/aj/cis-audit/step-13-irq-affinity.sh` | `docs/tool-install/step-13-irq-affinity.sh` | the scp mode | `0857547a1b6fc1e6862b602e26ec606056c8fc04e6f254b7e5b68ff27d8288bc` |

`/etc/johnny/capture-cores` is read, not written. sha256 stays `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b`.

Not mirrored, created on Johnny by a successful or reverted run:

| Path | Purpose |
|---|---|
| `/var/lib/johnny/irq-affinity-before.tsv` | first-run `eno1np0` and `eno2np1` masks. Kept so a later revert still restores them |
| `/var/lib/johnny/irqbalance.default.pre-step13` | first-run `/etc/default/irqbalance` |
| `/var/lib/johnny/step13-irqbalance-was-active` | `active`, `inactive`, or `failed` |
| `/root/step13-apply.log` | transcript |
| `/etc/default/irqbalance` | one `IRQBALANCE_ARGS` line, only if the unit exists. Hash is whatever the script prints at apply time. This draft does not invent it |

## Preconditions

- Second SSH session already open, and AMT KVM available. The paste does not `netplan apply`. It can restart `irqbalance`. If `eno3` drops, the KVM console runs the rollback below.
- The rock-box checkout contains this commit. If any of the five `scp` sources is missing, stop. Do not clone another copy in this step.
- `aj` has no passwordless sudo. The script has no sudoers change.
- Step 11 is still applied: `eno1np0` promisc + `NOARP` at 10000, `eno2np1` admin-down, tuning service active. This paste does not repair that shape.

## Paste

On rock-box. One block. `sudo -v` refreshes sudo on rock-box. The script runs as root on Johnny.

```bash
sudo -v
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-13-irq-affinity.sh aj@192.168.50.152:/home/aj/cis-audit/step-13-irq-affinity.sh
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-13-revert.sh aj@192.168.50.152:/home/aj/cis-audit/step-13-revert.sh
scp /home/aj/Projects/strix-halo-johnny/etc/johnny/irq-affinity.sh aj@192.168.50.152:/home/aj/cis-audit/irq-affinity.sh
scp /home/aj/Projects/strix-halo-johnny/etc/johnny/irqbalance-policy.sh aj@192.168.50.152:/home/aj/cis-audit/irqbalance-policy.sh
scp /home/aj/Projects/strix-halo-johnny/etc/systemd/system/johnny-capture-irq.service aj@192.168.50.152:/home/aj/cis-audit/johnny-capture-irq.service
ssh -t aj@192.168.50.152 'sudo bash /home/aj/cis-audit/step-13-irq-affinity.sh'
```

Success ends with `STEP13-IRQ-DONE`. The transcript is `/root/step13-apply.log`. When `irqbalance` is active the paste sleeps 12 seconds in the middle of that SSH session. SIGHUP and SIGPIPE are ignored. A dropped SSH session still runs the rollback if this run had already changed the box.

A failure before a change leaves the box as it was. The revert script may already be at `/root/step13-revert.sh`. A failure after a change prints `REVERTING` and runs that script. A rerun that changes nothing and then fails prints `CONFIG-KEPT`. A rerun that writes a file again and then fails rolls back to the first-run affinity save. After `STEP13-IRQ-DONE`, do not rerun unless that rollback is acceptable.

The script refuses any host other than `johnny` (`STOP-host`) and any kernel other than `7.0.0-42-generic` (`STOP-kernel`) before it opens the log. `STOP-not-root` is the same, before the log. `SUDO_USER` must be `aj` when it is set (`STOP-user`). An empty `SUDO_USER` prints `NOTE-no-sudo-user` and continues. That is the KVM root shell.

## Verify

Not part of the paste. On rock-box, after `STEP13-IRQ-DONE`, read-only:

```bash
ssh aj@192.168.50.152 'echo HOST $(hostname -s); echo KERNEL $(uname -r); ip -br link show eno1np0 eno2np1 eno3; ip -br addr show eno3; ip -4 route show default; echo TUNING $(systemctl is-active johnny-capture-tuning.service) $(systemctl is-enabled johnny-capture-tuning.service); echo IRQUNIT $(systemctl is-active johnny-capture-irq.service) $(systemctl is-enabled johnny-capture-irq.service); echo IRQBALANCE $(systemctl is-active irqbalance.service || true); echo LOCKDOWN $(tr -d "[:space:]" < /sys/kernel/security/lockdown); echo RPS $(tr -d "[:space:]" < /sys/class/net/eno1np0/queues/rx-0/rps_cpus); echo XPS $(tr -d "[:space:]" < /sys/class/net/eno1np0/queues/tx-0/xps_cpus); for n in /sys/class/net/eno1np0/device/msi_irqs/*; do i=$(basename "$n"); printf "ENO1 %s %s %s\n" "$i" "$(tr -d "[:space:]" < /proc/irq/$i/smp_affinity_list)" "$(tr -d "[:space:]" < /proc/irq/$i/effective_affinity_list)"; done'
```

Expect `HOST johnny`, `KERNEL 7.0.0-42-generic`, `eno1np0` still up with `PROMISC` and `NOARP`, `eno2np1` without the admin `UP` flag, `eno3` still `192.168.50.152`, the default route still `dev eno3`, tuning `active enabled`, the IRQ unit `active enabled`. Each `ENO1` line's mask is one of `1`, `2`, `3`, `4`. None of those masks is `0` or a list that contains `0`. `RPS` and `XPS` are whatever they were. This verify does not write them.

## Rollback

Not part of the paste. On Johnny, from the second SSH session or the KVM console, only after the paste has installed the script:

```bash
sudo bash /root/step13-revert.sh
```

That script restores `eno1np0` masks from `/var/lib/johnny/irq-affinity-before.tsv`, copies `/var/lib/johnny/irqbalance.default.pre-step13` back onto `/etc/default/irqbalance` when the backup exists, deletes the policyscript, the helper, and `johnny-capture-irq.service`, and restarts `irqbalance` only if the recorded state was `active`. It prints `NOTE-irqbalance-will-balance` in that case: once the ban is gone, `irqbalance` may move the ice IRQs again. That is the pre-step state. It does not change netplan, promiscuous mode, `capture-cores`, or `johnny-capture-tuning.service`. It does not reboot. Safe to run twice. It prints `REVERTED`.

Before the paste, `/root/step13-revert.sh` does not exist. There is nothing to roll back.

## Stops

The script prints the specific `STOP-*` line and exits non-zero. After a change, it also prints `REVERTING`.

| Line | When |
|---|---|
| `STOP-host` / `STOP-kernel` / `STOP-not-root` / `STOP-user` | Wrong machine, kernel, uid, or sudo user. No log file yet for the first three. |
| `STOP-cores-hash` / `STOP-cpu0-in-set` | `capture-cores` is not the step 11 file, or it lists CPU 0. |
| `STOP-tuning` / `STOP-tuning-epp` | The tuning unit is not active and enabled, or a capture CPU is not `performance`. |
| `STOP-eno1-link` / `STOP-eno1-flags` / `STOP-eno1-addr` | `eno1np0` is not the step 11 capture shape. |
| `STOP-eno2-up` / `STOP-eno2-same-pci` / `STOP-eno2-irq-moved` | `eno2np1` is up, shares a PCI device, or its mask changed. |
| `STOP-eno3-addr` / `STOP-eno3-route` / `STOP-eno3-down` | Management link is not the reserved address and route. |
| `STOP-xdp-present` | An XDP program is attached. The script does not detach it. |
| `STOP-affinity-ro` | Userspace cannot write the mask. No unit install and no `irqbalance` edit. |
| `STOP-irqbalance-env` / `STOP-irqbalance-args` / `STOP-irqbalance-banned` / `STOP-irqbalance-state` / `STOP-irqbalance-unknown` | The unit is not the Debian shape, or another ban is already set, or a stray daemon is running. |
| `STOP-effective` / `STOP-queues-changed` / `STOP-lockdown` | The pin did not land, RPS/XPS or the queue count moved, or lockdown changed. |
| `STOP-revert-failed` | The rollback itself failed. Use the KVM console and the revert script. |

## Local check

Not part of the paste. On rock-box, optional, before the paste. It does not SSH and does not write a NIC.

```bash
bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-13-self-test.sh
```

Expect `SELF-TEST-OK`. The writer ran that script on the draft host. It printed `SELF-TEST-OK`. The apply script, run on that same host, printed `STOP-host` and exited 1 before creating a log. That host is not Johnny.

## Sources

- `/proc/irq/N/smp_affinity_list`: <https://docs.kernel.org/core-api/irq/irq-affinity.html>
- Managed IRQs cannot be moved from userspace: <https://docs.kernel.org/core-api/irq/managed_irq.html>
- RSS, RPS, and XPS are different maps: <https://docs.kernel.org/networking/scaling.html>
- ice aRFS text says to stop `irqbalance`. This step bans the two PFs instead: <https://docs.kernel.org/networking/device_drivers/ethernet/intel/ice.html>
- **[Assumption]** `7.0.0-42` ice names and `netif_set_affinity_auto`: <https://github.com/torvalds/linux/blob/v7.0/drivers/net/ethernet/intel/ice/ice_main.c> and <https://github.com/torvalds/linux/blob/v7.0/net/core/dev.c>
- Ubuntu 26.04 `irqbalance` `1.9.4-3`: <https://packages.ubuntu.com/source/resolute/irqbalance>
- Unit env file path in that package: <https://sources.debian.org/src/irqbalance/1.9.4-3/debian/rules/>
- Policyscript arguments and `ban=true`: <https://github.com/Irqbalance/irqbalance/blob/v1.9.4/classify.c> and <https://github.com/Irqbalance/irqbalance/blob/v1.9.4/irqbalance.1>
