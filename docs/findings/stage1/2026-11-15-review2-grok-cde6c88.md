APPROVE-WITH-NITS

Re-review of tip `cde6c88` (fix `3317dca..cde6c88`, full `7f94230..cde6c88`). Read-only. Nothing was edited, committed, pushed, or sent to Johnny. `rustc 1.100.0 (0ef1bc386 2026-11-09)` from `~/.cargo/bin`. `cargo cyclonedx` is not installed.

Blockers: none.

## Review 1

### B1 — fixed

`docs/tool-install/stage1-rust-daemon-cutover.md:131-138` (S1-3) and `:213-221` (S1-5). Both pastes `install` the chosen `run-*.bin` to `/root/m1s2b/stage1-summary-snap.bin` and run `johnny-daemon --summary` and `johnny-m1s2b-reader.py --summary` on that copy. Neither compares the live inode.

A trailing partial record is ignored by both readers. Measured on a header plus four v1 records plus three extra bytes: stdout equal (`part` case). Same for a closed file, and for `--summary FILE --top 5` and `--top 5 --summary FILE`.

### B2 — fixed

`bash crates/release.sh` reproduced the recorded artifacts (`STAGE1-RELEASE-OK`, SBOM tool `cargo-metadata-lockfile`, SBOM bytes identical to the committed file).

| Claim | Recorded | Measured |
|---|---|---|
| Release binary sha256 | `e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5` | same |
| Release binary size | `461264` | `461264` (`stat -c '%s'`) |
| SBOM sha256 | `169558ff46d732ae471991edec867adec487757580682ff5e291583571dd7f58` | same, including `crates/dist/johnny-daemon.cdx.json` |
| SBOM shape | 24 library components + 1 application root | `len(components)=24`, all `type=library`, root `type=application` |
| Unit sha256 | `e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa` | same |

S1-1, S1-2, and S1-3 all pass that SBOM digest to `sha256sum -c`. CycloneDX 1.5. `tools[0].name` is `cargo-metadata-lockfile`. Crate checksums match `crates/Cargo.lock` (0 mismatches). `johnny-record-v1` has no checksum because it is a path crate. The application component hash is the binary digest above. `NEEDED` is `libgcc_s.so.1` and `libc.so.6` only. Highest glibc symbol version is `GLIBC_2.34`. Stripped PIE.

### B3 — fixed, one residual nit (N1 below)

The `RingSource` sentence and the candidate/validate/commit/rollback store are gone. Architecture, handoff, and the session note now say there is no rule store in this commit, and they point live retention at `etc/systemd/system/johnny-daemon.service:16`. That line is the `ExecStart` with `1073741824 / 3600 / keep 200 / 214748364800 / 107374182400`.

Checked against this tree (ranges that stop early stop at the last non-test line):

- `aya = { version = "=0.16.0", default-features = false }` at `crates/johnny-daemon/Cargo.toml:9`. Lockfile `aya` `0.16.0`. Import only at `crates/johnny-daemon/src/bpf.rs:28`. `attach` is `:235-277`. `probe` is `:283-322`. Probe JSON stamp is `:311`.
- `OUTPUT_VERSION` is `crates/johnny-record-v1/src/lib.rs:25`. Record JSON stamp starts at `record.rs:140-145`. Daemon JSON stamp is `status.rs:118`. Unknown record versions return at `record.rs:83-86`. Ring skip/stop is `ring.rs:133-140`. Unknown headers are `runfile.rs:130-145`.
- `crates/Cargo.toml` is 15 lines. `release.sh` is 146 lines. The cyclonedx-missing note is `release.sh:3-5` and `:29-32`. The generator is `:34-141`. Runbook note is `stage1-rust-daemon-cutover.md:23`. Signing step is `:60-67`.
- `config.rs:1-246` ends at `parse`. `policy.rs:1-92` ends at `run_file_name` (tests start at 94). `status.rs:1-244` ends at `Log::emit` (tests start at 246). `synth.rs:1-127` ends before `#[cfg(test)]` at 128. `KernelMaps` is `data/mod.rs:15-23`. `Ring` is `ring.rs:24-152`. `RotatingWriter` starts at `writer.rs:78`. `daemon.rs` is 128 lines; `run` is `:70-128`; `pump` starts at `:25`.
- Parity comparison is `parity.rs:243-460`. Discarded frame is `:280-287`. Version byte 2 is `:470-473`. Sandbox test is `:664-713`. Runbook audit is `:715-831`. Versions 0, 2, and 255 are `record.rs:287-292`. Header `rec_size` 96 is `runfile.rs:312-316`.
- `m2_rb` is `module1_xdp_records.c:218-221`. `struct m2_rec` is `:133-165`. Version constant is `:78`. The emit is `:594` (`r.ver = M2_REC_VERSION`). `do_verify`'s reader gate is `module1-slice2b-boot.sh:698-702`. `do_window` (`:836-891`) does not check the reader unit. Paste W is `module1-slice2b-boot-unit.md:583-601`. The review rule is `AGENTS.md:13`.

### N1 — fixed

`crates/release.sh:29-33` always sets `SBOM_TOOL=cargo-metadata-lockfile` and does not call `cargo cyclonedx`. The homemade document is the one that is written. A rebuild stamped `tool=cargo-metadata-lockfile` and did not change the file.

### N2 — fixed

`docs/sessions/2026-11-15-stage1-rust-daemon.md:23` names the six integration tests and the unit cases that exist: v1 byte parity with one discarded frame, version byte 2 skipped, versions 0/2/255 not parsed, header `rec_size` 96 rejected. No v99 case and no 96-byte unknown-field record.

### N3 — fixed

`docs/tool-install/stage1-rust-daemon-cutover.md:175-191`. After `enable --now`, the paste retries `reader-begin` up to ten one-second sleeps, tries once more, then `STOP-missing-reader-begin` and exits 1. GNU grep on this machine: a `{"version":1,"event":"reader-begin"` line matches the paste pattern (exit 0); a `reader-end` line does not (exit 1).

## Nits

### N1 — retention citation is one line high

`docs/architecture/architecture-rev2.md:314`.

The exit criterion cites today's retention at `docs/os-handoff.md:45`. That line is the Rev 114 heading. The limits (1 GiB / 3600 s, keep=200, 200 GiB, 100 GiB) are the next line, `docs/os-handoff.md:46`. The same sentence also cites `etc/systemd/system/johnny-daemon.service:16`, and that line is the live `ExecStart`. The paste does not read the handoff line. Point the handoff cite at line 46.

### N2 — the session says `systemd-analyze verify` was clean

`docs/sessions/2026-11-15-stage1-rust-daemon.md:41`.

Measured: exit 1, one diagnostic, no other output:

```
johnny-daemon.service: Command /usr/local/libexec/johnny/johnny-daemon is not executable: No such file or directory
```

The draft binary is not installed at that path on Rock Box. The unit text has no other verify diagnostic. The sandbox comparison still passed. Record the warning. This does not change the paste.

### N3 — a summary mismatch throws away the only copy

`docs/tool-install/stage1-rust-daemon-cutover.md:137-138` and `:219-221`.

S1-3 deletes the snapshot and then compares the two captured strings, and it prints neither. S1-5 prints the Rust summary only. On a mismatch the paste exits 1 with nothing to diff. Print both strings before the test, and delete the snapshot after it. Non-blocking: the strings are already taken from the stable copy, and v1 files match (measured).

## Checked, not findings

- `git diff 7f94230..cde6c88` does not touch `johnny-m1s2b-reader.py`, `module1_xdp_records.c`, `module1-xdp-records.o`, `module1-slice2b-boot.sh`, `johnny-m1s2b-reader.service`, or `johnny-capture-xdp-records.service`. Measured sha256: object `a73c5bd2dc0bd7c2c3b99a937d703abe4628f715b0aa1e00b3ce29fe8da99481`, boot `a4d4dfa4c7d6ba3c9ffb64810a54952f4e7ce652889a2fe6f628adadef1bf9eb`, capture unit `4e2e359d89691320f85464f8497cb94d18ee861ed7cd03fb49f69a543114de0a`, reader `476cf86762aacbeb3c71a42638bf0a01eacf9801cf02719a1a5c584cc93e6f37`, reader unit `e5c16249c479a5f807c2c794b146ee81ec2ed2f937c445f65480088cfa0d529c`.
- Workspace members are `johnny-record-v1` (`#![forbid(unsafe_code)]`) and `johnny-daemon`. Control plane is `src/control/` (bounds, rotate/keep/dir-cap/low-disk, log). Data plane is `src/data/` (`KernelMaps`, `Ring`, `RotatingWriter`). `aya` stays in `bpf.rs`. `probe` opens every pin `BPF_F_RDONLY` and maps the ring pages `PROT_READ` (`bpf.rs:279-295`). `attach` does not load or create a BPF object; the only kernel write it describes is the ring consumer position.
- Run file is 96-byte `JM1S2RB\0` then 80-byte records. `"version":1` is stamped on JSON logs, `--dump-json`, and `--probe`. Unknown ring versions are not parsed as v1. Default policy is skip (`config.rs:84`). The unit does not pass `--on-unknown-version`. `--summary` on a file that already contains a version-2 record does not match the Python reader (Rust skips it and adds `UNKNOWN-VERSION`; Python counts the bytes). The kernel emit path writes version 1 only, and neither writer stores another version, so S1-3 and S1-5 are comparing v1 files. Those matched, including a torn tail.
- `cargo test --locked --offline`: 41 passed (21 `johnny-daemon` unit, 6 `parity.rs`, 14 `johnny-record-v1`). `parity_run_files_and_summary_match_python_reader` passed. `cargo clippy --all-targets --locked --offline -- -D warnings`: exit 0. `bash docs/tool-install/module1-slice2b-self-test.sh`: `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=15`, `OUTSIDE-FENCE-DIFF-OK blocks=17`, `RUNBOOK-OK blocks=22`, `SELF-TEST-OK`.
- Daemon unit sandbox keys match the reader unit except `Description`, `ConditionPathExists` (the daemon binary), and `ExecStart` (the same retention flags). The only added key is `Conflicts=johnny-m1s2b-reader.service`. Draft banner is lines 1–2. `parity.rs:664-713` passed.
- Runbook banner is `DO NOT RUN BEFORE PASTE W` / `2026-11-21 15:33 CT`. It still says the adversarial-reviewer has not reviewed it. That sentence is this review. Rollback is a separate block (`stage1-rust-daemon-cutover.md:233-263`), puts `johnny-m1s2b-reader.service` back, and does not detach `j_xdp_records`. Signing is `git tag -s` / `git verify-tag` in a `text` fence (`:64-67`). No key material in the diff. Six bash fences; the runbook audit passed.
- `git status` was clean after `crates/release.sh`.
