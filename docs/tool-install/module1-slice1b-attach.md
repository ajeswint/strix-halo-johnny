# Module 1, slice 1b — passive observe-only native-XDP attach on `eno1np0` (applied; boot persistence by slice 1c)

Rev 2, 2026-11-06 ~19:50Z (~13:50 America/Chicago). Status: **applied on Johnny (2026-11-06 apply was boot-only; boot persistence now comes from slice 1c).** AJ ran Pastes 1–5 from rock-box on 2026-11-06 ~13:42 America/Chicago (CST, UTC-6; `M1S1B-ATTACH-START DATE-UTC 2026-11-06T19:42:48Z`). Tokens: **`SELF-TEST-OK`**, **`M1S1B-COPY-DONE`**, **`M1S1B-INSTALL-DONE`** (includes **`M1S1B-DETACH-DONE`** on the pre-attach clean box), **`M1S1B-ATTACH-DONE`**, and **`M1S1B-VERIFY-DONE`** (includes two **`M1S1B-STATUS-DONE`** reads 10 s apart). No `STOP-` line in any paste. On 2026-11-06 this slice attached Module 1 on `eno1np0` in native driver mode (`xdpdrv`, `prog_id=472`, `j_xdp_observe`, tag `b5b852630d7539c7`) for that boot only; no boot unit existed then. **Live state is slice 1c:** after the 2026-11-08 cold boot `johnny-capture-xdp.service` attached the observer as `xdpdrv` `prog_id=75`, and a reboot re-attaches it while the unit is enabled. One open observation is recorded below: `nic-rx-dropped-delta=4` in the 10 s attached observe window versus `0` in the 5 s pre-attach baseline window (`NOTE-nic-rx-dropped-up`), while `tcpdump` reported `0 packets dropped by kernel`. PR #24 (`claude/module1-slice1b-attach` tip `2960be2`, merged to `claude/practical-ritchie-4c6vvf` at `9c79ce3`) was reviewed by the adversarial-reviewer with verdict **APPROVE-WITH-NITS** before AJ ran the pastes; its three wording-only soft nits are folded in this revision. Object, attach, detach, self-test, and IRQ-helper scripts and their sha256 pins are **unchanged**. Rev 1 (2026-11-06 ~18:55Z, ~12:55 America/Chicago) was the draft (Status: **drafted, not applied.**). **Rev 3 (2026-11-08 UTC, docs only):** boot persistence is now applied by slice 1c ([`module1-slice1c-boot-unit.md`](module1-slice1c-boot-unit.md)); `johnny-capture-xdp.service` calls this slice's pinned attach script at boot. `prog_id=472` was this boot's id only and is gone after the 2026-11-08 cold reboot; the boot-attached id is now `75`. Live-state sentences below that said a reboot clears the attach are updated to point at the slice 1c Rollback block; sentences that describe the 2026-11-06 run, or text the unchanged script prints, keep their original meaning. This slice's scripts and pins are unchanged.

AJ said **go** on slice 1b (2026-11-06 America/Chicago). That confirms the path choice in `docs/tool-install/module1-slice1-span-xdp.md`: **a permanent native-XDP observer, always `XDP_PASS`.** This file does not reopen it.

**In plain English.** The mirror port already delivers copies of LAN traffic to `eno1np0`. This slice puts a tiny program inside the network card's driver that **counts** what goes by (frames, bytes, what kind of traffic, which receive queue) and then lets every frame carry on exactly as before. It keeps no packet contents and cannot drop or change a frame. The risky part is not the program, it is what the first attach does to the card (its queues, its link, the CPU pins from step 13). So the paste checks all of that before it attaches, checks it again after, and takes the program back off by itself if anything moved. On 2026-11-06 (~13:42 CT) AJ ran the pastes: the kernel verifier accepted the program (`prog_id=472`), native `xdpdrv` attached without moving the twelve step 13 IRQ pins, `tcpdump` continued to see traffic (`PASS-RATIO pct=90`, `0 packets dropped by kernel`), and the program stayed attached for that boot (since 2026-11-08 the slice 1c unit re-attaches it at every boot).

## Applied on Johnny (2026-11-06 ~13:42 America/Chicago)

AJ ran Pastes 1–5 from **rock-box** (`aj-rock-box`) to Johnny (`192.168.50.152`) on 2026-11-06 ~13:42 America/Chicago (CST, UTC-6) against base tip `9c79ce3` (PR #24 merged into `claude/practical-ritchie-4c6vvf`). Paste 6 (detach / rollback) was not run, leaving the observer attached for the rest of that 2026-11-06 boot.

| Paste | Where | Token(s) | Key evidence |
|---|---|---|---|
| 1 | Rock Box | **`SELF-TEST-OK`** | Three `OK` sha256 checks (`PINS-OK obj=8be9877f… attach=f9f95ec6… detach=f78ca14e…`); `SHELLCHECK-OK`; `PROGRAM-SOURCE-OK returns=5`; `ENUM-ORDER-OK pkts bytes ipv4 ipv6 arp other trunc vlan tcp udp icmp l4_other`; `OK-rebuild-reproducible Ubuntu clang version 22.1.8 (1ubuntu1)`; `OBJECT-DISASM-OK exits=1 calls=call 0x1; r0=w0 = 0x2;`; `OBJECT-LIBBPF-PARSE-OK (bpftool v7.8.0)`; `STATIC-INVOCATIONS-OK 7`; `UNIT-TESTS-OK`; `GATES-OK`; `E2E-OK scenarios=30`; `PASTE-SHAPE-OK rock=3 johnny=5`; `RUNBOOK-OK`. |
| 2 | Rock Box → Johnny (`scp`) | **`M1S1B-COPY-DONE`** | Copied `module1-xdp-observe.o`, `module1-slice1b-attach.sh`, `module1-slice1b-detach.sh` to `/home/aj/cis-audit/`; all three sha256 checks `OK`. |
| 3 | Johnny (`sudo` via `ssh -t`) | **`M1S1B-DETACH-DONE`**, **`M1S1B-INSTALL-DONE`** | Installed root-owned `0700` copies under `/root/m1s1b/`, verified all three hashes in `/home/aj/cis-audit/` and `/root/m1s1b/`. Pre-attach `bpftool net show`: `xdp:`, `tc:`, `flow_dissector:`, `netfilter:` all `(empty)`. Clean-box detach run: `NOTHING-ATTACHED`, `OK-no-xdp-on-eno1np0`, `NOTE-no-final-stats`, `PINS-ABSENT`, `OK-no-j_xdp_observe-loaded`, `PROG-XDP-COUNT 0`, `IRQ-PINS-OK (inside capture cores; no attach baseline file)`, `LINK eno1np0 flags=0x1183 speed=10000 carrier=1 oper=up mtu=1500`. |
| 4 | Johnny (`sudo` via `ssh -t`) | **`M1S1B-ATTACH-DONE`** | `M1S1B-ATTACH-START DATE-UTC 2026-11-06T19:42:48Z`; `OK-object-hash 8be9877f…`, `OK-rollback-hash f78ca14e…`, `OK-irq-helper-hash db58d7c7…`; `OK-link LINK eno1np0 flags=0x1183 speed=10000 carrier=1 oper=up mtu=1500`; `OK-eno3`; `OK-suricata disabled/inactive`; `COMBINED-BEFORE 12`; `IRQ-BASELINE-SAVED /root/m1s1b/irq-baseline.txt`; `IRQ-BEFORE ice-eno1np0-TxRx-0..11` on `aff=1,2,3,4` / `eff=1,2,3,4` repeating (`irq=189..200`); `BASE-WINDOW secs=5 tcpdump-captured=640 nic-rx-delta=715 nic-rx-dropped-delta=0`; `LOADED prog_id=472 (verifier accepted; not attached yet)`; `OK-readback-parse`; `ATTACHED xdpdrv prog_id=472`; `OK-xdp-mode driver id=472 (just-attached)`; `OK-irq-pins-unchanged (just-attached)`; `OK-link-queues-eno3 (just-attached) combined=12`; `OBS-WINDOW secs=10 xdp-pkts-delta=1599 xdp-pps=159 xdp-avg-bytes=495 tcpdump-captured=1444 nic-rx-delta=1618 nic-rx-dropped-delta=4`; `PASS-RATIO tcpdump=1444 xdp=1599 pct=90`; `NOTE-nic-rx-dropped-up delta=4`; `OK-xdp-pass-tcpdump-sees-traffic`; `OK-xdp-mode driver id=472 (after-window)`; `OK-irq-pins-unchanged (after-window)`; `OK-link-queues-eno3 (after-window) combined=12`; `OK-partition l3_diff=0 l4_diff=0`; `IRQ-AFTER ice-eno1np0-TxRx-0..11 unchanged`; `PROG-XDP-COUNT 1`; `STAT pkts 1679`, `bytes 812579`, `ipv4 1678`, `ipv6 0`, `arp 0`, `other 1`, `trunc 0`, `vlan 0`, `tcp 791`, `udp 717`, `icmp 168`, `l4_other 2`; `PART l3_diff=0 l4_diff=0`; `STAT-RXQ 0..11 present (sum matches)`; `STATE attached, native (driver) mode, for this boot only; nothing re-attaches it at boot.` |
| 5 | Johnny (`sudo` via `ssh -t`) | **`M1S1B-STATUS-DONE`** (×2), **`M1S1B-VERIFY-DONE`** | `bpftool net show`: `xdp: eno1np0(4) driver id 472`. `bpftool prog show name j_xdp_observe`: `472: xdp  name j_xdp_observe  tag b5b852630d7539c7  gpl`, `loaded_at 2026-11-06T19:42:53+0000  uid 0`, `xlated 3256B  jited 1899B  memlock 4096B  map_ids 64,65`, `btf_id 187`. First `status`: `HOST johnny`, `KERNEL 7.0.0-42-generic`, `XDP-ATTACH driver id=472`, `PROG-XDP-COUNT 1`, `PROG-OURS 1 ids=472`, `PINS dir=present prog=present stats=present rxq=present`, `LINK eno1np0 flags=0x1183 speed=10000 carrier=1 oper=up mtu=1500`, `IRQ-COUNT 12`, `IRQ-CAPTURE ok`, `IRQ-BASELINE same`, `STAT pkts 5172`, `STAT bytes 2364616`, `PART l3_diff=0 l4_diff=0`. Second `status` (10 s later): `XDP-ATTACH driver id=472`, `PROG-XDP-COUNT 1`, `IRQ-CAPTURE ok`, `IRQ-BASELINE same`, `STAT pkts 6947` (+1775 pkts), `STAT bytes 3503329` (+1138713 B). `ip -d link show eno1np0`: `<BROADCAST,MULTICAST,NOARP,PROMISC,UP,LOWER_UP> mtu 1500 xdp ... prog/xdp id 472`. `tcpdump` 5 s: `567 packets captured`, `635 packets received by filter`, **`0 packets dropped by kernel`**. |

### Open observation: `nic-rx-dropped-delta=4` in the 10 s observe window

In Paste 4, the 5 s pre-attach baseline window (`BASE-WINDOW`) recorded `nic-rx-dropped-delta=0` (`nic-rx-delta=715`, `tcpdump-captured=640`), whereas the 10 s post-attach observe window (`OBS-WINDOW`) recorded `nic-rx-dropped-delta=4` (`nic-rx-delta=1618`, `xdp-pkts-delta=1599`, `tcpdump-captured=1444`, `PASS-RATIO pct=90`), emitting `NOTE-nic-rx-dropped-up delta=4 (compare BASE-WINDOW nic-rx-dropped-delta)`. In Paste 5, the 5 s `tcpdump` run reported `567 packets captured`, `635 packets received by filter`, and `0 packets dropped by kernel`.

- This is recorded as an **open observation**, not a `STOP-` condition.
- No root cause is claimed here (the script reads `/sys/class/net/eno1np0/statistics/rx_dropped` across one 5 s pre-attach sample and one 10 s post-attach sample right after `bpftool net attach xdpdrv`, without per-reason `ethtool -S` deltas or longer baseline sampling), and it is neither claimed as a regression nor dismissed.

### Attachment state (boot persistence now by slice 1c)

As applied on 2026-11-06, this slice attached the observer (`j_xdp_observe`, `prog_id=472`, pinned under `/sys/fs/bpf/johnny_m1s1b/`) for that boot only. Slice 1c (`johnny-capture-xdp.service`, [`module1-slice1c-boot-unit.md`](module1-slice1c-boot-unit.md)) is applied: on every boot it runs this slice's pinned attach script after `johnny-capture-irq.service`. After the 2026-11-08 cold reboot the observer is attached as `xdpdrv` `prog_id=75`; `472` is gone. To detach, use the slice 1c Rollback block (`systemctl disable --now johnny-capture-xdp.service`, which runs this slice's detach script); running Paste 6 alone detaches only until the next boot.

## What is in this slice

| Piece | File | Notes |
|---|---|---|
| XDP program (source) | `docs/tool-install/module1_xdp_observe.c` | Counters only. One `return`, and it is `XDP_PASS`. |
| XDP program (object) | `docs/tool-install/module1-xdp-observe.o` | Built off-box on rock-box. sha256 pinned below. |
| Attach script | `docs/tool-install/module1-slice1b-attach.sh` | Runs as root on Johnny, from a root-owned copy. sha256 pinned. |
| Detach and status script | `docs/tool-install/module1-slice1b-detach.sh` | Installed **before** the attach (step 11 pattern). sha256 pinned. |
| Self-test | `docs/tool-install/module1-slice1b-self-test.sh` | Rock-box, no root, touches no NIC. |

Out of this slice, on purpose: a boot unit (this slice's files still omit one; boot persistence is the applied slice 1c unit `johnny-capture-xdp.service`, see [`module1-slice1c-boot-unit.md`](module1-slice1c-boot-unit.md)), AF_XDP sockets, a ring buffer, queue-count or MTU changes, any Suricata config, any `apt` on Johnny, any change to `eno3` or `eno2np1`, any change to the probe script (`module1-slice1-probe.sh` is untouched, sha256 `93d6253720dab71f1b7cc63704f844068daa2c54f7ad78922c9751ebf44fba47`).

## Live evidence this draft rests on (not re-probed)

All from the slice 1 probe applied 2026-11-06 ~09:57 to 10:00 CT (`docs/os-handoff.md` rev 98, `docs/tool-install/module1-slice1-span-xdp.md` rev 2). I did not re-run it. The only Johnny contact in this session was one read-only SSH line (`command -v` and `--version` for `tcpdump`, `dumpcap`, `python3`, `ethtool`, `timeout`, `flock`, `sha256sum`; `ls /sys/fs/bpf`, which `aj` cannot read; `id`). No write, no sudo.

| Fact | Value |
|---|---|
| Kernel | `7.0.0-42-generic`; lockdown `integrity` |
| bpftool | v7.7.0 at `/usr/sbin/bpftool` |
| Kernel offers | `have_xdp_prog_type yes`, `have_xskmap_map_type yes`, ringbuf yes, helpers `bpf_redirect_map`, `bpf_xdp_adjust_head`, `bpf_ringbuf_output` yes (this slice uses none of them) |
| Attach state today | `OK-no-xdp-on-eno1np0`, `PROG-XDP-COUNT 0` |
| `eno1np0` | `ice`, MTU 1500, flags `0x1183` (UP, PROMISC, NOARP), no address, 10000, SPAN traffic present (`RX-RATE-5S pps=568 mbit=1`) |
| IRQ pins (the baseline) | twelve `ice-eno1np0-TxRx-*` IRQs on CPUs 1 to 4 (`OK-irq-pins total=12`); `/etc/johnny/capture-cores` is `1 2 3 4` |
| Toolchain | **No compiler on Johnny** (`clang`, `llc`, `gcc`, `make`, `pahole`, `xdp-loader` all absent). Step 11's object was built off-box. This slice builds off-box too. |
| Suricata | `disabled` / `inactive` |
| Helper, cores | `/etc/johnny/irq-affinity.sh` sha256 `db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4`; `/etc/johnny/capture-cores` sha256 `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b` (both equal the repo mirrors under `etc/johnny/`) |
| Tools on Johnny | `tcpdump` 4.99.6, `python3`, `ethtool`, `timeout`, `flock`, `sha256sum` present (the paste needs them) |

## What the program counts

Per-CPU array maps, one slot per counter. Reading sums the CPUs. Classes are a partition, so the script can check the arithmetic.

| Slot | Name | Meaning |
|---|---|---|
| 0 | `pkts` | Every frame XDP sees |
| 1 | `bytes` | Sum of frame lengths as XDP sees them |
| 2 | `ipv4` | IPv4 ethertype (after up to two VLAN tags) and a full 20-byte fixed header present |
| 3 | `ipv6` | IPv6 ethertype and a full 40-byte fixed header present |
| 4 | `arp` | ARP ethertype |
| 5 | `other` | Any other ethertype |
| 6 | `trunc` | Too short to read the headers it needed |
| 7 | `vlan` | Frames that still carry a VLAN tag when XDP sees them (**not** part of the partition; the probe noted `rxvlan` is on, so most tags may already be stripped) |
| 8 to 11 | `tcp`, `udp`, `icmp`, `l4_other` | L4 class of every IPv4 and IPv6 frame (ICMP includes ICMPv6). IPv6 extension headers are not walked: such a frame is `l4_other`. |

Plus `m1_rxq`: a packet count per Rx queue index (64 slots; the card has 12 queues in use), so the counters can be lined up with the twelve IRQ pins.

Partition rule: `pkts = ipv4 + ipv6 + arp + other + trunc` and `ipv4 + ipv6 = tcp + udp + icmp + l4_other`. A live read is not exact (the slots are read one after another while frames arrive), so the attach script allows `max(256, 1% of pkts)`. The **detach** reads after the program is gone and requires an exact match (`FINAL-PARTITION-OK`, a note if not).

What the program reads: the Ethernet header, up to two VLAN tags, and one byte of the fixed IPv4 or IPv6 header (the L4 protocol number). It keeps no bytes and does not write to the frame. It uses one helper, `bpf_map_lookup_elem`. It has no `XDP_DROP`, `XDP_TX`, `XDP_REDIRECT` or `XDP_ABORTED`: the work is in a `void` function and the entry point's only `return` is `XDP_PASS`. A per-CPU slot has one writer, so the add is a plain add (the kernel page says the helpers "automatically access the slot for the current CPU", [map_array](https://docs.kernel.org/bpf/map_array.html); that no atomic is needed is **[Inference]**, the page does not say it).

## How a frame is kept visible: the cross-check

`bpftool net attach xdpdrv` is native XDP: it "runs earliest point in driver's receive path"; generic XDP runs "when packet already enters receive path as skb" ([bpftool-net man page](https://man.archlinux.org/man/bpftool-net.8.en)). `XDP_PASS` hands the frame on to the normal stack ([XDP actions](https://prototype-kernel.readthedocs.io/en/latest/networking/XDP/implementation/xdp_actions.html), a secondary reference, not kernel.org). **[Inference]** `tcpdump` (AF_PACKET) taps frames the stack received, so a frame the program dropped would never reach it. The attach script therefore runs `tcpdump` for 5 seconds **before** the attach and for 10 seconds **while attached**, and compares:

- `XDP counted > 0` and `tcpdump captured > 0` while attached: frames still reach the stack (`OK-xdp-pass-tcpdump-sees-traffic`).
- `XDP counted > 0` and `tcpdump captured = 0`: `STOP-pass-broken`. Rollback.
- NIC `rx_packets` rose but XDP counted nothing: `STOP-observer-no-count`. Rollback.
- `tcpdump` captured under 80% of what XDP counted: **a note**, not a stop (`tcpdump` starts a moment late and can drop under load). Both numbers are printed (`PASS-RATIO`). The 80% is my number, not a measurement.
- NIC `rx_dropped` delta is printed for the baseline window and the attached window (`BASE-WINDOW`, `OBS-WINDOW`); a rise is a note.

## What the first attach might do to the card (the reason for all the checks)

The ice driver is documented to support XDP and AF_XDP zero-copy, and to block XDP above 3 KB frames ([ice kernel doc](https://docs.kernel.org/networking/device_drivers/ethernet/intel/ice.html)); that page says nothing about queues or rings on attach. Patch threads show the driver has brought the interface down and up on an XDP program change, and later patches limited that to cases where it was needed ([lore thread on hot-swap](https://lore.kernel.org/all/87v8fogb7h.fsf@toke.dk/T/), [conditional restart commit](https://lab.nexedi.cn/kirr/linux/-/commit/04c7e14e5b0b6227e7b00d7a96ca2f2426ab9171)); I did not read `ice_main.c` for 7.0.0-42. **[Assumption]** the first attach may restart the card's queues and bounce the SPAN link for a moment, and may re-pin or re-number the queue IRQs. Step 11 attached and detached before step 13 pinned the IRQs, so the two have never run together. The script does not guess:

| Check | Before | After attach | After the 10 s window |
|---|---|---|---|
| The twelve `ice-eno1np0-TxRx-N` pins (affinity and effective CPU, per queue name) | saved to `/root/m1s1b/irq-baseline.txt`, printed as `IRQ-BEFORE` | must equal the baseline | must equal the baseline; printed as `IRQ-AFTER` |
| Link: up, 10000, `PROMISC`+`NOARP`+`UP`, MTU 1500, no address | read | read; waits up to 30 s for the link to return | read |
| `ethtool -l` combined channel count | recorded | must be unchanged | read via the same check |
| Attachment | `none`, `PROG-XDP-COUNT 0` | exactly `driver id=<ours>`, `PROG-XDP-COUNT 1` | same |
| `eno3` (mgmt) | `192.168.50.152` and the default route | same | same |

**Any change is a stop**: the script detaches, restores the pins with the step 13 helper if they moved, and ends `M1S1B-ATTACH-STOPS`. The recovery for moved pins is `/etc/johnny/irq-affinity.sh apply`, which is what `johnny-capture-irq.service` runs; the detach script does it for you (after checking the helper's sha256) and then compares to the baseline.

## Files, pins, hashes

| Item | sha256 |
|---|---|
| `module1-xdp-observe.o` | `8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d` |
| `module1-slice1b-attach.sh` | `f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb` |
| `module1-slice1b-detach.sh` | `f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58` |
| `module1_xdp_observe.c` (source, not copied to Johnny) | `3a0bf4698937864ec108478d40602d9bcfde81ee8c94c9ba4e58d4b137fa9ed7` |

The attach script embeds the object hash and the detach script hash and refuses to run if the root-owned copies on Johnny differ. The self-test requires every hash in this file to match the file.

| Path on Johnny | What |
|---|---|
| `/home/aj/cis-audit/` | the three files as `scp`'d (Paste 2); hash-checked, then installed |
| `/root/m1s1b/` (mode 0700, root) | the root-owned copies the pastes run: `module1-xdp-observe.o`, `module1-slice1b-attach.sh`, `module1-slice1b-detach.sh`; also `attach.log` (the attach transcript) and `irq-baseline.txt` (while attached) |
| `/sys/fs/bpf/johnny_m1s1b/` (bpffs, root only; mode 700 per the probe) | `prog` (the pinned program), `m1_stats`, `m1_rxq` (the pinned maps). Removed by detach. |
| `/run/johnny-m1s1b.lock` | one attach or detach at a time |

The scripts run from `/root/m1s1b/` (root-owned, 0700), not from `/home/aj/cis-audit/` as step 11's script did. The attach also refuses unless the files there are owned by root and not group- or world-writable.

## Build (off-box, rock-box)

Johnny has no compiler, so the object is built here and `scp`'d (as step 11). The committed object was built on rock-box (Ubuntu 26.10 `stonking`) with:

```text
Ubuntu clang version 22.1.8 (1ubuntu1)    (clang-22 1:22.1.8-1ubuntu1)
clang -O2 -g -Wall -Wextra -Werror -target bpfel -mcpu=v3 -ffile-prefix-map="$PWD"=. \
  -c docs/tool-install/module1_xdp_observe.c -o docs/tool-install/module1-xdp-observe.o
```

rock-box had no `clang`, so the compiler was unpacked, not installed (`apt-get download` needs no root; `dpkg-deb -x` into a fresh directory). Candidate version from `apt-cache policy clang-22` on rock-box. The program includes no kernel or libbpf headers (same style as step 11's `xdp_pass_count.c`), so the build does not depend on the distro's headers. `-target bpfel` pins little-endian; the source has `#error` for big-endian. `-ffile-prefix-map` plus compiling from the repo root with the relative path makes the object **reproducible from any checkout path**: I built it from two different directories and got the same hash. A different clang gives a different object; the pin is the committed `.o`, and the self-test does the rebuild comparison only when a clang is found (a difference is a note, not a failure).

**Optional, for the reviewer: reproduce the object.** Unprivileged, nothing is installed. It writes only to two fresh `/tmp` directories.

***<ins>Run on Rock Box</ins>***

```bash
D=$(mktemp -d /tmp/m1s1b-debs.XXXXXX)
R=$(mktemp -d /tmp/m1s1b-llvm.XXXXXX)
(cd "$D" && apt-get download clang-22 libclang-common-22-dev llvm-22)
for f in "$D"/*.deb; do dpkg-deb -x "$f" "$R"; done
cd /home/aj/Projects/strix-halo-johnny
"$R/usr/lib/llvm-22/bin/clang" -O2 -g -Wall -Wextra -Werror -target bpfel -mcpu=v3 -ffile-prefix-map="$PWD"=. -c docs/tool-install/module1_xdp_observe.c -o "$D/rebuilt.o"
sha256sum "$D/rebuilt.o" docs/tool-install/module1-xdp-observe.o
"$R/usr/lib/llvm-22/bin/llvm-objdump" -d --no-show-raw-insn docs/tool-install/module1-xdp-observe.o | grep -E 'call |w0 = |exit'
```

Expect the two hashes equal. The `grep` shows one `w0 = 0x2` (that is `XDP_PASS`), one `exit`, and only `call 0x1` (that is `bpf_map_lookup_elem`) repeated. **[Assumption]** `libclang-cpp22` and `libllvm22` are already installed on rock-box (they were, as `bpftrace` dependencies, 22.1.8-1ubuntu1); if not, `apt-get download` those two as well.

**Verifier status (retired on 2026-11-06 ~13:42 CT).** At draft time nobody could run `bpftool prog load` on rock-box without root. What was checked off-box: it compiles clean under `-Wall -Wextra -Werror`; libbpf on rock-box (bpftool v7.8.0 / libbpf v1.8) parses it (`bpftool gen skeleton` finds `m1_stats`, `m1_rxq` and `j_xdp_observe`); BTF shows two per-CPU array maps of 12 and 64 slots; the disassembly audit above. At Paste 4 on Johnny (`2026-11-06T19:42:48Z`), the kernel verifier accepted the object (`LOADED prog_id=472 (verifier accepted; not attached yet)`, `loaded_at 2026-11-06T19:42:53+0000`, `tag b5b852630d7539c7`, `xlated 3256B jited 1899B`, `map_ids 64,65`, `btf_id 187`). The program is small and follows the standard bounds-check pattern (every header read is preceded by a compare against `data_end`).

## Self-test (rock-box, no root, touches no NIC)

It runs both real scripts against a temp directory of fake `/proc` and `/sys` files and command shims (`bpftool`, `ip`, `ethtool`, `tcpdump`, `systemctl`, `journalctl`, `sleep`, `timeout`). The shims' JSON and text are **illustrative of each tool's documented format, not a live capture from Johnny.** What it checks:

- **Pins:** every hash in this file, in the scripts and in the pastes matches the files; the helper and cores hashes match the `etc/johnny/` mirrors.
- **Program:** no `XDP_DROP`, `XDP_TX`, `XDP_REDIRECT`, `XDP_ABORTED`, redirect, adjust, ring buffer, tail call or probe helper outside comments; exactly one `return XDP_PASS`; the only helper called is `bpf_map_lookup_elem`; the enum order equals the name table in the detach script. When `llvm-objdump` is found: the only call is helper 1, **every constant written to `r0` is 2**, no register is moved into `r0`, there is an `exit`. When `bpftool` is found: libbpf parses the object. When `clang` is found: the object rebuilds to the same hash.
- **Static invocations** (`STATIC-INVOCATIONS-OK`): every `bpftool`, `ip`, `ethtool`, `systemctl` line in both scripts is on an allowlist; the attach script has exactly one `net attach`, `xdpdrv`, with no `xdp`, `xdpgeneric` or `xdpoffload`; it never detaches (the rollback is the installed detach script); no `ip link set`, `ethtool` setter, `sysctl -w`, `apt`, `modprobe`, `systemctl` start/stop/enable/disable, `netplan`, `sudo`, reboot; `shellcheck` clean when available.
- **Parsers:** `bpftool -j net show`, `-j prog show` and the per-CPU map dump in both the BTF-formatted and raw shapes, bad shapes (exit 2); the IRQ snapshot, its numeric sort, and the capture-core membership rules.
- **Host gates:** on rock-box both scripts print `STOP-host` as the first line and change nothing.
- **End to end (30 scenarios):** the happy path; detach; a second detach (idempotent); a foreign XDP program (attach refuses, detach refuses to touch it); each pre-attach refusal (pins exist, no PROMISC, MTU, speed, IRQs outside the cores, eleven IRQs, no installed rollback, tampered rollback, tampered object, non-root-owned files, quiet SPAN, tcpdump blind); and, after the first change, every rollback: verifier refuses, attach refuses, attach lands in generic mode, IRQ pins moved (helper runs, baseline restored), queue count changed, tcpdump sees nothing, the program counts nothing, the partition is wrong, tcpdump fails while attached, `SIGTERM` mid-window, a detach that itself cannot finish (prints the manual command), counters still moving after detach. I also broke the scripts on purpose in a scratch copy (eleven mutations, such as dropping the IRQ baseline check, the rollback flag, the native-mode check, the frozen-counter check); the self-test caught every one.

**Applied 2026-11-06 ~13:42 CT on rock-box, printed `SELF-TEST-OK` (`E2E-OK scenarios=30`, `OBJECT-LIBBPF-PARSE-OK (bpftool v7.8.0)`, `OK-rebuild-reproducible Ubuntu clang version 22.1.8 (1ubuntu1)`).** Run it:

***<ins>Run on Rock Box</ins>***

```bash
cd /home/aj/Projects/strix-halo-johnny
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  docs/tool-install/module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  docs/tool-install/module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  docs/tool-install/module1-slice1b-detach.sh" | sha256sum -c - && bash docs/tool-install/module1-slice1b-self-test.sh
```

**Paste 1.** Expect three `OK` lines, then `PROGRAM-SOURCE-OK`, `ENUM-ORDER-OK`, `OBJECT-DISASM-OK` (if `llvm-objdump` runs), `STATIC-INVOCATIONS-OK`, `UNIT-TESTS-OK`, `GATES-OK`, `E2E-OK scenarios=30`, `RUNBOOK-OK`, and last **`SELF-TEST-OK`**. Any `SELF-TEST-FAIL` stops everything. Takes a few seconds.

## Machines and how the pastes work

| Machine | Role |
|---|---|
| rock-box (`aj-rock-box`) | The checkout (`/home/aj/Projects/strix-halo-johnny`) and the terminal you type in. **Nothing runs `sudo` on rock-box.** |
| Johnny (`johnny`, `192.168.50.152`) | Where the attach, verify and detach actually run. |

A paste labelled **Run on Rock Box** runs entirely on rock-box. A paste labelled **Run on Johnny** is still typed on rock-box, but every command in it runs on Johnny through `ssh`, and its one password prompt is Johnny's `sudo -v` at the start of the `ssh -t` line (the probe's Paste 2 pattern). Your SSH session rides `eno3`, which this slice never touches.

## Preconditions

- This branch checked out at `/home/aj/Projects/strix-halo-johnny` on rock-box. **[Assumption]** that is still the rock-box checkout.
- Paste 1 printed `SELF-TEST-OK`, and the adversarial-reviewer has reviewed these exact pastes.
- Johnny up, SSH key login working, the SPAN up (SFP+7 to `eno1np0` at 10000) **with traffic**: the attach script stops before changing anything if `tcpdump` sees no frames in its 5 s baseline window (`STOP-no-traffic-baseline`).
- Johnny's `johnny-capture-irq.service` has run this boot (the pins are on CPUs 1 to 4). Otherwise `STOP-irq-baseline-outside-capture-cores`, before any change.
- A second terminal open is a good idea but not required: the attach does not touch `eno3`. The AMT KVM is the fallback for the unlikely loss of SSH; **[Assumption]** it is available (`docs/network-map.md`).

## Paste 2 — copy the three files to Johnny

***<ins>Run on Rock Box</ins>***

```bash
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-xdp-observe.o /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1b-attach.sh /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1b-detach.sh aj@192.168.50.152:/home/aj/cis-audit/
ssh aj@192.168.50.152 'cd /home/aj/cis-audit && echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  module1-slice1b-detach.sh" | sha256sum -c - && echo M1S1B-COPY-DONE'
```

Ends **`M1S1B-COPY-DONE`**. No sudo, changes only three files in `/home/aj/cis-audit/`. The names `module1-xdp-observe.o`, `module1-slice1b-attach.sh` and `module1-slice1b-detach.sh` do not collide with anything from steps 11 or 13 or the probe.

## Paste 3 — install the rollback first (and prove it runs on a clean box)

***<ins>Run on Johnny</ins>*** (typed on rock-box; the commands run on Johnny through `ssh -t`)

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit &&
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  module1-slice1b-detach.sh" | sha256sum -c - &&
sudo install -d -m 0700 -o root -g root /root/m1s1b &&
sudo install -m 0700 -o root -g root module1-xdp-observe.o module1-slice1b-attach.sh module1-slice1b-detach.sh /root/m1s1b/ &&
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  /root/m1s1b/module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  /root/m1s1b/module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh" | sudo sha256sum -c - &&
sudo bpftool net show &&
sudo bash /root/m1s1b/module1-slice1b-detach.sh detach &&
echo M1S1B-INSTALL-DONE'
```

What it does: re-checks the hashes on Johnny, installs the three files root-owned into `/root/m1s1b/`, re-checks the installed copies, prints `bpftool net show` (the "before" picture: nothing on `eno1np0`), then runs the **detach on the clean box**. On a clean box detach changes nothing; it proves the rollback script runs, its gates pass, and `eno1np0` and `eno3` are as recorded. Expect in its output: `NOTHING-ATTACHED`, `OK-no-xdp-on-eno1np0`, `NOTE-no-final-stats`, `PINS-ABSENT`, `OK-no-j_xdp_observe-loaded`, `PROG-XDP-COUNT 0`, `IRQ-PINS-OK (inside capture cores; no attach baseline file)`, a `LINK eno1np0 flags=0x1183 speed=10000 ... mtu=1500` line, `M1S1B-DETACH-DONE`, then **`M1S1B-INSTALL-DONE`**.

Writes: `/root/m1s1b/` and three files in it. Nothing else. If anything prints `STOP-`, the chain stops and nothing was attached.

## Paste 4 — attach

***<ins>Run on Johnny</ins>*** (typed on rock-box; the commands run on Johnny through `ssh -t`)

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  /root/m1s1b/module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  /root/m1s1b/module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s1b/module1-slice1b-attach.sh attach'
```

About 40 seconds (a 5 s baseline window, the load, the attach and link wait, a 10 s observe window). Success ends **`M1S1B-ATTACH-DONE`**. The transcript is `/root/m1s1b/attach.log` on Johnny.

Order of events, so the output can be read:

1. `M1S1B-ATTACH-START`, then `OK-object-hash`, `OK-rollback-hash`, `OK-irq-helper-hash`.
2. **Preflight, read-only, fail-fast:** nothing attached anywhere, `PROG-XDP-COUNT 0`, no pins, twelve queue IRQs inside the capture cores, `eno1np0` flags/speed/MTU/no address, `eno3`, Suricata `disabled/inactive`, `COMBINED-BEFORE 12`. It saves `IRQ-BASELINE-SAVED` and prints twelve `IRQ-BEFORE` lines.
3. **Baseline window (5 s):** `BASE-WINDOW ... tcpdump-captured=N nic-rx-delta=M`. `N` must be above 0 or it stops here, having changed nothing.
4. **First change: load.** `bpftool prog load` pins the program and both maps under `/sys/fs/bpf/johnny_m1s1b/`; `LOADED prog_id=N (verifier accepted; not attached yet)`; the counter readback is parsed on the real output (`OK-readback-parse`) and all counters must be zero. **If the verifier refuses, nothing is attached** (`STOP-load`).
5. **Attach:** `bpftool net attach xdpdrv pinned ... dev eno1np0`, `ATTACHED xdpdrv prog_id=N`, then `KLOG>` lines (kernel log lines mentioning `ice`/`xdp`/`ddp`, for the record), and a wait for the link.
6. **Checks while attached** (`just-attached`): mode must be `driver` with our id; `PROG-XDP-COUNT 1`; flags still UP/PROMISC/NOARP; MTU 1500; no address; combined channels unchanged; `eno3` fine; `IRQ-BASELINE same`.
7. **Observe window (10 s):** `OBS-WINDOW ... xdp-pkts-delta=N xdp-pps=... xdp-avg-bytes=... tcpdump-captured=M nic-rx-delta=...`, `PASS-RATIO`, `OK-xdp-pass-tcpdump-sees-traffic`.
8. **Checks again** (`after-window`), the partition check, twelve `IRQ-AFTER` lines, and the counters: `STAT <name> <value>` for each slot, `STAT-RXQ <queue> <value>`, `PART`, `PROG-XDP-COUNT 1`.
9. `STATE attached, native (driver) mode, for this boot only`, the detach and read commands, `M1S1B-ATTACH-DONE`.

**On any `STOP-` after step 4** the script prints `REVERTING`, runs the installed detach, and ends **`M1S1B-ATTACH-STOPS`** (also on `Ctrl-C`, `SIGTERM`, or any unexpected error; a dropped SSH session does not interrupt it: `SIGHUP` is ignored, as in step 11). Before step 4 it prints `NOTHING-CHANGED` instead. If the rollback itself cannot finish, it prints `STOP-rollback-failed. Run: sudo bash /root/m1s1b/module1-slice1b-detach.sh detach` and the unchanged pinned script still prints `If that fails, a reboot removes the attach and the pins (no unit re-attaches it).` That sentence is stale while `johnny-capture-xdp.service` is enabled: a reboot re-attaches. To remove the observer, use the slice 1c Rollback block ([`module1-slice1c-boot-unit.md`](module1-slice1c-boot-unit.md)).

**Do not re-run the attach while attached**: it stops at `STOP-xdp-already-attached` before changing anything.

## Paste 5 — verify (read-only; sudo only because bpftool and bpffs need root)

***<ins>Run on Johnny</ins>*** (typed on rock-box; the commands run on Johnny through `ssh -t`)

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh" | sudo sha256sum -c - &&
sudo bpftool net show &&
sudo bpftool prog show name j_xdp_observe &&
sudo bash /root/m1s1b/module1-slice1b-detach.sh status &&
sleep 10 &&
sudo bash /root/m1s1b/module1-slice1b-detach.sh status | grep -E "^(XDP-ATTACH|PROG-XDP-COUNT|IRQ-BASELINE|IRQ-CAPTURE|STAT pkts|STAT bytes|M1S1B-)" &&
ip -d link show dev eno1np0 &&
sudo timeout -s INT 5 tcpdump -p -nn -i eno1np0 -w /dev/null;
echo M1S1B-VERIFY-DONE'
```

Run it any time after Paste 4, while attached. What to look for:

- `bpftool net show`: an `xdp:` entry `eno1np0(…) driver id N` (the mode must be `driver`, never `generic`). `bpftool prog show name j_xdp_observe`: `type xdp`, the same id, and two map ids.
- `status`: `XDP-ATTACH driver id=N`, `PROG-XDP-COUNT 1`, `PROG-OURS 1`, `IRQ-BASELINE same`, `IRQ-CAPTURE ok`, the counters, `M1S1B-STATUS-DONE`. The second read (10 s later) must show `STAT pkts` and `STAT bytes` **higher**: the counters are live. A `PART l3_diff=... l4_diff=...` close to 0 is the partition check.
- `ip -d link show dev eno1np0`: still `UP` with `PROMISC` and `NOARP`, and an XDP line for the attached program.
- `tcpdump` prints `N packets captured` with `N` above 0: frames still reach the stack. `tcpdump` exits through `timeout`, so a non-zero status from that step is normal; the final line is what matters. **`M1S1B-VERIFY-DONE`** is printed whatever happened above: read the lines, the token is not a verdict.

## Paste 6 — detach / rollback

Not part of the paste sequence above: run it only to take the program off (a review finding, a problem, or when slice 1b is finished). Safe to run twice, and safe on a clean box.

***<ins>Run on Johnny</ins>*** (typed on rock-box; the commands run on Johnny through `ssh -t`)

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s1b/module1-slice1b-detach.sh detach'
```

Ends **`M1S1B-DETACH-DONE`**. What it does, in order:

1. If an XDP program is on `eno1np0` **and it is ours** (`j_xdp_observe`), detach it in the mode it is in (`driver` normally; it uses the mode's own keyword so a stray generic attach can still be removed). A program that is not ours is never touched (`STOP-xdp-foreign`).
2. Wait until `bpftool net show` has no XDP on `eno1np0` (`OK-no-xdp-on-eno1np0`).
3. Read the counters one last time (`FINAL <name> <value>`), twice a second apart: they must be identical (`OK-counters-frozen`), which proves the program stopped counting. Then the exact partition check (`FINAL-PARTITION-OK`).
4. Remove the pins (`PINS-REMOVED`), wait until no `j_xdp_observe` is loaded (`OK-no-j_xdp_observe-loaded`), print `PROG-XDP-COUNT` (back to 0).
5. **Pins (IRQ):** compare the twelve queue pins with `irq-baseline.txt`. Same: `IRQ-PINS-OK`. Different: `NOTE-irq-pins-disturbed`, check the helper's sha256, run `/etc/johnny/irq-affinity.sh apply`, compare again: `IRQ-PINS-RESTORED`, or `STOP-irq-not-restored`. With no baseline file it checks that all twelve are single CPUs inside `capture-cores` and changes nothing if so.
6. Check `eno1np0` still has UP/PROMISC/NOARP, 10000, MTU 1500, no address, and `eno3` is as recorded. This script does not change any of those: a failure is reported, and you decide.
7. Delete `irq-baseline.txt` after a clean detach.

STOP lines are collected, not fail-fast (a rollback should do every step it can). Any STOP withholds the token and ends `M1S1B-DETACH-STOPS`.

To remove the observer for good, use the slice 1c Rollback block ([`module1-slice1c-boot-unit.md`](module1-slice1c-boot-unit.md)). While `johnny-capture-xdp.service` is enabled, Paste 6 above, or a **reboot**, detaches only until the next boot: the unit re-attaches at boot. (Before slice 1c, a reboot cleared the attach and the pins because bpffs is in memory and no unit re-attached it.)

Recovery for moved IRQ pins on its own (only if a detach reported `STOP-irq-not-restored`; **if `eno1np0` flags also moved — e.g. `STOP-eno1-flags` because `PROMISC` was cleared — restore the `UP`/`PROMISC`/`NOARP` flags first**, because `/etc/johnny/irq-affinity.sh apply` preflight refuses to run while `PROMISC` is off):

***<ins>Run on Johnny</ins>*** (typed on rock-box; the commands run on Johnny through `ssh -t`)

```bash
ssh -t aj@192.168.50.152 'sudo -v && sudo /etc/johnny/irq-affinity.sh apply'
```

## What each STOP means

| Line | Meaning |
|---|---|
| `STOP-host`, `STOP-not-root`, `STOP-kernel <v>` | Not Johnny, not root, or not `7.0.0-42-generic`. Fires before any read or write. |
| `STOP-args` | Wrong argument. |
| `STOP-locked` | Another attach or detach is running. |
| `STOP-missing-tool <x>`, `STOP-no-bpftool`, `STOP-no-python3` | A needed tool is absent. |
| `STOP-object-hash`, `STOP-rollback-hash`, `STOP-irq-helper-hash`, `STOP-irq-helper-missing` | A pinned file is not the reviewed one. |
| `STOP-object-not-root-owned-or-missing`, `STOP-rollback-not-root-owned-or-missing` | The copy in `/root/m1s1b/` is not root-owned, is writable by others, or is missing. |
| `STOP-no-rollback-installed` | Paste 3 has not been run. |
| `STOP-status-failed` | The detach script's `status` did not finish (its output is printed above the STOP). |
| `STOP-xdp-already-attached`, `STOP-xdp-progs-loaded`, `STOP-pins-exist` | Something is attached or loaded, or our pin directory exists. Nothing was changed. |
| `STOP-irq-count`, `STOP-irq-baseline-outside-capture-cores` | Not twelve queue IRQs, or one is off the capture cores. Fix with step 13, not here. |
| `STOP-eno1-flags`, `STOP-eno1-speed`, `STOP-eno1-link`, `STOP-mtu-not-1500`, `STOP-eno1-has-address`, `STOP-eno3-not-as-recorded` | The state the probe recorded no longer holds. |
| `STOP-suricata ...` | Suricata is enabled or running. |
| `STOP-ethtool-l` | `ethtool -l` could not be read or parsed. |
| `STOP-tcpdump-baseline-failed`, `STOP-no-traffic-baseline` | `tcpdump` failed, or saw no frames before the attach. Nothing was changed. |
| `STOP-mkdir-pin-dir`, `STOP-load`, `STOP-load-not-visible`, `STOP-prog-count-after-load`, `STOP-pins-after-load`, `STOP-irq-moved-by-load`, `STOP-readback-not-zero-before-attach` | The load stage. First change has happened, nothing is attached; rollback runs. `STOP-load` is the verifier or bpftool refusing the object. |
| `STOP-attach` | Native `xdpdrv` was refused. **There is no generic fallback by design**; the `KLOG>` lines are printed. Rollback runs. |
| `STOP-link-after-attach` | The link did not come back within 30 s of the attach. Rollback runs. |
| `STOP-xdp-mode-or-id-<when>`, `STOP-prog-count-<when>`, `STOP-prog-ours-<when>` | The attachment is not exactly our program in `driver` mode. |
| `STOP-eno1-flags-<when>`, `STOP-mtu-<when>`, `STOP-eno1-address-<when>`, `STOP-queues-changed-<when>`, `STOP-eno3-changed-<when>` | The attach changed the card or the mgmt link. Rollback runs; the card's flags are **not** restored by the script (it never sets them): look at `STOP-eno1-flags` in the detach output. **Recovery order when both flags and IRQ pins moved:** restore `eno1np0` flags (`UP`, `PROMISC`, `NOARP`) **before** running `/etc/johnny/irq-affinity.sh apply`, because the IRQ helper's preflight refuses while `PROMISC` is off. |
| `STOP-irq-pins-moved-<when>`, `STOP-irq-outside-capture-cores-<when>`, `STOP-irq-count-<when>` | The step 13 pins moved. Rollback runs the helper (`/etc/johnny/irq-affinity.sh apply`). If `eno1np0` flags (`PROMISC`) also moved, restore the flags first, then run `/etc/johnny/irq-affinity.sh apply`. |
| `STOP-pass-broken`, `STOP-observer-no-count`, `STOP-no-traffic`, `STOP-tcpdump-failed-while-attached` | The cross-check failed (see above). |
| `STOP-partition-l3`, `STOP-partition-l4` | The counters do not add up beyond tolerance: a bug in the program or its reader. |
| `STOP-rollback-failed` | The detach itself ended in STOPs. Run the printed command. The script's reboot sentence is stale while `johnny-capture-xdp.service` is enabled (a reboot re-attaches); to remove the observer, use the slice 1c Rollback block. |
| Detach: `STOP-xdp-foreign`, `STOP-xdp-mode-unknown`, `STOP-detach-failed`, `STOP-xdp-linger`, `STOP-counters-still-moving`, `STOP-unpin-failed`, `STOP-pin-leftover`, `STOP-prog-linger`, `STOP-prog-show-failed`, `STOP-net-show-failed`, `STOP-stats-read-failed`, `STOP-irq-not-restored`, `STOP-irq-no-queue-irqs`, `STOP-irq-cores-unreadable`, `STOP-eno1-mtu`, `STOP-eno3-changed` | See the detach steps above. For `STOP-irq-not-restored` together with `STOP-eno1-flags`: restore `eno1np0` flags (`UP`, `PROMISC`, `NOARP`) first, then run `/etc/johnny/irq-affinity.sh apply` (the helper preflight refuses while `PROMISC` is off). |

`NOTE-` lines never block: `NOTE-pass-ratio-low`, `NOTE-nic-rx-dropped-up`, `NOTE-wait-link`, `NOTE-xdp-mode-not-driver`, `NOTE-irq-pins-disturbed`, `NOTE-final-partition-off`, `NOTE-no-final-stats`, `NOTE-other-xdp-progs-loaded`, `NOTE-johnny-capture-irq.service <state>` and the same for the tuning unit.

## What to bring back

Simplest: paste the whole terminal output of each paste. It holds no secret (MACs are not printed; IRQ numbers and counters only). For the record, the closeout needs: the `OK-object-hash` line, `BASE-WINDOW`, `LOADED`, `ATTACHED`, every `KLOG>` line, `OK-xdp-mode`, `OBS-WINDOW`, `PASS-RATIO`, the twelve `IRQ-BEFORE` and `IRQ-AFTER` lines, the `STAT` lines, and the final token; from Paste 5, both `status` reads, `bpftool net show` and the `tcpdump` count.

## Not decided here (for AJ or the architecture pass; each is a choice, not a default I made)

1. **Boot persistence.** ~~Later slice.~~ **Done in slice 1c (applied 2026-11-08 UTC):** `johnny-capture-xdp.service` re-attaches after `johnny-capture-irq.service` with its own bounded wait; see [`module1-slice1c-boot-unit.md`](module1-slice1c-boot-unit.md).
2. **Netlink attach versus a pinned `bpf_link`.** Here: `bpftool net attach`, the netlink path step 11 proved on this card. It has no `overwrite`, so a second attach fails loudly. A pinned link would survive differently (the link, not the netlink slot, owns the attachment); not used here.
3. **Thresholds I picked:** 80% for the `tcpdump` versus XDP ratio (a note), `max(256, 1%)` for the live partition tolerance, a 30 s link wait, 5 s and 10 s windows. They are mine, not measurements.
4. **What the observer records next:** counters only, today. Header-only records (a ring buffer) or both directions on one queue (symmetric RSS) are not started.
5. **AF_XDP** stays deferred (twelve queues on four cores means twelve sockets or a queue-count change that the step 13 pins would likely not survive, **[Inference]** from the probe).

## Assumptions (marked; status after the 2026-11-06 apply)

- **[Assumption — measured on 2026-11-06]** The first native attach on `ice` may bounce the link and rebuild queue resources; it may move the IRQ pins. The script measures it (see above); it does not assume the outcome. Sources are patch threads, not `ice_main.c` for 7.0.0-42. **Live result (`M1S1B-ATTACH-DONE`):** `OK-irq-pins-unchanged (just-attached)` and `(after-window)`, `IRQ-BASELINE same`, `combined=12`, link `flags=0x1183 speed=10000 carrier=1 oper=up mtu=1500` unchanged.
- **[Assumption — retired on 2026-11-06]** `bpftool -j map dump pinned` of a per-CPU array prints either a `formatted` object (`key`, `values` with `cpu`/`value`) or raw byte arrays; the parser accepts both. Not a live capture of this map at draft time. The attach proved the parse on Johnny's real output before attaching (`OK-readback-parse`), and post-attach `STAT` / `STAT-RXQ` readbacks succeeded (`PART l3_diff=0 l4_diff=0`).
- **[Assumption — retired on 2026-11-06]** `bpftool -j net show dev` carries `devname`, `mode` and `id` for an XDP attachment (step 11 parsed `devname` and `mode` live; `id` was from the man page's JSON example at draft time). **Live result on Johnny:** `bpftool` 7.7.0 prints `mode` and `id` together (`OK-xdp-mode driver id=472`, `XDP-ATTACH driver id=472`). Correction from PR #24 review: if `id` were absent (`id=none`), the attach would print `driver id=none` and stop at the id comparison after the attach, and `detach_ours` in the rollback would **not** detach `id=none` (because `",none,"` does not match `",$ids,"` from `bpftool -j prog show`, so `detach_ours` reports `STOP-xdp-foreign mode=driver id=none (not j_xdp_observe; not detached)` instead of detaching; manual `sudo bpftool net detach xdpdrv dev eno1np0` would then be required; while `johnny-capture-xdp.service` is enabled, a reboot re-attaches, so the slice 1c Rollback block is the removal path).
- **[Assumption — retired on 2026-11-06]** `tcpdump` 4.99.6 prints `N packets captured` to stderr on `SIGINT` (`BASE-WINDOW tcpdump-captured=640`, `OBS-WINDOW tcpdump-captured=1444`, Paste 5 `567 packets captured`, `0 packets dropped by kernel`).
- **[Assumption — retired on 2026-11-06]** `ethtool -l` prints `Combined:` under `Current hardware settings:` (`COMBINED-BEFORE 12`, `combined=12`).
- **[Inference]** `tcpdump` sees only frames the program passed (see above).
- ~~The verifier has not seen the object (see "Build"). A refusal is a clean stop at the load stage.~~ **Retired on 2026-11-06:** `LOADED prog_id=472 (verifier accepted; not attached yet)` (`xlated 3256B jited 1899B`, `map_ids 64,65`, `btf_id 187`).
- bpftool man-page text is from the Arch Linux copy; Johnny's bpftool is 7.7.0 and the page may differ in small ways.
- The `ice` 3 KB XDP frame limit does not matter at MTU 1500 (measured).
- Compiler: Ubuntu clang 22.1.8 from the `stonking` archive on rock-box, not the clang 18.1.3 that built step 11's object.

## Sources

- bpftool `prog load` (`pinmaps MAP_DIR`, pins the first program at `PATH`; type inferred from the section name): <https://man.archlinux.org/man/bpftool-prog.8.en>
- bpftool `net attach` / `detach`, `xdp` (falls back to generic) versus `xdpdrv` (native) versus `xdpgeneric`, `overwrite`, `pinned FILE`: <https://man.archlinux.org/man/bpftool-net.8.en>
- ice driver: XDP and AF_XDP zero-copy supported, XDP blocked above 3 KB: <https://docs.kernel.org/networking/device_drivers/ethernet/intel/ice.html>
- ice XDP attach restarts the interface, later narrowed (patch threads, not current source): <https://lore.kernel.org/all/87v8fogb7h.fsf@toke.dk/T/>, <https://lab.nexedi.cn/kirr/linux/-/commit/04c7e14e5b0b6227e7b00d7a96ca2f2426ab9171>
- Per-CPU array maps: <https://docs.kernel.org/bpf/map_array.html>
- XDP action codes (secondary): <https://prototype-kernel.readthedocs.io/en/latest/networking/XDP/implementation/xdp_actions.html>
- Repo: `docs/os-handoff.md` rev 98; `docs/tool-install/module1-slice1-span-xdp.md` rev 2; `docs/tool-install/step-11-e810-capture.md` (the attach/detach/rollback pattern); `docs/tool-install/step-13-irq-affinity.md` and `etc/johnny/irq-affinity.sh` (the pins and the helper).
