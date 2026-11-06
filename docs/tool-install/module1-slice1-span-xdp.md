# Module 1, slice 1 — passive SPAN / XDP path on `eno1np0` (draft, not applied)

Rev 1, 2026-11-06 06:20Z (2026-11-06 00:20 America/Chicago). **Draft. Nothing here has run on Johnny.** Written by the code-writer seat (Sonnet). The adversarial-reviewer reviews the exact paste before AJ runs it. Docs, one script, one self-test. No sudo was used and Johnny was not contacted.

AJ said **go** on Module 1 (2026-11-05 evening America/Chicago). The OS gate is APPROVED (handoff rev 95, `docs/findings/overseer-review-os-gate.md` §8). This file is the first Module 1 artifact.

**In plain English.** The mirror port already delivers copies of LAN traffic to `eno1np0`. Step 11 proved Johnny can run a tiny program inside the NIC driver for a few seconds. Slice 1 turns that into a permanent, passive "watcher" that counts and describes packets without keeping them. Before any permanent attach, this file does one safe thing first: **ask the machine what it can do** (read-only, no changes). The answers decide the next paste.

## Scope (AJ, `docs/findings/overseer-review-os-gate.md` §8)

In: the passive SPAN / XDP path on `eno1np0` (SFP+7 → E810).

Out, unchanged by this file:

- Host-side LSM work (BPF-LSM exec, `vfs_write` entropy, CoW rollback): deferred to the architecture pass (`docs/agent-team.md` §7.4). Not started.
- Idle-memory investigation: deferred to Module 1 sizing. This probe records `MemAvailable` only.
- Suricata: stays disabled. No config is invented here (Detection owns it later; `etc/suricata/` does not exist).
- Inline mode, quarantine, Wi-Fi: later. Passive first.
- Lab UKI option A: unchanged. Nothing here reopens a CIS or OS paste.

## What step 11 already proved (not redone here)

`eno1np0` is `PROMISC`+`NOARP` with no address; `eno2np1` is admin-down; capture cores are `1 2 3 4` (`/etc/johnny/capture-cores`); a temporary native `xdpdrv` pass-counter attached, counted, and was **detached** (`XDP-OK`, mode `driver`). AF_XDP was **not** opened. Step 13 later put the twelve `ice-eno1np0-TxRx-N` IRQs on CPUs 1–4, three each (survives a cold boot). A permanent capture program is Module 1.

## Decision: which capture path for slice 1

Three ways to get packets from the E810 into something that can analyse them. Choice for slice 1: **a permanent native-XDP observer** (driver mode only, always `XDP_PASS`, header-only metadata kept in BPF maps). AF_XDP and AF_PACKET are not built in slice 1.

| Path | Where it runs | What reaches userspace | Verdict for slice 1 |
|---|---|---|---|
| **Permanent native-XDP observer** (`xdpdrv`, `XDP_PASS`) | Inside the `ice` driver's Rx path, before the kernel builds a packet buffer | Only what the program writes to a map (counters; later header-only records). No payload copy. | **Chosen.** Native attach is already proven on this exact NIC, kernel and MTU (step 11). Header-only and metadata-first matches the lab default in `docs/os-handoff.md` § Legal. It needs no consumer process, no extra memory region, and no queue-count change. It runs on whichever CPU services the queue's IRQ, which is already CPUs 1–4 (step 13), so there is nothing new to pin. |
| **AF_XDP, zero-copy** | XDP program redirects chosen frames to a userspace socket | Whole frames, in a shared memory area (UMEM) | **Deferred** (slice 2 decision). Needs: an XDP program that redirects through an `XSKMAP`; one socket bound to each queue id (the kernel doc says each socket is bound to "a specific queue id on that device"); UMEM memory sized against 32 GB of single-channel RAM that the on-box SLM also wants; and a consumer (Suricata's AF_XDP mode or Johnny's own daemon, which is Detection's and Daemon's call, not invented here). Twelve queues on four cores means twelve sockets, or a queue-count change. A queue-count change on `ice` rebuilds the queues, and **[Inference]** the step 13 IRQ pins would not survive that (the pin helper runs at boot only). This probe collects the facts that decide it (queue counts, memlock limits, huge pages, kernel config, existing AF_XDP sockets). |
| **AF_PACKET** (what `tcpdump` and `dumpcap` use) | After the kernel has built a packet buffer, in the normal stack path | Whole frames, copied | **Not built.** It works today (`dumpcap` has `cap_net_admin,cap_net_raw=eip`, `aj` is in `wireshark`) and stays the **cross-check**: because the observer always returns `XDP_PASS`, `tcpdump` on `eno1np0` still sees every frame, so counts can be compared. It is the slowest path and copies every frame. |

Notes on the choice:

- `XDP_PASS` keeps today's behaviour: the stack still receives the frame and drops it (unicast not for Johnny's MAC is dropped before `rp_filter`, **[Assumption]** from step 11). `XDP_DROP` would stop `tcpdump` seeing anything on this port and would hide the martian-log effect. That is a later choice, not slice 1.
- **Native only, no generic fallback.** Attach is `bpftool net attach xdpdrv` and nothing else. The plain `xdp` keyword falls back to generic mode, which runs after the packet buffer is built and would quietly hide a native failure ([bpftool-net man page](https://man.archlinux.org/man/bpftool-net.8.en); same text as the step 11 runbook). Slice 1 never uses `xdp` or `xdpgeneric`.
- For AF_XDP later, the same rule applies: bind with the zero-copy flag so a failure is loud. The kernel doc says the default tries zero-copy and "will fall back on using copy mode", and that `XDP_ZEROCOPY` "will force the socket into zero-copy mode or fail" ([AF_XDP kernel doc](https://docs.kernel.org/networking/af_xdp.html)).
- `ice` supports AF_XDP zero-copy ([ice kernel doc](https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html): "This driver supports XDP (Express Data Path) and AF_XDP zero-copy"). Zero-copy on Johnny is **untested**.

## Constraints this slice carries

| Constraint | Source | What it means here |
|---|---|---|
| ice blocks XDP above 3 KB | "XDP is blocked for frame sizes larger than 3KB" ([ice kernel doc](https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html)) | MTU is **1500** (**[Assumption]**, last recorded by step 11). The probe prints the live MTU: `STOP-mtu-over-3000`, `NOTE-mtu-not-1500`. This slice never changes the MTU. A January 2023 patch, "ice: add support for XDP multi-buffer on Rx side" ([posting](https://lists.openwall.net/netdev/2023/01/31/419)), limits the MTU only when the XDP program does not declare frags support; I did not confirm which kernel release merged it. The kernel doc's 3 KB sentence is the conservative reading and does not matter at MTU 1500. |
| Kernel lockdown, integrity | Handoff § Known gaps; `/sys/kernel/security/lockdown` reads `none [integrity] confidentiality`; step 11 attached a native program under it | A header-parsing XDP program uses none of the blocked helpers (`bpf_probe_write_user` is blocked, per the handoff; confidentiality mode also restricts the kernel-memory-read helpers, per the [2019 lockdown patch discussion](https://lore.kernel.org/netdev/alpine.LRH.2.21.1906270621080.28132@namei.org/T/)). Lockdown is not weakened. The probe prints the live mode and never runs `bpftool feature probe ... full` (that mode also probes `bpf_probe_write_user` and `bpf_trace_printk`, which "print warnings to kernel logs", [bpftool-feature man page](https://manpages.ubuntu.com/manpages/stonking/man8/bpftool-feature.8.html); that page is the Ubuntu `stonking` series, not `resolute`, so wording may differ from Johnny's bpftool 7.7.0). [Kernel lockdown man page](https://man7.org/linux/man-pages/man7/kernel_lockdown.7.html) lists BPF among the restricted features. |
| DDP package | "If the driver is unable to load the DDP package, the device will enter Safe Mode ... Safe Mode disables advanced and performance features" ([ice kernel doc](https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html)) | The handoff records "ICE OS Default" 1.3.43.0 loaded. The probe checks this boot's kernel log: `OK-ddp-loaded` or `STOP-ddp-safe-mode`. **No COMMS (or any other) DDP package is loaded.** A different package means unloading every `ice` PF (same doc); the home SPAN does not need it. |
| No `eno3` change | AGENTS.md; handoff | The probe never reads or touches `eno3`. It reads only `eno1np0`, system-wide settings, and unit state. |
| No sudoers change | AGENTS.md | Paste 1 needs no sudo. Paste 2 uses AJ's normal sudo password and adds no `NOPASSWD`. |
| Capture cores and IRQ pins | `/etc/johnny/capture-cores` (`1 2 3 4`); step 13 | Read only. `STOP-irq-baseline-outside-capture-cores` if a queue IRQ is outside the file's CPUs. **Not undone or re-applied.** |
| Native XDP attach may disturb the IRQ pins | **[Assumption, unverified]** `ice` may rebuild queue resources when the first XDP program attaches. Step 11 attached and detached *before* step 13 pinned the IRQs, so the two have never run together. | The probe cannot test it (read-only). It records the baseline. The attach paste (1b) must snapshot IRQ affinity before and after and treat a change as a stop. |
| No Suricata, no `suricata.yaml` | Handoff § Blocked or deferred | Probe reports `UNIT suricata ...`. `STOP-suricata-enabled` or `STOP-suricata-active` if that changed. |
| Never `pci=noaer`; never disable ACS Source Validation; no snaps | AGENTS.md | Not touched. |

## Why the first step is a probe, not an attach

An attach paste can be written now: step 11 already has the pattern. It would be guessing at facts the repo does not have. Each row below is a fact that changes the next paste.

| Fact the probe records | Why it matters | Decision it feeds |
|---|---|---|
| Live link, flags, MTU, address, "any XDP already attached" (`ip -d link`, `/sys/class/net`) | Confirms step 11 and step 13 state still holds before anything is attached | Go / no-go for 1b |
| Driver `ice`, version, firmware, bus (`ethtool -i`); DDP line in this boot's kernel log | Safe mode refuses native XDP | Go / no-go for 1b |
| Offloads: GRO, LRO, VLAN offload, hashing (`ethtool -k`) | LRO and VLAN stripping change what an XDP program sees. **[Assumption]** (ice behaviour not read from source) | What the observer can parse |
| Queues, rings, RSS hash and rules, private flags (`ethtool -l -g -x -n --show-priv-flags`) | AF_XDP needs one socket per queue; RSS decides whether both directions of a flow land on one queue | AF_XDP vs observer; per-CPU map layout |
| NIC counters and a 5-second packets/bytes sample (`ethtool -S`, `/sys/class/net/eno1np0/statistics`) | Is the SPAN alive, and how heavy is it? The step 11 check needed live traffic | Sizing; `NOTE-span-quiet` |
| Queue IRQs and where they land vs `capture-cores` (`/proc/interrupts`, `/proc/irq/N/*`) | Baseline for "attach did not move the pins" | The 1b before/after check |
| Kernel config (`/boot/config-7.0.0-42-generic`): BPF, JIT, `XDP_SOCKETS`, `XDP_SOCKETS_DIAG`, `ICE`, BTF, huge pages | AF_XDP is built into the kernel or it is not | Whether AF_XDP can be considered |
| BTF, bpffs mount, BPF sysctls, lockdown mode, memlock limits, huge pages, `MemAvailable` | Where a program can be pinned; UMEM sizing inputs. **[Assumption, unverified]** whether UMEM is charged to `RLIMIT_MEMLOCK` or to the memory cgroup on this kernel: my search found the 5.11 switch to cgroup accounting for BPF maps, and no source for UMEM ([BPF resource-limit notes](https://docs.ebpf.io/linux/concepts/resource-limit/)) | Service limits for a future consumer |
| Existing AF_XDP sockets (`ss -f xdp`) | Confirms none are open | Sanity |
| Toolchain: clang, libbpf, libxdp, xdp-tools present? apt candidates | The `.o` for step 11 was built off-box (Ubuntu clang 18.1.3, handoff). Resolute lists `libbpf1`/`libbpf-dev` 1:1.6.3-1ubuntu1 and `libxdp1`/`libxdp-dev` 1.6.2-1ubuntu1 ([libbpf search](https://packages.ubuntu.com/search?keywords=libbpf&searchon=names&suite=resolute&section=all), [libxdp search](https://packages.ubuntu.com/search?keywords=libxdp&searchon=names&suite=resolute&section=all)); whether Johnny's cached lists agree is what `APT-CANDIDATE` shows | Build host vs build-on-Johnny; whether any package install is needed (its own paste, its own review) |
| Units: `johnny-capture-irq`, `johnny-capture-tuning`, `irqbalance`, `suricata` | Slice 1 sits on top of the first two; Suricata must stay off | Go / no-go |
| The count of `martian` lines in `journalctl -k` (same count as step 11, all boots) | The handoff said this was not re-measured on a comparable basis | Note only |
| Root mode: `bpftool -j feature probe kernel`, `bpftool -j net show`, `bpftool -j prog show` | Does the running kernel offer the XDP program type, `XSKMAP`, per-CPU maps, ring buffer, redirect? Is anything attached? | Which map types the observer can use |

## What the probe does not do

- No `ip link set`, no `ethtool` setter (`-K -L -G -X -N -s -C`, `--set-priv-flags`), no `sysctl -w`, no module load, no sysfs or procfs write.
- No `bpftool` attach, detach, load, pin, or map update. No `feature probe ... full`. No AF_XDP socket. No XDP program attached or loaded by the script. (`bpftool feature probe kernel` makes the kernel create and drop tiny test objects. It attaches nothing.)
- No apt, no `apt update`, no package install. No netplan, networkd, ufw, or unit change. No start or stop of any service. No reboot.
- No read of `eno3`. No change to `eno2np1`. No Suricata config.
- No sudo in Paste 1. Paste 2 runs `bpftool` as root and writes only under `/root/m1s1-probe-root/`.
- No change to `/etc/johnny/capture-cores`, IRQ affinity, EPP, or idle states.

Enforced in code: every Johnny-state command goes through `ro()`, which refuses anything not on the read-only allowlist (`ro_allowed`) and exits 97 with `STOP-not-readonly`. The rock-box self-test checks the allowlist with positive and negative cases, runs `ro` against command shims to prove a refused command never executes, and checks that **every** `ro` / `save` call in the script passes the allowlist.

STOP lines are collected, not fail-fast: a probe should show every fact. Any STOP withholds the DONE token and exits 1. NOTE lines never do.

## Machines

| Machine | Role |
|---|---|
| Johnny (`johnny`, `192.168.50.152`) | The only host the probe may run on. `STOP-host` anywhere else, before any read. |
| rock-box (`aj-rock-box`) | The checkout and the SSH client. The self-test runs here. |

## Self-test (rock-box, touches no NIC)

```bash
bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1-self-test.sh
```

Expect `STATIC-INVOCATIONS-OK` and `SELF-TEST-OK`. It also runs `module1-slice1-probe.sh user` and `root` on rock-box and requires `STOP-host` and `STOP-not-root` (both fire before any read).

Probe script sha256 (the self-test requires this line to match the file): `41ac519898e83535e0b15a994648fe86647773cc26eac759cc7a7a4d1de0a9ca`

## Preconditions

- This branch checked out at `/home/aj/Projects/strix-halo-johnny` on rock-box. **[Assumption]** that is still the rock-box checkout (`docs/agent-team.md`).
- Johnny up, SSH key login working. The SPAN should be up (SFP+7 → `eno1np0` at 10000) so the 5-second sample can see traffic; a quiet SPAN prints `NOTE-span-quiet` and is not a stop.
- Paste 1 needs no second session and no KVM: it changes nothing. Paste 2 changes nothing either.

## Paste 1 (as `aj`, no sudo)

One block, from the rock-box checkout. It copies the script, checks its hash on Johnny, and runs it as `aj`. About 10 seconds (includes a 5-second sample).

```bash
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1-probe.sh aj@192.168.50.152:/home/aj/cis-audit/module1-slice1-probe.sh
ssh aj@192.168.50.152 'echo "41ac519898e83535e0b15a994648fe86647773cc26eac759cc7a7a4d1de0a9ca  /home/aj/cis-audit/module1-slice1-probe.sh" | sha256sum -c - && bash /home/aj/cis-audit/module1-slice1-probe.sh user'
```

Success ends with `M1S1-PROBE-DONE`. Raw files: `/home/aj/cis-audit/m1s1-probe/` on Johnny (a previous run is moved aside to `m1s1-probe.prev.<UTC time>`). `summary.txt` there repeats every line printed. Raw files stay on Johnny and are not committed.

## Paste 2 (optional, sudo, bpftool facts)

Do Paste 1 first. This adds what only root can read: which BPF program and map types the running kernel offers, and whether anything is attached to `eno1np0`. It writes only under `/root/m1s1-probe-root/` and attaches nothing. `sudo -v` refreshes rock-box's sudo; the password prompt that matters is Johnny's, at the last line.

```bash
sudo -v
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1-probe.sh aj@192.168.50.152:/home/aj/cis-audit/module1-slice1-probe.sh
ssh -t aj@192.168.50.152 'echo "41ac519898e83535e0b15a994648fe86647773cc26eac759cc7a7a4d1de0a9ca  /home/aj/cis-audit/module1-slice1-probe.sh" | sha256sum -c - && sudo bash /home/aj/cis-audit/module1-slice1-probe.sh root'
```

Success ends with `M1S1-PROBE-ROOT-DONE`. **[Assumption]** the `bpftool -j feature probe kernel` key names (`have_xdp_prog_type`, `have_xskmap_map_type`, and so on) are from memory of bpftool's JSON schema, not a live capture. A wrong name prints `NOTE-feature-key-absent`, never a silent pass, and the raw `feature-probe.json` is kept for the reviewer. Same trust level as step 11: the script runs as root from `/home/aj/cis-audit/` after a hash check; there is no root-owned copy.

## What to bring back

From Paste 1: every line starting `HOST`, `KERNEL`, `LINK`, `OK-`, `NOTE-`, `STOP-`, `DRIVER`, `FIRMWARE`, `DDP-LINE`, `FEATURE`, `QUEUES`, `RING`, `RSS-HASH`, `RX-RULES`, `PRIV`, `STAT`, `RX-RATE-5S`, `CAPTURE-CORES`, `IRQ`, `ZC-QUEUES`, `KCONFIG`, `BTF-VMLINUX`, `BPFFS`, `SYSCTL`, `LOCKDOWN`, `ULIMIT-L-AJ`, `SYSTEMD`, `HUGEPAGES`, `MEM-AVAILABLE-MB`, `THP`, `TOOL`, `TOOL-ABSENT`, `BPFTOOL`, `PKG`, `PKG-ABSENT`, `APT-CANDIDATE`, `UNIT`, `MARTIAN-COUNT`, and the final token. From Paste 2: `BPF-FEATURE`, `BPF-XDP-HELPER`, `PROG-XDP-COUNT`, and the final token. Simplest: paste the whole terminal output. It holds no secret (MACs and IRQ numbers only).

## Stop lines

| Line | Meaning |
|---|---|
| `STOP-root` | Paste 1 started as root. Run it as `aj`. |
| `STOP-not-root` | Paste 2 started without root. |
| `STOP-host` | Not on `johnny`. Do not continue. Fires before any read. |
| `STOP-user` | Paste 1 is not running as `aj`. |
| `STOP-not-readonly` | Internal guard: the script tried a command that is not on the allowlist. It exits 97 before running it. A reviewer bug, not a Johnny problem. |
| `STOP-no-iface` | `eno1np0` is not present. |
| `STOP-eno1-not-up`, `STOP-eno1-not-promisc`, `STOP-eno1-not-noarp` | Step 11 state is not as recorded: `UP`, `PROMISC`, `NOARP` (flags bits `0x1`, `0x100`, `0x80`). |
| `STOP-flags-form` | `/sys/class/net/eno1np0/flags` was not a number. |
| `STOP-mtu-form` | The MTU was not a number. |
| `STOP-mtu-over-3000` | ice blocks XDP above 3 KB. Do not attach. This slice does not change the MTU. |
| `STOP-link-not-10g-up` | Speed is not `10000`, or neither carrier nor operstate says up. The SPAN link is down. |
| `STOP-eno1-has-address` | `eno1np0` has an address. It must have none. |
| `STOP-xdp-attached-already` | An XDP program is already on `eno1np0` (`ip -d link`). Unexpected after step 11. |
| `STOP-driver-not-ice` | `ethtool -i` says the driver is not `ice`. |
| `STOP-ethtool-i` | `ethtool -i` failed. |
| `STOP-ddp-safe-mode` | The kernel log for this boot has a safe-mode line. Native XDP would be refused. Not a cue to download COMMS. |
| `STOP-no-capture-cores` | `/etc/johnny/capture-cores` is missing or unreadable. |
| `STOP-capture-cores-form` | A line in that file is not a CPU number. |
| `STOP-no-queue-irqs` | No `ice-eno1np0-TxRx-N` IRQ found in `/proc/interrupts`. |
| `STOP-irq-baseline-outside-capture-cores` | A queue IRQ's effective CPU is outside `capture-cores`. The step 13 pins are not as recorded, so the 1b before/after check has no baseline. Fix the pins first (step 13 runbook); this slice does not. |
| `STOP-kconfig-bpf-syscall` | `CONFIG_BPF_SYSCALL` is not `y`. |
| `STOP-kconfig-ice` | `CONFIG_ICE` is neither `y` nor `m`. |
| `STOP-suricata-enabled`, `STOP-suricata-active` | Suricata is enabled or running. It stays disabled until a capture point exists. |
| `STOP-no-xdp-prog-type` | Root probe: the kernel does not report the XDP program type as available. |
| `STOP-feature-json-parse`, `STOP-helper-json-parse`, `STOP-net-json-parse` | Root probe: a bpftool JSON output did not parse. The raw file is in `/root/m1s1-probe-root/`. |
| `STOP-feature-probe-failed`, `STOP-net-show-failed` | Root probe: that bpftool command failed. |
| `STOP-xdp-attached-on-eno1np0` | Root probe: `bpftool net show` lists an XDP program on `eno1np0`. The mode is printed after it. |

`NOTE-` lines are findings and never block the token. The ones most likely to matter: `NOTE-mtu-not-1500`, `NOTE-span-quiet`, `NOTE-lro-on`, `NOTE-rxvlan-on`, `NOTE-queue-irq-mismatch`, `NOTE-zc-one-xsk-per-queue`, `NOTE-no-af-xdp`, `NOTE-ddp-line-not-found`, `NOTE-journal-unreadable`, `NOTE-kernel-changed`, `NOTE-lockdown-not-integrity`, `NOTE-feature-key-absent`, `NOTE-cmd-failed`, `NOTE-apt-lists-not-refreshed`.

## Rollback

None needed. Neither paste changes Johnny's configuration. Ctrl-C leaves a partial output directory and no DONE token. Do not run `/root/step11-revert.sh` or `/root/step13-revert.sh`: nothing they cover moved.

The only files written are the copy at `/home/aj/cis-audit/module1-slice1-probe.sh`, the output directory `/home/aj/cis-audit/m1s1-probe/`, and (Paste 2) `/root/m1s1-probe-root/`. Delete any of them at will.

## What comes after (sketch only: not drafted, not reviewed, not applied)

The next paste, **1b**, would attach a permanent native-XDP observer. It needs the probe's answers first, and a build host with clang (Johnny has none recorded; the handoff says the step 11 object was built off-box). A sketch, to show what the probe is for. None of this is approved:

1. Preconditions re-checked (everything above, `OK` or `NOTE`).
2. Snapshot IRQ affinity for the twelve queues. Attach with `bpftool net attach xdpdrv` only. Re-snapshot. A changed mask is a stop; recovery is `/etc/johnny/irq-affinity.sh apply` (what `johnny-capture-irq.service` runs). Detach on any failure.
3. Decide how the program survives a reboot: a unit that attaches after `johnny-capture-irq.service`, with its own bounded wait (the lesson of the 13b–13d boot race: `network-online.target` gates nothing here because `systemd-networkd-wait-online` is skipped).
4. Compare the observer's counters with `ethtool -S` and a short `tcpdump -c` (the AF_PACKET cross-check).
5. A rollback that detaches and unpins, installed before the attach (the step 11 pattern).

Open questions for AJ or the architecture pass, not answered here: what the observer records (counters only, or header-only records via a ring buffer); whether flows need both directions on one queue (symmetric RSS); netlink attach versus a pinned `bpf_link` for the lifecycle; and when AF_XDP, and which consumer, enters.

## Assumptions (all marked above, collected)

- MTU is still 1500; the probe measures it.
- Unicast not addressed to Johnny is dropped before `rp_filter` (carried from step 11).
- `ice` behaviour with LRO and VLAN offload as it affects XDP: not read from source.
- A first XDP attach may disturb the IRQ pins: unverified; tested in 1b.
- UMEM accounting (memlock vs cgroup) on this kernel: unverified.
- bpftool JSON key names: from memory, not a live capture. Fixtures in the self-test are the same: illustrative, not live.
- `ethtool -S`, `-x`, `-n`, `--show-priv-flags` and `ss -f xdp` work as `aj`; the probe prints `NOTE-cmd-failed` or `NOTE-ss-xdp-unavailable` if not.
- Apt candidates come from cached lists that this probe does not refresh (rev 93: lists about a day old at that check).
- The Ubuntu `stonking` man pages cited for bpftool are not the `resolute` pages.

## Sources

- ice driver: XDP frame limit, AF_XDP zero-copy support, DDP safe mode: <https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html>
- ice XDP multi-buffer receive patch, Jan 2023 posting (kernel release not confirmed): <https://lists.openwall.net/netdev/2023/01/31/419>
- AF_XDP: per-queue binding, `XDP_ZEROCOPY` / `XDP_COPY`, `XSKMAP`, `need_wakeup`, shared UMEM: <https://docs.kernel.org/networking/af_xdp.html>
- `bpftool net attach` modes (`xdp` falls back to generic; `xdpdrv` does not): <https://man.archlinux.org/man/bpftool-net.8.en>
- `bpftool feature probe` and the `full` keyword: <https://manpages.ubuntu.com/manpages/stonking/man8/bpftool-feature.8.html>
- Kernel lockdown (BPF among restricted features): <https://man7.org/linux/man-pages/man7/kernel_lockdown.7.html>; BPF read-helper restriction history: <https://lore.kernel.org/netdev/alpine.LRH.2.21.1906270621080.28132@namei.org/T/>
- BPF memory accounting (memlock vs cgroup, 5.11): <https://docs.ebpf.io/linux/concepts/resource-limit/>
- Resolute packages: <https://packages.ubuntu.com/search?keywords=libbpf&searchon=names&suite=resolute&section=all>, <https://packages.ubuntu.com/search?keywords=libxdp&searchon=names&suite=resolute&section=all>
- Repo: `docs/tool-install/step-11-e810-capture.md`, `docs/tool-install/step-13-irq-affinity.md`, `docs/findings/overseer-review-os-gate.md` §5 and §8, `docs/os-handoff.md` rev 95.
