# Stage 1: Rust Userspace Sensor Daemon (`johnny-daemon`) — Draft Cutover & Rollback Runbook

Rev 1, 2026-11-15 America/Chicago. Status: **DRAFT ONLY — DO NOT RUN BEFORE PASTE W COMPLETES (after 2026-11-21 15:33 CT / 21:33Z). Not yet reviewed by the adversarial-reviewer. Nothing installed, enabled, or started on Johnny.**

> **HOLD — DO NOT RUN BEFORE PASTE W (after 2026-11-21 15:33 CT / 21:33Z):**
> Johnny's one-week uninterrupted capture test is running until **2026-11-21 15:33 CT (21:33Z)** (`docs/os-handoff.md:4, 33-39`, `docs/tool-install/module1-slice2b-boot-unit.md:583-601`). Do not touch Johnny, do not copy files to Johnny, and do not run any paste in this runbook until **Paste W** (`docs/tool-install/module1-slice2b-boot-unit.md:583-601`) has been run by AJ after `2026-11-21 15:33 CT` and printed `M1S2B-WEEK-DONE` and `M1S2B-NORC-WEEK-DONE`.

---

## 1. Purpose and AJ Decisions (2026-11-14 10:56 PM CT)

Stage 1 (`docs/architecture/architecture-rev2.md:287-324`) replaces the Python ring-buffer reader (`johnny-m1s2b-reader.py`) with the Rust userspace sensor daemon (`johnny-daemon`) while keeping the kernel XDP side (`j_xdp_records`) and all live BPF pins untouched, and keeping the Python reader installed on disk as an immediate rollback.

AJ approved the four Stage 1 code-shape decisions on **2026-11-14 at 10:56 PM CT** (`docs/architecture/architecture-rev2.md` §1.2, §4 Stage 1):

1. **BPF crate (`aya`, userspace only):** `johnny-daemon` uses `aya = "=0.16.0"` (`default-features = false`) isolated in a single module (`crates/johnny-daemon/src/bpf.rs`). It attaches in userspace only to the existing pinned maps under `/sys/fs/bpf/johnny_m1s2b` (`m2_rb` read-write for the ring consumer page; `m2_cfg` and `m2_ctl` opened `BPF_F_RDONLY` via `BPF_OBJ_GET` and wrapped in `aya::maps::MapData::from_fd`). It never modifies, loads, or rebuilds `docs/tool-install/module1_xdp_records.c` or `docs/tool-install/module1-xdp-records.o`, and never alters any live pins or hashes.
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
e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5  crates/dist/johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  etc/systemd/system/johnny-daemon.service
169558ff46d732ae471991edec867adec487757580682ff5e291583571dd7f58  crates/johnny-daemon.cdx.json
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

Agents never create signing keys or sign tags. When AJ approves the Stage 1 commit and binary hash (`e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5`), AJ creates and verifies a signed git tag on Rock Box using his own signing key:

```text
git tag -s stage1-daemon-v0.1.0 -m "Stage 1 johnny-daemon v0.1.0 (sha256 e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5)"
git verify-tag stage1-daemon-v0.1.0
```

---

## 4. Cutover Pastes — DO NOT RUN BEFORE PASTE W (after 2026-11-21 15:33 CT / 21:33Z)

Every paste below is typed on Rock Box. Pastes S1-2 through S1-5 touch Johnny and **MUST NOT** be run until after **2026-11-21 15:33 CT (21:33Z)** and after **Paste W** (`docs/tool-install/module1-slice2b-boot-unit.md:583-601`) has passed with `M1S2B-NORC-WEEK-DONE`.

### Paste S1-1: Rock Box self-test, Cargo test suite, release build, and hash gate (no root, no SSH)

***<u>Run on Rock Box</u>***

```bash
export PATH="$HOME/.cargo/bin:$PATH" &&
cd /home/aj/Projects/strix-halo-johnny-stage1 &&
bash docs/tool-install/module1-slice2b-self-test.sh &&
(cd crates && cargo test --locked --offline) &&
bash crates/release.sh &&
echo "e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5  crates/dist/johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  etc/systemd/system/johnny-daemon.service
169558ff46d732ae471991edec867adec487757580682ff5e291583571dd7f58  crates/johnny-daemon.cdx.json" | sha256sum -c - &&
echo STAGE1-ROCKBOX-GATE-DONE
```

Expect `SELF-TEST-OK`, all Rust unit and parity tests passing, `STAGE1-RELEASE-OK`, three `OK` hash lines, and **`STAGE1-ROCKBOX-GATE-DONE`**.

### Paste S1-2: Copy Stage 1 binary, unit, and SBOM to Johnny staging dir (DO NOT RUN BEFORE PASTE W; no sudo)

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p -m 0700 /home/aj/cis-audit/stage1' &&
scp /home/aj/Projects/strix-halo-johnny-stage1/crates/dist/johnny-daemon /home/aj/Projects/strix-halo-johnny-stage1/etc/systemd/system/johnny-daemon.service /home/aj/Projects/strix-halo-johnny-stage1/crates/johnny-daemon.cdx.json aj@192.168.50.152:/home/aj/cis-audit/stage1/ &&
ssh aj@192.168.50.152 'cd /home/aj/cis-audit/stage1 && echo "e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5  johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  johnny-daemon.service
169558ff46d732ae471991edec867adec487757580682ff5e291583571dd7f58  johnny-daemon.cdx.json" | sha256sum -c - && echo STAGE1-COPY-DONE'
```

Expect three `OK` hash lines and **`STAGE1-COPY-DONE`**.

### Paste S1-3: Preflight live pins, install Stage 1 files (not started), and run read-only `--probe` & `--summary` smoke (DO NOT RUN BEFORE PASTE W)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit/stage1 &&
echo "e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5  johnny-daemon
e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa  johnny-daemon.service
169558ff46d732ae471991edec867adec487757580682ff5e291583571dd7f58  johnny-daemon.cdx.json" | sha256sum -c - &&
echo "a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb  /root/m1s2b/module1-slice2b-boot.sh
476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37  /usr/local/libexec/johnny/johnny-m1s2b-reader.py
e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c  /etc/systemd/system/johnny-m1s2b-reader.service
4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a  /etc/systemd/system/johnny-capture-xdp-records.service
a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481  /root/m1s2b/module1-xdp-records.o" | sudo sha256sum -c - &&
sudo install -m 0755 -o root -g root johnny-daemon /usr/local/libexec/johnny/johnny-daemon &&
sudo install -m 0644 -o root -g root johnny-daemon.service /etc/systemd/system/johnny-daemon.service &&
echo "e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5  /usr/local/libexec/johnny/johnny-daemon
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

### Paste S1-4: Cutover from `johnny-m1s2b-reader.service` to `johnny-daemon.service` (DO NOT RUN BEFORE PASTE W)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5  /usr/local/libexec/johnny/johnny-daemon
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

### Paste S1-5: Verify 60 s zero-drop window and dual-reader run-file parity on Johnny (DO NOT RUN BEFORE PASTE W)

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
