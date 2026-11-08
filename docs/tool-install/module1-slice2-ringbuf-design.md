# Module 1, slice 2: header-only ring buffer records on `eno1np0` (design)

Rev 1, 2026-11-08 America/Chicago. Status: **DESIGN ONLY. NOT IMPLEMENTED, NOT REVIEWED, NOT APPLIED.** Branch `claude/module1-slice2-ringbuf` off `origin/claude/practical-ritchie-4c6vvf` at `fd3e7f2` (slice 1c reinstall closeout, handoff rev 104). This doc fixes the shape of slice 2 before any code exists. The code, the pastes and the sha256 pins come in a later phase. Each one gets its own adversarial-reviewer pass on the exact paste before AJ runs it (AGENTS.md).

AJ chose this slice from the three options in handoff rev 104 § Next steps: header-only ringbuf records, symmetric RSS, or AF_XDP evaluation. Owner: Fast Path (`ringbuf-producer`, `docs/agent-team.md` §2). The reader here is a bounded proof reader. It is not the Daemon's Rust `ringbuf-consumer`, which comes later. Governance owns `capture-privacy` (§ Privacy below).

## 1. Goal and non-goals

**Goal.** Replace "counters only" (slice 1b item 4, `module1-slice1b-attach.md` § Not decided here) with **one fixed-size, header-only record per sampled frame**. The XDP program on `eno1np0` writes these records to a `BPF_MAP_TYPE_RINGBUF`. A hardened, root-only reader that never sends traffic drains them into a bounded local file. The program keeps every slice 1b counter, so slice 1c's `verify` checks stay meaningful.

**Non-goals (slice 2).**
- No verdicts, no `XDP_DROP` / `XDP_TX` / `XDP_REDIRECT` / `XDP_ABORTED`, and no frame changes. The SPAN port stays passive.
- No payload bytes. No TCP options, DNS, TLS SNI or HTTP. Nothing past the fixed L4 header fields listed in §3.
- No AF_XDP, no symmetric RSS, no change to queue count or IRQ pins (step 13 stays authoritative).
- No boot persistence for the records program in slice 2. The trial attach lasts **this boot only**. Slice 1c's `johnny-capture-xdp.service` stays installed and enabled and still owns boot (§7).
- No database, no daemon, no upstream to the MAX, no SLM feed.

## 2. Program: `j_xdp_records` (passive, XDP_PASS only)

- Source `docs/tool-install/module1_xdp_records.c`, object `docs/tool-install/module1-xdp-records.o`. Same style as `module1_xdp_observe.c`: no kernel or libbpf headers, little-endian guard, `SEC("xdp")`, GPL license.
- **One `return`, and it is `XDP_PASS`.** All work lives in `void` helpers, as in slice 1b. Every path, including bounds-check failures, a full ring and a sampled-out frame, falls through to `XDP_PASS`.
- **Superset of slice 1b.** `m1_stats` and `m1_rxq` keep the same layout and slot order, so the slice 1b/1c readback (`STAT`, `STAT-RXQ`, `PART l3_diff/l4_diff`) runs unchanged against the new program. New slots go in a **separate** map (`m2_ctl`, §5), so the 1b name table and enum order check do not move.
- **Helper allowlist** (the self-test enforces it on the disassembly, the way slice 1b checks `call 0x1`):

  | id | helper | why |
  |---|---|---|
  | 1 | `bpf_map_lookup_elem` | counters, config |
  | 5 | `bpf_ktime_get_ns` | record timestamp, rate-limit clock |
  | 131 | `bpf_ringbuf_reserve` | record slot |
  | 132 | `bpf_ringbuf_submit` | publish record |

  Phase C: `bpf_ringbuf_discard` (133) is **not** used. The record is built on the stack and copied whole into the slot, so nothing can turn out unusable after reserve. The self-test allowlist is exactly {1, 5, 131, 132}.

  No `bpf_ringbuf_output` (it copies; reserve/submit writes in place). No `bpf_get_prandom_u32`: sampling is deterministic (§4) so tests can reproduce it. No redirect, adjust, tail-call or probe helpers. **[Assumption]** helper ids and `BPF_MAP_TYPE_RINGBUF = 27` follow upstream `include/uapi/linux/bpf.h` (<https://github.com/torvalds/linux/blob/master/include/uapi/linux/bpf.h>). The slice 1 probe already confirmed that the running kernel offers the ring buffer map type (`module1-slice1-span-xdp.md`, root-mode `bpftool -j feature probe kernel` row). The Phase B load-only step re-checks it on 7.0.0-42.
- **Timestamp choice:** `bpf_ktime_get_ns` (CLOCK_MONOTONIC, stops during suspend; Johnny does not suspend). The reader converts it to wall time once per run from a paired `clock_gettime(MONOTONIC)` / `REALTIME` sample and writes that offset into the file header. It does not convert per record. `bpf_ktime_get_boot_ns` (125) is the alternative if suspend ever matters. **[Assumption]** the NIC hardware RX timestamp (`bpf_xdp_metadata_rx_timestamp` kfunc) is **not** used: it needs device-bound programs and `ice` support we have not verified.

## 3. Record format (fixed 80 bytes, versioned)

One C struct `struct m2_rec`, shared byte for byte by the BPF source, the host-side layout test (§9) and the reader's `struct.unpack` format. Little-endian. `_Static_assert(sizeof(struct m2_rec) == 80)`.

| off | size | field | source | notes |
|---|---|---|---|---|
| 0 | 1 | `ver` | const `1` | reader refuses an unknown version |
| 1 | 1 | `flags` | computed | bit0 truncated-L3, bit1 truncated-L4, bit2 IPv4 fragment (MF or offset), bit3 IPv6 ext-hdr not walked, bit4 VLAN present, bit5 QinQ, bit6 rate-limit recovered (first record after a limited span) |
| 2 | 2 | `rxq` | `ctx->rx_queue_index` | 0..11 today |
| 4 | 4 | `wire_len` | `data_end - data` | linear frame length; FCS not included; multi-buffer not expected at MTU 1500 (`ice` 3 KB limit, slice 1b) |
| 8 | 8 | `ts_ns` | `bpf_ktime_get_ns` | monotonic |
| 16 | 6 | `dst_mac` | L2 | see § Privacy |
| 22 | 6 | `src_mac` | L2 | see § Privacy |
| 28 | 2 | `ethertype` | innermost, after ≤2 VLAN tags | host order |
| 30 | 2 | `vlan_tci` | outer tag, 0 if none | |
| 32 | 16 | `src_ip` | IPv4 in first 4 bytes, rest zero; or IPv6 | |
| 48 | 16 | `dst_ip` | same | |

L4 fields:

| off | size | field | notes |
|---|---|---|---|
| 64 | 1 | `l4_proto` | IPv4 protocol / IPv6 next-header (not walked past ext headers) |
| 65 | 1 | `ttl_hlim` | |
| 66 | 2 | `l3_len` | IPv4 `tot_len` / IPv6 `payload_len` + 40, saturated at 65535 (a `payload_len` above 65495 reads as 65535). A declared value, not a copy length or a read bound |
| 68 | 2 | `sport` | TCP/UDP only, else 0; ICMP: `type<<8 \| code` |
| 70 | 2 | `dport` | TCP/UDP only, else 0 |
| 72 | 1 | `tcp_flags` | byte 13 of the TCP header, else 0 |
| 73 | 1 | `rsv0` | 0 |
| 74 | 2 | `rsv1` | 0 |
| 76 | 4 | `seq_lo` | per-CPU record counter, low 32 bits; the reader uses it to detect gaps per CPU-queue |

The ring adds an 8-byte header per record, so each record costs 88 bytes in the ring. **Not recorded:** payload, IP options, TCP options, window, seq/ack, checksums, IP ID, DSCP/ECN, and any byte of a non-first IPv4 fragment beyond L3 (`sport`/`dport` stay 0 and `flags` bit2 is set).

Parsing bounds: every read checks `data_end` before the load. L4 reads must also fit inside the declared IP length (IPv4 `tot_len` - IHL*4, IPv6 `payload_len`); bytes after the declared end (Ethernet padding, trailing junk) are never read even when they are before `data_end` (review nit 1, 2026-11-08). A short frame still emits a record with what it parsed and sets the truncated bit, and the slice 1b `K_TRUNC` counter still counts it. IPv4 IHL < 5 or `tot_len` < IHL*4 sets truncated-L3 and skips L4. An L4 header cut short by `data_end` or by the declared length sets truncated-L4 and leaves the L4 fields 0.

## 4. Sampling and rate limits

Both knobs live in a `BPF_MAP_TYPE_ARRAY` config map `m2_cfg` (one slot, pinned, root-only). The reader never writes it. Only an AJ-run paste writes it, with `bpftool map update`, so changing a knob needs no reload.

- **Sampling 1-in-N, deterministic, per CPU:** a per-CPU counter `% N == 0` emits a record. Default **N = 1** (every frame), because measured load is small: slice 1b/1c windows saw 186 to 443 XDP pps on this SPAN. N = 0 means "records off" and keeps counters only, a kill switch that does not detach.
- **Rate limit: per-CPU token bucket** on `bpf_ktime_get_ns`. Default **2,000 records/s per CPU, burst 4,000**, about 8,000/s across the 4 capture CPUs. That is about 700 KB/s of ring traffic at 88 B, so a full 4 MiB ring holds about 6 s of worst-case backlog. **[Assumption]** these values are mine, not measurements, like the 80% and `max(256, 1%)` in slice 1b. AJ may change them, and they wait on the parked idle-memory investigation and the 92 °C register entry before any "production" sizing (handoff § Next steps).
- **Order in the program:** count (slice 1b counters) → sample → rate limit → reserve → fill → submit. Counters always see every frame. Records are a subset of counted frames.

## 5. Drop and accounting counters (`m2_ctl`, per-CPU array)

| slot | meaning |
|---|---|
| `C_SEEN` | frames that reached the record path |
| `C_SAMPLED_OUT` | skipped by 1-in-N |
| `C_RATE_LIMITED` | skipped by the token bucket |
| `C_RB_FULL` | `bpf_ringbuf_reserve` returned NULL (ring full: the reader is slow or stopped) |
| `C_EMITTED` | submitted |
| `C_DISCARDED` | reserved slot, never incremented (no discard call); always 0, kept so the slot layout is stable |

Invariant the tests and `verify` check: `C_SEEN = C_SAMPLED_OUT + C_RATE_LIMITED + C_RB_FULL + C_EMITTED + C_DISCARDED` (exact per CPU at quiescence; within a small tolerance when read live). The reader counts `records_read` and per-CPU `seq_lo` gaps. `C_EMITTED − records_read` over a window is reader-side loss. Its slice 1b counterparts (`tcpdump` kernel drops, NIC `rx_dropped`) stay in `verify`.

## 6. Ring buffer map and pins

- `m2_rb`: `BPF_MAP_TYPE_RINGBUF`, `max_entries = 4 MiB` (a power of 2 and a page multiple, as the kernel requires). One ring for all CPUs. The kernel serializes reserve per ring with a spinlock. At ≤ 8k rec/s that is not a bottleneck **[Inference]**; per-CPU rings (array-of-maps) are deferred.
- Pin dir **`/sys/fs/bpf/johnny_m1s2/`** (Phase C: one level, was `johnny/m1s2/`) (`prog`, `m1_stats`, `m1_rxq`, `m2_ctl`, `m2_cfg`, `m2_rb`), mode 0700 root. It does **not** reuse or touch slice 1b/1c's pin paths, so rollback cannot clobber them.
- Memory: 4 MiB data + metadata pages, locked kernel memory. It is a small part of the ~5.7 GB idle kernel allocation still under investigation (handoff § Parked).

## 7. Lifecycle and keeping slice 1c

Only one XDP program can hold the netlink slot on `eno1np0`. Slice 1b deliberately has no `overwrite`. So the records program **replaces** the observer for the trial. Slice 1c stays installed:

1. **Load-only (Phase B, Paste A):** `bpftool prog load … /sys/fs/bpf/johnny_m1s2/prog pinmaps /sys/fs/bpf/johnny_m1s2` (Phase C: one program, `prog load`, not `loadall`) with **no attach**. It proves the verifier accepts the program on 7.0.0-42 and prints `LOADED prog_id=…`. Rollback: unlink the seven named pins and `rmdir` (no `rm -r`). The observer stays attached the whole time.
2. **Swap (separate paste, AJ go):** `systemctl stop johnny-capture-xdp.service`, the proven slice 1c `stop` path, which detaches only `j_xdp_observe`. Then `bpftool net attach xdpdrv pinned …/prog dev eno1np0` (native; refuses if the slot is occupied), with the same link, IRQ-pin and partition checks as slice 1b. The unit is left **enabled, inactive**. Capture has a gap of a few seconds; that is acceptable for a passive SPAN trial.
3. **Reader run (separate paste):** bounded run (§8), then `verify` (counters invariant, `l3_diff=0 l4_diff=0`, IRQ pins unchanged, `ETHTOOL-DROP-DELTAS`).
4. **Back to slice 1c (rollback, and also the default end of the trial):** detach only if the attached id is the id behind our `prog` pin (`bpftool prog show pinned`; a same-name program without our pin is `STOP-xdp-records-unpinned`, not detached; never detach a foreign id). If ours is still attached after the detach step, the pins are **kept** (`KEEP-PINS`) so a later rollback can still prove ownership. Otherwise unlink the seven named pins and `rmdir /sys/fs/bpf/johnny_m1s2/`, then `systemctl start johnny-capture-xdp.service` (its fail-closed `start` re-attaches the observer). End token: `OK-xdp-mode driver id=…` with the program name `j_xdp_observe`.
5. **A reboot is also a rollback.** The records attach is not persistent, so at boot slice 1c re-attaches the observer. The `bpffs` pins are gone after reboot too.

**Explicit replacement** of slice 1c as the boot-time program (new unit or new helper mode, disabling `johnny-capture-xdp.service`) is **out of scope for slice 2**. It is a later slice (2b) that AJ must choose by name. Until then slice 2 does not edit the slice 1c unit, the slice 1c helper, `/root/m1s1b/*`, or `etc/systemd/system/johnny-capture-xdp.service`.

**Decision for AJ (recommendation given, not assumed):** the swap gap in step 2 versus `bpftool net attach … overwrite` (atomic, no gap, but it gives up the "fails loudly if occupied" property 1b chose on purpose). **Recommend stop/start**, because it reuses proven, reviewed paths.

## 8. Reader: bounded, root-only, no egress

`docs/tool-install/johnny-m1s2-reader.py`: Python 3 standard library only. Johnny has no compiler, `python3` is present (slice 1b § Tools), and there are no new packages or snaps.

- **How it reads:** `ctypes` `syscall(SYS_bpf, BPF_OBJ_GET)` on the pinned `m2_rb`; `mmap` the consumer page read-write and the producer page plus data (2× size, as the kernel maps it) **read-only**; `epoll` on the map fd; walk records, honoring the busy and discard bits in the 8-byte header; advance `consumer_pos` with a release store (a `ctypes` write after the data reads; **[Assumption]** CPython's ordering is enough on x86-64 TSO; Assurance to challenge). It validates `ver`, the length (= 80) and the bounds before unpacking. Any malformed header stops the reader (`STOP-ring-corrupt`). It never skips ahead silently.
- **Bounds (all hard caps; the first one hit ends the run):** `--max-seconds` (default 60, ceiling 600), `--max-records` (default 1,000,000), `--max-bytes` for the output file (default 64 MiB, ceiling 256 MiB), and at most `--keep` 3 run files in the output dir (oldest deleted first). With all three caps it cannot fill `/var`.
- **Output:** `/var/lib/johnny/m1s2/run-<UTC>.bin`: an 80-byte record stream plus a fixed header (magic, version, the mono→realtime offset, the cfg snapshot, start counters). Binary, not JSON, so the reader stays simple. A `--summary` mode prints counts, top talkers by count and per-queue totals to stdout for the runbook. Directory 0700 root, files 0600.
- **Hardening, systemd unit `johnny-m1s2-reader.service` (transient or templated, started only by a paste, not enabled):** `User=root` (needs the 0700 pin dir). `CapabilityBoundingSet=` **empty** (Phase C resolution, 2026-11-08; was `CAP_BPF CAP_PERFMON`: see the runbook § Changes from the design), `AmbientCapabilities=` (empty), `NoNewPrivileges=yes`. **`PrivateNetwork=yes`, `IPAddressDeny=any`, `RestrictAddressFamilies=none`** (Phase C; the reader opens no socket) (no egress, enforced three ways). `ProtectSystem=strict`, `ReadWritePaths=/var/lib/johnny/m1s2`, `ReadOnlyPaths=/sys/fs/bpf/johnny/m1s2`, `ProtectHome=yes`, `PrivateTmp=yes`, `ProtectKernelTunables/Modules/Logs=yes`, `ProtectControlGroups=yes`, `ProtectClock=yes`, `ProtectHostname=yes`, `LockPersonality=yes`, `MemoryDenyWriteExecute=yes` (**[Assumption]** `ctypes` without callbacks does not need W+X; to verify), `RestrictNamespaces=yes`, `RestrictRealtime=yes`, `RestrictSUIDSGID=yes`, `SystemCallArchitectures=native`, `SystemCallFilter=@system-service bpf`, `UMask=0077`, `RuntimeMaxSec=` = `--max-seconds` + 30, `MemoryMax=128M`, `CPUQuota=50%`, and the reader pinned to CPU 0 (off the capture CPUs 1–4) with `CPUAffinity=0`. `verify` prints `systemd-analyze security johnny-m1s2-reader.service`. **[Assumption]** `CAP_BPF`+`CAP_PERFMON` is enough for `BPF_OBJ_GET` plus ringbuf `mmap` with root-owned pins. If the kernel also wants `CAP_SYS_ADMIN` (`kernel.unprivileged_bpf_disabled` behavior), the load-only step finds out, and the design changes by review rather than silently widening.
- The reader **never** writes BPF maps, never loads or attaches programs, and never opens a socket other than journal `AF_UNIX`.

## 9. Build pins and tests

**Build (off-box, rock-box, same as slice 1b):** Ubuntu clang **22.1.8 (1ubuntu1)** unpacked from `apt-get download clang-22 libclang-common-22-dev llvm-22` with `dpkg-deb -x`, `-O2 -g -Wall -Wextra -Werror -target bpfel -mcpu=v3 -ffile-prefix-map="$PWD"=.`. The object's sha256 is pinned in the runbook, and a rebuild must match it byte for byte (`OK-rebuild-reproducible`). Every script and the reader get a sha256 pin too, checked by `sha256sum -c` in each paste before use (slice 1b/1c pattern).

**Phase B build pins (2026-11-08, rock-box, Ubuntu clang 22.1.8 (1ubuntu1)).** The object rebuilt byte for byte from the repo root and from a second checkout path; `bpftool gen skeleton` parsed it. The runbook copies these; a later change to any file needs a new pin and a new review.

```
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  docs/tool-install/module1-xdp-records.o
fa46115160c1aadc61fc4eb8027e9fa114347e90f4c67a28c4e664681e79053f  docs/tool-install/module1_xdp_records.c
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  docs/tool-install/johnny-m1s2-reader.py
e43fc1e35ea7e88310bb32e24b9640abe495a2e7a3d3466dea50dfd6abb54d85  etc/systemd/system/johnny-m1s2-reader.service
```

**Phase C final pins (2026-11-08)** supersede the unit pin above (capability fix) and add the helper and tests. The runbook § Final sha256 pins is the copy AJ's pastes use.

```
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  docs/tool-install/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  docs/tool-install/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  etc/systemd/system/johnny-m1s2-reader.service
044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  docs/tool-install/module1-slice2-records.sh
fa46115160c1aadc61fc4eb8027e9fa114347e90f4c67a28c4e664681e79053f  docs/tool-install/module1_xdp_records.c
54851655f6635fe2a7072aee8d8efb7f4982248bd98a0fbddb39c4f0f1998211  docs/tool-install/module1-slice2-host-test.c
3ebfc1970fe66b4b78bbabd0af1aa485a42a60fb65e7c6259ee7e145a304f63a  docs/tool-install/module1-slice2-reader-test.py
```

**rock-box self-test `module1-slice2-self-test.sh` → `SELF-TEST-OK`** (no Johnny, no sudo):
- Source and disassembly: exactly one `return XDP_PASS`; every `r0` constant before `exit` is 2; only helpers {1, 5, 131, 132}; no forbidden words outside comments (`XDP_DROP`, `XDP_TX`, `REDIRECT`, `ABORTED`, `adjust`, `tail_call`, `probe_read`, `ringbuf_output`, `prandom`).
- Slice 1b enum and name table unchanged (`ENUM-ORDER-OK`); the `m2_ctl` slot order matches the script name table.
- **Layout:** `module1-slice2-host-test.c` is built with host clang. It includes the same struct header and asserts `sizeof == 80` and every `offsetof`, and it prints the Python `struct` format, which must equal the reader's. It also runs the parse logic on crafted frames (short Ethernet, 2 VLAN, IPv4 IHL < 5, IPv4 fragment, IPv6 with ext header, TCP, UDP, ICMP, ARP) and checks the record fields. **[Assumption]** the parse is factored so the same C compiles for both BPF and host.
- **Object parse:** `bpftool gen object` / `btf dump` on the `.o`: map types and sizes (ringbuf 4 MiB, page-aligned power of 2), section `xdp`, license GPL.
- **Reader unit test `module1-slice2-reader-test.py`:** synthetic ring in a temp file `mmap`. It covers wrap-around, the busy bit, discarded records, a corrupt length (expect `STOP-ring-corrupt`), every cap (seconds, records, bytes, keep), file mode 0600 and dir mode 0700, and refusal of an unknown `ver`.
- `shellcheck` on every script, the runbook block count (`RUNBOOK-OK blocks=N`), and end-to-end scenarios with fake `bpftool` / `systemctl` / `ethtool` (`E2E-OK scenarios=N`), including: slot occupied by a foreign program → stop; observer unit missing → stop; counter invariant broken → `verify` fails; rollback when records is not attached → no-op that leaves the observer alone.

**On Johnny (Phase B onward, each one AJ-run and reviewed):** load-only verifier check → swap → bounded reader run (60 s) → `verify` → back to slice 1c. Each paste is one fenced block, `sudo -v` first, fail-fast checkpoints, a `M1S2-…-DONE` token, and the rollback as a later block not part of the paste.

## 10. Runbook and rollback (written in Phase C: `module1-slice2-ringbuf.md`)

`docs/tool-install/module1-slice2-ringbuf.md`, slice 1b/1c structure: Status banner, Facts (from the slice 1/1b/1c records, not re-probed), Build, Self-test, Pastes 1..N with expected tokens, Rollback (§7 step 4, as its own labeled block), Not decided here, Assumptions, Sources. `etc/systemd/system/johnny-m1s2-reader.service` mirrors the live unit path, in the same commit as any live change (AGENTS.md).

## Privacy (Governance, `capture-privacy`)

Records hold **MAC and IP addresses, ports and timing** for household devices. That is metadata, not payload, which fits "metadata first, header-only" (`docs/agent-team.md` §2, Governance `capture-privacy`). There is **no retention policy yet**. Slice 2 holds data **on Johnny only**, with root-only modes, at most 3 × 256 MiB, and with no egress. Run files are deleted at the end of the trial unless AJ says to keep them. Governance sets the real retention cap later. **Open for AJ:** whether MACs should be truncated or hashed in slice 2, or kept raw. The default here is raw, because the LAN asset inventory (Detection) needs them later.

## Not decided here (AJ or the architecture pass)

1. Swap gap vs `overwrite` (§7; recommendation: stop/start).
2. Sampling, rate and ring-size defaults (§4, §6): mine, pending idle-memory and thermal sizing.
3. MAC raw vs truncated/hashed (§ Privacy).
4. Slice 2b: boot persistence and the explicit replacement of slice 1c.
5. Per-CPU rings, NIC hardware timestamps, IPv6 extension-header walking: deferred.
6. The production consumer (Daemon, Rust: aya or libbpf-rs) replaces the proof reader. Its interface is the §3 record v1.

## Assumptions (marked above, collected)

- Helper ids and the map type number come from upstream `uapi/linux/bpf.h`, not from Johnny's BTF. The load-only step checks them.
- ~~`CAP_BPF`+`CAP_PERFMON` is enough for the reader.~~ Replaced in Phase C: a capability-less uid 0 is enough (upstream commit `1d28635abcf1`); the load smoke proves it on Johnny and fails closed. `MemoryDenyWriteExecute` works with `ctypes` as used.
- x86-64 TSO plus CPython makes the consumer-position store safe without an explicit fence.
- The parse code can be shared between the BPF and host builds.
- Throughput and size defaults are not measurements.
- No Johnny contact in this phase. Everything about Johnny comes from slice 1/1b/1c records and handoff rev 104.

## Sources

- Linux UAPI `bpf.h` (map types, helper ids): <https://github.com/torvalds/linux/blob/master/include/uapi/linux/bpf.h>
- BPF ring buffer design and the mmap layout (consumer page RW, producer+data RO, data mapped twice): <https://docs.kernel.org/bpf/ringbuf.html>
- `BPF_MAP_TYPE_RINGBUF` map docs: <https://docs.kernel.org/bpf/map_ringbuf.html>
- XDP `xdp_md` (`rx_queue_index`, `ingress_ifindex`): <https://docs.kernel.org/bpf/redirect.html> and UAPI above
- bpftool `prog load`, `net attach`: <https://man.archlinux.org/man/bpftool-prog.8.en>, <https://man.archlinux.org/man/bpftool-net.8.en>
- systemd sandboxing (`PrivateNetwork`, `IPAddressDeny`, `RestrictAddressFamilies`, `SystemCallFilter`): <https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html>, <https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html>
- ice driver XDP / 3 KB limit: <https://docs.kernel.org/networking/device_drivers/ethernet/intel/ice.html>
- Prior slices: `module1-slice1-span-xdp.md`, `module1-slice1b-attach.md`, `module1-slice1c-boot-unit.md`; handoff rev 104.
