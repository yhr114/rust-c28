#!/usr/bin/env bash
# build.sh - Build the C28x backend skeleton against an LLVM source tree.
#
# Prerequisites:
#   - An LLVM source tree (https://github.com/llvm/llvm-project)
#   - CMake, Ninja
#
# Usage:
#   LLVM_SRC=/path/to/llvm-project ./build.sh
#
# This script:
#   1. Symlinks llvm-c28x/ into llvm/lib/Target/C28x
#   2. Runs CMake with C28x enabled
#   3. Builds llc
#   4. Runs the hello world test

set -e

LLVM_SRC=${LLVM_SRC:-$HOME/llvm-project}
BUILD_DIR=$LLVM_SRC/build-c28x

echo "==> Using LLVM source at $LLVM_SRC"

# 1. Symlink backend into LLVM tree
ln -sf "$(pwd)" "$LLVM_SRC/llvm/lib/Target/C28x"

# 2. Enable C28x in LLVM build
echo "==> Configuring LLVM"
cmake -G Ninja -B "$BUILD_DIR" \
  -S "$LLVM_SRC/llvm" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="C28x" \
  -DLLVM_ENABLE_PROJECTS="" \
  -DCMAKE_BUILD_TYPE=Debug

# 3. Build llc
echo "==> Building llc"
ninja -C "$BUILD_DIR" llc llvm-objdump

# 4. Run hello world test
echo "==> Running hello world test"
"$BUILD_DIR/bin/llc" -mtriple=c28x-ti-none -mcpu=c28x test/CodeGen/hello.ll -o -

echo "==> Done"
