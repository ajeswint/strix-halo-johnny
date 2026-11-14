# Rate cap raise — apply output (2026-11-14)

Relayed from AJ's Rock Box terminal (pasted into chat 2026-11-14, America/Chicago). Paste A and Paste C output is copied verbatim below, minus the echoed commands. Paste B's output was cut short in the chat relay ("characters omitted"), so it is not reproduced; Paste C's `status` shows its result (baseline lines and new cfg).

## Paste A (read-only preflight) — output

```
/root/m1s2b/module1-slice2b-boot.sh: OK
/usr/local/libexec/johnny/johnny-m1s2b-reader.py: OK
/etc/systemd/system/johnny-m1s2b-reader.service: OK
/etc/systemd/system/johnny-capture-xdp-records.service: OK
/root/m1s2b/module1-xdp-records.o: OK
HOST johnny
ATTACH records 78
PROG-XDP-COUNT 1 records=78 observer=none
UNIT-2B enabled=enabled active=active
UNIT-READER enabled=enabled active=active
UNIT-1C enabled=disabled active=inactive
PINS m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state prog
STATS pkts=68885570 bytes=61896886572
CTL seen 68885571
CTL sampled_out 0
CTL rate_limited 18217138
CTL rb_full 0
CTL emitted 50668433
CTL discarded 0
CFG ver=1 sample_every=1 rate=8000 burst=16000
LINK eno1np0 speed=10000 carrier=1 oper=up
OUT-DIR /var/lib/johnny/m1s2b
IRQ-COUNT 12
M1S2B-STATUS-DONE
M1S2B-NORC-PREFLIGHT-DONE
```

## Paste C (verify + 60 s window) — output

```
/root/m1s2b/module1-slice2b-boot.sh: OK
M1S2B-VERIFY-BEGIN DATE-UTC 2026-11-14T21:32:23Z
OK-object-hash a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481
OK-reader-hash 476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37
OK-reader-unit-hash e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c
OK-boot-unit-hash 4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a
OK-irq-helper-hash db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4
OK-cores-hash 16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b
OK-unit johnny-capture-xdp-records.service enabled=enabled active=active
OK-reader johnny-m1s2b-reader.service enabled=enabled active=active
OK-suricata disabled/inactive
OK-irq-service active
OK-tuning-service active
OK-eno3
OK-xdp-mode driver id=78 (verify-before)
OK-cfg ver=1 sample_every=1 rate=1000000 burst=100000 (verify-before)
OK-irq-pins-unchanged (verify-before)
OK-xdp-mode driver id=78 (verify-after)
OK-cfg ver=1 sample_every=1 rate=1000000 burst=100000 (verify-after)
OK-irq-pins-unchanged (verify-after)
VERIFY-WINDOW secs=5 xdp-pkts-delta=582 xdp-bytes-delta=126824 ctl-seen-delta=581 tcpdump-captured=486 tcpdump-kernel-drops=0
PASS-RATIO tcpdump=486 xdp=582 pct=83
VERIFY-DROPS rate_limited=0 rb_full=0 discarded=0
OK-no-drops-verify
ETHTOOL-DROP-DELTAS none (checked=16)
OK-xdp-pass-tcpdump-sees-traffic
M1S2B-VERIFY-DONE
WINDOW secs=60 seen-delta=32812 rate_limited-delta=0 rb_full-delta=0 discarded-delta=0 emitted-delta=32812 pkts-delta=32814
OK-no-drops-window
M1S2B-WINDOW-DONE
HOST johnny
ATTACH records 78
PROG-XDP-COUNT 1 records=78 observer=none
UNIT-2B enabled=enabled active=active
UNIT-READER enabled=enabled active=active
UNIT-1C enabled=disabled active=inactive
PINS m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state prog
STATS pkts=68924105 bytes=61931641135
CTL seen 68924106
CTL sampled_out 0
CTL rate_limited 18217138
CTL rb_full 0
CTL emitted 50706968
CTL discarded 0
CFG ver=1 sample_every=1 rate=1000000 burst=100000
BASELINE-EXISTS /root/m1s2b/no-ratecap-baseline.txt
BASELINE DATE-UTC 2026-11-14T21:32:11Z
BASELINE boot_id e9476f51-151b-4593-aa88-811e397794d1
BASELINE records_prog_id 78
BASELINE STATS pkts=68888292 bytes=61897897686
BASELINE CTL seen 68888294
BASELINE CTL sampled_out 0
BASELINE CTL rate_limited 18217138
BASELINE CTL rb_full 0
BASELINE CTL emitted 50671156
BASELINE CTL discarded 0
BASELINE READER-INVOCATION=502eed3ad10a42abab7c05ce28607223
BASELINE READER-NRESTARTS=0
BASELINE READER-MAINPID=25996
BASELINE READER-MARK-DATE-UTC=2026-11-14T21:32:11Z
LINK eno1np0 speed=10000 carrier=1 oper=up
OUT-DIR /var/lib/johnny/m1s2b
IRQ-COUNT 12
M1S2B-STATUS-DONE
M1S2B-READER-BEGIN out_dir=/var/lib/johnny/m1s2b ring_map_id=34 cfg=ver:1,every:1,rate:1000000,burst:100000 file_max_bytes=1073741824 file_max_seconds=3600 keep=200 dir_cap=214748364800 reserve=107374182400
M1S2B-NORC-VERIFY-DONE
```

`rate_limited 18217138` is the historical total from before the change (it did not move between Paste A and Paste C).
