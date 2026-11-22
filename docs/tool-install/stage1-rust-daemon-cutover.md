# Stage 1: Rust Userspace Sensor Daemon (`johnny-daemon`) — Cutover & Rollback Runbook (APPLIED 2026-11-17; Stage 1 EXITED 2026-11-22T01:22:21Z)

Rev 4, 2026-11-21 America/Chicago. Status: **STAGE 1 EXITED.** Paste S1-6 passed (`STAGE1-EXIT-CHECK-DONE`) when AJ ran it at `2026-11-22T01:22:21Z` (2026-11-21 7:22 PM CST). Record: `docs/sessions/2026-11-21-stage1-exit-check-passed.md`. Accepted open gap: no cold boot tested under the Rust daemon. Paste text below is unchanged.

Rev 3, 2026-11-17 America/Chicago (historical). Status: **APPLIED AND VERIFIED ON JOHNNY (2026-11-17, PR #42 build, merge `c23ea4f`; `docs/os-handoff.md` rev 119, `docs/sessions/2026-11-17-stage1-cutover-applied.md`).**

> **APPLIED ON JOHNNY (2026-11-17):**
> AJ ended the Paste W week-test hold early by choice on 2026-11-17 (test ran `2026-11-14 15:33 CT` to cutover, ~3 days, not 7; Paste C at `20:27Z` printed `M1S2B-NORC-VERIFY-DONE` with `window-60 seen-delta=26416` and zero drops, and `BASELINE CTL rate_limited 18217138` had `0` new `rate_limited` from baseline `2026-11-14T21:32:11Z` to cutover) and ran Pastes S1-1 through S1-5 (`S1-3` ~3:29 PM CT `STAGE1-PROBE-INSTALL-DONE`, `S1-4` ~3:30 PM CT `STAGE1-CUTOVER-DONE`, `S1-5` ~3:42 PM CT `STAGE1-VERIFY-DONE`). Johnny now runs `johnny-daemon.service` (`enabled`/`active`, `/usr/local/libexec/johnny/johnny-daemon` SHA-256 `08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac`, `/etc/systemd/system/johnny-daemon.service` SHA-256 `e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa`); `johnny-m1s2b-reader.service` is `disabled`/`inactive` with its files kept on disk (`476cf867...`, unit `e5c16249...`), and the **Rollback** section below remains available. The historical Paste W hold banner below was superseded by AJ's choice (ended early after ~3 days; Paste W superseded, not passed) and retains its original gate substrings because `cutover_runbook_audit` in `crates/johnny-daemon/tests/parity.rs:745-746` asserts them.

Rev 2 note (2026-11-17 America/Chicago, historical): fixes S1-3 `--probe` `STOP-mmap-probe errno=22`: `probe()` in `crates/johnny-daemon/src/bpf.rs` now opens `m2_rb` read-write because on Johnny's Ubuntu `7.0.0-42.42` kernel `mm/mmap.c` `do_mmap` runs `vm_flags |= VM_SHARED | VM_MAYSHARE; if (!(file->f_mode & FMODE_WRITE)) vm_flags &= ~(VM_MAYWRITE | VM_SHARED);` — mainline v7.3's `vma_flags_clear(&vma_flags, VMA_MAYWRITE_BIT, VMA_SHARED_BIT)` spelling is equivalent — so `kernel/bpf/syscall.c` `bpf_map_mmap` returns `-EINVAL` without `FMODE_WRITE`; pages `0..1` are still mapped `PROT_READ`, where `bpf_map_mmap` clears `VM_MAYWRITE` when `VM_WRITE` is absent. Historical pre-cutover status: **DRAFT — DO NOT RUN CUTOVER BEFORE PASTE W COMPLETES (after 2026-11-21 15:33 CT / 21:33Z).**

> **HISTORICAL HOLD (superseded 2026-11-17 by AJ's choice) — DO NOT RUN BEFORE PASTE W (after 2026-11-21 15:33 CT / 21:33Z):**
> Pre-cutover week-test gate (`docs/os-handoff.md:30, 59-65`, `docs/tool-install/module1-slice2b-boot-unit.md:583-601`; superseded at `docs/os-handoff.md:4` when AJ chose on 2026-11-17 to end the `2026-11-14 15:33 CT` hold early after ~3 days, so Paste W was superseded, not passed): Johnny's one-week uninterrupted capture test was originally scheduled until **2026-11-21 15:33 CT (21:33Z)**.

---

## 1. Purpose and AJ Decisions (2026-11-14 10:56 PM CT)

Stage 1 (`docs/architecture/architecture-rev2.md:287-324`) replaces the Python ring-buffer reader (`johnny-m1s2b-reader.py`) with the Rust userspace sensor daemon (`johnny-daemon`) while keeping the kernel XDP side (`j_xdp_records`) and all live BPF pins untouched, and keeping the Python reader installed on disk as an immediate rollback.

AJ approved the four Stage 1 code-shape decisions on **2026-11-14 at 10:56 PM CT** (`docs/architecture/architecture-rev2.md` §1.2, §4 Stage 1):

1. **BPF crate (`aya`, userspace only):** `johnny-daemon` uses `aya = "=0.16.0"` (`default-features = false`) isolated in a single module (`crates/johnny-daemon/src/bpf.rs`). It attaches in userspace only to the existing pinned maps under `/sys/fs/bpf/johnny_m1s2b` (`m2_rb` read-write for the ring consumer page in `attach()` and for `--probe`'s `PROT_READ` `MAP_SHARED` position mapping, since on Johnny's Ubuntu `7.0.0-42.42` kernel `mm/mmap.c` `do_mmap` runs `vm_flags |= VM_SHARED | VM_MAYSHARE; if (!(file->f_mode & FMODE_WRITE)) vm_flags &= ~(VM_MAYWRITE | VM_SHARED);` — mainline v7.3's `vma_flags_clear(&vma_flags, VMA_MAYWRITE_BIT, VMA_SHARED_BIT)` spelling is equivalent — and `kernel/bpf/syscall.c` `bpf_map_mmap` then returns `-EINVAL` when `VM_SHARED` is clear; `m2_cfg` and `m2_ctl` opened `BPF_F_RDONLY` via `BPF_OBJ_GET` and wrapped in `aya::maps::MapData::from_fd`). It never modifies, loads, or rebuilds `docs/tool-install/module1_xdp_records.c` or `docs/tool-install/module1-xdp-records.o`, and never alters any live pins or hashes.
2. **Record v1 frozen; `"version": 1` stamped in userspace outputs:** Today's 80-byte `struct m2_rec` (`docs/tool-install/module1_xdp_records.c:133-165`) is frozen as implicit v1 across the kernel-to-userspace boundary. Every userspace JSON output line (`--log-format json`, `--dump-json`, `--probe`) is stamped `"version":1` first (`crates/johnny-record-v1/src/lib.rs:25`). Readers ignore unknown record versions safely (`Decoded::Unknown { version }` in `crates/johnny-record-v1/src/record.rs:54-59`; default `--on-unknown-version skip` in `crates/johnny-daemon/src/control/config.rs:39-45`). In-kernel binary header changes are deferred to v2.
3. **Cargo workspace (`crates/`):** `crates/` sits next to `docs/` with two workspace members (`crates/Cargo.toml:1-3`):
   - `crates/johnny-record-v1`: `#![forbid(unsafe_code)]` library crate containing the frozen 80-byte `RecordV1` codec, the 96-byte `RunHeader` (`JM1S2RB\0`) codec, `RunFileReader`, `--summary` renderer, and UTC timestamp math, reusable by the Stage 2 Rock Box agent.
   - `crates/johnny-daemon`: the Stage 1 binary crate with internal control-plane (`crates/johnny-daemon/src/control/`: `config.rs` Policy Administrator, `policy.rs` pure Policy Engine, `status.rs` structured logger) and data-plane (`crates/johnny-daemon/src/data/`: `ring.rs` ring consumer, `writer.rs` rotating run-file writer) separation per NIST SP 800-207 (`docs/architecture/architecture-rev2.md:42, 56`).
   - `docs/tool-install/johnny-m1s2b-reader.py` remains untouched in place for fallback/rollback.
4. **Plain Cargo builds, binary SHA-256, CycloneDX SBOM, and AJ-signed tags:**
   - `bash crates/release.sh` runs `cargo build --release --locked --offline` on Rock Box, emits `crates/dist/johnny-daemon` and `crates/dist/johnny-daemon.sha256`, and emits a CycloneDX 1.5 JSON SBOM at `crates/johnny-daemon.cdx.json` (and `crates/dist/johnny-daemon.cdx.json`). Note: `cargo-cyclonedx` is not installed in `~/.cargo/bin` on Rock Box (`cargo --list`), so `crates/release.sh:29-141` generates the CycloneDX 1.5 JSON SBOM deterministically from `cargo metadata --format-version 1 --locked --offline` and `crates/Cargo.lock` (`tools[0].name` is `cargo-metadata-lockfile`).
   - Release signing uses signed git tags signed by AJ (documented in §3 below; no signing keys are created by agents).

---

## 2. SHA-256 Pins

### Stage 1 deployables (built on Rock Box, `rustc 1.100.0 (0ef1bc386 2026-11-09)`):

```
08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac  crates/dist/johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  etc/systemd/system/johnny-daemon.service
8d74fe6ee2f9200ff8b18b63c596a5301688055287c72a5ecc756485ecb59b86  crates/johnny-daemon.cdx.json
```

### Existing slice 2b pins on Johnny (MUST remain unchanged on disk):

```
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o
a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb  /root/m1s2b/module1-slice2b-boot.sh
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  /etc/systemd/system/johnny-m1s2b-reader.service
```

### Installed layout on Johnny (after Stage 1 cutover):

| File | Path on Johnny | Mode | Notes |
|---|---|---|---|
| Stage 1 Rust daemon | `/usr/local/libexec/johnny/johnny-daemon` | `0755 root:root` | New consumer of `/sys/fs/bpf/johnny_m1s2b/m2_rb` |
| Stage 1 systemd unit | `/etc/systemd/system/johnny-daemon.service` | `0644 root:root` | Same sandbox + resource bounds as `johnny-m1s2b-reader.service`, plus `Conflicts=johnny-m1s2b-reader.service` |
| Reader boot guard drop-in | `/etc/systemd/system/johnny-m1s2b-reader.service.d/stage1-cutover.conf` | `0644 root:root` | `ConditionPathIsSymbolicLink=!/etc/systemd/system/multi-user.target.wants/johnny-daemon.service` so `johnny-capture-xdp-records.service`'s `Wants=johnny-m1s2b-reader.service` skips starting the Python reader while `johnny-daemon.service` is enabled, without altering `/etc/systemd/system/johnny-m1s2b-reader.service` or `/etc/systemd/system/johnny-capture-xdp-records.service` |
| Python reader (rollback) | `/usr/local/libexec/johnny/johnny-m1s2b-reader.py` | `0644 root:root` | Kept in place with hash `476cf867...` |
| Python reader unit (rollback) | `/etc/systemd/system/johnny-m1s2b-reader.service` | `0644 root:root` | Kept in place with hash `e5c16249...` |

---

## 3. Release Signing Step (AJ signs git tag on Rock Box)

Agents never create signing keys or sign tags. When AJ approves the Stage 1 commit and binary hash (`08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac`), AJ creates and verifies a signed git tag on Rock Box using his own signing key:

```text
git tag -s stage1-daemon-v0.1.0 -m "Stage 1 johnny-daemon v0.1.0 (sha256 08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac)"
git verify-tag stage1-daemon-v0.1.0
```

---

## 4. Cutover Pastes (APPLIED on Johnny 2026-11-17; Paste W hold ended early by AJ's choice)

Every paste below is typed on Rock Box. On 2026-11-17, AJ chose to end the one-week capture hold early (~3 days from `2026-11-14 15:33 CT` to cutover, not 7; Paste W at `docs/tool-install/module1-slice2b-boot-unit.md:583-601` was superseded, not passed) and ran Pastes S1-1 through S1-5 on Johnny (`docs/os-handoff.md` rev 119).

### Paste S1-1: Rock Box self-test, Cargo test suite, release build, and hash gate (no root, no SSH)

***<u>Run on Rock Box</u>***

```bash
export PATH="$HOME/.cargo/bin:$PATH" &&
cd /home/aj/Projects/strix-halo-johnny-stage1-fix &&
bash docs/tool-install/module1-slice2b-self-test.sh &&
(cd crates && cargo test --locked --offline) &&
bash crates/release.sh &&
echo "08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac  crates/dist/johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  etc/systemd/system/johnny-daemon.service
8d74fe6ee2f9200ff8b18b63c596a5301688055287c72a5ecc756485ecb59b86  crates/johnny-daemon.cdx.json" | sha256sum -c - &&
echo STAGE1-ROCKBOX-GATE-DONE
```

Expect `SELF-TEST-OK`, all Rust unit and parity tests passing, `STAGE1-RELEASE-OK`, three `OK` hash lines, and **`STAGE1-ROCKBOX-GATE-DONE`**.

### Paste S1-2: Copy Stage 1 binary, unit, and SBOM to Johnny staging dir (no sudo; applied 2026-11-17)

Note: any files already staged on Johnny in `/home/aj/cis-audit/stage1` from the failed `2026-11-17` S1-3 attempt are stale and must be re-copied by Paste S1-2 (`scp` overwrites them, and `sha256sum -c -` below and in Paste S1-3 will fail closed on a stale copy).

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p -m 0700 /home/aj/cis-audit/stage1' &&
scp /home/aj/Projects/strix-halo-johnny-stage1-fix/crates/dist/johnny-daemon /home/aj/Projects/strix-halo-johnny-stage1-fix/etc/systemd/system/johnny-daemon.service /home/aj/Projects/strix-halo-johnny-stage1-fix/crates/johnny-daemon.cdx.json aj@192.168.50.152:/home/aj/cis-audit/stage1/ &&
ssh aj@192.168.50.152 'cd /home/aj/cis-audit/stage1 && echo "08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac  johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  johnny-daemon.service
8d74fe6ee2f9200ff8b18b63c596a5301688055287c72a5ecc756485ecb59b86  johnny-daemon.cdx.json" | sha256sum -c - && echo STAGE1-COPY-DONE'
```

Expect three `OK` hash lines and **`STAGE1-COPY-DONE`**.

### Paste S1-3: Preflight live pins, install Stage 1 files (not started), and run read-only `--probe` & `--summary` smoke (applied 2026-11-17)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/stage1 &&
echo "08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac  johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  johnny-daemon.service
8d74fe6ee2f9200ff8b18b63c596a5301688055287c72a5ecc756485ecb59b86  johnny-daemon.cdx.json" | sha256sum -c - &&
echo "a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb  /root/m1s2b/module1-slice2b-boot.sh
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o" | sudo sha256sum -c - &&
sudo install -m 0755 -o root -g root johnny-daemon /usr/local/libexec/johnny/johnny-daemon &&
sudo install -m 0644 -o root -g root johnny-daemon.service /etc/systemd/system/johnny-daemon.service &&
echo "08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac  /usr/local/libexec/johnny/johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  /etc/systemd/system/johnny-daemon.service" | sudo sha256sum -c - &&
sudo systemctl daemon-reload &&
/usr/local/libexec/johnny/johnny-daemon --version &&
probe_out=$(sudo /usr/local/libexec/johnny/johnny-daemon --probe) &&
echo "$probe_out" &&
echo "$probe_out" | grep -q -- "\"version\":1,\"event\":\"probe\"" &&
latest_bin=$(sudo find /var/lib/johnny/m1s2b -maxdepth 1 -type f -name "run-*.bin" | sort | tail -n1) &&
[ -n "$latest_bin" ] &&
snap_bin=/root/m1s2b/stage1-summary-snap.bin &&
sudo install -m 0600 -o root -g root "$latest_bin" "$snap_bin" &&
sum_rs=$(sudo /usr/local/libexec/johnny/johnny-daemon --summary "$snap_bin" --top 5) &&
sum_py=$(sudo /usr/bin/python3 -I /usr/local/libexec/johnny/johnny-m1s2b-reader.py --summary "$snap_bin" --top 5) &&
sudo rm -f "$snap_bin" &&
[ "$sum_rs" = "$sum_py" ] &&
echo STAGE1-PROBE-INSTALL-DONE'
```

Expect staged and live hashes verified, `/usr/local/libexec/johnny/johnny-daemon` and `/etc/systemd/system/johnny-daemon.service` installed (not yet enabled or started), `--probe` outputting `"version":1,"event":"probe"` read-only alongside the live Python reader, `--summary` output matching the Python reader byte-for-byte on a stable snapshot copy of the newest run file (never comparing the live inode), and **`STAGE1-PROBE-INSTALL-DONE`**.

### Paste S1-4: Cutover from `johnny-m1s2b-reader.service` to `johnny-daemon.service` (applied 2026-11-17)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac  /usr/local/libexec/johnny/johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  /etc/systemd/system/johnny-daemon.service
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  /etc/systemd/system/johnny-m1s2b-reader.service" | sudo sha256sum -c - &&
sudo install -d -m 0755 -o root -g root /etc/systemd/system/johnny-m1s2b-reader.service.d &&
printf "[Unit]\nConditionPathIsSymbolicLink=!/etc/systemd/system/multi-user.target.wants/johnny-daemon.service\n" | sudo tee /etc/systemd/system/johnny-m1s2b-reader.service.d/stage1-cutover.conf >/dev/null &&
sudo chmod 0644 /etc/systemd/system/johnny-m1s2b-reader.service.d/stage1-cutover.conf &&
sudo systemctl daemon-reload &&
sudo systemctl disable --now johnny-m1s2b-reader.service &&
sudo systemctl enable --now johnny-daemon.service &&
st_xdp=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true) &&
st_py=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true) &&
en_py=$(sudo systemctl is-enabled johnny-m1s2b-reader.service 2>/dev/null || true) &&
st_rs=$(sudo systemctl is-active johnny-daemon.service 2>/dev/null || true) &&
en_rs=$(sudo systemctl is-enabled johnny-daemon.service 2>/dev/null || true) &&
if [ "$st_xdp" != "active" ] || [ "$st_py" != "inactive" ] || [ "$en_py" != "disabled" ] || [ "$st_rs" != "active" ] || [ "$en_rs" != "enabled" ]; then
  echo "STOP-cutover-unit-state xdp=$st_xdp py=$en_py/$st_py rs=$en_rs/$st_rs" >&2
  exit 1
fi &&
props=$(sudo systemctl show johnny-daemon.service -p MemoryMax -p MemorySwapMax -p NRestarts -p Result) &&
echo "$props" &&
echo "$props" | grep -q "^MemoryMax=1073741824$" &&
echo "$props" | grep -q "^MemorySwapMax=0$" &&
echo "$props" | grep -q "^NRestarts=0$" &&
echo "$props" | grep -q "^Result=success$" &&
j_begin="" &&
for _ in 1 2 3 4 5 6 7 8 9 10; do
  j_begin=$(sudo journalctl -u johnny-daemon.service -b --no-pager -o cat | grep "\"event\":\"reader-begin\"" | tail -n1 || true)
  if [ -n "$j_begin" ]; then
    break
  fi
  sleep 1
done &&
if [ -z "$j_begin" ]; then
  j_begin=$(sudo journalctl -u johnny-daemon.service -b --no-pager -o cat | grep "\"event\":\"reader-begin\"" | tail -n1 || true)
fi &&
if [ -z "$j_begin" ]; then
  echo "STOP-missing-reader-begin" >&2
  exit 1
fi &&
echo "$j_begin" &&
echo "$j_begin" | grep -q -- "^\\{\"version\":1,\"event\":\"reader-begin\"" &&
echo STAGE1-CUTOVER-DONE'
```

Expect `johnny-capture-xdp-records.service` untouched (`active`), `johnny-m1s2b-reader.service` `disabled`/`inactive` (with its files and hashes untouched on disk), `johnny-daemon.service` `enabled`/`active` with `MemoryMax=1073741824`, `NRestarts=0`, `Result=success`, bounded wait for journal line starting `{"version":1,"event":"reader-begin"`, and **`STAGE1-CUTOVER-DONE`**.

### Paste S1-5: Verify 60 s zero-drop window and dual-reader `--summary` parity on Johnny (applied 2026-11-17)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
st_xdp=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true) &&
st_rs=$(sudo systemctl is-active johnny-daemon.service 2>/dev/null || true) &&
if [ "$st_xdp" != "active" ] || [ "$st_rs" != "active" ]; then
  echo "STOP-units-not-active xdp=$st_xdp daemon=$st_rs" >&2
  exit 1
fi &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh window 60 &&
status_out=$(sudo bash /root/m1s2b/module1-slice2b-boot.sh status) &&
echo "$status_out" &&
echo "$status_out" | grep -q "^CFG ver=1 sample_every=1 rate=1000000 burst=100000$" &&
newest_bin=$(sudo find /var/lib/johnny/m1s2b -maxdepth 1 -type f -name "run-*.bin" | sort | tail -n1) &&
[ -n "$newest_bin" ] &&
snap_bin=/root/m1s2b/stage1-summary-snap.bin &&
sudo install -m 0600 -o root -g root "$newest_bin" "$snap_bin" &&
sum_rs=$(sudo /usr/local/libexec/johnny/johnny-daemon --summary "$snap_bin" --top 5) &&
sum_py=$(sudo /usr/bin/python3 -I /usr/local/libexec/johnny/johnny-m1s2b-reader.py --top 5 --summary "$snap_bin") &&
sudo rm -f "$snap_bin" &&
echo "$sum_rs" &&
[ "$sum_rs" = "$sum_py" ] &&
j_stops=$(sudo journalctl -u johnny-daemon.service -b --no-pager -o cat | grep -c "STOP-" || true) &&
[ "$j_stops" = "0" ] &&
echo STAGE1-VERIFY-DONE'
```

Expect `window 60` passing with zero drops (`OK-no-drops-window`, `M1S2B-WINDOW-DONE`), `status` confirming `CFG ver=1 sample_every=1 rate=1000000 burst=100000`, a stable snapshot copy of the newest run file written by `johnny-daemon` parsed identically by both `johnny-daemon --summary` and `johnny-m1s2b-reader.py --summary` (never comparing the live inode), zero `STOP-` lines in `johnny-daemon.service` journal, and **`STAGE1-VERIFY-DONE`**.

Note: `module1-slice2b-boot.sh verify` (`docs/tool-install/module1-slice2b-boot.sh:698-702`) asserts `johnny-m1s2b-reader.service` is `enabled` and `active`, so Paste S1-5 uses `boot.sh window 60` + `boot.sh status` while `johnny-daemon.service` is active, and the Rollback section below runs `boot.sh verify` once `johnny-m1s2b-reader.service` is re-enabled.

### Paste S1-6: Stage 1 exit check — drop counters unchanged since cutover (read-only; run after 2026-11-21 15:33 CT)

**Review state: Claude reviewed 7dee6ad: APPROVE-WITH-NITS n1–n3** (n1–n3 applied here; see `docs/findings/stage2/2026-11-17-stage2-decisions-2-rereview-claude-7dee6ad.md`). AJ decided O27 window A on 2026-11-17 9:01 PM CT (`docs/architecture/architecture-rev2.md` O27): Stage 1 exits when this check passes after 2026-11-21 15:33 CT (`2026-11-21T21:33:00Z`), not on the date alone. Open gap AJ accepted with window A: no cold boot has been tested under the Rust daemon.

Baseline (cutover, daemon-written run file `HEADER start_utc=2026-11-17 21:30:30Z` and `CTL-START`, `docs/sessions/2026-11-17-stage1-cutover-applied.md:25, 35-36`): `seen=168066737 sampled_out=0 rate_limited=18217138 rb_full=0 emitted=149849599 discarded=0`. The CTL counters (`module1-slice2b-boot.sh status`, one `CTL <name> <total>` line per counter) are cumulative since `j_xdp_records` loaded, so "unchanged" means `rate_limited` is still `18217138` and `rb_full` and `discarded` are still `0`, while `seen` has increased past `168066737`. A missing or unparsable counter emits `STOP-exit-ctl-UNREADABLE`, never `*-changed`. `docs/sessions/2026-11-17-stage1-cutover-applied.md` did not record a `boot_id` or `johnny-daemon.service` `InvocationID`, so this check prints the live `boot_id` and `InvocationID` without inventing a pin and verifies `/proc/stat` `btime` plus `systemctl show johnny-daemon.service` (`NRestarts=0`, `Result=success`, `ActiveEnterTimestamp` at or before `2026-11-17T21:30:30Z`) to fail on any reboot or daemon restart since cutover.

Read-only: `sudo` is used only for `sha256sum -c`, `systemctl is-active`, `systemctl show`, `module1-slice2b-boot.sh status` (takes no lock and writes nothing), `find`, `stat`, and `journalctl` (plus unprivileged `date`, `cat /proc/sys/kernel/random/boot_id`, and `sed` on `/proc/stat`). Nothing is started, stopped, installed, or written on Johnny.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb  /root/m1s2b/module1-slice2b-boot.sh
08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac  /usr/local/libexec/johnny/johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  /etc/systemd/system/johnny-daemon.service" | sudo sha256sum -c - &&
now_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ) &&
now_epoch=$(date -u +%s) &&
gate_epoch=$(TZ=America/Chicago date -d "2026-11-21 15:33:00" +%s) &&
echo "DATE-UTC $now_utc BOOT-ID $(cat /proc/sys/kernel/random/boot_id)" &&
if ! [[ "$now_epoch" =~ ^[0-9]+$ ]] || ! [[ "$gate_epoch" =~ ^[0-9]+$ ]] || [ "$now_epoch" -lt "$gate_epoch" ]; then
  echo "STOP-exit-NOT-YET now=$now_utc gate=2026-11-21T21:33:00Z (2026-11-21 15:33 CT)" >&2
  exit 1
fi &&
cutover_epoch=$(date -u -d "2026-11-17T21:30:30Z" +%s) &&
btime=$(sed -n "s/^btime //p" /proc/stat) &&
if ! [[ "$cutover_epoch" =~ ^[0-9]+$ ]] || ! [[ "$btime" =~ ^[0-9]+$ ]] || [ "$btime" -gt "$cutover_epoch" ]; then
  echo "STOP-exit-rebooted btime=$btime cutover=2026-11-17T21:30:30Z" >&2
  exit 1
fi &&
st_xdp=$(sudo systemctl is-active johnny-capture-xdp-records.service 2>/dev/null || true) &&
st_rs=$(sudo systemctl is-active johnny-daemon.service 2>/dev/null || true) &&
st_py=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true) &&
if [ "$st_xdp" != "active" ] || [ "$st_rs" != "active" ] || [ "$st_py" != "inactive" ]; then
  echo "STOP-exit-units xdp=$st_xdp rs=$st_rs py=$st_py" >&2
  exit 1
fi &&
nrestarts=$(sudo systemctl show johnny-daemon.service -p NRestarts --value 2>/dev/null || true) &&
result=$(sudo systemctl show johnny-daemon.service -p Result --value 2>/dev/null || true) &&
active_enter=$(sudo systemctl show johnny-daemon.service -p ActiveEnterTimestamp --value 2>/dev/null || true) &&
inv_id=$(sudo systemctl show johnny-daemon.service -p InvocationID --value 2>/dev/null || true) &&
active_epoch=$(date -u -d "$active_enter" +%s 2>/dev/null || true) &&
echo "DAEMON-STATE nrestarts=$nrestarts result=$result active_enter=\"$active_enter\" active_epoch=$active_epoch invocation=$inv_id" &&
if [ "$nrestarts" != "0" ] || [ "$result" != "success" ] || [ -z "$inv_id" ] || [ -z "$active_enter" ] || ! [[ "$active_enter" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]] || ! [[ "$active_epoch" =~ ^[0-9]+$ ]] || [ "$active_epoch" -lt "$btime" ] || [ "$active_epoch" -gt "$cutover_epoch" ]; then
  echo "STOP-exit-daemon-restarted nrestarts=$nrestarts result=$result active_enter=\"$active_enter\" cutover=2026-11-17T21:30:30Z" >&2
  exit 1
fi &&
if ! status_out=$(sudo bash /root/m1s2b/module1-slice2b-boot.sh status); then
  echo "STOP-exit-ctl-UNREADABLE status-failed" >&2
  exit 1
fi &&
{ echo "$status_out" | grep -E "^(ATTACH|UNIT-|PINS|STATS|CTL|CFG|NOTE-)" || true; } &&
ctl_seen=$(echo "$status_out" | sed -n "s/^CTL seen //p") &&
ctl_so=$(echo "$status_out" | sed -n "s/^CTL sampled_out //p") &&
ctl_rl=$(echo "$status_out" | sed -n "s/^CTL rate_limited //p") &&
ctl_rb=$(echo "$status_out" | sed -n "s/^CTL rb_full //p") &&
ctl_emit=$(echo "$status_out" | sed -n "s/^CTL emitted //p") &&
ctl_disc=$(echo "$status_out" | sed -n "s/^CTL discarded //p") &&
if echo "$status_out" | grep -q "^NOTE-ctl-unreadable$" ||
   ! [[ "$ctl_seen" =~ ^[0-9]+$ ]] ||
   ! [[ "$ctl_so" =~ ^[0-9]+$ ]] ||
   ! [[ "$ctl_rl" =~ ^[0-9]+$ ]] ||
   ! [[ "$ctl_rb" =~ ^[0-9]+$ ]] ||
   ! [[ "$ctl_emit" =~ ^[0-9]+$ ]] ||
   ! [[ "$ctl_disc" =~ ^[0-9]+$ ]]; then
  echo "STOP-exit-ctl-UNREADABLE seen=$ctl_seen sampled_out=$ctl_so rate_limited=$ctl_rl rb_full=$ctl_rb emitted=$ctl_emit discarded=$ctl_disc" >&2
  exit 1
fi &&
{ [ "$ctl_rl" = "18217138" ] || { echo "STOP-exit-rate_limited-changed got=$ctl_rl base=18217138" >&2; exit 1; }; } &&
{ [ "$ctl_rb" = "0" ] || { echo "STOP-exit-rb_full-changed got=$ctl_rb base=0" >&2; exit 1; }; } &&
{ [ "$ctl_disc" = "0" ] || { echo "STOP-exit-discarded-changed got=$ctl_disc base=0" >&2; exit 1; }; } &&
if [ "$ctl_seen" -le 168066737 ]; then
  echo "STOP-exit-seen-not-increased seen=$ctl_seen base=168066737" >&2
  exit 1
fi &&
newest_bin=$(sudo find /var/lib/johnny/m1s2b -maxdepth 1 -type f -name "run-*.bin" 2>/dev/null | sort | tail -n1) &&
if [ -z "$newest_bin" ]; then
  echo "STOP-exit-runfile-UNREADABLE newest_bin=none" >&2
  exit 1
fi &&
newest_mtime=$(sudo stat -c %Y "$newest_bin" 2>/dev/null || true) &&
now_check=$(date -u +%s) &&
if ! [[ "$newest_mtime" =~ ^[0-9]+$ ]] || ! [[ "$now_check" =~ ^[0-9]+$ ]]; then
  echo "STOP-exit-runfile-UNREADABLE file=$newest_bin mtime=$newest_mtime" >&2
  exit 1
fi &&
run_age=$((now_check - newest_mtime)) &&
echo "NEWEST-RUNFILE file=$newest_bin mtime=$newest_mtime age_secs=$run_age" &&
if [ "$run_age" -gt 600 ] || [ "$run_age" -lt -5 ]; then
  echo "STOP-exit-runfile-stale file=$newest_bin age_secs=$run_age max_secs=600" >&2
  exit 1
fi &&
if ! j_out=$(sudo journalctl -u johnny-daemon.service -b --no-pager -o cat); then
  echo "STOP-exit-journal-UNREADABLE" >&2
  exit 1
fi &&
if ! echo "$j_out" | grep -q "\"event\":\"reader-begin\""; then
  echo "STOP-exit-journal-UNREADABLE missing=reader-begin" >&2
  exit 1
fi &&
j_stops=$(echo "$j_out" | grep -c "STOP-" || true) &&
if [ "$j_stops" != "0" ]; then
  echo "STOP-exit-journal-stops count=$j_stops" >&2
  exit 1
fi &&
echo STAGE1-EXIT-CHECK-DONE'
```

Expect three `OK` hash lines, current time at or after `2026-11-21 15:33 CT` (`2026-11-21T21:33:00Z`; `STOP-exit-NOT-YET` before then), `/proc/stat` `btime` at or before cutover `2026-11-17T21:30:30Z` (`STOP-exit-rebooted` on any reboot since cutover), units xdp `active` / daemon `active` / Python reader `inactive` (`STOP-exit-units` otherwise), `johnny-daemon.service` `NRestarts=0` + `Result=success` + `ActiveEnterTimestamp` at or before `2026-11-17T21:30:30Z` (`STOP-exit-daemon-restarted` on any restart), all six `CTL` counters readable and parsed as integers (`STOP-exit-ctl-UNREADABLE` if unreadable, missing, or non-integer) with `rate_limited 18217138`, `rb_full 0`, `discarded 0` (`STOP-exit-*-changed` only when a parsed counter differs) and `seen > 168066737` (`STOP-exit-seen-not-increased`), newest `/var/lib/johnny/m1s2b/run-*.bin` readable (`STOP-exit-runfile-UNREADABLE`) with `mtime` age `<= 600` s (`STOP-exit-runfile-stale`), `journalctl -u johnny-daemon.service -b` readable with `"event":"reader-begin"` present (`STOP-exit-journal-UNREADABLE`) and zero `STOP-` lines (`STOP-exit-journal-stops`), and **`STAGE1-EXIT-CHECK-DONE`**. S1-6 is the first runbook paste to use bash `[[ ]]` over SSH (`[[: not found means aj's login shell is not bash; send it back.` — it fails safe before `STAGE1-EXIT-CHECK-DONE` can be reached). `STOP-exit-journal-UNREADABLE missing=reader-begin` can mean journald deleted (rotated away) the 11-17 entries. That is a false stop, not a Stage 1 failure. Any `STOP-exit-*` means Stage 1 has not exited; send the full output back.

**S1-6 result:** passed `2026-11-22T01:22:21Z` (2026-11-21 7:22 PM CST), final line `STAGE1-EXIT-CHECK-DONE`. Stage 1 EXITED. Record: `docs/sessions/2026-11-21-stage1-exit-check-passed.md`.

---

## Rollback (not part of the paste sequence above)

Run this block to switch Johnny back from `johnny-daemon.service` to the Python reader `johnny-m1s2b-reader.service` (`docs/architecture/architecture-rev2.md:315-316`). The BPF program `j_xdp_records` is never detached, and all existing `/var/lib/johnny/m1s2b/run-*.bin` files remain readable by both readers.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb  /root/m1s2b/module1-slice2b-boot.sh
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o" | sudo sha256sum -c - &&
sudo systemctl disable --now johnny-daemon.service &&
sudo rm -f /etc/systemd/system/johnny-m1s2b-reader.service.d/stage1-cutover.conf &&
sudo rmdir --ignore-fail-on-non-empty /etc/systemd/system/johnny-m1s2b-reader.service.d 2>/dev/null || true &&
sudo systemctl daemon-reload &&
sudo systemctl enable --now johnny-m1s2b-reader.service &&
en_rs=$(sudo systemctl is-enabled johnny-daemon.service 2>/dev/null || true) &&
st_rs=$(sudo systemctl is-active johnny-daemon.service 2>/dev/null || true) &&
en_py=$(sudo systemctl is-enabled johnny-m1s2b-reader.service 2>/dev/null || true) &&
st_py=$(sudo systemctl is-active johnny-m1s2b-reader.service 2>/dev/null || true) &&
if [ "$en_rs" != "disabled" ] || [ "$st_rs" != "inactive" ] || [ "$en_py" != "enabled" ] || [ "$st_py" != "active" ]; then
  echo "STOP-stage1-rollback-not-clean rs=$en_rs/$st_rs py=$en_py/$st_py" >&2
  exit 1
fi &&
sudo bash /root/m1s2b/module1-slice2b-boot.sh verify &&
echo STAGE1-ROLLBACK-DONE'
```

Expect all 5 slice 2b pins verified, `johnny-daemon.service` disabled and stopped, the drop-in removed, `johnny-m1s2b-reader.service` enabled and active, `module1-slice2b-boot.sh verify` passing (`M1S2B-VERIFY-DONE`), and **`STAGE1-ROLLBACK-DONE`**.
