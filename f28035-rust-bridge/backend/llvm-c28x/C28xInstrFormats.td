//===-- C28xInstrFormats.td - C28x Instruction Formats -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// C28x instruction formats.  All C28x instructions are 16-bit or 32-bit words.
// We model three broad formats:
//
//   1. ALU/ACC register-immediate    :  ADD ACC, #123
//   2. Register-indirect memory       :  MOV *XAR4, AL
//   3. Direct (DP-relative) memory    :  MOV @0x1234, AL
//
//===----------------------------------------------------------------------===//

class C28xInst<dag outs, dag ins, string asmstr, list<dag> pattern>
  : Instruction {
  let Namespace = "C28x";
  let OutOperandList = outs;
  let InOperandList = ins;
  let AsmString = asmstr;
  let Pattern = pattern;
}

class C28xPseudo<dag outs, dag ins, list<dag> pattern = []>
  : C28xInst<outs, ins, "", pattern> {
  let isPseudo = 1;
  let isCodeGenOnly = 1;
}

//===----------------------------------------------------------------------===//
// Operand types
//===----------------------------------------------------------------------===//

// i16imm is already defined in Target.td

// i32 immediate operand (for ACC instructions that take a 16-bit or 8-bit imm
// but the immediate value itself is an i32 in the DAG).
def i32immop : Operand<i32>;

// 16-bit sign-extended immediate that lives in an i32 (ACC) instruction field.
def imm16s : ImmLeaf<i32, [{
  return isInt<16>(Imm) || isUInt<16>(Imm);
}]>;

// 22-bit address immediate (used by MOVL XARn, #addr)
def i22imm : Operand<i32>;

// Value predicate for i22imm.  MOVL XARn,#22bit encodes an unsigned 22-bit
// *word* address (SPRU430F "MOVL XARn,#22bit"), so anything wider must fail at
// ISel with the ordinary "Cannot select" diagnostic rather than being silently
// truncated by the encoder.  Kept in sync with the range check in
// C28xMCCodeEmitter.cpp's MOVL_XAR_imm case.
def imm22 : ImmLeaf<i32, [{ return isUInt<22>(Imm); }]>;

// Branch target (machine basic block reference, lowered to an MCSymbol).
def brtarget : Operand<OtherVT>;

// Conditional branch condition code (an ISD::CondCode integer).
def ccond : Operand<i8>;

// Memory operand via XARn (indirect)
def mem_ind : Operand<i16> {
  let EncoderMethod = "getMemEncoding";
}

// DP-relative direct memory
def mem_direct : Operand<i16> {
  let EncoderMethod = "getDirectMemEncoding";
}
