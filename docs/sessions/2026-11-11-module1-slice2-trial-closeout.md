# 2026-11-11 UTC (~19:11 to ~19:21 UTC, where ~19:11 is the Paste 5 run-file stamp `20261111T191146Z` (Pastes 1–4 printed no clock and ran before it) and ~19:21 rounds the printed close 19:20:39Z; ~1:11 to ~1:21 PM America/Chicago): Module 1 slice 2 header-only ringbuf trial applied on Johnny and closed (closeout)

Seat: code-writer (Claude Code, Claude Fable 5.1). Branch `claude/module1-slice2-closeout`, from `origin/claude/practical-ritchie-4c6vvf` tip `f7840f4` (PR #30 merged there: slice 2 design, code, runbook, self-test; reviewed by the adversarial-reviewer). Docs-only closeout. **No SSH, no sudo, no write on Johnny in this closeout.** No deployed object, reader, unit, helper or source changed; all seven sha256 pins unchanged; the self-test is unchanged and still prints `SELF-TEST-OK`.

**What AJ ran (from rock-box to Johnny; runbook `docs/tool-install/module1-slice2-ringbuf.md`, Pastes 1–9, unchanged).**
- **Paste 1**: 7 pins OK, `HOST-TEST cases=44`, `READER-TEST cases=22`, `E2E scenarios=23`, `RUNBOOK blocks=12`, **`SELF-TEST-OK`**.
- **Paste 2**: copied to `/home/aj/cis-audit/m1s2`, hashes checked, **`M1S2-COPY-DONE`**.
- **Paste 3**: `unprivileged_bpf_disabled=2`, Python 3.14.4, observer `driver id=75`, **`M1S2-PROBE-DONE`**.
- **Paste 4**: NIC `rx_dropped=7` baseline (pre-existing, not a trial failure), **`M1S2-INSTALL-DONE`**.
- **Paste 5**: **`M1S2-LOAD-DONE prog_id=125`** (verifier accepted, not attached). Reader smoke: `run-20261111T191146Z.bin records=0 bytes=96 reason=signal-15 seq_gaps=0 ring_discarded=0`, `READER-RESULT success` (capability-less uid 0 reader works on `7.0.0-42`).
- **Decision 1**: AJ chose (a) stop-then-attach (brief capture gap).
- **Paste 6** at **2026-11-11T19:18:05Z** (1:18:05 PM CST): `observer=75 records=125`, `OK-c1-stopped`, `ATTACHED xdpdrv prog_id=125`, post-swap partition/IRQ/ctl OK (`seen=365 sum=365 pkts=362`), `C1-UNIT enabled=enabled active=inactive`, **`M1S2-SWAP-DONE`**.
- **Paste 7**: `run-20261111T191845Z.bin`, `reason=max-seconds records=31419 bytes=2513616 seq_gaps=0 ring_discarded=0 backlog=176`, `ctl_seen=21420 ctl_sampled_out=0 ctl_rate_limited=6119 ctl_rb_full=0 ctl_emitted=15301 ctl_discarded=0`, `READER-RESULT success`; `span_s=98.160`; flags all `0` except `rl_recovered=601`; RXQ 6 = 15794 of 31419; udp 23676, tcp 6126, icmp 1566; top src `172.217.153.231` 18917, `192.168.50.223` 7185, `34.225.159.174` 1001, `192.168.50.188` 787, `10.5.0.1` 783; cumulative ctl `seen 46978 rate_limited 15527 emitted 31451 rb_full 0`; IRQ pins unchanged; `l3_diff=0 l4_diff=0`; **`M1S2-READ-DONE`**.
- **Paste 8**: all checks OK at start and end, `VERIFY-WINDOW secs=5 pkts=406 seen=407 emitted=407`, `NIC-DROP-DELTAS rx_dropped=0 rx_missed_errors=0 rx_fifo_errors=0 rx_errors=0`, **`M1S2-VERIFY-DONE`**.
- **Paste 9** at **2026-11-11T19:20:39Z** (1:20:39 PM CST): `DETACHED mode=driver id=125 j_xdp_records`, `PINS-REMOVED`, `OK-no-j_xdp_records-loaded`, `C1-STARTED`, observer `driver id=138 j_xdp_observe`, **`M1S2-ROLLBACK-DONE`**; slice 1c status all hashes OK, `johnny-capture-xdp`/`irq`/`tuning` enabled+active, `suricata` disabled+inactive, `IRQ-BASELINE same`, `M1S1B-STATUS-DONE`, `M1S1C-STATUS-DONE`, **`M1S2-TRIAL-CLOSED`**.
- Rollback blocks R2 (uninstall) and R3 (delete run files) were not run. No reboot.

**Left in place.** Installed slice 2 files (`/root/m1s2/*`, `/usr/local/libexec/johnny/johnny-m1s2-reader.py`, `/etc/systemd/system/johnny-m1s2-reader.service`, not enabled) and two run files under `/var/lib/johnny/m1s2`. Nothing from slice 2 is attached or pinned.

**Not claimed.** One 60 s read is not a traffic baseline. Zero NIC drop deltas were one 5 s window. The rate limit dropped about one third of sampled records under a bursty UDP flow on RXQ 6 (top talker `172.217.153.231`): that is the compiled default (2000 rec/s/CPU, burst 4000) working as designed, not a trial failure. Tuning is a future decision, not a change in this closeout.

**Docs changed.** `docs/tool-install/module1-slice2-ringbuf.md` (title and status: applied and closed; Decision 1/2 outcomes; new § Trial record; paste blocks unchanged), `docs/tool-install/module1-slice2-ringbuf-design.md` (status banner), `docs/os-handoff.md` (rev 105; Module 1 next-steps entry), `README.md` (Module 1 status line), this note and its CSV.

**Next Module 1 step (identified, not started).** AJ chooses: symmetric RSS, AF_XDP evaluation, a slice 2 rate/sampling tuning pass, or the Daemon's Rust ring-buffer consumer. R2/R3 on the slice 2 files and run files are also AJ's call.
