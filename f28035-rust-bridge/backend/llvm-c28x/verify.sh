#!/usr/bin/env bash
# verify.sh — C28x backend MC-layer verification (Linux/WSL bootstrap flow).
#
# Checks (contract L1-2, ABI_FREEZE.md):
#   1. llc / llvm-objdump exist and llc lists the c28x target.
#   2. hello.ll compiles to TI-compatible asm containing add + lretr.
#   3. const3.ll   -> .text bytes 68 03 7b 00  (MOV_AL_imm 3; LRETR)
#   4. const255.ll -> .text bytes 68 ff 7b 00  (imm8 boundary)
#   5. hello.ll with -filetype=obj must FAIL with "no verified encoding"
#      (ADD16rr is not in the verified set; never emit unverified bytes).
#
# Usage:  LLVM_BUILD_DIR=... ./verify.sh   (default: $HOME/llvm-project/build)
set -euo pipefail

BUILD="${LLVM_BUILD_DIR:-$HOME/llvm-project/build}"
LLC="$BUILD/bin/llc"
OBJDUMP="$BUILD/bin/llvm-objdump"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEGEN="$HERE/test/CodeGen"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  OK: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

echo "==> [1/6] Checking tools"
[ -x "$LLC" ]     || fail "llc not found at $LLC"
[ -x "$OBJDUMP" ] || fail "llvm-objdump not found at $OBJDUMP"
if ! "$LLC" --version | grep -qi c28x; then
  echo "  WARN: llc --version does not list c28x (may still work)"
else
  pass "llc lists c28x"
fi

echo "==> [2/6] hello.ll -> asm (add + lretr)"
"$LLC" -mtriple=c28x-ti-none -mcpu=c28x "$CODEGEN/hello.ll" -o "$TMP/hello.s"
grep -qi 'add' "$TMP/hello.s"   || fail "hello.s missing add"
grep -qi 'lretr' "$TMP/hello.s" || fail "hello.s missing lretr"
pass "hello.ll asm OK"

echo "==> [3/6] const3.ll -> object bytes 68037b00"
"$LLC" -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj "$CODEGEN/const3.ll" -o "$TMP/const3.o"
HEX=$("$OBJDUMP" -s -j .text "$TMP/const3.o" | tr -d ' \n' )
case "$HEX" in
  *68037b00*) pass "const3 bytes OK (68037b00)" ;;
  *) fail "const3 .text bytes unexpected: $HEX" ;;
esac

echo "==> [4/6] const255.ll -> object bytes 68ff7b00"
"$LLC" -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj "$CODEGEN/const255.ll" -o "$TMP/const255.o"
HEX=$("$OBJDUMP" -s -j .text "$TMP/const255.o" | tr -d ' \n' )
case "$HEX" in
  *68ff7b00*) pass "const255 bytes OK (68ff7b00)" ;;
  *) fail "const255 .text bytes unexpected: $HEX" ;;
esac

echo "==> [5/6] negative: hello.ll -filetype=obj must refuse ADD16rr"
if "$LLC" -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj "$CODEGEN/hello.ll" -o "$TMP/hello.o" 2>"$TMP/hello.err"; then
  fail "hello.ll object emission unexpectedly succeeded"
fi
grep -qi 'no verified encoding' "$TMP/hello.err" || fail "negative error message missing: $(cat "$TMP/hello.err")"
pass "unverified instruction refused"

echo "==> [6/6] MC layer self-check complete"
