# Module 1 slice 2b — cold-boot verify evidence (2026-11-12)

AJ ran Paste 7 (cold reboot of Johnny), then Paste 8 (post-reboot verify) from Rock Box at about 2026-11-12 05:54Z.

**First Paste 8 run: false positive.** The original ordering-cycle gate
`sudo journalctl -b --grep "ordering cycle" -q` searched every journal line of the boot, so it
matched sudo's own log entry of the command line (which contains the words "ordering cycle") and
opened a pager. That was a runbook bug, not a Johnny fault.

**Corrected gate used for the passing run:**

```
cyc=$(sudo journalctl -b --no-pager -q _PID=1 -o cat | grep -ci "ordering cycle" || true) &&
if [ "$cyc" != "0" ]; then echo "STOP-ordering-cycle-warning count=$cyc"; false; fi &&
```

It searches only systemd's (PID 1) own messages, never pages, and fails if `cyc` is not `0`.

## Output of the passing Paste 8 run (verbatim from AJ)

```
/root/m1s2b/module1-slice2b-boot.sh: OK
M1S2B-VERIFY-BEGIN DATE-UTC 2026-11-12T05:54:49Z
OK-object-hash a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481
OK-reader-hash fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573
OK-reader-unit-hash 5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c
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
OK-cfg ver=1 sample_every=1 rate=8000 burst=16000 (verify-before)
OK-irq-pins-unchanged (verify-before)
OK-xdp-mode driver id=78 (verify-after)
OK-cfg ver=1 sample_every=1 rate=8000 burst=16000 (verify-after)
OK-irq-pins-unchanged (verify-after)
VERIFY-WINDOW secs=5 xdp-pkts-delta=3882 xdp-bytes-delta=4048054 ctl-seen-delta=3662 tcpdump-captured=3141 tcpdump-kernel-drops=0
PASS-RATIO tcpdump=3141 xdp=3882 pct=80
ETHTOOL-DROP-DELTAS none (checked=16)
OK-xdp-pass-tcpdump-sees-traffic
M1S2B-VERIFY-DONE
HOST johnny
ATTACH records 78
PROG-XDP-COUNT 1 records=78 observer=none
UNIT-2B enabled=enabled active=active
UNIT-READER enabled=enabled active=active
UNIT-1C enabled=disabled active=inactive
PINS m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state prog
STATS pkts=33433 bytes=27947787
CTL seen 33436
CTL sampled_out 0
CTL rate_limited 0
CTL rb_full 0
CTL emitted 33436
CTL discarded 0
CFG ver=1 sample_every=1 rate=8000 burst=16000
LINK eno1np0 speed=10000 carrier=1 oper=up
OUT-DIR /var/lib/johnny/m1s2b
IRQ-COUNT 12
M1S2B-STATUS-DONE
M1S2B-COLD-BOOT-VERIFY-DONE
```
