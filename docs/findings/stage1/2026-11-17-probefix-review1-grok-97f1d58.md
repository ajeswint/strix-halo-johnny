APPROVE-WITH-NITS

No blockers.

N1. docs/sessions/2026-11-17-stage1-probe-rdwr-fix.md:62 records the SBOM size as 17213 bytes. The file whose sha256 is b7d0d2472528afb9f4041b24c9337eecb0fb6e61f4094d47a0ac38a370559136 is 14948 bytes (`stat -c %s` and `git cat-file -s HEAD:crates/johnny-daemon.cdx.json`; the parent blob is also 14948). The hash is right. The size is not. Required fix: put 14948 in that table. No paste uses the size.

N2. The do_mmap citation is the wrong spelling for the kernel that failed. Johnny is Ubuntu linux 7.0.0-42.42 (`docs/os-handoff.md` kernel row). That tree's `mm/mmap.c` (Launchpad `Ubuntu-7.0.0-42.42`) does not call `vma_flags_clear`. At lines 463-465, `MAP_SHARED` falls through to `MAP_SHARED_VALIDATE` and does:

    vm_flags |= VM_SHARED | VM_MAYSHARE;
    if (!(file->f_mode & FMODE_WRITE))
        vm_flags &= ~(VM_MAYWRITE | VM_SHARED);

`vma_flags_clear(&vma_flags, VMA_MAYWRITE_BIT, VMA_SHARED_BIT)` is mainline v7.3 `mm/mmap.c`, which is the Rock Box kernel line (7.3.0-10), not Johnny. The bits cleared are the same, and that is why `bpf_map_mmap` returns `-EINVAL`. The quotes in `crates/johnny-daemon/src/bpf.rs:11-12`, `docs/tool-install/stage1-rust-daemon-cutover.md:3`, `docs/os-handoff.md` rev 118, and `docs/sessions/2026-11-17-stage1-probe-rdwr-fix.md:22-24` should name the Ubuntu 7.0.0-42.42 statement, or say the v7.3 spelling is equivalent and not the Johnny source.

N3. `crates/johnny-daemon/src/bpf.rs:13-14` and `:281-282` attribute the `VM_MAYWRITE` clear to `ringbuf_map_mmap_kern` as well as `bpf_map_mmap`. On Ubuntu 7.0.0-42.42 only `bpf_map_mmap` (`kernel/bpf/syscall.c:1137-1138`) clears `VM_MAYWRITE`, and it does that before `map->ops->map_mmap`. `ringbuf_map_mmap_kern` (`kernel/bpf/ringbuf.c:281-284`) does not touch `VM_MAYWRITE`. If `VM_WRITE` is set it returns `-EPERM` unless the VMA is exactly one page at `vm_pgoff == 0`. Required fix: say only `bpf_map_mmap` clears `VM_MAYWRITE`. The session's section 2 bullet that splits those two facts is already right.

N4. `docs/os-handoff.md` rev 117 (the 2026-11-15 section, now lines 21-23) was rewritten to the 2026-11-17 binary and SBOM hashes. The handoff no longer records `e39d77684dc7e67b0939dda80f7de18be6e2b59a43ab2c3dd71d8ebe394174b5` or `169558ff46d732ae471991edec867adec487757580682ff5e291583571dd7f58`. Those hashes are still only in the untouched 2026-11-15 session and findings files. Required fix: leave the rev 117 hash sentences as the 2026-11-15 measurement and keep the new hashes in rev 118. Not a paste hazard. The 2026-11-15 files themselves are unmodified.

## What was checked

Range `5520d1d..97f1d58` is one commit, `97f1d58`, parent `5520d1d`. Six files. No ssh, no sudo, no contact with Johnny. Live Johnny state in the session was not re-observed. It matches the shape of Paste S1-3: hashes, `install`, `daemon-reload`, `--version`, then `--probe` under `&&`, with `enable --now` only in S1-4. A failure at `--probe` leaves the unit installed and not enabled or started. `git status --porcelain` was empty after `crates/release.sh`.

### (1) Root cause and whether the fix is sufficient

The failure string is what this code emits. `mmap_stop("probe")` formats `STOP-mmap-probe errno={} ({e})`, and `std::io::Error` for errno 22 displays as `Invalid argument (os error 22)`.

Before this commit, `probe()` called `open_pin(..., true)`, which is `BPF_OBJ_GET` with `file_flags = BPF_F_RDONLY` (`crates/johnny-daemon/src/bpf.rs:42`, `:71`). `bpf_get_file_flag` maps that to `O_RDONLY`, so the anon-inode map file has no `FMODE_WRITE`. `probe()` then `mmap`s `MAP_SHARED` (`Mapping::new`, `:174`) of `2 * page` at offset 0 with `PROT_READ` (`:294`).

On Ubuntu 7.0.0-42.42 that shared mmap of a non-writable file clears `VM_SHARED` (and `VM_MAYWRITE`) after setting them. `bpf_map_mmap` then does `if (!(vma->vm_flags & VM_SHARED)) return -EINVAL` (`kernel/bpf/syscall.c:1100`). Errno 22 is that check. It is not the ringbuf size check: `ringbuf_map_mmap_kern` returns `-EPERM` (errno 1), and only when `VM_WRITE` is set. The old mapping was `PROT_READ`, so `VM_WRITE` was clear and the ringbuf helper would have accepted it. The diagnosis of the errno is right.

The fix opens `m2_rb` with `rdonly = false` (`bpf.rs:285`). That is `MapData::from_pin`. aya 0.16.0 `bpf_get_object` zero-fills `bpf_attr`, so `file_flags` is 0, and `bpf_get_file_flag(0)` returns `O_RDWR`. The fd has `FMODE_WRITE`. `do_mmap` therefore leaves `VM_SHARED` set. `bpf_map_mmap` passes the shared check.

The 2-page `PROT_READ` `MAP_SHARED` mapping at offset 0 of a `BPF_MAP_TYPE_RINGBUF` is then accepted:

- `map->frozen` is not set by mmap. `map_freeze` is a separate command (`syscall.c:2232-2266`) and returns `-EBUSY` if `bpf_map_write_active` is non-zero. The live Python reader already holds a writable consumer mapping, so the map is not frozen. A read-only VMA does not take the `VM_WRITE && frozen` `-EPERM` branch (`syscall.c:1105-1108`) and does not increment the write-active count (`:1114` is inside the `VM_WRITE` branch).
- `map_get_sys_perms` (`syscall.c:994-1003`) strips `FMODE_CAN_WRITE` only when `map->frozen`, and only for the map syscall checks (update, delete, freeze). `do_mmap` tests `FMODE_WRITE`, which an `O_RDWR` open still has. A frozen map would not bring back the EINVAL. This map is not frozen.
- `bpf_map_mmap` clears `VM_MAYEXEC`, and clears `VM_MAYWRITE` because `VM_WRITE` is absent (`:1129-1138`), then calls `ringbuf_map_mmap_kern`.
- `ringbuf_map_mmap_kern` (`ringbuf.c:275-288`) skips the `-EPERM` consumer-page check because `VM_WRITE` is clear, then `remap_vmalloc_range(vma, rb, vm_pgoff + RINGBUF_PGOFF)` with `vm_pgoff == 0`. `RINGBUF_PGOFF` is `offsetof(consumer_pos) >> PAGE_SHIFT`. Two pages from there are the consumer page and the producer page. Both sit inside the vmap: `vmap(..., VM_MAP | VM_USERMAP, ...)` (`ringbuf.c:138-139`), meta pages are `RINGBUF_PGOFF + 2`, and the data area is `max_entries` (4 MiB, page-aligned) mapped twice. `remap_vmalloc_range_partial` rejects a missing `VM_USERMAP`, a misaligned address, or an end past `get_vm_area_size`. This range ends at the meta/data boundary, which is inside the area. `get_vm_area_size` subtracts one guard page when `VM_NO_GUARD` is unset; the data pages still leave slack. This is the same helper the live reader already uses for its producer mapping.

`m2_cfg` and `m2_ctl` stay `open_pin(..., true)` (`:128`, `:136`). They are lookup-only. They are never passed to `Mapping::new`.

So the fix is sufficient for this mapping on Johnny's kernel. It does not depend on the v7.3 spelling in N2.

### (2) attach() versus the Python reader

`attach()` was not logic-changed. It still opens `m2_rb` with `rdonly = false` (`bpf.rs:237`) and maps:

- consumer: `page`, `PROT_READ | PROT_WRITE`, offset 0 (`:250`)
- producer plus data, twice: `page + 2 * RB_BYTES`, `PROT_READ`, offset `page` (`:252`)

`Mapping::new` always uses `MAP_SHARED` (`:174`). `docs/tool-install/johnny-m1s2b-reader.py:245-249` is the same pair: `PROT_READ | PROT_WRITE` at 0 for one page, then `PROT_READ` at `page` for `page + 2 * size`. `m2_rb` is `rdonly=False` (`:504`). `m2_cfg` / `m2_ctl` are `rdonly=True` (`:505-506`) and are only looked up. `RB_BYTES` is `1 << 22` on both sides (`bpf.rs:39`). The live attach path does not have the read-only-fd mmap bug.

### (3) Other mmap of a read-only BPF fd

Repo search for `mmap` / `BPF_F_RDONLY` / `from_pin`: the only `libc::mmap` is `Mapping::new`. Both callers (`attach` at `:250` and `:252`, `probe` at `:294`) use the `m2_rb` fd opened with `rdonly = false`. `obj_get_rdonly` is only reached from `open_pin` when `rdonly` is true, which is only `cfg_map` and `ctl_map`, and those fds are not mapped.

`johnny-m1s2b-reader.py` and `johnny-m1s2-reader.py` (`:345-348`) mmap only the `rdonly=False` ring fd. `module1-slice2-reader-test.py:323` asserts `rdonly == (name != "m2_rb")` and its `mmap_ring` returns the synthetic ring. `module1-slice2b-self-test.sh:219-224` uses `FakeMmap`. `module1-slice2b-drain-bench.py` has neither `BPF_OBJ_GET` nor `mmap`. No other mmap of a `BPF_F_RDONLY` fd.

### (4) The probe still cannot write the kernel

`probe()` does not call map update, does not store `consumer_pos`, and does not map `PROT_WRITE`. The two reads are `read_volatile` of the first `u64` of each page (`bpf.rs:297-302`), which are `consumer_pos` and `producer_pos`. It does not advance the consumer, so it does not consume beside the Python reader.

On the VMA, `bpf_map_mmap` clears `VM_MAYWRITE` when `VM_WRITE` is absent, so `mprotect` to `PROT_WRITE` fails. `bpf_dummy_write` returns `-EINVAL`. `ringbuf_map_update_elem` returns `-ENOTSUPP`. The open is `O_RDWR` for the life of the function, which is required for `VM_SHARED`. The function never maps the one writable shape the kernel allows (exactly one page at offset 0 with `PROT_WRITE`). `Drop` for `Mapping` is `munmap` only. `bpf_map_write_active` is not incremented, so this mmap does not pin the map against freeze and does not disturb the live reader's writable consumer mapping.

### (5) Regression test and runbook audit

`probe_opens_m2_rb_read_write_and_maps_positions_read_only` (`parity.rs:841-884`) is a real lock on the bug that shipped: the `probe` body must contain `open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, false)`, must not contain the `true` form, must contain the `PROT_READ` `Mapping::new` of `2 * page` at offset 0, and must not contain `PROT_WRITE`. It passed. It is a source lock, not a kernel mmap. The session says that, and it is true: Rock Box has `kernel.unprivileged_bpf_disabled=2`, and this review did not create a map. The brace scan does not understand strings. The current `probe` body has no braces inside strings, so the scan bounds the function. That is enough for this fix. It would not catch a later `ptr::write_volatile` that never mentions `PROT_WRITE`. I am not requiring a kernel test on Rock Box.

`cutover_runbook_audit` (`:716-839`) now hashes `crates/johnny-daemon.cdx.json` from disk, reads the binary sha from `metadata.component.hashes[0].content`, and checks every `sha256sum`-shaped pair inside the six `bash` pastes. Unit paths must match `sha256sum` of `etc/systemd/system/johnny-daemon.service`. SBOM paths must match the file hash. `johnny-daemon` paths (exact name or `/johnny-daemon`) must match the SBOM's embedded binary hash. `.service` and `.cdx.json` are matched first, so they are not mistaken for the binary. The test passed. Section 2 and the tag fence are not `bash` blocks, so the test does not see them. I checked them by hand; they carry the same three hashes. S1-5 and Rollback correctly do not pin the new binary. Rollback still pins the five slice 2b hashes only.

### (6) Pins, paths, slice 2b, historical records

`bash crates/release.sh` printed `STAGE1-RELEASE-OK`. Measured after that run:

| Artifact | sha256 | size |
|---|---|---|
| `crates/dist/johnny-daemon` | `e80253b2dad575923a8a557ddc42800f85d81d67681ed6b21990e79ae0858e30` | 461264 |
| `crates/johnny-daemon.cdx.json` and `crates/dist/johnny-daemon.cdx.json` | `b7d0d2472528afb9f4041b24c9337eecb0fb6e61f4094d47a0ac38a370559136` | 14948 |
| `etc/systemd/system/johnny-daemon.service` | `e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa` | unchanged |

`readelf -d` NEEDED is `libgcc_s.so.1` and `libc.so.6`. Highest glibc symbol is `GLIBC_2.34`. `rustc` is `1.100.0 (0ef1bc386 2026-11-09)`, which is the string in the SBOM and in runbook section 2. The SBOM diff against `5520d1d` is only the binary hash string. `git status --porcelain` was empty, so the rebuild did not drift the committed SBOM.

Those three hashes are the only Stage 1 hashes in runbook section 2, the tag command (`stage1-rust-daemon-cutover.md:65`), S1-1 (`:85-87`), S1-2 (`:102-104`), S1-3 (`:116-118` and the installed-path check `:126-127`), and S1-4 (`:152-153`). The old hashes `e39d7768…` and `169558ff…` are gone from the runbook and from the handoff. S1-1 and S1-2 both use `/home/aj/Projects/strix-halo-johnny-stage1-fix`, which is this worktree. No `strix-halo-johnny-stage1` path without `-fix` remains in the runbook.

Slice 2b bytes in this tree match the runbook pins and were not in the diff: `module1-xdp-records.o` `a73c5bd2…`, `module1-slice2b-boot.sh` `a4d4dfa4…`, `johnny-capture-xdp-records.service` `4e2e359d…`, `johnny-m1s2b-reader.py` `476cf867…`, `johnny-m1s2b-reader.service` `e5c16249…`. `git diff --name-only 5520d1d..97f1d58` does not include them, the C source, or the unit.

`docs/sessions/2026-11-15-stage1-rust-daemon.md`, `docs/sessions/Johnny_Stage1RustDaemon_Session_Log_2026-11-15.csv`, and `docs/findings/stage1/2026-11-15-*` are not in the diff. N4 is only the rewritten rev 117 paragraphs inside `docs/os-handoff.md`.

### (7) Session note

`docs/sessions/2026-11-17-stage1-probe-rdwr-fix.md` matches what I measured, except N1 and the kernel spelling in N2.

- Branch, parent `5520d1d`, handoff rev 118, runbook rev 2: right.
- Failure JSON: matches `mmap_stop`.
- `attach` / reader line numbers (`bpf.rs:237`, reader `:504-508`): right.
- Audit of other mmaps: right, re-checked above.
- Fix description (`probe` `:285`, cfg/ctl stay read-only, `PROT_READ`): right.
- New test at `:841-885` and audit at `:716-839`: the test function is `:841-884`; close enough.
- Hash table: both hashes and the binary size and the unchanged unit hash are right. SBOM size is N1.
- `bash docs/tool-install/module1-slice2b-self-test.sh` printed `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=15`, `OUTSIDE-FENCE-DIFF-OK blocks=17`, `RUNBOOK-OK blocks=22`, `SELF-TEST-OK`.
- `cargo test --locked --offline` in `crates/`: 21 unit (`johnny-daemon`) + 7 parity + 14 unit (`johnny-record-v1`) = 42 passed, 0 failed.
- `cargo clippy --all-targets --locked --offline -- -D warnings`: clean.
- `bash crates/release.sh`: `STAGE1-RELEASE-OK` and the hashes above.

The "kernel-only, proven on Johnny" caveat is accurate. This review did not rerun Paste S1-3.

## Relay

APPROVE-WITH-NITS. The EINVAL root cause holds on Ubuntu 7.0.0-42.42: `MAP_SHARED` without `FMODE_WRITE` clears `VM_SHARED` (`mm/mmap.c:463-465`, `vm_flags &= ~(VM_MAYWRITE | VM_SHARED)`), then `bpf_map_mmap` returns `-EINVAL` (`syscall.c:1100`). Opening `m2_rb` `O_RDWR` and mapping 2 pages `PROT_READ` at offset 0 is enough: `ringbuf_map_mmap_kern` only `-EPERM`s `VM_WRITE` VMAs, `remap_vmalloc_range` covers consumer+producer, `map->frozen` / `map_get_sys_perms` do not block it and do not let this VMA write. `attach` already matches `johnny-m1s2b-reader.py` `mmap_ring`. No other `BPF_F_RDONLY` mmap. Pins after `crates/release.sh` match the runbook (binary `e80253b2…` 461264, SBOM `b7d0d247…`, unit `e3c8df9c…` unchanged). Slice 2b and the 2026-11-15 files were not modified. Nits only: session SBOM size is 14948 not 17213; cite Johnny's `vm_flags &= ~` not v7.3 `vma_flags_clear`; `ringbuf_map_mmap_kern` does not clear `VM_MAYWRITE`; put the 2026-11-15 hashes back into handoff rev 117.

## Outline

- Verdict: APPROVE-WITH-NITS. No blockers.
- N1: session SBOM size 17213; measured 14948. Hash is right.
- N2: Johnny 7.0.0-42.42 clears `VM_SHARED` with `vm_flags &= ~(VM_MAYWRITE | VM_SHARED)`, not `vma_flags_clear`. Same effect. Docs quote v7.3.
- N3: only `bpf_map_mmap` clears `VM_MAYWRITE`. `ringbuf_map_mmap_kern` returns `-EPERM` for a writable VMA that is not the one consumer page.
- N4: handoff rev 117 hashes were overwritten with the new pins. 2026-11-15 files themselves are untouched.
- Root cause: `BPF_F_RDONLY` fd, `MAP_SHARED`, `bpf_map_mmap` `EINVAL`. Old mapping was `PROT_READ`, so the ringbuf `-EPERM` path was not the failure.
- Fix: `probe` `open_pin(..., false)` via aya `from_pin` (`O_RDWR`). 2-page `PROT_READ` at 0 passes `bpf_map_mmap`, `ringbuf_map_mmap_kern`, and `remap_vmalloc_range`. `frozen` and `map_get_sys_perms` do not reject it and do not grant a write through this VMA.
- `attach` matches the Python reader's two mmaps. cfg/ctl stay `BPF_F_RDONLY` and are not mapped. No other read-only mmap.
- Test is a source lock and passed. Runbook audit checks the six bash pastes against the unit file and the SBOM. Section 2 and the tag match by hand.
- `release.sh` reproduced binary `e80253b2…` size 461264, SBOM `b7d0d247…`, unit `e3c8df9c…`. NEEDED and `GLIBC_2.34` unchanged. Slice 2b hashes match and were not in the diff.
- Tests: 42 passed. Clippy clean. Self-test `SELF-TEST-OK` with the session's counts.
