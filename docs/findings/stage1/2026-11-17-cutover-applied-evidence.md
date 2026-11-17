# Stage 1 cutover evidence (AJ ran on Johnny, 2026-11-17, PR #42 build)
- Earlier S1-3 ~2:30 PM CT with e39d7768 build: FAILED STOP-mmap-probe errno=22 -> PR #42 (merge c23ea4f).
- Paste C just before, 20:27Z: M1S2B-NORC-VERIFY-DONE, window-60 seen-delta=26416, zero drops.
- S1-1..S1-5 all passed. S1-3 ~3:29 PM CT, S1-4 ~3:30 PM CT, S1-5 ~3:42 PM CT.
- S1-3 probe line: {"version":1,"event":"probe","ring_map_id":34,"ring_bytes":4194304,"cfg":{"ver":1,"sample_every":1,"rate":1000000,"burst":100000},"ctl":{"seen":168053271,"sampled_out":0,"rate_limited":18217138,"rb_full":0,"emitted":149836133,"discarded":0},"consumer_pos":13185579704,"producer_pos":13185579704,"backlog":0}. Rust/Python summaries matched; STAGE1-PROBE-INSTALL-DONE.
- S1-4: Python reader wants symlink removed, johnny-daemon enabled. Unit props Result=success NRestarts=0 MemoryMax=1073741824 MemorySwapMax=0. reader-begin JSON: ring_map_id 34, same cfg, file_max_bytes 1073741824, file_max_seconds 3600, keep 200, dir_cap_bytes 214748364800, reserve_bytes 107374182400, on_unknown_version skip. STAGE1-CUTOVER-DONE.
- S1-5 (verbatim key lines):
  WINDOW secs=60 seen-delta=17087 rate_limited-delta=0 rb_full-delta=0 discarded-delta=0 emitted-delta=17087 pkts-delta=17088
  OK-no-drops-window
  ATTACH records 78 ; UNIT-2B enabled=enabled active=active ; UNIT-READER enabled=disabled active=inactive ; UNIT-1C enabled=disabled active=inactive
  STATS pkts=168241298 bytes=153998600277
  CTL seen 168241300 / sampled_out 0 / rate_limited 18217138 / rb_full 0 / emitted 150024162 / discarded 0
  CFG ver=1 sample_every=1 rate=1000000 burst=100000
  BASELINE DATE-UTC 2026-11-14T21:32:11Z, BASELINE CTL rate_limited 18217138 (=> 0 new rate_limited from baseline to cutover)
  HEADER magic=JM1S2RB ver=1 start_utc=2026-11-17 21:30:30Z cfg=ver:1,every:1,rate:1000000,burst:100000
  CTL-START seen=168066737 sampled_out=0 rate_limited=18217138 rb_full=0 emitted=149849599 discarded=0
  SUMMARY records=174588 total_wire_bytes=109633379 seq_gaps=0
  QUEUES rxq0=9369 rxq1=12283 rxq2=7822 rxq3=11978 rxq4=41818 rxq5=9650 rxq6=21718 rxq7=14769 rxq8=7718 rxq9=17240 rxq10=11497 rxq11=8726
  PROTO tcp=88176 udp=74748 icmp=11346 0=201 2=117
  Rust and Python summaries matched; 0 STOP- lines in johnny-daemon journal; STAGE1-VERIFY-DONE.
- Johnny live pins now: /usr/local/libexec/johnny/johnny-daemon 08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac ; /etc/systemd/system/johnny-daemon.service e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa. Python reader files still present (476cf867…, unit e5c16249…) but disabled; Rollback section of the runbook stays available. Slice 2b pins unchanged.
- Paste W (week test) was ended early by AJ's choice (test ran 2026-11-14 15:33 CT to cutover, ~3 days, not 7); superseded, no longer the gate.
