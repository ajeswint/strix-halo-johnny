# Module 1 Slice 2b: Boot-time j_xdp_records and Persistent Rotating Reader

Rev 4, 2026-11-14 America/Chicago. Status: **2b APPLIED, VERIFIED, and COLD-BOOT PROVEN on Johnny (2026-11-12 ~05:54Z). Retention raise (1 GiB / 3600 s per file, keep=200, 200 GiB dir cap, 100 GiB reserve) DRAFTED, NOT APPLIED.**

## Purpose and Scope

Slice 2 (`docs/tool-install/module1-slice2-ringbuf.md`) verified the header-only passive ring-buffer records program `j_xdp_records` on Johnny on 2026-11-11 during a bounded trial run. Following the trial, Johnny was cleanly rolled back to the slice 1c observer (`j_xdp_observe`, `xdpdrv`, `prog_id=138`).

AJ chose slice 2b by name (2026-11-11) to make `j_xdp_records` the boot-time program on `eno1np0`, replacing slice 1c's observer unit/helper as the boot attach, with the root-only reader as a bounded, rotating, persistent service so the mirror port is continuously recorded.

This runbook specifies:
1. Reuse of the already-verified pinned slice 2 BPF object (`module1-xdp-records.o`).
2. Boot-time configuration of `m2_cfg` (ver=1, sample_every=1, rate=8000, burst=16000) verified before attach.
3. New boot helper `/root/m1s2b/module1-slice2b-boot.sh`.
4. New oneshot unit `johnny-capture-xdp-records.service` with identical ordering to 1c (`After=/Wants= network-online.target johnny-capture-irq.service`, NO `After=johnny-capture-tuning.service`).
5. New persistent rotating reader `johnny-m1s2b-reader.py` and service `johnny-m1s2b-reader.service` outputting to `/var/lib/johnny/m1s2b` with rotation at 64 MiB or 3600 s, `keep=6` (dir cap 384 MiB), and 256 MiB free space reserve.
6. Cutover path disabling (not uninstalling) slice 1c, keeping 1c deployables for instant rollback.
7. Separate cold-reboot verification paste.

## Decisions (AJ)

Plain words, numbered (AJ confirmed decisions: option A, 2026-11-11 22:13 CT):
1. **Rate/burst:** 8,000 rec/s per CPU, burst 16,000, written to `m2_cfg` at boot. Live evidence at 2026-11-12T04:13Z showed `m2_ctl` `rate_limited` 407,183 of 843,847 seen (~48%) over ~7 min; at the 2026-11-12 ~05:54Z cold boot, `rate_limited` was 0 of 33,436 seen at the same config. Rate left at 8000/16000; still AJ's call whether to revisit.
2. **Retention:** 64 MiB or 3,600 s per file, `keep=6` (max 384 MiB dir cap), 256 MiB free-space reserve. Boundedness is not optional.
3. **This-boot cutover:** Stop/disable 1c, then start 2b (few-second capture gap). Not overwrite. Completed on Johnny 2026-11-12T04:05Z.
4. **1c files:** Disable the 1c unit, leave its files in place for rollback. Do not uninstall 1c in the apply path. Completed on Johnny 2026-11-12T04:05Z.
5. **MACs stay raw:** Defaults as applied (AJ chose option A 2026-11-11 22:13 CT).
6. **Cold-reboot proof is a separate later paste:** Cold boot run and verified clean 2026-11-12 ~05:54Z (`M1S2B-COLD-BOOT-VERIFY-DONE`; see `docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md`).

## Rate-Limit Reasoning

Trial Paste 7 used 2,000 rec/s/CPU, burst 4,000; cumulative `ctl_seen=46978`, `rate_limited=15527`, `emitted=31451`, `rb_full=0` (15,527/46,978 = 33.1% rate-limited); output file `span_s=98.160`; RXQ 6 = 15,794 of 31,419 emitted; top src 172.217.153.231 = 18,917; Paste 8 NIC drop deltas 0. Ring and reader kept up; the per-CPU token bucket was the limiter. The ~479 pps figure divides cumulative `ctl_seen` (46,978) across all CPUs by one file's 98.160 s span (~478.6 pps), so unused quota on idle CPUs could not help the hot queue.

A 4× increase to 8,000 rec/s and burst 16,000 gives an exact 2.0 s burst window (16,000/8,000) and an exact token leak period of 125,000 ns (`1000000000/8000`), giving one hot CPU 8,000 rec/s (on-disk size is 80 B per record, about 625 KiB/s per CPU, or ~2.44 MiB/s across 4 CPUs). In the kernel BPF ring buffer, each slot is 88 B (80 B record + 8 B header); at 4 × 8,000 rec/s (32,000 rec/s = 2,816,000 B/s), the 4 MiB ring buffer holds about 1.49 s of worst-case backlog. This is a proposed default, not a proof. Sampling stays N=1. The compiled limits `M2_RATE_MAX=1000000` and `M2_BURST_MAX=100000` in the verified BPF object already permit 8,000/16,000.

## Short Design Addendum

- **BPF Object:** Reuses `docs/tool-install/module1-xdp-records.o` byte-for-byte. The object's compiled fallback is 2,000/4,000 with `ver=0`. `module1-slice2b-boot.sh start` writes `m2_cfg` with `ver=1`, `sample_every=1`, `rate=8000`, `burst=16000` and verifies the map before attach. If write or verify fails, it fails closed: no attach, no reader start.
- **Boot Helper:** `/root/m1s2b/module1-slice2b-boot.sh` (0700 root:root). Owns `start`, `stop`, `verify`, `status`. Incorporates the proven 30 × 2 s `wait_boot_ready` guard from slice 1c. Refuses if a foreign program or the slice 1c observer holds the slot (no overwrite). On failure after load or attach, detaches only our program and unpins to leave a clean unattached state; never starts 1c from a failed 2b start.
- **XDP Boot Unit:** `etc/systemd/system/johnny-capture-xdp-records.service`. Type=oneshot, RemainAfterExit=yes. Ordered `After=/Wants= network-online.target johnny-capture-irq.service`. No `After=johnny-capture-tuning.service` (avoids rev 89/90 ordering cycle). `Wants=johnny-m1s2b-reader.service` (no BindsTo).
- **Persistent Reader:** `docs/tool-install/johnny-m1s2b-reader.py` -> `/usr/local/libexec/johnny/johnny-m1s2b-reader.py` (0644 root:root). Service `etc/systemd/system/johnny-m1s2b-reader.service`. Continuous drain without `RuntimeMaxSec`. Rotates output files under `/var/lib/johnny/m1s2b/run-<UTC>.bin` (0700 dir, 0600 files). Rotates at 64 MiB or 3600 s. Prunes oldest files to maintain `keep=6` and total directory size <= 384 MiB. Refuses to start or stops writing if free disk space is below 256 MiB reserve. Exits immediately on corrupt ring without skipping ahead. A reader `STOP` exits 1 (`johnny-m1s2b-reader.py:674-675`); under `Restart=on-failure` and `StartLimitBurst=5` (`johnny-m1s2b-reader.service:6-13`), repeated failures leave the reader failed while the XDP unit stays active (`Wants=`, without `BindsTo=`), preserving kernel packet capture while dropping unread ring records.

## Final sha256 Pins

Live on Johnny (rev 113 retention applied and verified 2026-11-14 19:18Z):

```
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  docs/tool-install/module1-xdp-records.o
0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f  docs/tool-install/module1-slice2b-boot.sh
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  etc/systemd/system/johnny-capture-xdp-records.service
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  docs/tool-install/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  etc/systemd/system/johnny-m1s2b-reader.service
```

Rate cap removal draft (this PR, NOT APPLIED; apply via the Rate cap removal section):

```
1f449f12a0975f05005e16703f96dc21a5a133b10608c3506dbe49e670f3989d  docs/tool-install/module1-slice2b-boot.sh
```

Unchanged system dependencies:

```
16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b  etc/johnny/capture-cores
db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4  etc/johnny/irq-affinity.sh
```
Installed layout on Johnny:

| File | Path | Mode |
|---|---|---|
| Boot helper | `/root/m1s2b/module1-slice2b-boot.sh` | 0700 root:root |
| BPF object | `/root/m1s2b/module1-xdp-records.o` | 0600 root:root |
| Persistent reader | `/usr/local/libexec/johnny/johnny-m1s2b-reader.py` | 0644 root:root |
| Reader unit | `/etc/systemd/system/johnny-m1s2b-reader.service` | 0644 root:root |
| XDP records unit | `/etc/systemd/system/johnny-capture-xdp-records.service` | 0644 root:root |
| BPF pins | `/sys/fs/bpf/johnny_m1s2b/` | 0700 root:root |
| Output dir | `/var/lib/johnny/m1s2b/` | 0700 root:root |

## Pastes (all typed on Rock Box; sudo only inside `ssh -t aj@192.168.50.152`)

No paste in this runbook is typed directly on Johnny. Every paste is labeled `***<u>Run on Rock Box</u>***`. Pastes that touch Johnny run over `ssh aj@192.168.50.152` or `ssh -t aj@192.168.50.152 'sudo -v && ...'`. AJ alone runs them. Each paste is one fenced block with fail-fast `&&` checkpoints and ends with a unique done token.

### Paste 1: Rock-box self-test (no root, no SSH)

***<u>Run on Rock Box</u>***

```bash
cd /home/aj/Projects/strix-halo-johnny-slice2b-fix3 &&
bash docs/tool-install/module1-slice2b-self-test.sh
```

Expect `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=11`, `RUNBOOK-OK blocks=13`, and **`SELF-TEST-OK`**.

### Paste 2: Copy deployables to Johnny (no sudo)

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p -m 0700 /home/aj/cis-audit/m1s2b' &&
scp /home/aj/Projects/strix-halo-johnny-slice2b-fix3/docs/tool-install/module1-xdp-records.o /home/aj/Projects/strix-halo-johnny-slice2b-fix3/docs/tool-install/module1-slice2b-boot.sh /home/aj/Projects/strix-halo-johnny-slice2b-fix3/etc/systemd/system/johnny-capture-xdp-records.service /home/aj/Projects/strix-halo-johnny-slice2b-fix3/docs/tool-install/johnny-m1s2b-reader.py /home/aj/Projects/strix-halo-johnny-slice2b-fix3/etc/systemd/system/johnny-m1s2b-reader.service aj@192.168.50.152:/home/aj/cis-audit/m1s2b/ &&
ssh aj@192.168.50.152 'cd /home/aj/cis-audit/m1s2b && echo "a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  module1-xdp-records.o
b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  module1-slice2b-boot.sh
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  johnny-capture-xdp-records.service
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  johnny-m1s2b-reader.service" | sha256sum -c - && echo M1S2B-COPY-DONE'
```

Expect five `OK` hash lines and **`M1S2B-COPY-DONE`**.

### Paste 3: Read-only probe (installs nothing)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/m1s2b &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  module1-slice2b-boot.sh" | sha256sum -c - &&
echo "16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b  /etc/johnny/capture-cores
db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4  /etc/johnny/irq-affinity.sh" | sudo sha256sum -c - &&
sudo bpftool net show dev eno1np0 &&
sudo systemctl is-enabled johnny-capture-xdp.service &&
sudo systemctl is-active johnny-capture-xdp.service &&
echo M1S2B-PROBE-DONE'
```

Expect three `OK` hash lines, `eno1np0` showing driver attachment, `enabled`, `active`, and **`M1S2B-PROBE-DONE`**.

### Paste 4: Install files and daemon-reload (units not enabled)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/m1s2b &&
echo "a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  module1-xdp-records.o
b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  module1-slice2b-boot.sh
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  johnny-capture-xdp-records.service
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  johnny-m1s2b-reader.service" | sha256sum -c - &&
sudo install -d -m 0700 -o root -g root /root/m1s2b &&
sudo install -m 0700 -o root -g root module1-slice2b-boot.sh /root/m1s2b/module1-slice2b-boot.sh &&
sudo install -m 0600 -o root -g root module1-xdp-records.o /root/m1s2b/module1-xdp-records.o &&
sudo mkdir -p -m 0755 /usr/local/libexec/johnny &&
sudo install -m 0644 -o root -g root johnny-m1s2b-reader.py /usr/local/libexec/johnny/johnny-m1s2b-reader.py &&
sudo install -m 0644 -o root -g root johnny-m1s2b-reader.service /etc/systemd/system/johnny-m1s2b-reader.service &&
sudo install -m 0644 -o root -g root johnny-capture-xdp-records.service /etc/systemd/system/johnny-capture-xdp-records.service &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service" | sudo sha256sum -c - &&
sudo systemctl daemon-reload &&
sudo systemd-analyze verify /etc/systemd/system/johnny-capture-xdp-records.service /etc/systemd/system/johnny-m1s2b-reader.service &&
echo M1S2B-INSTALL-DONE'
```

Expect five `OK` lines twice, clean daemon-reload, no systemd verify errors, and **`M1S2B-INSTALL-DONE`**.

### Paste 5: This-boot cutover (stop/disable 1c, enable/start 2b XDP + reader)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service" | sudo sha256sum -c - &&
sudo systemctl stop johnny-capture-xdp.service &&
sudo systemctl disable johnny-capture-xdp.service &&
sudo systemctl enable johnny-capture-xdp-records.service johnny-m1s2b-reader.service &&
sudo systemctl start johnny-capture-xdp-records.service &&
sudo systemctl start johnny-m1s2b-reader.service &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh status &&
echo M1S2B-CUTOVER-DONE'
```

Expect five `OK` hash lines, slice 1c stopped/disabled, slice 2b units enabled/started, `status` showing `ATTACH records <id>`, `CFG ver=1 sample_every=1 rate=8000 burst=16000`, `UNIT-2B enabled=enabled active=active`, `UNIT-READER enabled=enabled active=active`, and **`M1S2B-CUTOVER-DONE`**.

### Paste 6: Short read-only verify window

Note: The boot.sh hash `b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55` is the pre-retention helper; after retention Paste B it will not match (fails closed) until the retention rollback restores it.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
echo M1S2B-VERIFY-DONE'
```

Expect `VERIFY-WINDOW`, `PASS-RATIO`, `ETHTOOL-DROP-DELTAS none`, and **`M1S2B-VERIFY-DONE`**.

### Paste 7: Cold reboot (separate; only after AJ go)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service" | sudo sha256sum -c - &&
echo "Issuing reboot to test unattended boot persistence..." &&
sudo reboot &&
echo M1S2B-REBOOT-ISSUED'
```

Expect five `OK` hash lines and **`M1S2B-REBOOT-ISSUED`**. Johnny reboots (~60–90 s).

### Paste 8: Post-reboot verify (unattended boot persistence check)

Note: The boot.sh hash `b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55` is the pre-retention helper; after retention Paste B it will not match (fails closed) until the retention rollback restores it.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
for i in {1..24}; do
  st_xdp=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true)
  st_rdr=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true)
  if [ "$st_xdp" = "active" ] && [ "$st_rdr" = "active" ]; then
    break
  fi
  sleep 5
done &&
if [ "$st_xdp" != "active" ] || [ "$st_rdr" != "active" ]; then
  echo "STOP-units-not-active xdp=$st_xdp reader=$st_rdr"
  false
fi &&
cyc=$(sudo journalctl -b --no-pager -q _PID=1 -o cat | grep -ci "ordering cycle" || true) &&
if [ "$cyc" != "0" ]; then echo "STOP-ordering-cycle-warning count=$cyc"; false; fi &&
if [ "$(sudo systemctl is-enabled johnny-capture-xdp.service 2>/dev/null || true)" != "disabled" ]; then
  echo "STOP-1c-unit-not-disabled"
  false
fi &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh status &&
echo M1S2B-COLD-BOOT-VERIFY-DONE'
```

Expect both units active, no ordering cycles, 1c disabled, verify and status clean, and **`M1S2B-COLD-BOOT-VERIFY-DONE`**.

Note: The ordering-cycle gate searches only PID 1 systemd messages (`_PID=1`) with `--no-pager`; the old form matched sudo's own log line on 2026-11-12. Known limitation: without pipefail, a journalctl failure with empty stdout reads as cyc=0; stderr would still show; a future revision could capture journalctl output and STOP on its non-zero exit.

## Verify-fix reinstall (2b already live)

Slice 2b is live on Johnny since 2026-11-12T04:05Z (`j_xdp_records` driver mode id 192 was the 04:05Z pre-reboot attach; live id after the 2026-11-12 ~05:54Z cold boot is 78; reader active writing `/var/lib/johnny/m1s2b/run-*.bin`, 1c disabled). Paste 6 verify stopped at `STOP-no-traffic-verify` because the checker parsed per-CPU maps using an invalid JSON shape.

This procedure updates only the two changed files (`module1-slice2b-boot.sh` and `johnny-m1s2b-reader.py`) on Johnny, restarts only the reader service (leaving XDP driver attach untouched), runs status, and completes verify.

Rollback note: if reinstall needs to be rolled back to the original slice 2b deployables, their previous hashes are:
- `module1-slice2b-boot.sh`: `650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2`
- `johnny-m1s2b-reader.py`: `e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581`

### Paste R1: Rock-box self-test (no root, no SSH)

***<u>Run on Rock Box</u>***

```bash
cd /home/aj/Projects/strix-halo-johnny-slice2b-fix3 &&
bash docs/tool-install/module1-slice2b-self-test.sh
```

Expect `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=11`, `RUNBOOK-OK blocks=13`, and **`SELF-TEST-OK`**.

### Paste R2: Copy changed fix files to Johnny (no sudo)

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p -m 0700 /home/aj/cis-audit/m1s2b-fix' &&
scp /home/aj/Projects/strix-halo-johnny-slice2b-fix3/docs/tool-install/module1-slice2b-boot.sh /home/aj/Projects/strix-halo-johnny-slice2b-fix3/docs/tool-install/johnny-m1s2b-reader.py aj@192.168.50.152:/home/aj/cis-audit/m1s2b-fix/ &&
ssh aj@192.168.50.152 'cd /home/aj/cis-audit/m1s2b-fix && echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  module1-slice2b-boot.sh
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  johnny-m1s2b-reader.py" | sha256sum -c - && echo M1S2B-FIX-COPY-DONE'
```

Expect two `OK` hash lines and **`M1S2B-FIX-COPY-DONE`**.

### Paste R3: Install fix files, restart reader service, and status check

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/m1s2b-fix &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  module1-slice2b-boot.sh
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  johnny-m1s2b-reader.py" | sha256sum -c - &&
echo "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  /root/m1s2b/module1-slice2b-boot.sh
e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581  /usr/local/libexec/johnny/johnny-m1s2b-reader.py" | sudo sha256sum -c - &&
sudo install -m 0700 -o root -g root module1-slice2b-boot.sh /root/m1s2b/module1-slice2b-boot.sh &&
sudo install -m 0644 -o root -g root johnny-m1s2b-reader.py /usr/local/libexec/johnny/johnny-m1s2b-reader.py &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  /usr/local/libexec/johnny/johnny-m1s2b-reader.py" | sudo sha256sum -c - &&
sudo systemctl restart johnny-m1s2b-reader.service &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh status &&
echo M1S2B-FIX-INSTALL-DONE'
```

Expect two `OK` hash lines for source files, two `OK` hash lines for previous installed files, two `OK` hash lines for updated installed files, clean restart of `johnny-m1s2b-reader.service` (XDP unit unchanged), `status` showing non-zero parsed `STATS` and `CTL` counters, and **`M1S2B-FIX-INSTALL-DONE`**.

### Paste R4: Verify window

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
echo M1S2B-VERIFY-DONE'
```

Expect one `OK` hash line, `VERIFY-WINDOW` with positive `xdp-pkts-delta` and `tcpdump-captured`, `PASS-RATIO`, `ETHTOOL-DROP-DELTAS none`, and **`M1S2B-VERIFY-DONE`**.

## Retention raise (2b already live)

Slice 2b is live on Johnny since 2026-11-12T04:05Z and cold-boot proven 2026-11-12 ~05:54Z (`j_xdp_records` native driver mode `prog_id=78`, both units active, slice 1c disabled). AJ approved raising reader retention limits ("we have plenty of room"):
- Per-file rotate at 1 GiB (1073741824 bytes) or 3600 s, whichever first.
- Total directory cap 200 GiB (214748364800 bytes), oldest file deleted first. Keep count raised to 200 files (`--keep 200`).
- Free-space reserve 100 GiB (107374182400 bytes): reader stops writing/prunes rather than dip below reserve.
- Unit `LimitFSIZE` raised to 1025M (1074790400 bytes); the 96-byte header is included in the 1 GiB file cap (max file 1073741776 bytes; `LimitFSIZE=1025M` covers it without triggering SIGXFSZ).
- MemoryMax=1G (raised from 128M, 1 GiB = 1073741824 bytes); after the first file passes 1 GiB, check the reader was not oom-killed (`systemctl show -p NRestarts -p Result johnny-m1s2b-reader.service`).

Tradeoff note: At low traffic, hourly rotation means `keep=200` bounds retention to ~200 hours (~8.3 days) before the 200 GiB directory byte cap is reached; at high traffic, 1 GiB per-file rotation reaches the 200 GiB cap and retains 200 GiB of packet captures. Cap + reserve = 300 GiB exactly, so a disk that only just passes preflight may stop recording (low-disk, ~100 GiB still free) once the cap fills.

Previous installed deployable hashes on Johnny before this change:
- `module1-slice2b-boot.sh`: `b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55`
- `johnny-m1s2b-reader.py`: `fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573`
- `johnny-m1s2b-reader.service`: `5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c`

### Paste A: Read-only preflight

Note: Directory cap (200 GiB) plus free-space reserve (100 GiB) equals 300 GiB exactly, so a disk that only just passes may stop recording (low-disk, ~100 GiB still free) once the cap fills.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
sudo df -h /var/lib/johnny/m1s2b &&
free_b=$(sudo df --output=avail -B1 /var/lib/johnny/m1s2b | tail -n1 | tr -d " ") &&
if [ "$free_b" -lt 322122547200 ]; then echo "STOP-low-disk free=$free_b" >&2; exit 1; fi &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  /etc/systemd/system/johnny-m1s2b-reader.service" | sudo sha256sum -c - &&
sudo du -sb /var/lib/johnny/m1s2b &&
echo M1S2B-RET-PREFLIGHT-DONE'
```

Expect df showing free space >= 300 GiB (322122547200 bytes), three `OK` hash lines for the currently installed deployables, directory usage in bytes, and **`M1S2B-RET-PREFLIGHT-DONE`**.

### Paste B: Copy changed files, install, and restart reader service

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p -m 0700 /home/aj/cis-audit/m1s2b-retention' &&
scp /home/aj/Projects/strix-halo-johnny-slice2b-reader-mem/docs/tool-install/module1-slice2b-boot.sh /home/aj/Projects/strix-halo-johnny-slice2b-reader-mem/docs/tool-install/johnny-m1s2b-reader.py /home/aj/Projects/strix-halo-johnny-slice2b-reader-mem/etc/systemd/system/johnny-m1s2b-reader.service aj@192.168.50.152:/home/aj/cis-audit/m1s2b-retention/ &&
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/m1s2b-retention &&
echo "0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f  module1-slice2b-boot.sh
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  johnny-m1s2b-reader.service" | sha256sum -c - &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  /etc/systemd/system/johnny-m1s2b-reader.service" | sudo sha256sum -c - &&
sudo install -d -m 0700 -o root -g root /root/m1s2b/backup-pre-retention &&
sudo cp -p /root/m1s2b/module1-slice2b-boot.sh /root/m1s2b/backup-pre-retention/ &&
sudo cp -p /usr/local/libexec/johnny/johnny-m1s2b-reader.py /root/m1s2b/backup-pre-retention/ &&
sudo cp -p /etc/systemd/system/johnny-m1s2b-reader.service /root/m1s2b/backup-pre-retention/ &&
sudo install -m 0700 -o root -g root module1-slice2b-boot.sh /root/m1s2b/module1-slice2b-boot.sh &&
sudo install -m 0644 -o root -g root johnny-m1s2b-reader.py /usr/local/libexec/johnny/johnny-m1s2b-reader.py &&
sudo install -m 0644 -o root -g root johnny-m1s2b-reader.service /etc/systemd/system/johnny-m1s2b-reader.service &&
echo "0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f  /root/m1s2b/module1-slice2b-boot.sh
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  /etc/systemd/system/johnny-m1s2b-reader.service" | sudo sha256sum -c - &&
sudo systemctl daemon-reload &&
sudo systemctl restart johnny-m1s2b-reader.service &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh status &&
echo M1S2B-RET-APPLY-DONE'
```

Expect three `OK` hash lines for copied staging files, three `OK` hash lines verifying the old installed files, three `OK` hash lines for newly installed files, clean restart of `johnny-m1s2b-reader.service` (XDP unit untouched), clean `status` output, and **`M1S2B-RET-APPLY-DONE`**.

### Paste C: Verify retention settings and service operation

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
st_xdp=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true) &&
st_rdr=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true) &&
if [ "$st_xdp" != "active" ] || [ "$st_rdr" != "active" ]; then
  echo "STOP-units-not-active xdp=$st_xdp reader=$st_rdr" >&2
  exit 1
fi &&
echo "0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh status &&
show_out=$(sudo systemctl show -p ExecStart -p LimitFSIZE -p MemoryMax johnny-m1s2b-reader.service) &&
echo "$show_out" &&
echo "$show_out" | grep -q -- "--file-max-bytes 1073741824" &&
echo "$show_out" | grep -q -- "--file-max-seconds 3600" &&
echo "$show_out" | grep -q -- "--keep 200" &&
echo "$show_out" | grep -q -- "--dir-cap-bytes 214748364800" &&
echo "$show_out" | grep -q -- "--reserve-bytes 107374182400" &&
echo "$show_out" | grep -q -- "LimitFSIZE=1074790400" &&
echo "$show_out" | grep -q -- "MemoryMax=1073741824" &&
last_start=$(sudo journalctl -u johnny-m1s2b-reader.service -b --no-pager -o cat | grep "M1S2B-READER-BEGIN" | tail -n1) &&
echo "$last_start" &&
echo "$last_start" | grep -q -- "file_max_bytes=1073741824 file_max_seconds=3600 keep=200 dir_cap=214748364800 reserve=107374182400" &&
echo M1S2B-RET-VERIFY-DONE'
```

Expect both units active, boot.sh verify and status clean, `systemctl show` displaying new args on ExecStart, LimitFSIZE=1074790400, and MemoryMax=1073741824, latest reader startup line showing `file_max_bytes=1073741824 file_max_seconds=3600 keep=200 dir_cap=214748364800 reserve=107374182400`, and **`M1S2B-RET-VERIFY-DONE`**.

### Retention rollback: restore previous configuration (not part of the paste sequence)

> [!WARNING]
> Restoring the previous reader configuration reinstates `keep=6` and the 384 MiB directory cap. When the restored reader starts, its initial `prune()` will delete older run files until at most 5 existing files remain and total directory usage is within 384 MiB. The restored 384 MiB cap means existing 1 GiB files are deleted by the byte prune, not kept as five files.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/backup-pre-retention/module1-slice2b-boot.sh
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  /root/m1s2b/backup-pre-retention/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  /root/m1s2b/backup-pre-retention/johnny-m1s2b-reader.service" | sudo sha256sum -c - &&
sudo cp -p /root/m1s2b/backup-pre-retention/module1-slice2b-boot.sh /root/m1s2b/module1-slice2b-boot.sh &&
sudo cp -p /root/m1s2b/backup-pre-retention/johnny-m1s2b-reader.py /usr/local/libexec/johnny/johnny-m1s2b-reader.py &&
sudo cp -p /root/m1s2b/backup-pre-retention/johnny-m1s2b-reader.service /etc/systemd/system/johnny-m1s2b-reader.service &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh
fbe2449e4030dac7c1b16804040f030d2ecf064a08350a2d6219940c9cc5d573  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  /etc/systemd/system/johnny-m1s2b-reader.service" | sudo sha256sum -c - &&
sudo systemctl daemon-reload &&
sudo systemctl restart johnny-m1s2b-reader.service &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh status &&
echo M1S2B-RET-ROLLBACK-DONE'
```

Expect three `OK` hash lines verifying backup files, three `OK` hash lines verifying restored installed files, clean restart of `johnny-m1s2b-reader.service`, clean status, and **`M1S2B-RET-ROLLBACK-DONE`**.

## Rate cap removal (2b already live)

AJ approved (2026-11-14): Record ALL mirrored traffic — a week of uninterrupted header records, validated after a week.

### Rate-Limit Reasoning and Removal

- **Admit Path Facts (`module1_xdp_records.c` `admit()`):**
  - `rate == 0` means records are OFF (fails closed, not unlimited).
  - There is no bypass flag in the BPF kernel code.
  - Rate is clamped in kernel C to `M2_RATE_MAX = 1000000` records/s per CPU.
  - Burst is clamped to `M2_BURST_MAX = 100000`.
  - Token bucket state is per-CPU (`m2_state` percpu array).
- **Decision (no BPF rebuild, `.o` stays `a73c5bd2…`):**
  - Set `m2_cfg` to `ver=1 sample_every=1 rate=1000000 burst=100000` (the compiled maxima; value hex `01 00 00 00 01 00 00 00 40 42 0f 00 a0 86 01 00`).
  - Across 12 queues spread over 4 CPUs, 1M rec/s per CPU is far above 1 Gbps line rate (max ~1.488M pps total min-size 64 B frames, 81.25k pps at 1500 B MTU) except for a pathological single-flow min-size flood all on one queue.
- **Capacity Note:**
  - Pinned ring buffer size is 4 MiB (4,194,304 bytes). Each slot takes 88 bytes (80 B record + 8 B header), yielding 47,662 slots.
  - Time-to-fill with no drain:
    - At 83,000 pps (~1500 B wire frames): ~0.574 s (574 ms).
    - At 1,488,000 pps (64 B line rate): ~0.032 s (32 ms).
    - At current LAN average (~300 pps): ~158.8 s (~2.6 minutes).
  - Reader drain micro-benchmark: Measured on Rock Box (Ryzen 9 9900X, Python 3.12, ctypes copy + bounds + seq gap tracking + buffer write + statvfs flush): ~1,480,000 records/s.
  - Sustained packet rates above the reader's measured drain would show as `rb_full` (now a fatal STOP condition in `verify` and `window`).
  - The per-CPU 1,000,000 rec/s clamp in `module1_xdp_records.c` is the only remaining cap.
  - No BPF rebuild, no ring change.
- **Reader Restart Behavior:**
  - The reader mmap consumer position (`self.cons.value`) is mapped to page 0 of the pinned ring buffer (`/sys/fs/bpf/johnny_m1s2b/m2_rb`).
  - Because `/sys/fs/bpf/johnny_m1s2b/m2_rb` is pinned in the kernel, the consumer position persists across reader service restarts.
  - During the few-second reader restart gap, records emitted by XDP sit in the pinned ring buffer between consumer and producer. When the restarted reader begins draining, it resumes reading from `cons.value`. No records are skipped. If traffic during the restart gap exceeds 4 MiB, `bpf_ringbuf_reserve` fails and `rb_full` increments.
  - Reader restarts are necessary after `apply-cfg` because the reader snapshots `m2_cfg` into memory at startup to write into the 96-byte header of newly opened run files.
- **Notes Outside Fences:**
  - After Paste B, every older paste that pins `module1-slice2b-boot.sh` hash `0fb61363…` (retention Pastes A/B/C, Paste 6, Paste 8, R-pastes, retention rollback, slice-1c rollback) will fail closed until the rate-cap rollback is executed.
  - Remaining drop risks:
    1. Pathological single-queue flood >1M pps on a single CPU.
    2. Reader drain backlog leading to `rb_full`.
    3. Host reboot or extended reader downtime causing buffer overflow or counter reset.
    4. Mirrored traffic dropped upstream by switch (e.g. oversubscribed mirror port: bidirectional 1 Gbps traffic can total up to 2 Gbps, exceeding the 1 Gbps mirror destination port). These drops are invisible to Johnny.
    5. NIC-level ring drops show in `ethtool -S eno1np0` drop deltas.
  - Week-long storage estimate from real data:
    - Live data since Nov 12 cold boot: ~300 pps average.
    - ~300 pps * 86,400 s * 7 days ≈ 181.4M records/week.
    - 181.4M records * 80 B ≈ 14.5 GB/week, well below the 200 GiB directory cap and 100 GiB reserve.
    - 200 hourly files = 200 hours = 8.33 days of retention before pruning, so >= 7 days of continuous hourly captures fit without being pruned.

Deployable hashes on Johnny before this change (rev 113 applied):
- `module1-slice2b-boot.sh`: `0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f`
- `johnny-m1s2b-reader.py`: `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37`
- `johnny-m1s2b-reader.service`: `e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c`
- `johnny-capture-xdp-records.service`: `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a`
- `module1-xdp-records.o`: `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481`

New deployable hash for this change:
- `module1-slice2b-boot.sh`: `1f449f12a0975f05005e16703f96dc21a5a133b10608c3506dbe49e670f3989d`

### Paste A: Read-only preflight

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f  /root/m1s2b/module1-slice2b-boot.sh
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o" | sudo sha256sum -c - &&
st_xdp=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true) &&
st_rdr=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true) &&
if [ "$st_xdp" != "active" ] || [ "$st_rdr" != "active" ]; then
  echo "STOP-units-not-active xdp=$st_xdp reader=$st_rdr" >&2
  exit 1
fi &&
status_out=$(sudo bash /root/m1s2b/module1-slice2b-boot.sh status) &&
echo "$status_out" &&
echo "$status_out" | grep -q "^CFG ver=1 sample_every=1 rate=8000 burst=16000$" &&
echo "$status_out" | grep "^CTL " &&
echo M1S2B-NORC-PREFLIGHT-DONE'
```

Expect five `OK` hash lines, units active, status showing old CFG (8000/16000), CTL rows printed, and **`M1S2B-NORC-PREFLIGHT-DONE`**.

### Paste B: Apply new rate-limit configuration

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p -m 0700 /home/aj/cis-audit/m1s2b-no-ratecap' &&
scp /home/aj/Projects/strix-halo-johnny-slice2b-no-ratecap/docs/tool-install/module1-slice2b-boot.sh aj@192.168.50.152:/home/aj/cis-audit/m1s2b-no-ratecap/ &&
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/m1s2b-no-ratecap &&
echo "1f449f12a0975f05005e16703f96dc21a5a133b10608c3506dbe49e670f3989d  module1-slice2b-boot.sh" | sha256sum -c - &&
echo "0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f  /root/m1s2b/module1-slice2b-boot.sh
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o" | sudo sha256sum -c - &&
sudo install -d -m 0700 -o root -g root /root/m1s2b/backup-pre-no-ratecap &&
sudo cp -p /root/m1s2b/module1-slice2b-boot.sh /root/m1s2b/backup-pre-no-ratecap/ &&
sudo install -m 0700 -o root -g root module1-slice2b-boot.sh /root/m1s2b/module1-slice2b-boot.sh &&
echo "1f449f12a0975f05005e16703f96dc21a5a133b10608c3506dbe49e670f3989d  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh apply-cfg &&
sudo systemctl restart johnny-m1s2b-reader.service &&
status_out=$(sudo bash /root/m1s2b/module1-slice2b-boot.sh status) &&
echo "$status_out" &&
echo "$status_out" | grep -q "^CFG ver=1 sample_every=1 rate=1000000 burst=100000$" &&
echo M1S2B-NORC-APPLY-DONE'
```

Expect one `OK` staged hash line, five `OK` live hash lines, one `OK` post-install hash line, `M1S2B-APPLY-CFG-DONE`, clean restart of `johnny-m1s2b-reader.service` (XDP unit NOT restarted), status showing CFG `ver=1 sample_every=1 rate=1000000 burst=100000`, and **`M1S2B-NORC-APPLY-DONE`**.

### Paste C: Verify rate-limit configuration and zero drops

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
st_xdp=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true) &&
st_rdr=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true) &&
if [ "$st_xdp" != "active" ] || [ "$st_rdr" != "active" ]; then
  echo "STOP-units-not-active xdp=$st_xdp reader=$st_rdr" >&2
  exit 1
fi &&
echo "1f449f12a0975f05005e16703f96dc21a5a133b10608c3506dbe49e670f3989d  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh window 60 &&
status_out=$(sudo bash /root/m1s2b/module1-slice2b-boot.sh status) &&
echo "$status_out" &&
echo "$status_out" | grep -q "^CFG ver=1 sample_every=1 rate=1000000 burst=100000$" &&
last_start=$(sudo journalctl -u johnny-m1s2b-reader.service -b --no-pager -o cat | grep "M1S2B-READER-BEGIN" | tail -n1) &&
echo "$last_start" &&
echo "$last_start" | grep -q -- "cfg=ver:1,every:1,rate:1000000,burst:100000" &&
echo "$last_start" | grep -q -- "file_max_bytes=1073741824 file_max_seconds=3600 keep=200 dir_cap=214748364800 reserve=107374182400" &&
echo M1S2B-NORC-VERIFY-DONE'
```

Expect both units active, boot.sh hash verified, `verify` passing with zero drops (`VERIFY-DROPS rate_limited=0 rb_full=0 discarded=0`), `window 60` passing with zero drops (`OK-no-drops-window`), status showing new CFG, reader journal startup showing new cfg snapshot alongside 1 GiB / 200 GiB / 100 GiB retention settings, and **`M1S2B-NORC-VERIFY-DONE`**.

### Paste W: One-week validation (read-only, run >= 7 days after Paste B)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
st_xdp=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true) &&
st_rdr=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true) &&
if [ "$st_xdp" != "active" ] || [ "$st_rdr" != "active" ]; then
  echo "STOP-units-not-active xdp=$st_xdp reader=$st_rdr" >&2
  exit 1
fi &&
sudo systemctl show -p NRestarts -p Result -p ActiveEnterTimestamp -p ExecMainStartTimestamp johnny-m1s2b-reader.service &&
sudo systemctl show -p ActiveEnterTimestamp johnny-capture-xdp-records.service &&
base_file="/root/m1s2b/no-ratecap-baseline.txt" &&
if [ ! -f "$base_file" ]; then echo "STOP-baseline-missing $base_file" >&2; exit 1; fi &&
cur_boot_id=$(tr -d "\n\r " < /proc/sys/kernel/random/boot_id) &&
base_boot_id="" &&
base_seen=0 && base_rl=0 && base_rb=0 && base_disc=0 && base_emit=0 && base_date="" &&
while read -r c1 c2 c3; do
  if [ "$c1" = "boot_id" ]; then
    base_boot_id="$c2"
  elif [ "$c1" = "DATE-UTC" ]; then
    base_date="$c2"
  elif [ "$c1" = "CTL" ]; then
    case "$c2" in
      seen) base_seen="$c3" ;;
      rate_limited) base_rl="$c3" ;;
      rb_full) base_rb="$c3" ;;
      discarded) base_disc="$c3" ;;
      emitted) base_emit="$c3" ;;
    esac
  fi
done < "$base_file" &&
if [ "$cur_boot_id" = "$base_boot_id" ]; then
  echo "BOOT-SAME id=$cur_boot_id"
else
  echo "STOP-rebooted-since-apply cur=$cur_boot_id base=$base_boot_id (counters reset by reboot)" >&2
  exit 1
fi &&
status_out=$(sudo bash /root/m1s2b/module1-slice2b-boot.sh status) &&
echo "$status_out" &&
cur_seen=0 && cur_rl=0 && cur_rb=0 && cur_disc=0 && cur_emit=0 &&
while read -r c1 c2 c3; do
  if [ "$c1" = "CTL" ]; then
    case "$c2" in
      seen) cur_seen="$c3" ;;
      rate_limited) cur_rl="$c3" ;;
      rb_full) cur_rb="$c3" ;;
      discarded) cur_disc="$c3" ;;
      emitted) cur_emit="$c3" ;;
    esac
  fi
done <<<"$status_out" &&
delta_seen=$((cur_seen - base_seen)) &&
delta_rl=$((cur_rl - base_rl)) &&
delta_rb=$((cur_rb - base_rb)) &&
delta_disc=$((cur_disc - base_disc)) &&
delta_emit=$((cur_emit - base_emit)) &&
echo "CTL-DELTAS seen=$delta_seen rate_limited=$delta_rl rb_full=$delta_rb discarded=$delta_disc emitted=$delta_emit" &&
if [ "$delta_rl" -gt 0 ] || [ "$delta_rb" -gt 0 ] || [ "$delta_disc" -gt 0 ]; then
  echo "STOP-drops-since-baseline rate_limited=$delta_rl rb_full=$delta_rb discarded=$delta_disc" >&2
  exit 1
fi &&
files=($(find /var/lib/johnny/m1s2b -maxdepth 1 -name "run-*.bin" | sort)) &&
count="${#files[@]}" &&
if [ "$count" -lt 1 ]; then echo "STOP-no-run-files" >&2; exit 1; fi &&
oldest="${files[0]}" &&
newest="${files[-1]}" &&
old_fn=$(basename "$oldest") &&
new_fn=$(basename "$newest") &&
old_ts=${old_fn#run-} && old_ts=${old_ts%.bin} && old_ts=${old_ts%-*} &&
old_fmt="${old_ts:0:4}-${old_ts:4:2}-${old_ts:6:2} ${old_ts:9:2}:${old_ts:11:2}:${old_ts:13:2} UTC" &&
old_start=$(date -u -d "$old_fmt" +%s) &&
old_mtime=$(stat -c %Y "$oldest") &&
old_mtime_utc=$(date -u -d "@$old_mtime" "+%Y-%m-%dT%H:%M:%SZ") &&
new_mtime=$(stat -c %Y "$newest") &&
new_mtime_utc=$(date -u -d "@$new_mtime" "+%Y-%m-%dT%H:%M:%SZ") &&
echo "FILES count=$count oldest=$old_fn (mtime=$old_mtime_utc start=$old_fmt) newest=$new_fn (mtime=$new_mtime_utc)" &&
cov_s=$((new_mtime - old_start)) &&
cov_d=$((cov_s / 86400)) &&
echo "COVERAGE secs=$cov_s days=$cov_d" &&
if [ "$cov_s" -lt 604800 ]; then
  echo "STOP-coverage-short secs=$cov_s (want >= 604800 / 7 days)" >&2
  exit 1
fi &&
gaps_found=0 &&
prev_start=0 &&
prev_file="" &&
for f in "${files[@]}"; do
  fn=$(basename "$f")
  ts=${fn#run-}
  ts=${ts%.bin}
  ts=${ts%-*}
  fmt="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2} UTC"
  cur_start=$(date -u -d "$fmt" +%s)
  if [ "$prev_start" -gt 0 ]; then
    gap=$((cur_start - prev_start))
    if [ "$gap" -gt 3700 ]; then
      echo "GAP-DETECTED prev=$prev_file cur=$fn gap_secs=$gap"
      gaps_found=$((gaps_found + 1))
    fi
  fi
  prev_start=$cur_start
  prev_file=$fn
done &&
echo "GAP-COUNT $gaps_found" &&
if [ "$gaps_found" -gt 0 ]; then
  echo "STOP-gap-detected count=$gaps_found" >&2
  exit 1
fi &&
sudo du -sb /var/lib/johnny/m1s2b &&
sudo df -h /var/lib/johnny/m1s2b &&
journal_stops=$(sudo journalctl -u johnny-m1s2b-reader.service --since "$base_date" --no-pager -o cat | grep -c -E "STOP|Traceback" || true) &&
echo "READER-JOURNAL-ERRORS count=$journal_stops (since $base_date)" &&
if [ "$journal_stops" -gt 0 ]; then
  echo "STOP-reader-journal-errors count=$journal_stops" >&2
  exit 1
fi &&
echo M1S2B-NORC-WEEK-DONE'
```

Expect units active, reader restart and enter timestamps clean (NRestarts=0, Result=success), current boot_id matching baseline (`BOOT-SAME`), zero drop deltas since apply (`rate_limited=0 rb_full=0 discarded=0`), `boot.sh status` clean, run file count >= 168, coverage >= 7 days (604800 s), zero file start gaps > 3700 s, `du -sb` and `df -h` within bounds, zero reader journal errors since apply, and **`M1S2B-NORC-WEEK-DONE`**.

### Rate cap rollback: restore previous configuration (not part of the paste sequence)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f  /root/m1s2b/backup-pre-no-ratecap/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo cp -p /root/m1s2b/backup-pre-no-ratecap/module1-slice2b-boot.sh /root/m1s2b/module1-slice2b-boot.sh &&
echo "0fb61363ddce962f0a645c340072fe5085b5ebeda0794230fa6dbc492dd2388f  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo bpftool map update pinned /sys/fs/bpf/johnny_m1s2b/m2_cfg key hex 00 00 00 00 value hex 01 00 00 00 01 00 00 00 40 1f 00 00 80 3e 00 00 &&
status_out=$(sudo bash /root/m1s2b/module1-slice2b-boot.sh status) &&
echo "$status_out" &&
echo "$status_out" | grep -q "^CFG ver=1 sample_every=1 rate=8000 burst=16000$" &&
sudo systemctl restart johnny-m1s2b-reader.service &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
echo M1S2B-NORC-ROLLBACK-DONE'
```

Expect backup helper verified (`0fb61363...`), restored helper verified, `m2_cfg` restored to old 8000/16000 via bpftool map update, status confirming old CFG, reader restarted, old verify passing (note: old verify does not STOP on drops), and **`M1S2B-NORC-ROLLBACK-DONE`**.

## Rollback (not part of the paste sequence above)

Run this block to revert Johnny back to slice 1c (`j_xdp_observe` attached, `johnny-capture-xdp.service` enabled and active). Slice 2b files remain on disk for inspection.

Note: The boot.sh hash `b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55` is the pre-retention helper; after retention Paste B it will not match (fails closed) until the retention rollback restores it.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "b3c0b6bc8d409b930e2724672e6b398db8585dfa46d207f2c0c8023139981f55  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo systemctl stop johnny-m1s2b-reader.service &&
sudo systemctl stop johnny-capture-xdp-records.service &&
sudo systemctl disable johnny-capture-xdp-records.service johnny-m1s2b-reader.service &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh stop &&
sudo systemctl enable --now johnny-capture-xdp.service &&
st=$(sudo bpftool net show dev eno1np0 2>/dev/null || true) &&
drv_ids=($(echo "$st" | grep -o "driver id [0-9]*" | awk "{print \$3}")) &&
pname= &&
if [ "${#drv_ids[@]}" -eq 1 ]; then
  pname=$(sudo bpftool prog show id "${drv_ids[0]}" 2>/dev/null | grep -o "name [^ ]*" | head -n1 | awk "{print \$2}")
fi &&
e1c=$(sudo systemctl is-enabled johnny-capture-xdp.service 2>/dev/null || true) &&
u1c=$(sudo systemctl is-active johnny-capture-xdp.service 2>/dev/null || true) &&
e2x=$(sudo systemctl is-enabled johnny-capture-xdp-records.service 2>/dev/null || true) &&
u2x=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true) &&
e2r=$(sudo systemctl is-enabled johnny-m1s2b-reader.service 2>/dev/null || true) &&
u2r=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true) &&
if [ "${#drv_ids[@]}" -eq 1 ] && [ "$pname" = "j_xdp_observe" ] && [ "$e1c" = "enabled" ] && [ "$u1c" = "active" ] && [ "$e2x" = "disabled" ] && [ "$e2r" = "disabled" ] && [ "$u2x" = "inactive" ] && [ "$u2r" = "inactive" ]; then
  echo M1S2B-ROLLBACK-DONE
else
  echo "STOP-rollback-not-clean st=$st drv_ids=${drv_ids[*]} pname=$pname 1c=$e1c/$u1c 2x=$e2x/$u2x 2r=$e2r/$u2r"
  false
fi'
```

Expect slice 2b stopped/disabled, 2b pins removed, slice 1c enabled/active, observer attached (`driver id <id>`, name `j_xdp_observe`), and **`M1S2B-ROLLBACK-DONE`**.

## What Each STOP Means

| STOP Line | Meaning and Action |
|---|---|
| `STOP-not-root`, `STOP-host`, `STOP-kernel`, `STOP-no-iface` | Preflight platform check failed before any change. |
| `STOP-tool-missing <t>` | Required utility missing from PATH. |
| `STOP-<what>-not-root-owned-or-missing`, `STOP-<what>-hash` | Deployable or system configuration file corrupted or missing. |
| `STOP-boot-wait-timeout` | Bounded 60 s wait for `eno1np0`, `eno3`, or `johnny-capture-irq.service` timed out; fails closed without touching netlink. |
| `STOP-observer-attached-stop-first` | The slice 1c observer holds the slot; helper refuses to overwrite. Apply paste must stop 1c first. |
| `STOP-xdp-foreign-attached` | A foreign XDP program is attached; helper refuses to touch it. |
| `STOP-cfg-write-verify-failed` | Writing or verifying `m2_cfg` (8000/16000) failed; helper detaches and cleans up (fail-closed). |
| `STOP-units-not-active` | One or both 2b units did not reach active within 120 s after boot. |
| `STOP-ordering-cycle-warning` | Systemd ordering cycle detected in PID 1 journal messages (`count=<n>`). |
| `STOP-1c-unit-not-disabled` | Slice 1c unit remained enabled after reboot. |
| `STOP-low-disk free=<bytes>` | Preflight available disk space check failed on `/var/lib/johnny/m1s2b` (< 300 GiB / 322122547200 bytes available). |
| `STOP-rollback-not-clean` | Rollback did not return Johnny to clean slice 1c observer state (requires one attached driver id with prog name `j_xdp_observe`, 1c enabled/active, and both 2b units disabled/inactive). |
| `STOP-drops-in-verify-window rate_limited=.. rb_full=.. discarded=..` | Verify detected packet drops in the sampling window; fails closed. |
| `STOP-drops-in-window rate_limited=.. rb_full=.. discarded=..` | Window command detected packet drops in the sampling window; fails closed. |
| `STOP-baseline-missing <file>` | Baseline file `/root/m1s2b/no-ratecap-baseline.txt` missing during week validation. |
| `STOP-rebooted-since-apply` | Host rebooted since rate cap removal; counters were reset. |
| `STOP-drops-since-baseline rate_limited=.. rb_full=.. discarded=..` | Week validation detected drops since baseline was taken. |
| `STOP-coverage-short secs=..` | Output file timespan is less than 7 days (604,800 s). |
| `STOP-gap-detected count=..` | Detected consecutive run file start interval > 3700 s. |
| `STOP-reader-journal-errors count=..` | Journal shows STOP or Traceback in reader service since apply. |
| reader exit 1 (`Restart=on-failure`) | Reader encountered a STOP condition (e.g. disk reserve or corrupt ring); after `StartLimitBurst=5`, systemd leaves the reader failed while XDP unit remains active. |

## Tokens AJ Sends Back

1. Paste 1: **`SELF-TEST-OK`**
2. Paste 2: **`M1S2B-COPY-DONE`**
3. Paste 3: **`M1S2B-PROBE-DONE`**
4. Paste 4: **`M1S2B-INSTALL-DONE`**
5. Paste 5: **`M1S2B-CUTOVER-DONE`**
6. Paste 6: **`M1S2B-VERIFY-DONE`**
7. Paste 7: **`M1S2B-REBOOT-ISSUED`**
8. Paste 8: **`M1S2B-COLD-BOOT-VERIFY-DONE`**
9. Paste R1: **`SELF-TEST-OK`**
10. Paste R2: **`M1S2B-FIX-COPY-DONE`**
11. Paste R3: **`M1S2B-FIX-INSTALL-DONE`**
12. Paste R4: **`M1S2B-VERIFY-DONE`**
13. Retention Paste A: **`M1S2B-RET-PREFLIGHT-DONE`**
14. Retention Paste B: **`M1S2B-RET-APPLY-DONE`**
15. Retention Paste C: **`M1S2B-RET-VERIFY-DONE`**
16. Rollback (retention): **`M1S2B-RET-ROLLBACK-DONE`**
17. Rate cap Paste A: **`M1S2B-NORC-PREFLIGHT-DONE`**
18. Rate cap Paste B: **`M1S2B-NORC-APPLY-DONE`**
19. Rate cap Paste C: **`M1S2B-NORC-VERIFY-DONE`**
20. Rate cap Paste W: **`M1S2B-NORC-WEEK-DONE`**
21. Rollback (rate cap): **`M1S2B-NORC-ROLLBACK-DONE`**
22. Rollback (full 1c): **`M1S2B-ROLLBACK-DONE`**

## Assumptions

1. CPython's x86-64 memory model and ctypes store to `cons.value` provide sufficient store-release ordering for consumer position updates.
2. The capability-less uid 0 sandbox allows BPF map lookup, OBJ_GET, and ringbuf mmap on `7.0.0-42-generic` as observed during the slice 2 trial.
3. 8,000 rec/s per CPU and 16,000 burst provides adequate headroom for observed bursty flows on RXQ 6 while bounding worst-case memory consumption.

## Sources

- Slice 2 design: `docs/tool-install/module1-slice2-ringbuf-design.md`
- Slice 2 runbook: `docs/tool-install/module1-slice2-ringbuf.md`
- Slice 1c boot unit runbook: `docs/tool-install/module1-slice1c-boot-unit.md`
- systemd.unit(5) and systemd.exec(5) man pages.
