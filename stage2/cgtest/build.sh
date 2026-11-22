#!/usr/bin/env bash
# Unprivileged build script for Stage 2 S2-1 BPF LSM cgroup-scoping test.
# Generates vmlinux.h at build time from /sys/kernel/btf/vmlinux into the
# gitignored stage2/cgtest/build/ directory and compiles j_s2_cgtest.bpf.c.
# Never runs sudo; never loads, attaches, or pins any BPF program.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR="$SCRIPT_DIR/build"
VMLINUX_H="$BUILD_DIR/vmlinux.h"
SRC="$SCRIPT_DIR/j_s2_cgtest.bpf.c"
OBJ="$BUILD_DIR/j_s2_cgtest.bpf.o"

for tool in bpftool clang llvm-strip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "STOP-build-missing-tool tool=$tool"
    exit 1
  fi
done

if [ ! -r /sys/kernel/btf/vmlinux ] || [ ! -s /sys/kernel/btf/vmlinux ]; then
  echo "STOP-build-no-vmlinux-btf"
  exit 1
fi

mkdir -p "$BUILD_DIR"

# Generate vmlinux.h cleanly from the running kernel's BTF (never committed).
tmp_hdr=$(mktemp "$BUILD_DIR/vmlinux.h.XXXXXX")
trap 'rm -f "$tmp_hdr"' EXIT
bpftool btf dump file /sys/kernel/btf/vmlinux format c >"$tmp_hdr"
mv -f "$tmp_hdr" "$VMLINUX_H"
trap - EXIT

clang \
  -O2 \
  -g \
  -target bpf \
  -D__TARGET_ARCH_x86 \
  -isystem "$BUILD_DIR" \
  -Wall \
  -Wextra \
  -Werror \
  -c "$SRC" \
  -o "$OBJ"

# Strip DWARF debug sections while preserving .BTF and .BTF.ext for CO-RE.
llvm-strip -g "$OBJ"

sha=$(sha256sum "$OBJ" | awk '{print $1}')
echo "S2-CGTEST-BUILD-OK obj=$OBJ sha256=$sha"
