# 2026-11-17 America/Chicago: Stage 1 `probe()` Opens `m2_rb` Read-Write (Fix Paste S1-3 `mmap` `EINVAL`)

- **Date:** 2026-11-17 America/Chicago
- **Status:** **FIXED AND REBUILT ON ROCK BOX ONLY (`claude/stage1-probe-rdwr-fix`). Johnny live state is unchanged (`johnny-m1s2b-reader.service` remains live and active; `/usr/local/libexec/johnny/johnny-daemon` and `/etc/systemd/system/johnny-daemon.service` were installed by Paste S1-3 before `--probe` exited, never enabled or started; nothing was cut over and there is nothing to roll back).**
- **Branch:** `claude/stage1-probe-rdwr-fix` (worktree `/home/aj/Projects/strix-halo-johnny-stage1-fix`, based on `5520d1d`)
- **Revision:** handoff rev 118 (`docs/os-handoff.md`), runbook rev 2 (`docs/tool-install/stage1-rust-daemon-cutover.md`)
- **Constraints kept:** no ssh, no sudo, no contact with Johnny (`192.168.50.152`). `main` and all other worktrees untouched. Historical records (`docs/findings/stage1/2026-11-15-*`, `docs/sessions/2026-11-15-stage1-rust-daemon.md`, `docs/sessions/Johnny_Stage1RustDaemon_Session_Log_2026-11-15.csv`) untouched.

## 1. Paste S1-3 Failure on Johnny (Ubuntu Kernel 7.0.0-42.42)

When Paste S1-3 of `docs/tool-install/stage1-rust-daemon-cutover.md` ran on Johnny, all staged and live SHA-256 checks passed and `/usr/local/libexec/johnny/johnny-daemon` and `/etc/systemd/system/johnny-daemon.service` were installed, after which `sudo /usr/local/libexec/johnny/johnny-daemon --probe` failed with verbatim output:

```json
{"version":1,"event":"stop","stop":"STOP-mmap-probe errno=22 (Invalid argument (os error 22))"}
```

Nothing was cut over: `johnny-m1s2b-reader.service` remains active and enabled, and `johnny-daemon.service` was never enabled or started.

## 2. Root Cause (Verified Against Ubuntu 7.0.0-42.42 Kernel Source)

- `crates/johnny-daemon/src/bpf.rs` `probe()` opened the `/sys/fs/bpf/johnny_m1s2b/m2_rb` pin with `BPF_F_RDONLY` (`open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, true)`) and then called `mmap` with `MAP_SHARED`, `PROT_READ`, 2 pages at offset 0.
- On Johnny's Ubuntu kernel `7.0.0-42.42`, in `mm/mmap.c` `do_mmap()` (`case MAP_SHARED` falling through to `MAP_SHARED_VALIDATE`):
  `vm_flags |= VM_SHARED | VM_MAYSHARE; if (!(file->f_mode & FMODE_WRITE)) vm_flags &= ~(VM_MAYWRITE | VM_SHARED);`
  (mainline v7.3's `vma_flags_clear(&vma_flags, VMA_MAYWRITE_BIT, VMA_SHARED_BIT)` spelling on Rock Box is equivalent, but is not Johnny's source) — a file descriptor without `FMODE_WRITE` (`BPF_F_RDONLY`) has `VM_SHARED` cleared even for a `PROT_READ` mapping.
- In `kernel/bpf/syscall.c` `bpf_map_mmap()`:
  `if (!(vma->vm_flags & VM_SHARED)) return -EINVAL;`
  — returns `-EINVAL` (`errno=22`).
- `attach()` (`crates/johnny-daemon/src/bpf.rs:240-282`) already opens `m2_rb` read-write (`rdonly = false`, `MapData::from_pin`), matching `docs/tool-install/johnny-m1s2b-reader.py` (`obj_get(..., rdonly=False)` + `mmap_ring`), so the live attach path is not affected. `m2_cfg` and `m2_ctl` are never mmapped (lookup only) and stay `BPF_F_RDONLY`.
- With a read-write fd (`FMODE_WRITE` present), a `PROT_READ`, `MAP_SHARED` mapping of pages `0..1` is accepted: only `kernel/bpf/syscall.c` `bpf_map_mmap()` clears `VM_MAYWRITE` when `VM_WRITE` is absent (before `map->ops->map_mmap`), and `kernel/bpf/ringbuf.c` `ringbuf_map_mmap_kern()` only rejects a `VM_WRITE` VMA that is not the one consumer page at `pgoff 0` (`-EPERM`). Thus `probe()` still cannot write `consumer_pos` and consumes nothing beside the live reader.

## 3. Audit of `crates/` and `docs/tool-install/*.py` for Other Read-Only `mmap` Calls

Searched `crates/` and `docs/tool-install/*.py` (`johnny-m1s2b-reader.py`, `johnny-m1s2-reader.py`, `module1-slice2-reader-test.py`, `module1-slice2b-drain-bench.py`) for any other `mmap` on a `BPF_F_RDONLY` descriptor:

- **Result:** **None besides `probe()` in `crates/johnny-daemon/src/bpf.rs`.**
  - `crates/johnny-daemon/src/bpf.rs`: `attach()` opens `m2_rb` with `rdonly = false` (`:242`) before mapping consumer/producer pages; `cfg_map()` (`:133`) and `ctl_map()` (`:141`) open `m2_cfg` and `m2_ctl` with `rdonly = true` (`BPF_F_RDONLY`) for map lookups only and never call `mmap`.
  - `docs/tool-install/johnny-m1s2b-reader.py`: opens `m2_rb` with `rdonly=False` (`:504`) before `mmap_ring` (`:508`); opens `m2_cfg` (`:505`) and `m2_ctl` (`:506`) with `rdonly=True` for lookups only.
  - `docs/tool-install/johnny-m1s2-reader.py`: opens `m2_rb` with `rdonly=False` (`:345`) before `mmap_ring` (`:348`); opens `m2_cfg` (`:346`) and `m2_ctl` (`:347`) with `rdonly=True` for lookups only.
  - `docs/tool-install/module1-slice2-reader-test.py`: asserts `rdonly == (name != "m2_rb")` (`:323`) and only mmaps synthetic temp files / mock ring fds.
  - `docs/tool-install/module1-slice2b-drain-bench.py`: no `BPF_OBJ_GET` or `mmap` calls.

## 4. Fix & Regression Guard

1. **`crates/johnny-daemon/src/bpf.rs`:**
   - In `probe()` (`:299`), changed `open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, true)` to `open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, false)`.
   - Kept `m2_cfg` and `m2_ctl` read-only (`BPF_F_RDONLY`) and kept `probe()`'s 2-page position mapping `libc::PROT_READ` at offset `0`.
   - Updated the module header comment (`:9-21`) and `probe()` doc comment (`:284-296`) citing Johnny's Ubuntu `7.0.0-42.42` `mm/mmap.c` `do_mmap` (noting mainline v7.3 `vma_flags_clear` is equivalent), `kernel/bpf/syscall.c` `bpf_map_mmap`, and `kernel/bpf/ringbuf.c` `ringbuf_map_mmap_kern`.
2. **`crates/johnny-daemon/tests/parity.rs`:**
   - Added `probe_opens_m2_rb_read_write_and_maps_positions_read_only` (`:841-884`), which parses `pub fn probe` from `src/bpf.rs` and asserts `open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, false)` is present, `rdonly = true` is absent on `m2_rb`, and the `Mapping::new` call uses `libc::PROT_READ` without `PROT_WRITE`.
   - Extended `cutover_runbook_audit` (`:716-839`) to verify all three Stage 1 SHA-256 pins (`johnny-daemon`, `johnny-daemon.service`, `johnny-daemon.cdx.json`) across every runbook paste.
   - **Kernel-only caveat:** A real BPF ringbuf `mmap` test requires creating a kernel BPF map, which requires privilege on Rock Box (`kernel.unprivileged_bpf_disabled=2`). The actual kernel `mmap` behavior is kernel-only and is proven only by running Paste S1-3 on Johnny.
3. **`docs/tool-install/stage1-rust-daemon-cutover.md` & `docs/os-handoff.md`:**
   - Replaced every occurrence of the old binary and SBOM pins with the new pins across `docs/tool-install/stage1-rust-daemon-cutover.md` (Section 2, Section 3 tag signing, Pastes S1-1..S1-4) and recorded the current pins in `docs/os-handoff.md` rev 118 while preserving the historical 2026-11-15 measurement in rev 117.
   - Set Rock Box checkout path consistently to `/home/aj/Projects/strix-halo-johnny-stage1-fix` in Pastes S1-1 and S1-2, and noted that the rev 1 files already staged in `/home/aj/cis-audit/stage1` on Johnny from the failed S1-3 attempt are stale and must be re-copied by Paste S1-2 before re-running Paste S1-3.

## 5. New SHA-256 Pins & Sizes

| Artifact | SHA-256 | Size | Notes |
|---|---|---|---|
| `crates/dist/johnny-daemon` | `08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac` | `461264` bytes | Rebuilt via `bash crates/release.sh` (was `e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5`, `461264` bytes; `97f1d58` before comment line shift was `e80253b2dad575923a8a557ddc42800f85d81d67681ed6b21990e79ae0858e30`) |
| `etc/systemd/system/johnny-daemon.service` | `e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa` | `1240` bytes | Unchanged |
| `crates/johnny-daemon.cdx.json` | `8d74fe6ee2f9200ff8b18b63c596a5301688055287c72a5ecc756485ecb59b86` | `14948` bytes | Updated CycloneDX 1.5 SBOM (was `169558ff46d732ae471991edec867adec487757580682ff5e291583571dd7f58`, `14948` bytes; `97f1d58` was `b7d0d2472528afb9f4041b24c9337eecb0fb6e61f4094d47a0ac38a370559136`) |

## 6. Verification Results on Rock Box

- `bash docs/tool-install/module1-slice2b-self-test.sh`: `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=15`, `OUTSIDE-FENCE-DIFF-OK blocks=17`, `RUNBOOK-OK blocks=22`, `SELF-TEST-OK`.
- `(cd crates && cargo test --locked --offline)`: **42 passed, 0 failed** (21 unit tests in `johnny-daemon`, 7 integration/parity tests in `crates/johnny-daemon/tests/parity.rs`, 14 unit tests in `johnny-record-v1`).
- `(cd crates && cargo clippy --all-targets --locked --offline)`: **0 warnings**.
- `bash crates/release.sh`: `STAGE1-RELEASE-OK`, hashes verified against `docs/tool-install/stage1-rust-daemon-cutover.md` and `docs/os-handoff.md`.
