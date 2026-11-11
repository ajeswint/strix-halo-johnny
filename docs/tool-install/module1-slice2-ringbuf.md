# Module 1, slice 2: header-only ring buffer records (`j_xdp_records`) on `eno1np0` (runbook; trial applied and closed 2026-11-11)

**Status (2026-11-11):** **trial APPLIED on Johnny and CLOSED** (back on slice 1c). Phase A design `bd14b28`, Phase B code `c6a69fc`, Phase C (this runbook, the self-test, the reader unit capability fix) reviewed by the adversarial-reviewer and merged in PR #30 (`f7840f4`). AJ ran Pastes 1–9 from rock-box on 2026-11-11 (~19:11 to ~19:21 UTC, where ~19:11 is the Paste 5 run-file stamp `20261111T191146Z` (Pastes 1–4 printed no clock and ran before it) and ~19:21 rounds the printed close 19:20:39Z; ~1:11 to ~1:21 PM CST): `SELF-TEST-OK`, `M1S2-COPY-DONE`, `M1S2-PROBE-DONE`, `M1S2-INSTALL-DONE`, `M1S2-LOAD-DONE prog_id=125`, `M1S2-SWAP-DONE`, `M1S2-READ-DONE`, `M1S2-VERIFY-DONE`, `M1S2-ROLLBACK-DONE`, `M1S2-TRIAL-CLOSED`. Record: § Trial record below; session `docs/sessions/2026-11-11-module1-slice2-trial-closeout.md`; handoff rev 105. The slice 2 files and the two run files are still on Johnny (Rollback blocks R2 and R3 were not run). The paste blocks below are kept unchanged as the record of what ran; re-running any of them is a new decision for AJ with a fresh review.

Design: `docs/tool-install/module1-slice2-ringbuf-design.md` (the "design"). This runbook follows it; where it differs, § Changes from the design says so.

## Purpose and scope

- Load `j_xdp_records` (passive: every path returns `XDP_PASS`; no payload; one fixed 80-byte header-only record per sampled frame: L2/L3/L4 header fields and lengths, `rx_queue_index`, `bpf_ktime_get_ns` timestamp) into a BPF ring buffer, run one bounded reader, verify, and go back to slice 1c.
- Slice 1c stays installed and **enabled** the whole time. Slice 2 never edits `johnny-capture-xdp.service`, `/root/m1s1b/*`, or the slice 1c helper. The only slice 1c action is `systemctl stop` / `systemctl start johnny-capture-xdp.service` (its proven paths). A reboot at any point is also a rollback (the records attach and the bpffs pins do not persist).
- The reader is root-only, bounded (60 s, 1,000,000 records, 64 MiB, 3 run files), has no network (`PrivateNetwork=yes`, `IPAddressDeny=any`, `RestrictAddressFamilies=none`), and **no capabilities**. It reports sampling, rate-limit and drop counters (`m2_ctl`: `seen sampled_out rate_limited rb_full emitted discarded`).

## Facts (from the slice 1/1b/1c records and handoff rev 104; not re-probed)

- Johnny: Ubuntu 26.04, kernel `7.0.0-42-generic`, `ssh aj@192.168.50.152`, `aj` has no passwordless sudo.
- Capture port `eno1np0` (E810, SPAN destination). Slice 1c's `johnny-capture-xdp.service` attaches `j_xdp_observe` native (`xdpdrv`) at boot. Capture IRQs pinned to CPUs listed in `/etc/johnny/capture-cores`.
- Slice 1b library `/root/m1s1b/module1-slice1b-detach.sh` (sha256 `f78ca14e…`) is sourced by the slice 2 helper for its reviewed parsers, IRQ snapshot and link checks.
- No compiler on Johnny; `python3` is present. No new packages, no snaps.

## Changes from the design (resolved in Phase C)

1. **Reader capabilities (design §8 said `CAP_BPF CAP_PERFMON`).** The unit now runs as uid 0 with an **empty** `CapabilityBoundingSet=`. Upstream moved the `unprivileged_bpf_disabled` check out of the `bpf()` entry and into `map_create()` / `bpf_prog_load()` (commit `1d28635abcf1`, "bpf: Move unprivileged checks into map_create() and bpf_prog_load()", June 2023). The reader uses only `BPF_OBJ_GET`, `BPF_MAP_LOOKUP_ELEM`, `BPF_OBJ_GET_INFO_BY_FD` and the ring `mmap`; those are gated by the pin's file mode (root-owned, 0600 in a 0700 dir), not by a capability. **[Assumption]** Ubuntu `7.0.0-42` matches upstream here. Paste 5's reader smoke proves it on Johnny. If it does not, the reader logs `STOP-obj-get errno=1`, the helper prints `STOP-reader-smoke-result`, rolls back by itself, and the fix goes through review (no silent widening). The self-test covers that path (`E2E load-reader-eperm`).
2. **Pin dir is `/sys/fs/bpf/johnny_m1s2`** (one level; design §6 said `/sys/fs/bpf/johnny/m1s2/`). One `mkdir` that fails if it exists, and nothing else under `/sys/fs/bpf` is created or touched.
3. **`RestrictAddressFamilies=none`** (design said `AF_UNIX`). The reader opens no socket at all; journal output goes to the stdout stream systemd hands it.
4. Pins: `prog m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state`. Only `m2_rb` is writable inside the reader sandbox (consumer page).
5. **Review nits (2026-11-08, PR #30 review).** L4 reads are bounded by the declared IP length as well as `data_end` (IPv4 `tot_len` < IHL*4 is truncated-L3; an L4 header past the declared end is truncated-L4); IPv6 `l3_len` saturation at 65535 is documented; rollback ownership is the id behind our `prog` pin, and pins are kept when ours is still attached; `read` stops an overran reader; `bpf_ringbuf_discard` (133) dropped from the design and the allowlist.

## Final sha256 pins (Phase C)

Deployables (copied to Johnny):

```
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  docs/tool-install/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  docs/tool-install/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  etc/systemd/system/johnny-m1s2-reader.service
044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  docs/tool-install/module1-slice2-records.sh
```

Sources and tests (rock-box only):

```
fa46115160c1aadc61fc4eb8027e9fa114347e90f4c67a28c4e664681e79053f  docs/tool-install/module1_xdp_records.c
54851655f6635fe2a7072aee8d8efb7f4982248bd98a0fbddb39c4f0f1998211  docs/tool-install/module1-slice2-host-test.c
3ebfc1970fe66b4b78bbabd0af1aa485a42a60fb65e7c6259ee7e145a304f63a  docs/tool-install/module1-slice2-reader-test.py
```

Slice 1c files the helper checks but never changes: `module1-slice1b-detach.sh` `f78ca14e…`, `module1-slice1c-boot.sh` `a501dbb7…`, `johnny-capture-xdp.service` `2510bc97…`, `/etc/johnny/capture-cores` `16fbd7d1…`.

Installed layout on Johnny:

| File | Path | Mode |
|---|---|---|
| helper | `/root/m1s2/module1-slice2-records.sh` | 0700 root |
| object | `/root/m1s2/module1-xdp-records.o` | 0600 root |
| reader | `/usr/local/libexec/johnny/johnny-m1s2-reader.py` | 0644 root |
| reader unit (never enabled) | `/etc/systemd/system/johnny-m1s2-reader.service` | 0644 root |
| pins (runtime) | `/sys/fs/bpf/johnny_m1s2/` | 0700 root |
| run files (runtime) | `/var/lib/johnny/m1s2/run-<UTC>.bin` | dir 0700, files 0600 |

## Decisions (AJ)

1. **Swap method (before Paste 6).** Options: (a) `systemctl stop johnny-capture-xdp.service`, then native `bpftool net attach xdpdrv pinned`, which refuses if the slot is taken; a capture gap of a few seconds. (b) `bpftool net attach … overwrite`: atomic, no gap, but gives up the "fails loudly if occupied" rule slice 1b chose. **Recommendation: (a).** The helper implements only (a). Choosing (b) means a helper change and a new review. **AJ chose (a) on 2026-11-11** (the swap at 19:18:05 UTC ran stop-then-attach; brief capture gap).
2. Sampling/rate/ring defaults (compiled: every 1, 2000 rec/s/CPU, burst 4000, 4 MiB ring), MAC raw vs hashed, run-file retention: open (design § Not decided). Default here: raw MACs, run files deleted at the end (Rollback block R3) unless AJ says keep. **Outcome 2026-11-11:** defaults used as compiled; R3 was not run, so the two run files (`run-20261111T191146Z.bin`, `run-20261111T191845Z.bin`) are still under `/var/lib/johnny/m1s2`; deleting them, and any rate-limit tuning, is a later decision (§ Trial record, follow-up).

## Trial record (2026-11-11, AJ ran from rock-box; UTC from the paste output)

No paste was edited for the run. All seven sha256 pins matched on rock-box (Paste 1) and on Johnny (every sudo paste). Nothing in slice 1c was changed: `johnny-capture-xdp.service` stayed enabled; it was stopped once in Paste 6 and started once in Paste 9.

- **Paste 1** (rock-box): all 7 pins OK, `HOST-TEST cases=44`, `READER-TEST cases=22`, `E2E scenarios=23`, `RUNBOOK blocks=12`, **`SELF-TEST-OK`**.
- **Paste 2**: four deployables copied to `/home/aj/cis-audit/m1s2`, hashes checked, **`M1S2-COPY-DONE`**.
- **Paste 3** (read-only): `unprivileged_bpf_disabled=2`, Python 3.14.4, observer `driver id=75`, **`M1S2-PROBE-DONE`**.
- **Paste 4**: files installed, nothing loaded, unit not enabled; NIC `rx_dropped=7` baseline (pre-existing from the boot attach, not a trial failure), **`M1S2-INSTALL-DONE`**.
- **Paste 5**: verifier accepted, pinned, not attached, **`M1S2-LOAD-DONE prog_id=125`**. Reader smoke under the full sandbox (uid 0, empty capability set): `file=/var/lib/johnny/m1s2/run-20261111T191146Z.bin records=0 bytes=96 reason=signal-15 seq_gaps=0 ring_discarded=0`, `READER-RESULT success`. Observed on Johnny: the capability-less reader did `BPF_OBJ_GET` and `mmap` the root-owned ring (Paste 5 open/mmap smoke: `records=0 bytes=96 reason=signal-15`, `READER-RESULT success`; Paste 7 then drained it for real: `records=31419 seq_gaps=0`). That is the behaviour this runbook's § Changes from the design item 1 marks `[Assumption]` on `7.0.0-42`; one run observed, not a proof.
- **Decision 1**: AJ chose (a) stop-then-attach.
- **Paste 6** (swap) at **2026-11-11T19:18:05Z** (1:18:05 PM CST): before `observer=75 records=125`; `OK-c1-stopped`; `ATTACHED xdpdrv prog_id=125`; post-swap partition, IRQ and ctl accounting OK (`seen=365 sum=365 pkts=362`); `C1-UNIT enabled=enabled active=inactive`; **`M1S2-SWAP-DONE`**.
- **Paste 7** (one bounded read): `run-20261111T191845Z.bin`, `reason=max-seconds`, `records=31419 bytes=2513616 seq_gaps=0 ring_discarded=0 backlog=176`; `ctl_seen=21420 ctl_sampled_out=0 ctl_rate_limited=6119 ctl_rb_full=0 ctl_emitted=15301 ctl_discarded=0`; `READER-RESULT success`. Summary: `span_s=98.160`; `SUMMARY-FLAGS trunc_l3=0 trunc_l4=0 frag=0 ip6_ext=0 vlan=0 qinq=0 rl_recovered=601 vlan_deep=0`; `SUMMARY-RXQ 0=858 1=3408 2=743 3=595 4=499 5=519 6=15794 7=787 8=759 9=6243 10=680 11=534` (RXQ 6 dominant); `SUMMARY-L4 0=26 1=1566 2=23 6=6126 17=23676 58=2` (udp 23676, tcp 6126, icmp 1566); top src `172.217.153.231` 18917, `192.168.50.223` 7185, `34.225.159.174` 1001, `192.168.50.188` 787, `10.5.0.1` 783. Cumulative `m2_ctl` after the read: `seen 46978 rate_limited 15527 emitted 31451 rb_full 0` (about one third rate-limited, by design at the compiled 2000 rec/s/CPU, burst 4000, concentrated on RXQ 6). IRQ pins unchanged; partitions `l3_diff=0 l4_diff=0`; **`M1S2-READ-DONE`**.
- **Paste 8** (verify, read-only): all checks OK at start and end; `VERIFY-WINDOW secs=5 pkts=406 seen=407 emitted=407`; `NIC-DROP-DELTAS rx_dropped=0 rx_missed_errors=0 rx_fifo_errors=0 rx_errors=0`; **`M1S2-VERIFY-DONE`**.
- **Paste 9** (close) at **2026-11-11T19:20:39Z** (1:20:39 PM CST): `DETACHED mode=driver id=125 j_xdp_records`, `PINS-REMOVED`, `OK-no-j_xdp_records-loaded`, `C1-STARTED`, observer now `driver id=138 j_xdp_observe`, **`M1S2-ROLLBACK-DONE`**. Slice 1c status: all hashes OK; `johnny-capture-xdp`, `johnny-capture-irq` and `johnny-capture-tuning` units enabled and active; `suricata` disabled and inactive; `IRQ-BASELINE same`; `M1S1B-STATUS-DONE`, `M1S1C-STATUS-DONE`, **`M1S2-TRIAL-CLOSED`**.

**Left in place (by AJ's choice, not an omission):** `/root/m1s2/module1-slice2-records.sh`, `/root/m1s2/module1-xdp-records.o`, `/usr/local/libexec/johnny/johnny-m1s2-reader.py`, `/etc/systemd/system/johnny-m1s2-reader.service` (not enabled) and the two run files under `/var/lib/johnny/m1s2`. Rollback blocks R2 (uninstall) and R3 (delete run files) were not run. Nothing is attached or pinned from slice 2; the observer id changes at every attach (`75` before, `138` after), as slice 1c documents.

**Not claimed.** One 60 s read on one afternoon is not a traffic baseline. `rx_dropped=7` was the pre-existing boot-attach count from slice 1c, and the verify deltas were `0`; that is one 5 s window, not proof of lossless capture. The `[Assumption]` lines in § Assumptions about `MemoryDenyWriteExecute` and the consumer-position store are exercised by this run, not proven in general.

**Follow-up (noted, not decided):** the per-CPU rate limit dropped about one third of the sampled records (`rate_limited 15527` of `seen 46978` cumulative) under a bursty UDP flow on one queue (RXQ 6, top talker `172.217.153.231`). That is the compiled default doing what the design says, not a trial failure. Raising the rate or burst, sampling 1-in-N, or spreading the flow (symmetric RSS) is a future decision for AJ and a new review; this closeout changes no value.

## Pastes (all typed on Rock Box; sudo only inside `ssh -t aj@192.168.50.152`)

No paste in this runbook is typed on Johnny. Every paste is labeled `***<u>Run on Rock Box</u>***`; the Johnny side runs over `ssh aj@192.168.50.152` or `ssh -t aj@192.168.50.152 'sudo -v && ...'`. AJ alone runs them. Each paste is one fenced block with fail-fast `&&` checkpoints and ends with one `M1S2-…` token. The paths assume the branch is checked out at `/home/aj/Projects/strix-halo-johnny-slice2`; the pins make a wrong checkout fail at the first `sha256sum -c`.

### Paste 1: Rock-box self-test (no root, no SSH)

***<u>Run on Rock Box</u>***

```bash
cd /home/aj/Projects/strix-halo-johnny-slice2 &&
echo "a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  docs/tool-install/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  docs/tool-install/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  etc/systemd/system/johnny-m1s2-reader.service
044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  docs/tool-install/module1-slice2-records.sh
fa46115160c1aadc61fc4eb8027e9fa114347e90f4c67a28c4e664681e79053f  docs/tool-install/module1_xdp_records.c
54851655f6635fe2a7072aee8d8efb7f4982248bd98a0fbddb39c4f0f1998211  docs/tool-install/module1-slice2-host-test.c
3ebfc1970fe66b4b78bbabd0af1aa485a42a60fb65e7c6259ee7e145a304f63a  docs/tool-install/module1-slice2-reader-test.py" | sha256sum -c - &&
bash docs/tool-install/module1-slice2-self-test.sh
```

Expect seven `OK` lines, `PINS-OK`, `SHELLCHECK-OK`, `ENUM-ORDER-OK`, `OK-rebuild-reproducible`, `OBJECT-DISASM-OK`, `OBJECT-LIBBPF-PARSE-OK`, `HOST-TEST-OK cases=44`, `READER-TEST-OK cases=22`, `READER-STATIC-OK`, `UNIT-STATIC-OK`, `HELPER-STATIC-OK`, `E2E-OK scenarios=23`, `RUNBOOK-OK blocks=12`, and **`SELF-TEST-OK`**.

### Paste 2: Copy the four deployables to Johnny (no sudo)

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p -m 0700 /home/aj/cis-audit/m1s2' &&
scp /home/aj/Projects/strix-halo-johnny-slice2/docs/tool-install/module1-xdp-records.o /home/aj/Projects/strix-halo-johnny-slice2/docs/tool-install/johnny-m1s2-reader.py /home/aj/Projects/strix-halo-johnny-slice2/etc/systemd/system/johnny-m1s2-reader.service /home/aj/Projects/strix-halo-johnny-slice2/docs/tool-install/module1-slice2-records.sh aj@192.168.50.152:/home/aj/cis-audit/m1s2/ &&
ssh aj@192.168.50.152 'cd /home/aj/cis-audit/m1s2 && echo "a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  johnny-m1s2-reader.service
044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  module1-slice2-records.sh" | sha256sum -c - && echo M1S2-COPY-DONE'
```

Expect four `OK` lines and **`M1S2-COPY-DONE`**.

### Paste 3: Probe (read-only preflight; installs nothing)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/m1s2 &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  module1-slice2-records.sh" | sha256sum -c - &&
sudo bash /home/aj/cis-audit/m1s2/module1-slice2-records.sh probe'
```

Expect `OK-lib-hash`, `OK-c1-helper-hash`, `OK-c1-unit-hash`, `C1-UNIT enabled=enabled active=active`, `OK-observer driver id=…`, `OK-bpffs`, `OK-reader-unit inactive`, `NOTE-unprivileged_bpf_disabled …` (any value; per § Changes 1 it does not gate the reader, and Paste 5 proves that), `PYTHON 3.…`, `OK-var-free …`, the link lines, and **`M1S2-PROBE-DONE`**. Nothing is changed by this paste.

### Paste 4: Install (files only; nothing loaded, unit not enabled)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/m1s2 &&
echo "a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  johnny-m1s2-reader.service
044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  module1-slice2-records.sh" | sha256sum -c - &&
sudo test ! -e /root/m1s2 &&
sudo test ! -e /etc/systemd/system/johnny-m1s2-reader.service &&
sudo install -d -m 0700 -o root -g root /root/m1s2 &&
sudo install -m 0700 -o root -g root module1-slice2-records.sh /root/m1s2/module1-slice2-records.sh &&
sudo install -m 0600 -o root -g root module1-xdp-records.o /root/m1s2/module1-xdp-records.o &&
sudo mkdir -p -m 0755 /usr/local/libexec/johnny &&
sudo install -m 0644 -o root -g root johnny-m1s2-reader.py /usr/local/libexec/johnny/johnny-m1s2-reader.py &&
sudo install -m 0644 -o root -g root johnny-m1s2-reader.service /etc/systemd/system/johnny-m1s2-reader.service &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  /root/m1s2/module1-slice2-records.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  /usr/local/libexec/johnny/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  /etc/systemd/system/johnny-m1s2-reader.service" | sudo sha256sum -c - &&
sudo systemctl daemon-reload &&
sudo systemd-analyze verify /etc/systemd/system/johnny-m1s2-reader.service &&
sudo bash /root/m1s2/module1-slice2-records.sh status &&
echo M1S2-INSTALL-DONE'
```

Expect four `OK` lines twice, `ATTACH observer …`, `C1-UNIT enabled=enabled active=active`, `READER-UNIT active=inactive`, `PINS dir=absent`, `M1S2-STATUS-DONE`, then **`M1S2-INSTALL-DONE`**. If the two `test ! -e` lines stop the paste, a previous install exists: run Rollback R2 first.

### Paste 5: Load + pin, no attach, reader smoke

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  /root/m1s2/module1-slice2-records.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  /usr/local/libexec/johnny/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  /etc/systemd/system/johnny-m1s2-reader.service" | sudo sha256sum -c - &&
sudo bash /root/m1s2/module1-slice2-records.sh load'
```

Expect `OK-observer driver id=…`, `CFG ver=0 …`, `LOADED prog_id=… (verifier accepted; not attached)`, `OK-readback-parse`, the reader's `M1S2-READER-END reason=signal-15 records=0 …`, `READER-RESULT success`, `OK-reader-smoke`, and **`M1S2-LOAD-DONE prog_id=…`**. The observer stays attached the whole time. On any STOP the helper removes its pins itself and ends `M1S2-ROLLBACK-DONE` + `M1S2-LOAD-STOPS`.

### Paste 6: Swap observer → records (capture gap of a few seconds; needs AJ's Decision 1)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  /root/m1s2/module1-slice2-records.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  /usr/local/libexec/johnny/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  /etc/systemd/system/johnny-m1s2-reader.service" | sudo sha256sum -c - &&
sudo bash /root/m1s2/module1-slice2-records.sh swap'
```

Expect `OK-irq-baseline …`, `SWAP-BEGIN observer=… records=…`, `OK-c1-stopped`, `ATTACHED xdpdrv prog_id=…`, `OK-xdp-mode driver id=… j_xdp_records (post-swap)`, `OK-ctl-accounting (post-swap)`, `C1-UNIT enabled=enabled active=inactive`, and **`M1S2-SWAP-DONE`**. On any STOP it returns to slice 1c by itself (`REVERTING-TO-SLICE-1C`, `OK-xdp-mode driver id=… j_xdp_observe`, `M1S2-SWAP-STOPS`).

### Paste 7: One bounded reader run (60 s) and summary

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  /root/m1s2/module1-slice2-records.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  /usr/local/libexec/johnny/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  /etc/systemd/system/johnny-m1s2-reader.service" | sudo sha256sum -c - &&
sudo bash /root/m1s2/module1-slice2-records.sh read'
```

Takes about 60 s. Expect `READER-STARTED invocation=…`, `M1S2-READER-END reason=max-seconds records=… bytes=…` (or `reason=max-records` / `max-bytes`), `READER-RESULT success`, `RUN-FILE /var/lib/johnny/m1s2/run-….bin mode=600 0:0 dir=700 0:0`, the summary (counts, per-queue totals, top 5 talkers), and **`M1S2-READ-DONE`**. The records program stays attached; a STOP here changes nothing (run Paste 9 or Rollback R1 next), except `STOP-reader-overran`: the helper first stops the still-running reader unit (`READER-STOPPED`) rather than leaving it to `RuntimeMaxSec`.

### Paste 8: Verify (read-only)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  /root/m1s2/module1-slice2-records.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  /usr/local/libexec/johnny/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  /etc/systemd/system/johnny-m1s2-reader.service" | sudo sha256sum -c - &&
sudo bash /root/m1s2/module1-slice2-records.sh verify'
```

Expect, at both `verify-start` and `verify-end`: `OK-xdp-mode driver id=… j_xdp_records`, `OK-irq-pins-unchanged`, `OK-partition … l3_diff=… l4_diff=…` (within tolerance), `OK-ctl-accounting`; then `VERIFY-WINDOW secs=5 pkts=… seen=… emitted=…`, `NIC-DROP-DELTAS …`, and **`M1S2-VERIFY-DONE`**. Read-only: a STOP changes nothing.

### Paste 9: Close the trial: back to slice 1c (the default end)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  /root/m1s2/module1-slice2-records.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2/module1-xdp-records.o
32dc159f01b42a4b7cf3906c6fd0d12535b85cf1a36262f30d6211e44cce38e2  /usr/local/libexec/johnny/johnny-m1s2-reader.py
267c9bd63292adfd1c157b7476acd9872c535f406a77c50b5b46d8af799eba52  /etc/systemd/system/johnny-m1s2-reader.service
a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  /root/m1s1b/module1-slice1c-boot.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2/module1-slice2-records.sh rollback &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh status &&
echo M1S2-TRIAL-CLOSED'
```

Expect `DETACHED mode=driver id=… j_xdp_records`, `PINS-REMOVED`, `OK-no-j_xdp_records-loaded`, `C1-STARTED`, `OK-xdp-mode driver id=… j_xdp_observe`, `M1S2-ROLLBACK-DONE`, slice 1c's `M1S1C-STATUS-DONE`, and **`M1S2-TRIAL-CLOSED`**. The installed files and the run file stay until AJ runs R2 / R3.

## Rollback (not part of the paste sequence above)

These blocks are run only when AJ chooses. A reboot is also a full return to slice 1c for the attach and the pins (not for the installed files or run files).

### R1: Back to slice 1c now (idempotent; safe in any state)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  /root/m1s2/module1-slice2-records.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2/module1-slice2-records.sh rollback'
```

Ends **`M1S2-ROLLBACK-DONE`**. With nothing of ours loaded it prints `KEEP-observer …`, `PINS-ABSENT`, `C1-ALREADY-ACTIVE` and changes nothing. A foreign XDP id is never detached (`STOP-xdp-foreign`, then `M1S2-ROLLBACK-STOPS`). Ownership is the id behind `/sys/fs/bpf/johnny_m1s2/prog`, not the name: a `j_xdp_records` without our pin is `STOP-xdp-records-unpinned` and is not detached. If our program is still attached after the detach step, the pins stay (`KEEP-PINS`) so R1 can be rerun.

### R2: Uninstall the slice 2 files (runs R1 first)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "044a0868bf2f118a91e836909f09b5c2dc1a29700bd6114f05864daee0264d95  /root/m1s2/module1-slice2-records.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2/module1-slice2-records.sh rollback &&
sudo rm -f /etc/systemd/system/johnny-m1s2-reader.service /usr/local/libexec/johnny/johnny-m1s2-reader.py /root/m1s2/module1-slice2-records.sh /root/m1s2/module1-xdp-records.o /root/m1s2/irq-baseline.txt &&
sudo rmdir /root/m1s2 &&
sudo rmdir --ignore-fail-on-non-empty /usr/local/libexec/johnny &&
sudo systemctl daemon-reload &&
sudo test ! -e /etc/systemd/system/johnny-m1s2-reader.service &&
sudo test ! -e /root/m1s2 &&
sudo test ! -e /sys/fs/bpf/johnny_m1s2 &&
rm -f /home/aj/cis-audit/m1s2/module1-xdp-records.o /home/aj/cis-audit/m1s2/johnny-m1s2-reader.py /home/aj/cis-audit/m1s2/johnny-m1s2-reader.service /home/aj/cis-audit/m1s2/module1-slice2-records.sh &&
rmdir /home/aj/cis-audit/m1s2 &&
echo M1S2-UNINSTALL-DONE'
```

Ends `M1S2-ROLLBACK-DONE` then **`M1S2-UNINSTALL-DONE`**. Slice 1c files are not touched.

### R3: Delete the run files (privacy default at the end of the trial)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
sudo find /var/lib/johnny/m1s2 -maxdepth 1 -type f -name "run-*.bin" -print -delete &&
sudo rmdir /var/lib/johnny/m1s2 &&
sudo rmdir --ignore-fail-on-non-empty /var/lib/johnny &&
sudo test ! -e /var/lib/johnny/m1s2 &&
echo M1S2-RUNFILES-DELETED'
```

Lists each deleted `run-….bin`, then **`M1S2-RUNFILES-DELETED`**. Skip this block if AJ wants to keep the run files.

## What each STOP means

| STOP | Meaning | What changed |
|---|---|---|
| `STOP-lib-hash`, `STOP-c1-*-hash`, `STOP-object-hash`, `STOP-reader-hash`, `STOP-reader-unit-hash` | A pinned file differs or is not root-owned | Nothing |
| `STOP-observer-not-attached` | Slice 1c is not in its normal state | Nothing; check slice 1c first |
| `STOP-records-already-loaded`, `STOP-pin-dir-exists` | Leftovers from an earlier try | Nothing; run R1 |
| `STOP-load` | Verifier or bpftool refused the object | Pins removed by the helper; observer untouched |
| `STOP-reader-smoke-result` (journal `STOP-obj-get errno=1`) | The kernel wants a capability for the reader (§ Changes 1 assumption wrong) | Pins removed; back to review, no widening in place |
| `STOP-attach` | Native attach refused (slot taken) | Helper restarts slice 1c |
| `STOP-ctl-accounting-*`, `STOP-irq-pins-moved-*` | Counter invariant or IRQ pin changed | `verify`: nothing; `swap`: back to slice 1c |
| `STOP-reader-result`, `STOP-reader-end-reason` | Reader failed or ended without a cap | Records still attached; run Paste 9 |
| `STOP-xdp-foreign` | An XDP id that is not ours and not the observer | Never detached; AJ decides |
| `STOP-xdp-records-unpinned` | A program named `j_xdp_records` is attached but is not the id behind our `prog` pin | Never detached; AJ decides |
| `STOP-detach-failed`, `STOP-records-still-attached` (+ `KEEP-PINS`) | Our pinned program could not be detached | Pins kept so ownership is still provable; rerun R1 |
| `STOP-reader-overran` (+ `READER-STOPPED`) | The reader unit was still active after the wait | Reader stopped by the helper; records still attached; run Paste 9 |
| `STOP-load-pin-mismatch`, `STOP-records-not-pinned` | The loaded `j_xdp_records` id is not the one behind our pin | `load`: rolled back; `swap`: nothing |
| `STOP-locked` | Another slice 2 helper run holds `/run/johnny-m1s2.lock` | Nothing |

## Tokens AJ sends back

`SELF-TEST-OK`, `M1S2-COPY-DONE`, `M1S2-PROBE-DONE`, `M1S2-INSTALL-DONE`, `M1S2-LOAD-DONE prog_id=…`, `M1S2-SWAP-DONE`, `M1S2-READ-DONE` (+ the summary), `M1S2-VERIFY-DONE` (+ `NIC-DROP-DELTAS`), `M1S2-TRIAL-CLOSED`; rollback: `M1S2-ROLLBACK-DONE`, `M1S2-UNINSTALL-DONE`, `M1S2-RUNFILES-DELETED`. Any `STOP-…` or `M1S2-…-STOPS`: send the whole output.

## Assumptions

- **[Assumption]** Ubuntu `7.0.0-42` keeps upstream's post-6.5 placement of the `unprivileged_bpf_disabled` check, so a capability-less uid 0 can `BPF_OBJ_GET` and `mmap` a root-owned pinned ring. Paste 5 tests it and fails closed.
- **[Assumption]** `MemoryDenyWriteExecute=yes` works with the reader's `ctypes` use (no callbacks). Paste 5's smoke runs under the full sandbox.
- **[Assumption]** x86-64 TSO plus CPython ordering makes the consumer-position store safe without a fence (design §8; Assurance to challenge).
- Defaults (sampling, rate, ring size) are not measurements.
- Everything about Johnny comes from slice 1/1b/1c records and handoff rev 104; no Johnny contact while writing this.

## Sources

- Upstream `kernel/bpf/syscall.c` and commit `1d28635abcf1` (moving unprivileged checks into `map_create()` / `bpf_prog_load()`): <https://github.com/torvalds/linux/commit/1d28635abcf1914425d6516e641978011984c58a>
- BPF ring buffer mmap layout: <https://docs.kernel.org/bpf/ringbuf.html>
- systemd sandboxing: <https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html>
- Design and prior slices: `module1-slice2-ringbuf-design.md`, `module1-slice1b-attach.md`, `module1-slice1c-boot-unit.md`.
