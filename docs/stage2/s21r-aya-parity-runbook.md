# Stage 2: S2-1R `aya =0.16.0` Loader Parity Test Runbook

Rev 1, 2026-11-27 America/Chicago. Status: **DRAFT — NOT YET REVIEWED, NOT RUN.**

Review gate (`AGENTS.md`): **Paste S2-1R-2 and Rollback require `sudo` and MUST be reviewed by the adversarial-reviewer (Claude Code Opus medium) before AJ runs them.** Nothing in this draft has loaded or attached any BPF program, run `sudo`, or touched Johnny (`192.168.50.152`).

---

## 1. Purpose, Parity Gate, and Scope

### Goal of S2-1R (AJ decision, 2026-11-24 Q4)
Re-run S2-1 Cases A–D on Rock Box kernel `7.3.0-10-generic` using an **`aya =0.16.0`** userspace loader instead of Python `ctypes` + `libbpf.so.1`, with the **same clang-built C BPF object** (`stage2/cgtest/build/j_s2_cgtest.bpf.o` built by the untouched `stage2/cgtest/build.sh` from `stage2/cgtest/j_s2_cgtest.bpf.c`).

Source record: [`docs/sessions/2026-11-24-stage2-decisions-q1-q4.md`](../sessions/2026-11-24-stage2-decisions-q1-q4.md) (Q1–Q4) and [`docs/sessions/2026-11-23-stage2-s21-applied.md`](../sessions/2026-11-23-stage2-s21-applied.md) (S2-1 applied baseline: `STAGE2-CGROUP-SCOPE-PASS mechanism=M1`).

### Parity Gate (Hard Gate — Do Not Soften)
- **If S2-1R parity fails, revisit `aya` vs `libbpf-rs`.**
- Full Q4 revisit triggers (`docs/sessions/2026-11-24-stage2-decisions-q1-q4.md` §1 Q4):
  1. **S2-1R parity fails**;
  2. **Kernel-verified signed BPF becomes required** (`libbpf` light skeletons; **UNVERIFIED**); or
  3. **A needed BPF attach type is missing in `aya 0.16.0`**.
- S2-1 baseline comparison: S2-1 on Rock Box (`7.3.0-10-generic`) had `VERIFIER-M1=accepted`, `VERIFIER-M2=accepted`, `ACTIVE_MECHANISM=M1`, Case A `observed_outside=1 denied_inside=0 denied_outside=0 cg_helper_err=0 rc=0`, Case B `denied_inside=1 rc=126`, Case C `denied_inside=2 rc=126`, Case D `PASS-case-d-clean-detach`. Full parity on Rock Box expects **`STAGE2-S21R-PARITY-PASS mechanism=M1`**. If M1 unexpectedly fails under `aya` while it passed under `libbpf` on the same kernel and BPF object, treat that as a loader discrepancy and revisit `aya` vs `libbpf-rs` before proceeding to S2-2 or Stage 2 agent design.

### AJ Q2 Policy Applied in `stage2/s21r/run_s2_1r.sh`
Unlike the frozen SHA-pinned `stage2/cgtest/run_s2_1.sh` (untouched), `stage2/s21r/run_s2_1r.sh` enforces AJ's 2026-11-24 Q2 verdict rules:
- **M1 selected** (`VERIFIER-M1=accepted`): full pass emits `STAGE2-CGROUP-SCOPE-PASS mechanism=M1` and `STAGE2-S21R-PARITY-PASS mechanism=M1` (exit `0`).
- **M2 + global observer** (`VERIFIER-M1=rejected`, `VERIFIER-M2=accepted`, `VERIFIER-M2-OBS=accepted`): full pass emits `STAGE2-CGROUP-SCOPE-PASS mechanism=M2 obs=yes` and `STAGE2-S21R-PARITY-PASS mechanism=M2 obs=yes` (exit `0`).
- **Bare M2 without observer** (`obs=no`): **still requires Case A safety checks** (`exec rc=0`, `denied_inside=0`, `denied_outside=0`, `m2_seen=0`) and runs Cases B–D to verify isolation and clean detach, then emits `STAGE2-CGROUP-SCOPE-PARTIAL mechanism=M2 obs=no` and `STAGE2-S21R-PARITY-FAIL case=case-a-m2-no-observer mechanism=M2 obs=no` with **non-zero exit (`1`)**.
- **Any failure** (preflight, setup, verifier/attach, Case A–D): emits the relevant `STOP-*` token, runs emergency cleanup + residual verification (`CLEANUP-ON-STOP-OK`), emits `STAGE2-S21R-PARITY-FAIL case=<failing-case>`, and exits non-zero (`1`).

---

## 2. `aya =0.16.0` Source Audit and `UNVERIFIED` Boundaries

### Source-Level Capability Check (Verified in Cargo Registry)
Inspected `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/aya-0.16.0/src/` and `aya-obj-0.6.0/src/`:

| Capability needed by `stage2/cgtest/loader.py` | `aya =0.16.0` / `aya-obj =0.6.0` API | Source location | Status |
|---|---|---|---|
| M1 global LSM (`SEC("lsm/bprm_check_security")`, `BPF_LSM_MAC`) | `aya::programs::Lsm` (`load`, `attach` via `bpf_raw_tracepoint_open(None, prog_fd)`, `take_link` -> `FdLink::pin`) | `aya-0.16.0/src/programs/lsm.rs`, `src/programs/utils.rs`, `src/programs/links.rs` | Present in source; **runtime UNVERIFIED** |
| M2 cgroup LSM (`SEC("lsm_cgroup/bprm_check_security")`, `BPF_LSM_CGROUP`) | `aya::programs::LsmCgroup` (`load`, `attach(&cg_file)` via `bpf_link_create(..., BPF_LSM_CGROUP, 0, None)`, `take_link` -> `FdLink::pin`) | `aya-0.16.0/src/programs/lsm_cgroup.rs`, `src/programs/links.rs` | Present in source; **runtime UNVERIFIED** |
| Global observer (`j_s2_cgtest_obs`, second function in `lsm/bprm_check_security`) | `aya_obj::Object::parse` keys each `SymbolKind::Text` by symbol name; `relocate_maps` slices by `section_offset..section_offset+size`; loads as `aya::programs::Lsm` | `aya-obj-0.6.0/src/obj.rs`, `src/relocation.rs`, `aya-0.16.0/src/bpf.rs` | ELF/BTF parse + CO-RE reloc verified unprivileged; **runtime UNVERIFIED** |
| `BPF_MAP_TYPE_CGROUP_ARRAY` (`j_s2_cgtest_cg`) | `aya::maps::CgroupArray` (`set(0, cg_fd, 0)`, `Map::pin`) | `aya-0.16.0/src/maps/array/cgroup_array.rs`, `src/maps/mod.rs` | Present in source; **runtime UNVERIFIED** |
| `BPF_MAP_TYPE_ARRAY` (`j_s2_cgtest_cfg`, `j_s2_cgtest_st`) | `aya::maps::Array`, `Map::pin`, `MapData::from_pin` | `aya-0.16.0/src/maps/array/array.rs`, `src/maps/mod.rs` | Present in source; **runtime UNVERIFIED** |

- **Revisit trigger 3 ("a needed attach type is missing in `aya 0.16.0`"):** **not hit** at source/compile level. Zero raw `SYS_bpf` workarounds are used in `stage2/s21r/`. If `Ebpf` ever returns an unexpected `Program` variant at runtime, `s21r-loader` emits `STOP-aya-missing-attach-type trigger=3 ...` explicitly.

### Known Differences vs `stage2/cgtest/loader.py` (`libbpf.so.1`)
1. **Verifier log on acceptance:** `aya 0.16.0`'s `retry_with_verifier_logs` (`aya-0.16.0/src/sys/bpf.rs:1626-1656`) only allocates a verifier log buffer after an initial `BPF_PROG_LOAD` error, and discards the log on `Ok(())`. On rejection, `s21r-loader` prints the real kernel verifier log tail (`VERIFIER-M1-LOG: ...`); on acceptance, it prints `VERIFIER-M1-LOG: <aya-0.16.0-omits-log-on-accept>` rather than bypassing `aya` with a raw syscall.
2. **Map autocreate during M2-only attach:** `EbpfLoader::load_file` creates all maps declared in the ELF object before individual program loads (no `bpf_map__set_autocreate(false)`). When M2 is active without M1, `s21r-loader` intentionally leaves `j_s2_cgtest_cg` unpinned so the kernel releases it when `Ebpf` drops (teardown **UNVERIFIED** until Paste S2-1R runs; Case D verifies zero residual maps via `bpftool map list -f`).

### Verified Unprivileged During Drafting vs Still `UNVERIFIED`
- **Verified unprivileged on Rock Box (zero `sudo`, zero `bpf()` syscalls):**
  - `cargo build --release --locked --offline` in `stage2/s21r`: succeeded (`888 KiB` stripped LTO binary linking only `libc.so.6` and `libgcc_s.so.1`, zero `libbpf.so.1`).
  - `cargo clippy --all-targets --locked --offline -- -D warnings`: 0 warnings.
  - `cargo test --locked --offline`: 9 passed, 0 failed.
  - `shellcheck stage2/s21r/run_s2_1r.sh`: 0 warnings (`SHELLCHECK-OK`).
  - `s21r-loader self-test --obj stage2/cgtest/build/j_s2_cgtest.bpf.o`: parsed all 3 programs and 3 maps via `aya-obj 0.6.0`, resolved `bpf_lsm_bprm_check_security` (`hook_btf_id=101319`) from `/sys/kernel/btf/vmlinux`, and completed userspace CO-RE relocation (`core_reloc=ok`, `S2-1R-LOADER-SELFTEST-OK`).
  - Unprivileged `s21r-loader exec-check --mode outside --forbidden-cgroup 0::/johnny-stage2-test --sentinel /bin/true`: printed `SELF_CGROUP` and exited `0`.
- **Still `UNVERIFIED` until AJ runs Paste S2-1R-2 on Rock Box (`7.3.0-10-generic`):**
  - Kernel `BPF_BTF_LOAD` and `BPF_MAP_CREATE` inside `aya::EbpfLoader::load_file`.
  - Kernel verifier acceptance of `j_s2_cgtest_m1`, `j_s2_cgtest_m2`, and `j_s2_cgtest_obs` via `aya` (`Lsm::load`, `LsmCgroup::load`).
  - `CgroupArray::set`, `Array::set`, `Map::pin`, `MapData::from_pin` (`read-stats`).
  - `Lsm::attach` + `FdLink::pin` (`BPF_LSM_MAC`) and `LsmCgroup::attach` + `FdLink::pin` (`BPF_LSM_CGROUP`).
  - Runtime isolation counters across Cases A–D (`observed_outside`, `denied_inside`, `denied_outside`, `cg_helper_err`, `m2_seen`, `obs_seen`) and clean kernel RCU teardown after `rm -rf /sys/fs/bpf/johnny_s2_cgtest`.

---

## 3. Pinned SHA-256 Checksums

All files below are verified in the paste blocks before build and before `sudo` execution. The four `stage2/cgtest/` files remain byte-identical to S2-1.

```text
4ebb76508e1841eceedc7638bbf70fa71dec172879217587aba605ca3a0592ea  stage2/cgtest/j_s2_cgtest.bpf.c
d033c78664d49b6a6824aa2975b1ae98c84cb69f5eebd34d187017bd680173f3  stage2/cgtest/build.sh
2d30df1ba7a6f15f30dd68550346dcc64f5983ab3ea4b3435ed22783bf452728  stage2/cgtest/loader.py
6953e1e0be278cf103bc95f59f2ff7bc3540319944fd729ab102bbcf7cd70acc  stage2/cgtest/run_s2_1.sh
86b94e414517ac8cd51edfd3b970eb2581f63d8757addec59b22f4ed7ac22e6a  stage2/s21r/Cargo.toml
4f8a9e502130a1b51c5d9da0f52fd1436aac31db42748c95ad06e6e96c03c842  stage2/s21r/Cargo.lock
d43539e21a12fe07bd005b7066d977bf718b0537f45601e4bd7ad6e0cbd8580e  stage2/s21r/src/main.rs
222f54d6d6876b208df238a813d353003e30359131694e85e4a7668d15fa4017  stage2/s21r/src/abi.rs
a7bdc81b5a3f453ac045fefd7e0e6b2191d8aa9cd31217ef5dfb7b44ed01756e  stage2/s21r/src/bpf_ops.rs
1dc6eae0da29c4d6dfd0efe9ae90c127aea9f062503564dc780a3519687d42b9  stage2/s21r/src/exec_check.rs
eaeeaa1bcc0f3ca22b1f4f89dad8f5f55fc526d61b4b27033137d6471da665c1  stage2/s21r/run_s2_1r.sh
```

> **Worktree path note:** The paste blocks below assume `/home/aj/Projects/strix-halo-johnny` after merge/checkout of the S2-1R commit. If running directly from a separate git worktree, adjust the `cd` directory before running.

---

## 4. Paste S2-1R-0: Read-Only Preflight (No Sudo, No Writes)

Verifies kernel version, `bpf` in `/sys/kernel/security/lsm`, `/sys/kernel/btf/vmlinux`, unified `cgroup2`, toolchain (`cargo`, `rustc`, `clang`, `bpftool`, `llvm-strip`), outer shell cgroup, and all pinned SHA-256 checksums. Makes zero changes.

***<u>Run on Rock Box</u>***

```bash
(
  set -eu
  export PATH="$HOME/.cargo/bin:$PATH"
  if [ ! -f /home/aj/Projects/strix-halo-johnny/stage2/s21r/run_s2_1r.sh ]; then
    echo "STOP-missing-stage2-s21r-files root=/home/aj/Projects/strix-halo-johnny"
    exit 1
  fi
  cd /home/aj/Projects/strix-halo-johnny
  echo "== kernel & LSM & BTF & cgroup2"
  echo "KERNEL $(uname -r)"
  lsm_list=$(cat /sys/kernel/security/lsm)
  echo "LSM_LIST $lsm_list"
  case ",$lsm_list," in
    *,bpf,*) echo "PASS-preflight-lsm-bpf" ;;
    *) echo "STOP-preflight-no-bpf-lsm"; exit 1 ;;
  esac
  if [ ! -r /sys/kernel/btf/vmlinux ] || [ ! -s /sys/kernel/btf/vmlinux ]; then
    echo "STOP-preflight-no-btf"
    exit 1
  fi
  echo "PASS-preflight-btf bytes=$(stat -c '%s' /sys/kernel/btf/vmlinux)"
  cg_fstype=$(findmnt -no FSTYPE --target /sys/fs/cgroup 2>/dev/null || echo unknown)
  if [ "$cg_fstype" != "cgroup2" ]; then
    echo "STOP-preflight-not-cgroup2 fstype=$cg_fstype"
    exit 1
  fi
  echo "PASS-preflight-cgroup2"
  shell_cg=$(cat /proc/self/cgroup)
  echo "SHELL_CGROUP $shell_cg"
  case "$shell_cg" in
    "0::/johnny-stage2-test"|"0::/johnny-stage2-test/"*)
      echo "STOP-preflight-shell-in-test-cgroup cgroup=$shell_cg"
      exit 1
      ;;
  esac
  echo "== toolchain"
  for tool in cargo rustc clang bpftool llvm-strip python3; do
    p=$(command -v "$tool" 2>/dev/null || true)
    if [ -z "$p" ]; then
      echo "STOP-preflight-missing-tool tool=$tool"
      exit 1
    fi
    echo "TOOL $tool=$p"
  done
  rustc --version
  cargo --version
  echo "== sha256 pin check"
  echo "4ebb76508e1841eceedc7638bbf70fa71dec172879217587aba605ca3a0592ea  stage2/cgtest/j_s2_cgtest.bpf.c
d033c78664d49b6a6824aa2975b1ae98c84cb69f5eebd34d187017bd680173f3  stage2/cgtest/build.sh
2d30df1ba7a6f15f30dd68550346dcc64f5983ab3ea4b3435ed22783bf452728  stage2/cgtest/loader.py
6953e1e0be278cf103bc95f59f2ff7bc3540319944fd729ab102bbcf7cd70acc  stage2/cgtest/run_s2_1.sh
86b94e414517ac8cd51edfd3b970eb2581f63d8757addec59b22f4ed7ac22e6a  stage2/s21r/Cargo.toml
4f8a9e502130a1b51c5d9da0f52fd1436aac31db42748c95ad06e6e96c03c842  stage2/s21r/Cargo.lock
d43539e21a12fe07bd005b7066d977bf718b0537f45601e4bd7ad6e0cbd8580e  stage2/s21r/src/main.rs
222f54d6d6876b208df238a813d353003e30359131694e85e4a7668d15fa4017  stage2/s21r/src/abi.rs
a7bdc81b5a3f453ac045fefd7e0e6b2191d8aa9cd31217ef5dfb7b44ed01756e  stage2/s21r/src/bpf_ops.rs
1dc6eae0da29c4d6dfd0efe9ae90c127aea9f062503564dc780a3519687d42b9  stage2/s21r/src/exec_check.rs
eaeeaa1bcc0f3ca22b1f4f89dad8f5f55fc526d61b4b27033137d6471da665c1  stage2/s21r/run_s2_1r.sh" | sha256sum -c -
  echo "STAGE2-S21R-PREFLIGHT-DONE"
)
```

### Expect (Paste S2-1R-0)
- `KERNEL 7.3.0-10-generic`, `PASS-preflight-lsm-bpf`, `PASS-preflight-btf`, `PASS-preflight-cgroup2`, all 6 `TOOL` lines, 11 `OK` SHA-256 lines, and final token **`STAGE2-S21R-PREFLIGHT-DONE`**.

---

## 5. Paste S2-1R-1: Unprivileged Build & Self-Test (No Sudo, Zero `bpf()` Syscalls)

Compiles `stage2/cgtest/build/j_s2_cgtest.bpf.o` using the untouched `stage2/cgtest/build.sh`, builds `stage2/s21r/target/release/s21r-loader` with `--locked --offline`, verifies `s21r-loader` does not link `libbpf.so.1`, runs unit tests, and runs `s21r-loader self-test --obj stage2/cgtest/build/j_s2_cgtest.bpf.o` (userspace ELF + BTF + CO-RE relocation only).

***<u>Run on Rock Box</u>***

```bash
(
  set -eu
  export PATH="$HOME/.cargo/bin:$PATH"
  cd /home/aj/Projects/strix-halo-johnny
  echo "== build C BPF object (untouched stage2/cgtest/build.sh)"
  bash stage2/cgtest/build.sh
  echo "== build standalone aya =0.16.0 loader"
  (cd stage2/s21r && cargo build --release --locked --offline)
  echo "== verify no libbpf dynamic dependency"
  needed=$(readelf -d stage2/s21r/target/release/s21r-loader | grep NEEDED || true)
  printf '%s\n' "$needed"
  if printf '%s\n' "$needed" | grep -qi libbpf; then
    echo "STOP-build-unexpected-libbpf-dep"
    exit 1
  fi
  echo "== run Rust unit tests"
  (cd stage2/s21r && cargo test --locked --offline)
  echo "== run unprivileged s21r-loader self-test"
  stage2/s21r/target/release/s21r-loader self-test --obj stage2/cgtest/build/j_s2_cgtest.bpf.o
  echo "STAGE2-S21R-BUILD-SELFTEST-DONE"
)
```

### Expect (Paste S2-1R-1)
- `S2-CGTEST-BUILD-OK ...`
- `Finished release profile ...`, `NEEDED` showing only `libc.so.6` and `libgcc_s.so.1`
- `test result: ok. 9 passed; 0 failed`
- `AYA_CAPABILITIES version=0.16.0 lsm=present lsm_cgroup=present cgroup_array=present`
- `SELFTEST_OBJ_OK obj=stage2/cgtest/build/j_s2_cgtest.bpf.o hook=bpf_lsm_bprm_check_security hook_btf_id=... core_reloc=ok`
- `S2-1R-LOADER-SELFTEST-OK` and final token **`STAGE2-S21R-BUILD-SELFTEST-DONE`**.

---

## 6. Paste S2-1R-2: Privileged `aya` Parity Test (Requires Sudo; Review Gate Before Running)

Re-verifies the SHA-256 of `stage2/s21r/run_s2_1r.sh` and the `stage2/cgtest/` build inputs, confirms both `stage2/cgtest/build/j_s2_cgtest.bpf.o` and `stage2/s21r/target/release/s21r-loader` exist, then executes `bash stage2/s21r/run_s2_1r.sh` (preflight residual scan, setup, M1 + M2 verifier probes, attach, Cases A–D, and clean detach with residual verification).

***<u>Run on Rock Box</u>***

```bash
sudo -v &&
(
  set -eu
  cd /home/aj/Projects/strix-halo-johnny
  echo "4ebb76508e1841eceedc7638bbf70fa71dec172879217587aba605ca3a0592ea  stage2/cgtest/j_s2_cgtest.bpf.c
d033c78664d49b6a6824aa2975b1ae98c84cb69f5eebd34d187017bd680173f3  stage2/cgtest/build.sh
eaeeaa1bcc0f3ca22b1f4f89dad8f5f55fc526d61b4b27033137d6471da665c1  stage2/s21r/run_s2_1r.sh" | sha256sum -c -
  if [ ! -f stage2/cgtest/build/j_s2_cgtest.bpf.o ]; then
    echo "STOP-missing-bpf-obj run-paste-s2-1r-1-first"
    exit 1
  fi
  if [ ! -x stage2/s21r/target/release/s21r-loader ]; then
    echo "STOP-missing-s21r-loader run-paste-s2-1r-1-first"
    exit 1
  fi
  bash stage2/s21r/run_s2_1r.sh
)
```

### Expect (Paste S2-1R-2)
- Three `OK` SHA-256 lines.
- `VERIFIER-M1=accepted` and `VERIFIER-M2=accepted` (with `<aya-0.16.0-omits-log-on-accept>` on acceptance, or real verifier log tail on rejection).
- `ACTIVE_MECHANISM=M1`, `ATTACH-DONE mechanism=M1 obs=na ...`, `SELECTED mechanism=M1 obs=na`.
- `CASE_A_STATS observed_outside=1 denied_inside=0 denied_outside=0 cg_helper_err=0 ... m2_seen=0 obs_seen=0 rc=0` and `PASS-case-a-observe-outside mechanism=M1 ...`.
- `CASE_B_STATS ... denied_inside=1 ... rc=126` and `PASS-case-b-deny-inside mechanism=M1 denied_inside=1`.
- `CASE_C_STATS ... denied_inside=2 ... rc=126` and `PASS-case-c-deny-subtree mechanism=M1 denied_inside=2`.
- `POST_DETACH_SENTINEL_OK`, `PASS-case-d-clean-detach`.
- Final tokens on full parity:
  - **`STAGE2-CGROUP-SCOPE-PASS mechanism=M1`**
  - **`STAGE2-S21R-PARITY-PASS mechanism=M1`**
- On bare M2 (`obs=no`): `STAGE2-CGROUP-SCOPE-PARTIAL mechanism=M2 obs=no` + `STAGE2-S21R-PARITY-FAIL case=case-a-m2-no-observer mechanism=M2 obs=no` (non-zero exit).
- On any failure: `STOP-*`, `CLEANUP-ON-STOP-OK`, and `STAGE2-S21R-PARITY-FAIL case=<failing-case>`. Per AJ's Q4 parity gate, any `STAGE2-S21R-PARITY-FAIL` triggers revisiting `aya` vs `libbpf-rs`.

---

## 7. Cleanup / Rollback (not part of the paste sequence above)

`run_s2_1r.sh` detaches and verifies zero residuals automatically in Case D and via its `EXIT` trap on any `STOP-*`. If Paste S2-1R-2 is interrupted before its `EXIT` trap finishes (e.g. terminal killed or `SIGKILL`), run this standalone idempotent cleanup/rollback block. It removes `/sys/fs/bpf/johnny_s2_cgtest` (detaching any pinned links/programs), removes the test cgroups and `/run/johnny-s2-cgtest.*`, and verifies zero residual BPF programs, links, maps, pins, cgroups, or sentinel directories within a bounded 3-second kernel RCU settle window. It never kills processes.

***<u>Run on Rock Box</u>***

```bash
sudo -v &&
(
  set -eu
  sudo rm -rf /sys/fs/bpf/johnny_s2_cgtest || true
  if [ -d /sys/fs/cgroup/johnny-stage2-test/nested-child ]; then
    sudo rmdir /sys/fs/cgroup/johnny-stage2-test/nested-child || true
  fi
  if [ -d /sys/fs/cgroup/johnny-stage2-test ]; then
    sudo rmdir /sys/fs/cgroup/johnny-stage2-test || true
  fi
  for d in /run/johnny-s2-cgtest.*; do
    if [ -e "$d" ]; then
      sudo rm -rf -- "$d" || true
    fi
  done
  python3 -I - <<'PY'
import glob, os, subprocess, sys, time

def scan():
    bad = []
    try:
        p_pin = subprocess.run(
            ["sudo", "test", "-e", "/sys/fs/bpf/johnny_s2_cgtest"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except OSError as exc:
        bad.append(f"pin-check-oserror={exc.errno}")
    else:
        if p_pin.returncode == 0:
            bad.append("pin-dir-exists")
        elif p_pin.returncode != 1 or p_pin.stderr.strip():
            bad.append(f"pin-check-rc={p_pin.returncode}")
    if os.path.exists("/sys/fs/cgroup/johnny-stage2-test/nested-child"):
        bad.append("cgroup-nested-exists")
    if os.path.exists("/sys/fs/cgroup/johnny-stage2-test"):
        bad.append("cgroup-root-exists")
    if glob.glob("/run/johnny-s2-cgtest.*"):
        bad.append("sentinel-dir-exists")

    checks = (
        ("prog", ["sudo", "bpftool", "prog", "list"], ("j_s2_cgtest",)),
        ("link", ["sudo", "bpftool", "link", "list", "-f"], ("johnny_s2_cgtest",)),
        ("map", ["sudo", "bpftool", "map", "list", "-f"], ("johnny_s2_cgtest", "j_s2_cgtest")),
    )
    for subcmd, cmd, needles in checks:
        try:
            p = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        except FileNotFoundError:
            bad.append(f"bpftool-{subcmd}-missing")
            continue
        except OSError as exc:
            bad.append(f"bpftool-{subcmd}-oserror={exc.errno}")
            continue
        if p.returncode != 0:
            bad.append(f"bpftool-{subcmd}-rc={p.returncode}")
        else:
            for needle in needles:
                if needle in p.stdout:
                    bad.append(f"residual-{subcmd}-{needle}")
    return bad

deadline = None
while True:
    bad = scan()
    if not bad:
        print("STAGE2-S21R-ROLLBACK-DONE")
        sys.exit(0)
    if deadline is None:
        deadline = time.monotonic() + 3.0
    only_rcu = all(
        item.startswith("residual-prog-")
        or item.startswith("residual-link-")
        or item.startswith("residual-map-")
        for item in bad
    )
    if only_rcu and time.monotonic() < deadline:
        time.sleep(0.2)
        continue
    print("STOP-rollback-residual " + ",".join(bad))
    sys.exit(1)
PY
)
```

---

## 8. What Evidence to Paste Back

After running Pastes S2-1R-0, S2-1R-1, and S2-1R-2 (and Rollback if ever needed), paste the full terminal output back, ensuring it includes:
1. All `sha256sum -c` `OK` lines and `STAGE2-S21R-PREFLIGHT-DONE`.
2. `S2-CGTEST-BUILD-OK`, `readelf -d` `NEEDED` lines, unit test summary, `SELFTEST_OBJ_OK`, `S2-1R-LOADER-SELFTEST-OK`, and `STAGE2-S21R-BUILD-SELFTEST-DONE`.
3. Full `run_s2_1r.sh` output: `TARGET`, `VERIFIER-M1` / `VERIFIER-M2` (and `VERIFIER-M2-OBS` if M2 fell back), `ACTIVE_MECHANISM`, `ATTACH-DONE`, `CASE_A_STATS`, `CASE_B_STATS`, `CASE_C_STATS`, `PASS-case-*` (or any `STOP-*` / `CLEANUP-ON-STOP-OK`), `STAGE2-CGROUP-SCOPE-PASS` / `PARTIAL`, and final **`STAGE2-S21R-PARITY-PASS`** or **`STAGE2-S21R-PARITY-FAIL`**.

---

## 9. Open Questions for AJ

> These are open questions for AJ to decide — not architecture decisions. AJ decides architecture.

1. **Standalone crate vs future workspace member:** `stage2/s21r/` is kept as a standalone crate (its own `Cargo.toml` and `Cargo.lock`) so `crates/` and `crates/johnny-daemon` remain completely untouched during feasibility testing. Once Stage 2 moves into agent implementation (after S2-1R and S2-2), should Stage 2 crates join the `crates/` workspace (sharing `crates/Cargo.lock` and `johnny-record-v1`) or live in a separate workspace?
2. **Lifecycle of `stage2/s21r/` after S2-1R closes:** After S2-1R records a PASS or FAIL closeout, should `stage2/s21r/` stay in-tree as a frozen feasibility test (like `stage2/cgtest/`) or be retired once the Stage 2 agent crate exists?
3. **S2-2 (`socket_connect`) loader structure:** If S2-1R passes, should S2-2 follow this same standalone `aya =0.16.0` loader crate pattern under `stage2/s22/` (keeping `crates/` untouched until agent design locks), or share a small test-helper library crate with `stage2/s21r/`?
4. **Verifier log on acceptance:** `aya =0.16.0` returns the kernel verifier log only when `BPF_PROG_LOAD` fails (not on acceptance). Is rejection-only verifier logging acceptable for Stage 2's production agent and S2-2, or do you want instruction/state stats logged on acceptance too?
