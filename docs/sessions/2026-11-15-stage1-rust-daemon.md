# 2026-11-15 America/Chicago: Stage 1 Rust Userspace Daemon (`johnny-daemon`) Drafted & Parity-Tested on Rock Box

- **Date:** 2026-11-15 America/Chicago (AJ go 2026-11-14 10:56 PM CT; writer seat catch-up 2026-11-15 ~12:50 AM CT)
- **Status:** **COMPLETE ON ROCK BOX (DRAFTED + PARITY-TESTED). Nothing applied on Johnny. Nothing ran on Johnny.**
- **Branch:** `claude/stage1-rust-daemon` (worktree `/home/aj/Projects/strix-halo-johnny-stage1`, based on `claude/practical-ritchie-4c6vvf` tip `7f94230`)
- **Revision:** handoff rev 117
- **Seats:** writer = Claude Fable 5.2 (initial workspace crates) -> Gemini 4 Argon (audit, parity test suite, release build + CycloneDX SBOM, draft systemd unit, draft cutover/rollback runbook, docs, verification). Reviewer = Grok 4.7 high (adversarial-reviewer).
- **Constraints kept:** no ssh, no sudo, no contact with Johnny (`192.168.50.152`), the switch, or any other host. `main` untouched. No live slice 2b script, unit, C BPF source, compiled C BPF object, or sha256 pin changed. No signing keys created. Johnny's one-week capture test runs until 2026-11-21 15:33 CT (21:33Z); nothing asks AJ to touch Johnny before then.

## AJ Stage 1 Decisions Recorded (2026-11-14 10:56 PM CT)

1. **Userspace BPF (`aya`, O5):** Use `aya` (`=0.16.0`, `default-features = false`) in userspace only (`crates/Cargo.toml:26`, `crates/johnny-daemon/src/bpf.rs:1-143`). Attach to the existing pinned maps (`m2_rb`, `m2_cfg`, `m2_ctl`) under `/sys/fs/bpf/johnny_m1s2b` or load the existing compiled C object (`docs/tool-install/module1-xdp-records.o`) in userspace without modifying the C BPF source, object, or live pins/hashes.
2. **Implicit v1 wire contract (`struct m2_rec`, O6):** Freeze today's 80-byte `struct m2_rec` (`docs/tool-install/module1_xdp_records.c:133-165`) as implicit v1 across the kernel-to-userspace boundary, stamp `"version": 1` in userspace outputs (`crates/johnny-record-v1/src/lib.rs:20`, `crates/johnny-daemon/src/control/status.rs:41`), safely skip unknown versions or fields in readers (`crates/johnny-record-v1/src/record.rs:106-135`, `crates/johnny-record-v1/src/runfile.rs:182-198`), and defer new fields / in-kernel binary header changes to v2.
3. **Cargo workspace (`crates/`, O8):** `crates/` is a Cargo workspace next to `docs/` (`crates/Cargo.toml:1-27`) with a shared `johnny-record-v1` parser library crate (`crates/johnny-record-v1/`, `#![forbid(unsafe_code)]`, reusable by the Stage 2 Rock Box agent) and a `johnny-daemon` binary crate (`crates/johnny-daemon/`). Keep `docs/tool-install/johnny-m1s2b-reader.py` in place for fallback/rollback.
4. **Plain Cargo builds, SHA-256, CycloneDX SBOM, and AJ-signed git tags (O9):** `crates/release.sh` builds the release binary (`cargo build --release --locked`), emits `crates/dist/johnny-daemon.sha256`, and generates CycloneDX 1.5 SBOM `crates/johnny-daemon.cdx.json` (`cargo-cyclonedx` is missing on Rock Box; `crates/release.sh:57-129` generates deterministic CycloneDX 1.5 JSON from `cargo metadata --locked --offline` + `crates/Cargo.lock`, and uses `cargo cyclonedx` if installed later). Release signing uses AJ-signed git tags (`git tag -s`); no signing keys created by agents (`docs/tool-install/stage1-rust-daemon-cutover.md:62-85`).

## Work Completed

1. **Audited & verified workspace crates (`crates/johnny-record-v1`, `crates/johnny-daemon`):**
   - `crates/johnny-record-v1`: zero-unsafe shared parser library (`src/record.rs`, `src/runfile.rs`, `src/summary.rs`, `src/utc.rs`) matching the 96-byte `JM1S2RB\0` run-file header and 80-byte `struct m2_rec` v1 layout, safely skipping unknown versions/fields, and stamping `"version": 1` in JSON outputs.
   - `crates/johnny-daemon`: userspace sensor daemon separating NIST SP 800-207 control plane (`src/control/{config.rs,policy.rs,status.rs}`) and data plane (`src/data/{ring.rs,synth.rs,writer.rs}`), with `aya` userspace BPF inspection/attachment in `src/bpf.rs` and `src/data/ring.rs`, plus `--summary`, `--dump-json`, and `--synth-ring` modes.
2. **Parity & integration test suite (`crates/johnny-daemon/tests/parity.rs`):**
   - 6 end-to-end tests proving byte-identical run-file generation, rotation, retention pruning, and `--summary` output between `johnny-daemon` and `docs/tool-install/johnny-m1s2b-reader.py` across 9 synthetic/recorded scenarios (basic, size-rotate, keep-prune, dir-cap, low-disk-space, wraparound + discard + unknown v2/v99 records + 96B unknown-field record, corrupt ring pointer, and cross-reader `--summary` verification), plus `"version": 1` JSON stamping, time-based rotation + stop-file shutdown, CLI smoke tests, systemd unit sandbox comparison, and cutover runbook audit.
3. **Release build & CycloneDX SBOM (`crates/release.sh`, `crates/johnny-daemon.cdx.json`):**
   - Built release binary `crates/dist/johnny-daemon` (SHA-256 `e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5`, 462000 bytes, stripped LTO, links only `libc.so.6` and `libgcc_s.so.1`, `GLIBC_2.34`).
   - Generated CycloneDX 1.5 SBOM `crates/johnny-daemon.cdx.json` (SHA-256 `8921f99596566491daab31a29688b43977313d4dcdf87a77758a08ab60d157d1`, 21 library components + 1 application root).
4. **Draft systemd unit (`etc/systemd/system/johnny-daemon.service`):**
   - SHA-256 `e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa`. Matches every sandbox directive of `etc/systemd/system/johnny-m1s2b-reader.service`. Not installed, not enabled, not started.
5. **Draft cutover/rollback runbook (`docs/tool-install/stage1-rust-daemon-cutover.md`):**
   - Marked `DO NOT RUN BEFORE PASTE W (after 2026-11-21 15:33 CT / 21:33Z)`, with Pastes S1-1 through S1-5 and a standalone Rollback section keeping `johnny-m1s2b-reader.service` as the immediate rollback.
6. **Architecture & handoff updates:**
   - Updated `docs/architecture/architecture-rev2.md` to Rev 2 (`2026-11-15`) recording AJ's four Stage 1 picks (O5, O6, O8, O9).
   - Bumped `docs/os-handoff.md` to rev 117.

## Checks

- `cargo test --locked --offline` (in `crates/`): 41 passed, 0 failed (21 unit + 6 integration/parity + 14 `johnny-record-v1` unit).
- `cargo clippy --all-targets --locked --offline` (in `crates/`): 0 warnings.
- `bash crates/release.sh`: `RELEASE-BINARY dist/johnny-daemon sha256=e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5`, `RELEASE-SBOM johnny-daemon.cdx.json tool=cargo-metadata-lockfile`, `STAGE1-RELEASE-OK`.
- `systemd-analyze verify etc/systemd/system/johnny-daemon.service`: clean.
- `bash docs/tool-install/module1-slice2b-self-test.sh`: `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=15`, `OUTSIDE-FENCE-DIFF-OK blocks=17`, `RUNBOOK-OK blocks=22`, `SELF-TEST-OK`.
