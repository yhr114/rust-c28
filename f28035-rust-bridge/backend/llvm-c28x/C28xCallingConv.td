//===-- C28xCallingConv.td - C28x Calling Convention ---------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// C28x C ABI (per TI cl2000 EABI, verified via disassembly):
//   - 16-bit argument #1 -> AL
//   - 16-bit argument #2 -> AH   (packed into ACC's high half)
//   - 16-bit argument #3 -> AR4  (caller-saved)
//   - 16-bit argument #4 -> AR5  (caller-saved)
//   - 32-bit argument #1 -> ACC  (AL=low, AH=high)
//   - 32-bit argument #2 -> stack (NOT XT!)
//   - pointer arguments (incl. function pointers) -> XAR4, XAR5, then stack
//   - hidden sret (struct return buffer) -> XAR6
//   - Return value 16-bit -> AL
//   - Return value 32-bit -> ACC
//   - Remaining args go on the stack.
//
// Verified against cl2000 -v28 --abi=eabi disassembly:
//   f2(short a, short b):   a->AL(reg0), b->AH(reg1)
//   f3args(a,b,c):          c->AR4(reg12)
//   fmany(a,b,c,d,e,f):     d->AR5(reg14), e/f->stack
//   f32(long a, long b):    a->ACC(reg0), b->stack(SP-6)
//   fmix(short a, long b):  b->ACC(reg0), a->AR4(reg12)
//   Pointer pool, verified 2026-10-20 with a 120-signature permutation
//   sweep (i16/i32/ptr, 1-4 args) plus targeted cases:
//   fptr(short *p, long v): p->XAR4, v->ACC
//   fpp(short *p, short *q): p->XAR4, q->XAR5, third pointer -> stack
//   fsret return: sret buffer -> XAR6 (MOVL XAR6,#sym ; LCR)
//   indirect call: MOVL XAR7,XAR4 ; LCR *XAR7
//   Mixed i16/i32: see CC_C28x_Custom in C28xISelLowering.cpp (the
//   independent CCIfType lists below cannot express it; they are retained
//   for reference / library-call fallbacks).
//
//===----------------------------------------------------------------------===//

// First 16-bit argument in AL.
def CC_C28x_16 : CallingConv<[
  CCIfType<[i16], CCAssignToReg<[AL]>>,
]>;

// First 32-bit argument in ACC.
def CC_C28x_32 : CallingConv<[
  CCIfType<[i32], CCAssignToReg<[ACC]>>,
]>;

// Stack fallback (for args that don't fit in registers).
def CC_C28x_Stack : CallingConv<[
  CCAssignToStack<2, 2>
]>;

// Full calling convention.
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
//   library-call fallbacks; it is NOT used by LowerCall/LowerFormalArguments.
def CC_C28x : CallingConv<[
  CCIfType<[i16], CCAssignToReg<[AL, AH, AR4, AR5]>>,
  CCIfType<[i32], CCAssignToReg<[ACC]>>,
  CCIfType<[i16], CCAssignToStack<2, 2>>,
  CCIfType<[i32], CCAssignToStack<4, 2>>
]>;

// Return value: 16-bit in AL, 32-bit in ACC, 64-bit in P:ACC.
// TI's convention for `long long` puts the LOW 32 bits in P and the HIGH 32
// bits in ACC (verified against cl2000: `MOVL P,ACC` for the low half followed
// by `MOVB ACC,#0` for the high half).  CCAssignToReg fills the register list
// from the least-significant part, so the order here is [P, ACC], not
// [ACC, P].  Without this rule an i64 return fails CheckReturn and silently
// degrades to an sret pointer, which is self-consistent inside Rust but
// incompatible with any TI C caller.
def RetCC_C28x : CallingConv<[
  CCIfType<[i16], CCAssignToReg<[AL]>>,
  CCIfType<[i32], CCAssignToReg<[ACC]>>,
  CCIfType<[i64], CCAssignToReg<[P, ACC]>>,
]>;

// C calling convention aliases (used by library calls).
def CC_C : CallingConv<[
  CCIfType<[i16], CCAssignToReg<[AL, AH, AR4, AR5]>>,
  CCIfType<[i32], CCAssignToReg<[ACC]>>,
  CCIfType<[i16], CCAssignToStack<2, 2>>,
  CCIfType<[i32], CCAssignToStack<4, 2>>
]>;

def RetCC_C : CallingConv<[
  CCIfType<[i16], CCAssignToReg<[AL]>>,
  CCIfType<[i32], CCAssignToReg<[ACC]>>,
]>;
