# Module 1, slice 1 — passive SPAN / XDP path on `eno1np0` (probe applied; no attach)

Rev 2, 2026-11-06 ~16:05Z (~10:05 America/Chicago). **The read-only probe (Paste 1 and Paste 2) has been applied on Johnny. Nothing is attached: no XDP program, no AF_XDP socket, no config change. Module 1 is still unattached, and no attach paste (1b) is drafted.** Rev 1 (2026-11-06 06:20Z, 00:20 America/Chicago) was the draft. Written by the code-writer seat (Sonnet). Whether the adversarial-reviewer re-reviewed the exact pastes after the B1/B2 fix is **not recorded in the repo** (handoff rev 97 said not re-reviewed); both pastes are read-only. Docs, one script, one self-test. The probe script is unchanged since rev 1's fix round (sha256 below).

AJ said **go** on Module 1 (2026-11-05 evening America/Chicago). The OS gate is APPROVED (handoff rev 95, `docs/findings/overseer-review-os-gate.md` §8). This file is the first Module 1 artifact.

**In plain English.** The mirror port already delivers copies of LAN traffic to `eno1np0`. Step 11 proved Johnny can run a tiny program inside the NIC driver for a few seconds. Slice 1 turns that into a permanent, passive "watcher" that counts and describes packets without keeping them. Before any permanent attach, this file did one safe thing first: **ask the machine what it can do** (read-only, no changes). That has now been done and the answers are below. The next open item is AJ confirming the path choice; the attach paste (1b) is drafted only after that.

## Applied on Johnny (probe, read-only), 2026-11-06

AJ ran both pastes from **rock-box** (`aj-rock-box`), over SSH to Johnny, on 2026-11-06 about 09:57 to 10:00 CT (America/Chicago, CST, UTC-6). Paste 2 has to be rock-box to Johnny: its one password prompt is Johnny's `sudo -v` inside the `ssh -t` line, and nothing runs `sudo` on rock-box. Both pastes were the blocks below (**[Assumption]** as in the repo at tip `9a10212`; each block checks the script hash before running it, and Johnny's copy matches, see below). Source of the lines below: AJ's pasted terminal output (relayed in the closeout brief). Lines marked "(read-only SSH)" are from the code-writer seat reading Johnny's `/home/aj/cis-audit/m1s1-probe/summary.txt` with `grep` at 2026-11-06 ~16:01Z (no write, no sudo). That file repeats the lines Paste 1 printed (runbook design); **[Assumption]** it is unedited since the run, its mtime is 15:57:23Z.

| Paste | Mode | Token | `DATE-UTC` | Result |
|---|---|---|---|---|
| 1 | `user` (as `aj`, no sudo) | **`M1S1-PROBE-DONE`** | `2026-11-06T15:57:17Z` (09:57 CT) | No `STOP-` lines |
| 2 | `root` (`bpftool` only, sudo on Johnny) | **`M1S1-PROBE-ROOT-DONE`** | `2026-11-06T15:59:11Z` (09:59 CT) | No `STOP-` lines |

Johnny's copy of the script at `/home/aj/cis-audit/module1-slice1-probe.sh` has sha256 `93d6253720dab71f1b7cc63704f844068daa2c54f7ad78922c9751ebf44fba47` (read-only SSH, 16:01Z; mtime 15:59:06Z, which is Paste 2's `scp` over Paste 1's copy). It equals the repo file. I did not read `/root/m1s1-probe-root/` (root only); the Paste 2 lines below are AJ's.

### What Paste 1 found

| Area | Recorded line(s) | What it says |
|---|---|---|
| Host, kernel | `HOST johnny`, `KERNEL 7.0.0-42-generic` | Unchanged since step 11 and step 13 |
| Link | `LINK eno1np0 flags=0x1183 mtu=1500 speed=10000 carrier=1 oper=up`; `OK-mtu-1500`; `OK-no-address`; `OK-no-xdp-attached` | Up, 10G, MTU 1500 (**measured**; the MTU assumption is retired), no address. `0x1183` is UP, BROADCAST, NOARP, PROMISC, MULTICAST. `ip -d link` shows no XDP program on it. |
| Driver, DDP | `DRIVER ice`; DDP "ICE OS Default" `1.3.43.0`; `OK-ddp-loaded` | Not in safe mode this boot. (read-only SSH) the kernel log lines are `The DDP package was successfully loaded` on `0000:01:00.0` and `DDP package already present` on `0000:01:00.1`, boot of 2026-11-06 01:55Z. No COMMS package. |
| Offloads | `NOTE-rxvlan-on` | VLAN tags may be stripped before XDP sees the frame (**[Assumption]**, `ice` behaviour not read from source; unchanged). A finding, not a stop. |
| SPAN traffic | `OK-span-traffic`, `RX-RATE-5S pps=568 mbit=1` | The mirror is alive. One 5-second sample, light load. |
| Martians | `MARTIAN-COUNT 3478` | Same all-boots `journalctl -k` count as step 11 per the runbook table (2475, then 2477 on 2026-11-05 ~08:26 CT). Up by about 1000 since. Note only; this probe does not say what rate or why. |
| Capture cores, IRQ pins | `CAPTURE-CORES 1,2,3,4`; twelve `ice-eno1np0-TxRx-*` IRQs effective on CPUs 1 to 4; `OK-irq-pins total=12` | Step 13 pins hold (boot at 2026-11-06 01:55Z, after step 13f). This is the baseline for the 1b before/after check. |
| Queues | (read-only SSH) `QUEUES-COMBINED max=24 cur=12`; `ZC-QUEUES queues=12 cores=4`; `NOTE-zc-one-xsk-per-queue` | Twelve queues on four cores. AF_XDP binds one socket to one queue id, so AF_XDP is twelve sockets or a queue-count change (the step 13 pins would likely not survive that, **[Inference]**, unchanged). |
| Kernel config | `KCONFIG` `BPF_SYSCALL`, `XDP_SOCKETS`, `ICE`, `BTF` ok | `XDP_SOCKETS` is enabled; AF_XDP is not ruled out at config level. Zero-copy on Johnny is still untested. |
| Lockdown | `LOCKDOWN integrity` | Unchanged, not weakened. |
| BPF environment | (read-only SSH) `BTF-VMLINUX present`; `BPFFS` bpf, mode=700; `kernel.unprivileged_bpf_disabled 2`; `net.core.bpf_jit_enable 1`; `NOTE-sysctl-unreadable net.core.bpf_jit_harden` (as `aj`) | bpffs is mounted with mode 700, so pinning there is root only. The JIT is on. |
| Memory inputs | (read-only SSH) `ULIMIT-L-AJ 8192` (KB); `HUGEPAGES total=0`; `MEM-AVAILABLE-MB 24564` | Inputs for any UMEM sizing. Whether UMEM is charged to memlock or the memory cgroup on this kernel is **still unverified**. |
| Units | `UNIT suricata disabled/inactive`; `johnny-capture-irq` and `johnny-capture-tuning` enabled/active | Suricata still off; the two capture units are enabled and active. (read-only SSH) `irqbalance` is `not-found`/`inactive`. |
| Toolchain | `BPFTOOL bpftool v7.7.0` at `/usr/sbin/bpftool`; `PKG-ABSENT` and `APT-CANDIDATE` recorded | **No build tools on Johnny.** (read-only SSH) `TOOL-ABSENT`: `clang`, `llc`, `gcc`, `make`, `pahole`, `xdp-loader`, `xdpdump`, `xdp-bench`. Installed: `libbpf1` 1:1.6.3-1ubuntu1, `libxdp1` 1.6.2-1ubuntu1. `PKG-ABSENT`: `libbpf-dev`, `libxdp-dev`, `xdp-tools`, `clang`, `llvm`, `gcc`, `libelf-dev` (and `make` is not installed). `APT-CANDIDATE` (cached lists, not refreshed: `NOTE-apt-lists-not-refreshed`): `clang` and `llvm` 1:21.1.6-71, `gcc` 4:15.2.0-5ubuntu1, `make` 4.4.1-3, `libelf-dev` 0.194-4, `libbpf-dev` 1:1.6.3-1ubuntu1, `libxdp-dev` and `xdp-tools` 1.6.2-1ubuntu1. |

The brief called the toolchain "mostly absent"; the read-only SSH lines show every compiler and loader tool probed is absent and `bpftool` is the one tool present. I did not read the `FEATURE`, `RING`, `RSS-HASH`, `RX-RULES`, `PRIV`, `STAT` or `FIRMWARE` lines; they are in `summary.txt` on Johnny and in AJ's terminal output.

### What Paste 2 found (AJ's relay)

- `have_xdp_prog_type yes`; `have_xskmap_map_type yes`.
- Helpers: `bpf_redirect_map` yes, `bpf_xdp_adjust_head` yes, and others (the full `BPF-XDP-HELPER` list was not transcribed into the closeout brief; it is in AJ's terminal output).
- `OK-no-xdp-on-eno1np0` (`bpftool net show`) and `PROG-XDP-COUNT 0` (`bpftool prog show`: no XDP-type program is loaded anywhere). Nothing attached, nothing loaded.
- The key-name assumption is **partly retired**: the keys for the XDP program type, `XSKMAP` and the helpers named above resolved on the live kernel. AJ reported no STOP lines; whether any `NOTE-feature-key-absent` line printed for other keys is not in the brief.

### What this probe did not settle

- Whether a first native XDP attach on `ice` moves the step 13 IRQ pins. A read-only probe cannot test it. It stays the 1b before/after check.
- UMEM memory accounting (memlock vs cgroup) on this kernel.
- AF_XDP zero-copy on this NIC, kernel and MTU (not attempted, by design).
- Where the XDP object is built: Johnny has no compiler (step 11's object was built off-box, handoff). Building off-box, or a separate reviewed apt install on Johnny, is a 1b input. **Not decided here.**
- The path choice itself (below). It is a draft recommendation; **AJ's confirmation is the next open item.** This file does not claim the probe results confirm the choice; they are inputs for AJ.

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

Probe script sha256 (the self-test requires this line to match the file): `93d6253720dab71f1b7cc63704f844068daa2c54f7ad78922c9751ebf44fba47`

## Preconditions

- This branch checked out at `/home/aj/Projects/strix-halo-johnny` on rock-box. **[Assumption]** that is still the rock-box checkout (`docs/agent-team.md`).
- Johnny up, SSH key login working. The SPAN should be up (SFP+7 → `eno1np0` at 10000) so the 5-second sample can see traffic; a quiet SPAN prints `NOTE-span-quiet` and is not a stop.
- Paste 1 needs no second session and no KVM: it changes nothing. Paste 2 changes nothing either.

## Paste 1 (as `aj`, no sudo)

**Applied 2026-11-06 ~09:57 CT, printed `M1S1-PROBE-DONE`.** Kept for the record; re-running is read-only and is not needed for this closeout.

One block, from the rock-box checkout. It copies the script, checks its hash on Johnny, and runs it as `aj`. About 10 seconds (includes a 5-second sample).

```bash
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1-probe.sh aj@192.168.50.152:/home/aj/cis-audit/module1-slice1-probe.sh
ssh aj@192.168.50.152 'echo "93d6253720dab71f1b7cc63704f844068daa2c54f7ad78922c9751ebf44fba47  /home/aj/cis-audit/module1-slice1-probe.sh" | sha256sum -c - && bash /home/aj/cis-audit/module1-slice1-probe.sh user'
```

Success ends with `M1S1-PROBE-DONE`. Raw files: `/home/aj/cis-audit/m1s1-probe/` on Johnny (a previous run is moved aside to `m1s1-probe.prev.<UTC time>`). `summary.txt` there repeats every line printed. Raw files stay on Johnny and are not committed.

## Paste 2 (optional, sudo, bpftool facts)

**Applied 2026-11-06 ~09:59 CT from rock-box to Johnny, printed `M1S1-PROBE-ROOT-DONE`.** Kept for the record. It must be run from the rock-box checkout, not on Johnny: the block `scp`s the script from the rock-box path.

Do Paste 1 first. This adds what only root can read: which BPF program and map types the running kernel offers, and whether anything is attached to `eno1np0`. It writes only under `/root/m1s1-probe-root/` and attaches nothing. Every `sudo` here runs on **Johnny**, inside the last `ssh -t` line, so the one password prompt is Johnny's, up front (`sudo -v`, then the hash check, then the script). Nothing in this block runs `sudo` on rock-box.

```bash
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1-probe.sh aj@192.168.50.152:/home/aj/cis-audit/module1-slice1-probe.sh
ssh -t aj@192.168.50.152 'sudo -v && echo "93d6253720dab71f1b7cc63704f844068daa2c54f7ad78922c9751ebf44fba47  /home/aj/cis-audit/module1-slice1-probe.sh" | sha256sum -c - && sudo bash /home/aj/cis-audit/module1-slice1-probe.sh root'
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

**Update (2026-11-06, after AJ said go on 1b):** slice 1b is now **drafted, not applied, not reviewed** in its own file: [`module1-slice1b-attach.md`](module1-slice1b-attach.md) (permanent native-XDP observer, always `XDP_PASS`, off-box build, attach, verify, detach). Where the sketch below differs from that file, the 1b file wins. Its step 3 (boot persistence) is **not** drafted. This file's probe pastes are unchanged.

**Next open item: AJ confirms the path choice** (the Decision section above is a draft recommendation, not his decision). Then the attach paste **1b** is drafted in its own PR. It would attach a permanent native-XDP observer. The probe is applied; its answers include that Johnny has **no compiler** (clang, llc, gcc, make, pahole all `TOOL-ABSENT`; the handoff says the step 11 object was built off-box), so 1b needs an off-box build or a separately reviewed apt install. Nothing is attached today. A sketch of 1b, as it stood in rev 1. None of this is approved:

1. Preconditions re-checked (everything above, `OK` or `NOTE`).
2. Snapshot IRQ affinity for the twelve queues. Attach with `bpftool net attach xdpdrv` only. Re-snapshot. A changed mask is a stop; recovery is `/etc/johnny/irq-affinity.sh apply` (what `johnny-capture-irq.service` runs). Detach on any failure.
3. Decide how the program survives a reboot: a unit that attaches after `johnny-capture-irq.service`, with its own bounded wait (the lesson of the 13b–13d boot race: `network-online.target` gates nothing here because `systemd-networkd-wait-online` is skipped).
4. Compare the observer's counters with `ethtool -S` and a short `tcpdump -c` (the AF_PACKET cross-check).
5. A rollback that detaches and unpins, installed before the attach (the step 11 pattern).

Open questions for AJ or the architecture pass, not answered here: what the observer records (counters only, or header-only records via a ring buffer); whether flows need both directions on one queue (symmetric RSS); netlink attach versus a pinned `bpf_link` for the lifecycle; and when AF_XDP, and which consumer, enters.

## Assumptions (collected; status after the 2026-11-06 apply)

- ~~MTU is still 1500~~ **Retired:** measured `mtu=1500`, `OK-mtu-1500`.
- Unicast not addressed to Johnny is dropped before `rp_filter` (carried from step 11).
- `ice` behaviour with LRO and VLAN offload as it affects XDP: not read from source.
- A first XDP attach may disturb the IRQ pins: unverified; tested in 1b.
- UMEM accounting (memlock vs cgroup) on this kernel: unverified.
- bpftool JSON key names: **partly retired.** The keys for the XDP program type, `XSKMAP` and the helpers named in the Paste 2 result resolved live. The rest are unconfirmed from the brief. Fixtures in the self-test are still illustrative, not live captures.
- `ethtool -S`, `-x`, `-n`, `--show-priv-flags` and `ss -f xdp` work as `aj`: **no `NOTE-cmd-failed` or `NOTE-ss-xdp-unavailable` line appears among the `NOTE-` lines in Johnny's `summary.txt`** (read-only SSH grep of `^NOTE-`, 2026-11-06 ~16:01Z). Not retired for the unread `FEATURE`/`RING`/`RSS-HASH`/`RX-RULES`/`PRIV` lines' content, only for failure.
- Apt candidates come from cached lists that this probe does not refresh (rev 93: lists about a day old at that check). The probe printed `NOTE-apt-lists-not-refreshed`; the candidate versions above may be stale.
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
