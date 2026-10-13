#!/usr/bin/env python3
"""Update C28xCallingConv.td comments to reflect the custom C++ CC."""
path = r"D:\c28x-toolchain\llvm-project-23.1.1.src\llvm\lib\Target\C28x\C28xCallingConv.td"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

old_note = """// Full calling convention.
//
// The TI EABI uses a packed 16-bit slot model:
//   slot:   0     1     2      3
//   reg:    AL    AH    AR4    AR5
//   i32:   ACC (slots 0-1 only; second i32 goes on stack)
//
// i16 args consume one slot in order: AL, AH, AR4, AR5.
// i32 args consume ACC (slots 0-1).  There is NO second 32-bit register;
// the second 32-bit arg goes on the stack.
//
// NOTE: The independent CCIfType lists mean mixed (i16, i32) and (i32, i16)
// pairs may overlap on AL/ACC.  In practice Rust extern "C" functions use
// either all-i16 or all-i32 signatures; the common cases are correct."""

new_note = """// Full calling convention.
//
// The TI EABI uses a packed 16-bit slot model:
//   slot:   0     1     2      3
//   reg:    AL    AH    AR4    AR5
//   i32:   ACC (slots 0-1 only; second i32 goes on stack)
//
// i16 args consume one slot in order: AL, AH, AR4, AR5.
// i32 args consume ACC (slots 0-1).  There is NO second 32-bit register;
// the second 32-bit arg goes on the stack.
//
// MIXED-TYPE RULE (verified against cl2000 -v28 --abi=eabi disassembly):
//   Whenever the arg list contains ANY i32 argument, the first i32 takes ACC
//   and ALL i16 arguments skip AL/AH, starting at AR4.  This prevents a leading
//   i16 from stealing AL and overlapping ACC.  The generated CC_C28x below
//   cannot express this (independent CCIfType lists cause AL/AH overlap), so
//   the real argument lowering uses the C++ function CC_C28x_Custom in
//   C28xISelLowering.cpp.  This .td def is retained for reference and for
//   library-call fallbacks; it is NOT used by LowerCall/LowerFormalArguments."""

assert old_note in src, "old CC_C28x note not found"
src = src.replace(old_note, new_note, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("Updated C28xCallingConv.td comments")
