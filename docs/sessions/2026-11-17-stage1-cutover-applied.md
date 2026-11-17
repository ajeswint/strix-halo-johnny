# 2026-11-17 America/Chicago: Stage 1 Cutover Applied and Verified on Johnny (`johnny-daemon.service`)

- **Date:** 2026-11-17 America/Chicago
- **Status:** **APPLIED AND VERIFIED ON JOHNNY (2026-11-17, PR #42 build, merge `c23ea4f`).** Johnny now runs `johnny-daemon.service` (`enabled`/`active`); `johnny-m1s2b-reader.service` is `disabled`/`inactive` with its files kept on disk for rollback via the Rollback section of [`docs/tool-install/stage1-rust-daemon-cutover.md`](../tool-install/stage1-rust-daemon-cutover.md). Paste W (week test) was ended early by AJ's choice (test ran `2026-11-14 15:33 CT` to cutover, ~3 days, not 7) and is superseded (no longer the gate).
- **Branch:** `claude/stage1-cutover-applied` (worktree `/home/aj/Projects/strix-halo-johnny-stage1-applied`)
- **Revision:** handoff rev 119 ([`docs/os-handoff.md`](../os-handoff.md)), runbook rev 3 ([`docs/tool-install/stage1-rust-daemon-cutover.md`](../tool-install/stage1-rust-daemon-cutover.md)), architecture rev 2 ([`docs/architecture/architecture-rev2.md`](../architecture/architecture-rev2.md))
- **Constraints kept:** docs-only closeout on Rock Box (`claude/stage1-cutover-applied`). No push, no ssh, no sudo, no contact with `192.168.50.152`, no code/script/unit/pin changes, and no historical session/findings files edited.

## 1. Pre-Cutover Context & Earlier Attempt (2026-11-17)

- **Earlier Paste S1-3 attempt (`~2:30 PM CT`):** Ran on Johnny with the `e39d7768` (`e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5`) build and failed at `--probe` with `FAILED STOP-mmap-probe errno=22`, resolved in PR #42 (merge `c23ea4f`, [`docs/sessions/2026-11-17-stage1-probe-rdwr-fix.md`](2026-11-17-stage1-probe-rdwr-fix.md)).
- **Pre-cutover Paste C (`20:27Z`):** Ran just before cutover: `M1S2B-NORC-VERIFY-DONE`, `window-60` `seen-delta=26416`, zero drops.
- **Paste W (week test) superseded:** Ended early by AJ's choice (test ran `2026-11-14 15:33 CT` to cutover, ~3 days, not 7); superseded and no longer the gate.

## 2. Stage 1 Cutover Execution on Johnny (2026-11-17, PR #42 Build)

All five pastes (`S1-1..S1-5`) in [`docs/tool-install/stage1-rust-daemon-cutover.md`](../tool-install/stage1-rust-daemon-cutover.md) passed:

1. **Paste S1-1 & Paste S1-2:** Passed (`STAGE1-ROCKBOX-GATE-DONE`, `STAGE1-COPY-DONE`).
2. **Paste S1-3 (`~3:29 PM CT`):** Preflight hashes verified, binary and unit installed, and `--probe` emitted verbatim:
   ```json
   {"version":1,"event":"probe","ring_map_id":34,"ring_bytes":4194304,"cfg":{"ver":1,"sample_every":1,"rate":1000000,"burst":100000},"ctl":{"seen":168053271,"sampled_out":0,"rate_limited":18217138,"rb_full":0,"emitted":149836133,"discarded":0},"consumer_pos":13185579704,"producer_pos":13185579704,"backlog":0}
   ```
   Rust and Python `--summary` outputs matched; **`STAGE1-PROBE-INSTALL-DONE`**.
3. **Paste S1-4 (`~3:30 PM CT`):** Python reader wants symlink removed (`johnny-m1s2b-reader.service` disabled and stopped; drop-in `/etc/systemd/system/johnny-m1s2b-reader.service.d/stage1-cutover.conf` installed) and `johnny-daemon.service` enabled and started. Unit properties: `Result=success`, `NRestarts=0`, `MemoryMax=1073741824`, `MemorySwapMax=0`. Journal `reader-begin` JSON: `ring_map_id` `34`, same `cfg` (`ver=1`, `sample_every=1`, `rate=1000000`, `burst=100000`), `file_max_bytes` `1073741824`, `file_max_seconds` `3600`, `keep` `200`, `dir_cap_bytes` `214748364800`, `reserve_bytes` `107374182400`, `on_unknown_version` `skip`. **`STAGE1-CUTOVER-DONE`**.
4. **Paste S1-5 (`~3:42 PM CT`):** Verbatim key lines:
   ```text
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
   ```
   Rust and Python summaries matched; `0` `STOP-` lines in `johnny-daemon` journal; **`STAGE1-VERIFY-DONE`**.

## 3. Johnny Live Pins & Rollback State

- **Active Stage 1 pins on Johnny:**
  - `/usr/local/libexec/johnny/johnny-daemon`: `08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac`
  - `/etc/systemd/system/johnny-daemon.service`: `e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa`
  - CycloneDX 1.5 SBOM (`crates/johnny-daemon.cdx.json`, staged in `/home/aj/cis-audit/stage1/johnny-daemon.cdx.json`): `8d74fe6ee2f9200ff8b18b63c596a5301688055287c72a5ecc756485ecb59b86`
- **Python reader rollback state:** `/usr/local/libexec/johnny/johnny-m1s2b-reader.py` (`476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37`) and `/etc/systemd/system/johnny-m1s2b-reader.service` (`e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c`) remain present on disk with `johnny-m1s2b-reader.service` `disabled`/`inactive`; the Rollback section of [`docs/tool-install/stage1-rust-daemon-cutover.md`](../tool-install/stage1-rust-daemon-cutover.md) stays available.
- **Slice 2b pins unchanged:** `/root/m1s2b/module1-slice2b-boot.sh` (`a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb`), `/etc/systemd/system/johnny-capture-xdp-records.service` (`4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a`), `/root/m1s2b/module1-xdp-records.o` (`a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481`).
