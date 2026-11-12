# Slice 2b apply on Johnny, 2026-11-12T04:05Z (2026-11-11 ~22:05 CT), run by AJ from Rock Box

- Paste 1: PINS-OK, SHELLCHECK-OK, STATIC-CHECKS-OK, READER-TESTS-OK, E2E-OK scenarios=11, RUNBOOK-OK blocks=9, SELF-TEST-OK
- Paste 2: 5x sha256 OK, M1S2B-COPY-DONE
- Paste 3: hashes OK; `eno1np0(4) driver id 138`; 1c unit enabled/active; M1S2B-PROBE-DONE
- Paste 4: 10x sha256 OK; systemd-analyze verify clean except unrelated xfs_scrub CPUAccounting warnings; M1S2B-INSTALL-DONE
- Paste 5 status output:

```
Removed '/etc/systemd/system/multi-user.target.wants/johnny-capture-xdp.service'.
Created symlink '/etc/systemd/system/multi-user.target.wants/johnny-capture-xdp-records.service' -> '/etc/systemd/system/johnny-capture-xdp-records.service'.
Created symlink '/etc/systemd/system/multi-user.target.wants/johnny-m1s2b-reader.service' -> '/etc/systemd/system/johnny-m1s2b-reader.service'.
HOST johnny
ATTACH records 192
PROG-XDP-COUNT 1 records=192 observer=none
UNIT-2B enabled=enabled active=active
UNIT-READER enabled=enabled active=active
UNIT-1C enabled=disabled active=inactive
PINS m1_rxq m1_stats m2_cfg m2_ctl m2_rb m2_state prog
STATS pkts=0 bytes=0
CTL seen 0
CTL sampled_out 0
CTL rate_limited 0
CTL rb_full 0
CTL emitted 0
CTL discarded 0
CFG ver=1 sample_every=1 rate=8000 burst=16000
LINK eno1np0 speed=10000 carrier=1 oper=up
OUT-DIR /var/lib/johnny/m1s2b
IRQ-COUNT 12
M1S2B-STATUS-DONE
M1S2B-CUTOVER-DONE
```

- Paste 6 verify output (did NOT print M1S2B-VERIFY-DONE):

```
M1S2B-VERIFY-BEGIN DATE-UTC 2026-11-12T04:06:53Z
OK-object-hash a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481
OK-reader-hash e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581
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
OK-xdp-mode driver id=192 (verify-before)
OK-cfg ver=1 sample_every=1 rate=8000 burst=16000 (verify-before)
OK-irq-pins-unchanged (verify-before)
OK-xdp-mode driver id=192 (verify-after)
OK-cfg ver=1 sample_every=1 rate=8000 burst=16000 (verify-after)
OK-irq-pins-unchanged (verify-after)
VERIFY-WINDOW secs=5 xdp-pkts-delta=0 xdp-bytes-delta=0 ctl-seen-delta=0 tcpdump-captured=879 tcpdump-kernel-drops=0
STOP-no-traffic-verify (SPAN quiet during verify window)
```

Note: tcpdump saw 879 packets in the same window while the XDP counters read 0. That fits the independent cloud audit's finding that dump_stats/ctl_rows parse a bpftool JSON shape that bpftool doesn't emit (see 2026-11-11-cloud-audit.md). Not yet confirmed on Johnny.
