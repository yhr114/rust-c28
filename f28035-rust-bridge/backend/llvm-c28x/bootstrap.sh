#!/usr/bin/env bash
# bootstrap.sh — Clone LLVM, configure C28x, build llc, and run the smoke test.
#
# Usage:
#   ./bootstrap.sh
#
# This will:
#   1. Clone LLVM source tree (shallow)
#   2. Symlink our C28x backend into llvm/lib/Target/C28x
#   3. Configure C28x as an experimental target
#   4. Build llc (CMake runs TableGen into the build directory)
#   5. Run hello.ll through llc

set -e

HERE="$(pwd)"
LLVM_DIR="${LLVM_DIR:-$HOME/llvm-project}"
BUILD_DIR="$LLVM_DIR/build"

echo "==> [1/5] Cloning LLVM source tree (shallow)"
if [ ! -d "$LLVM_DIR" ]; then
    git clone --depth=1 https://github.com/llvm/llvm-project.git "$LLVM_DIR"
else
    echo "    Already exists: $LLVM_DIR"
fi

echo "==> [2/5] Symlink C28x backend into LLVM tree"
ln -sf "$HERE" "$LLVM_DIR/llvm/lib/Target/C28x"

if ! grep -q 'c28x' "$LLVM_DIR/llvm/include/llvm/TargetParser/Triple.h"; then
    echo "ERROR: LLVM Triple::c28x is not installed."
    echo "See llvm-patches/README.md before configuring."
    exit 1
fi

echo "==> [3/5] Configuring LLVM (C28x + X86 host)"
cmake -G Ninja -B "$BUILD_DIR" \
    -S "$LLVM_DIR/llvm" \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="C28x" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS="" \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF

echo "==> [4/5] Building llc"
ninja -C "$BUILD_DIR" llc llvm-objdump

echo "==> [5/5] Running hello.ll"
"$BUILD_DIR/bin/llc" -mtriple=c28x-ti-none -mcpu=c28x \
    "$HERE/test/CodeGen/hello.ll" -o -
