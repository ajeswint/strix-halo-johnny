# Module 1 Slice 2b: Boot-time j_xdp_records and Persistent Rotating Reader

Rev 1, 2026-11-11 America/Chicago. Status: **drafted, NOT APPLIED.**

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

Plain words, numbered:
1. **Rate/burst:** Proposed 8,000 rec/s per CPU, burst 16,000, written to `m2_cfg` at boot. Confirm or name another pair.
2. **Retention:** 64 MiB or 3,600 s per file, `keep=6` (max 384 MiB dir cap), 256 MiB free-space reserve. Confirm or name other caps. Boundedness is not optional.
3. **This-boot cutover:** Stop/disable 1c, then start 2b (few-second capture gap). Not overwrite. Same recommendation as slice 2 Decision 1 (a).
4. **1c files:** Disable the 1c unit, leave its files in place for rollback. Do not uninstall 1c in the apply path.
5. **MACs stay raw:** Unless AJ says otherwise (slice 2 default).
6. **Cold-reboot proof is a separate later paste:** Run only after this-boot verify passes, not part of the first apply batch.

## Rate-Limit Reasoning

Trial Paste 7 used 2,000 rec/s/CPU, burst 4,000; cumulative `ctl_seen=46978`, `rate_limited=15527`, `emitted=31451`, `rb_full=0` (15,527/46,978 = 33.1% rate-limited); output file `span_s=98.160`; RXQ 6 = 15,794 of 31,419 emitted; top src 172.217.153.231 = 18,917; Paste 8 NIC drop deltas 0. Ring and reader kept up; the per-CPU token bucket was the limiter. The ~479 pps figure divides cumulative `ctl_seen` (46,978) across all CPUs by one file's 98.160 s span (~478.6 pps), so unused quota on idle CPUs could not help the hot queue.

A 4× increase to 8,000 rec/s and burst 16,000 gives an exact 2.0 s burst window (16,000/8,000) and an exact token leak period of 125,000 ns (`1000000000/8000`), giving one hot CPU 8,000 rec/s (on-disk size is 80 B per record, about 625 KiB/s per CPU, or ~2.44 MiB/s across 4 CPUs). In the kernel BPF ring buffer, each slot is 88 B (80 B record + 8 B header); at 4 × 8,000 rec/s (32,000 rec/s = 2,816,000 B/s), the 4 MiB ring buffer holds about 1.49 s of worst-case backlog. This is a proposed default, not a proof. Sampling stays N=1. The compiled limits `M2_RATE_MAX=1000000` and `M2_BURST_MAX=100000` in the verified BPF object already permit 8,000/16,000.

## Short Design Addendum

- **BPF Object:** Reuses `docs/tool-install/module1-xdp-records.o` byte-for-byte. The object's compiled fallback is 2,000/4,000 with `ver=0`. `module1-slice2b-boot.sh start` writes `m2_cfg` with `ver=1`, `sample_every=1`, `rate=8000`, `burst=16000` and verifies the map before attach. If write or verify fails, it fails closed: no attach, no reader start.
- **Boot Helper:** `/root/m1s2b/module1-slice2b-boot.sh` (0700 root:root). Owns `start`, `stop`, `verify`, `status`. Incorporates the proven 30 × 2 s `wait_boot_ready` guard from slice 1c. Refuses if a foreign program or the slice 1c observer holds the slot (no overwrite). On failure after load or attach, detaches only our program and unpins to leave a clean unattached state; never starts 1c from a failed 2b start.
- **XDP Boot Unit:** `etc/systemd/system/johnny-capture-xdp-records.service`. Type=oneshot, RemainAfterExit=yes. Ordered `After=/Wants= network-online.target johnny-capture-irq.service`. No `After=johnny-capture-tuning.service` (avoids rev 89/90 ordering cycle). `Wants=johnny-m1s2b-reader.service` (no BindsTo).
- **Persistent Reader:** `docs/tool-install/johnny-m1s2b-reader.py` -> `/usr/local/libexec/johnny/johnny-m1s2b-reader.py` (0644 root:root). Service `etc/systemd/system/johnny-m1s2b-reader.service`. Continuous drain without `RuntimeMaxSec`. Rotates output files under `/var/lib/johnny/m1s2b/run-<UTC>.bin` (0700 dir, 0600 files). Rotates at 64 MiB or 3600 s. Prunes oldest files to maintain `keep=6` and total directory size <= 384 MiB. Refuses to start or stops writing if free disk space is below 256 MiB reserve. Exits immediately on corrupt ring without skipping ahead. A reader `STOP` exits 1 (`johnny-m1s2b-reader.py:671-673`); under `Restart=on-failure` and `StartLimitBurst=5` (`johnny-m1s2b-reader.service:6-13`), repeated failures leave the reader failed while the XDP unit stays active (`Wants=`, without `BindsTo=`), preserving kernel packet capture while dropping unread ring records.

## Final sha256 Pins

Deployables (copied to Johnny):

```
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  docs/tool-install/module1-xdp-records.o
650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  docs/tool-install/module1-slice2b-boot.sh
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  etc/systemd/system/johnny-capture-xdp-records.service
e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581  docs/tool-install/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  etc/systemd/system/johnny-m1s2b-reader.service
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
cd /home/aj/Projects/strix-halo-johnny-slice2b &&
bash docs/tool-install/module1-slice2b-self-test.sh
```

Expect `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=11`, `RUNBOOK-OK blocks=9`, and **`SELF-TEST-OK`**.

### Paste 2: Copy deployables to Johnny (no sudo)

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p -m 0700 /home/aj/cis-audit/m1s2b' &&
scp /home/aj/Projects/strix-halo-johnny-slice2b/docs/tool-install/module1-xdp-records.o /home/aj/Projects/strix-halo-johnny-slice2b/docs/tool-install/module1-slice2b-boot.sh /home/aj/Projects/strix-halo-johnny-slice2b/etc/systemd/system/johnny-capture-xdp-records.service /home/aj/Projects/strix-halo-johnny-slice2b/docs/tool-install/johnny-m1s2b-reader.py /home/aj/Projects/strix-halo-johnny-slice2b/etc/systemd/system/johnny-m1s2b-reader.service aj@192.168.50.152:/home/aj/cis-audit/m1s2b/ &&
ssh aj@192.168.50.152 'cd /home/aj/cis-audit/m1s2b && echo "a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  module1-xdp-records.o
650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  module1-slice2b-boot.sh
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  johnny-capture-xdp-records.service
e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581  johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  johnny-m1s2b-reader.service" | sha256sum -c - && echo M1S2B-COPY-DONE'
```

Expect five `OK` hash lines and **`M1S2B-COPY-DONE`**.

### Paste 3: Read-only probe (installs nothing)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/m1s2b &&
echo "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  module1-slice2b-boot.sh" | sha256sum -c - &&
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
650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  module1-slice2b-boot.sh
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  johnny-capture-xdp-records.service
e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581  johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  johnny-m1s2b-reader.service" | sha256sum -c - &&
sudo install -d -m 0700 -o root -g root /root/m1s2b &&
sudo install -m 0700 -o root -g root module1-slice2b-boot.sh /root/m1s2b/module1-slice2b-boot.sh &&
sudo install -m 0600 -o root -g root module1-xdp-records.o /root/m1s2b/module1-xdp-records.o &&
sudo mkdir -p -m 0755 /usr/local/libexec/johnny &&
sudo install -m 0644 -o root -g root johnny-m1s2b-reader.py /usr/local/libexec/johnny/johnny-m1s2b-reader.py &&
sudo install -m 0644 -o root -g root johnny-m1s2b-reader.service /etc/systemd/system/johnny-m1s2b-reader.service &&
sudo install -m 0644 -o root -g root johnny-capture-xdp-records.service /etc/systemd/system/johnny-capture-xdp-records.service &&
echo "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  /root/m1s2b/module1-slice2b-boot.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o
e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
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
echo "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  /root/m1s2b/module1-slice2b-boot.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o
e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
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

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
echo M1S2B-VERIFY-DONE'
```

Expect `VERIFY-WINDOW`, `PASS-RATIO`, `ETHTOOL-DROP-DELTAS none`, and **`M1S2B-VERIFY-DONE`**.

### Paste 7: Cold reboot (separate; only after AJ go)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  /root/m1s2b/module1-slice2b-boot.sh
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o
e33195e4cdbf16be0efd07791a0eca1bd7e5be394b518da2e3d358f9d7689581  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
5e685d3d1f1c891d3b7d746d26e352a9d1a40a31d1dde58e6d286e2d6b7ac10c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service" | sudo sha256sum -c - &&
echo "Issuing reboot to test unattended boot persistence..." &&
sudo reboot &&
echo M1S2B-REBOOT-ISSUED'
```

Expect five `OK` hash lines and **`M1S2B-REBOOT-ISSUED`**. Johnny reboots (~60–90 s).

### Paste 8: Post-reboot verify (unattended boot persistence check)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
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
if sudo journalctl -b --grep "ordering cycle" -q; then
  echo "STOP-ordering-cycle-warning"
  false
fi &&
if [ "$(sudo systemctl is-enabled johnny-capture-xdp.service 2>/dev/null || true)" != "disabled" ]; then
  echo "STOP-1c-unit-not-disabled"
  false
fi &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh status &&
echo M1S2B-COLD-BOOT-VERIFY-DONE'
```

Expect both units active, no ordering cycles, 1c disabled, verify and status clean, and **`M1S2B-COLD-BOOT-VERIFY-DONE`**.

## Rollback (not part of the paste sequence above)

Run this block to revert Johnny back to slice 1c (`j_xdp_observe` attached, `johnny-capture-xdp.service` enabled and active). Slice 2b files remain on disk for inspection.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "650340a253da41bdbbb9f8ab23ac0e7e545bc86df7b75c514a6d7176107145f2  /root/m1s2b/module1-slice2b-boot.sh" | sudo sha256sum -c - &&
sudo systemctl stop johnny-m1s2b-reader.service &&
sudo systemctl stop johnny-capture-xdp-records.service &&
sudo systemctl disable johnny-capture-xdp-records.service johnny-m1s2b-reader.service &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh stop &&
sudo systemctl enable --now johnny-capture-xdp.service &&
st=$(sudo bpftool net show dev eno1np0 2>/dev/null || true) &&
drv_ids=($(echo "$st" | grep -o 'driver id [0-9]*' | awk '{print $3}')) &&
pname= &&
if [ "${#drv_ids[@]}" -eq 1 ]; then
  pname=$(sudo bpftool prog show id "${drv_ids[0]}" 2>/dev/null | grep -o 'name [^ ]*' | head -n1 | awk '{print $2}')
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
| `STOP-ordering-cycle-warning` | Systemd ordering cycle detected in journal. |
| `STOP-1c-unit-not-disabled` | Slice 1c unit remained enabled after reboot. |
| `STOP-rollback-not-clean` | Rollback did not return Johnny to clean slice 1c observer state (requires one attached driver id with prog name `j_xdp_observe`, 1c enabled/active, and both 2b units disabled/inactive). |
| reader exit 1 (`Restart=on-failure`) | Reader encountered a STOP condition (e.g. disk reserve or corrupt ring); after `StartLimitBurst=5`, systemd leaves the reader failed while XDP unit remains active. |

## Tokens AJ Sends Back

1. Paste 1: **`SELF-TEST-OK`**
2. Paste 2: **`M1S2B-COPY-DONE`**
3. Paste 3: **`M1S2B-PROBE-DONE`**
4. Paste 4: **`M1S2B-INSTALL-DONE`**
5. Paste 5: **`M1S2B-CUTOVER-DONE`**
6. Paste 7: **`M1S2B-REBOOT-ISSUED`**
7. Paste 8: **`M1S2B-COLD-BOOT-VERIFY-DONE`**
8. Rollback: **`M1S2B-ROLLBACK-DONE`**

## Assumptions

1. CPython's x86-64 memory model and ctypes store to `cons.value` provide sufficient store-release ordering for consumer position updates.
2. The capability-less uid 0 sandbox allows BPF map lookup, OBJ_GET, and ringbuf mmap on `7.0.0-42-generic` as observed during the slice 2 trial.
3. 8,000 rec/s per CPU and 16,000 burst provides adequate headroom for observed bursty flows on RXQ 6 while bounding worst-case memory consumption.

## Sources

- Slice 2 design: `docs/tool-install/module1-slice2-ringbuf-design.md`
- Slice 2 runbook: `docs/tool-install/module1-slice2-ringbuf.md`
- Slice 1c boot unit runbook: `docs/tool-install/module1-slice1c-boot-unit.md`
- systemd.unit(5) and systemd.exec(5) man pages.
