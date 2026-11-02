//===-- C28xRegisterInfo.td - C28x Register File  ------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// C28x core registers (per TMS320C28x CPU reference guide).
//
// 32-bit registers are split into two 16-bit halves:
//   ACC = AH:AL, XT = T:TL, P = PH:PL, XARn = ARnH:ARn.
//
//===----------------------------------------------------------------------===//

class C28xReg<string n> : Register<n> {
  let Namespace = "C28x";
}

class C28xRegWithSubregs<string n, list<Register> subregs>
    : RegisterWithSubRegs<n, subregs> {
  let Namespace = "C28x";
}

//===----------------------------------------------------------------------===//
// 16-bit registers
//===----------------------------------------------------------------------===//

def AL  : C28xReg<"al">,  DwarfRegNum<[0]>;
def AH  : C28xReg<"ah">,  DwarfRegNum<[1]>;
def PL  : C28xReg<"pl">,  DwarfRegNum<[2]>;   // P low (product low)
def PH  : C28xReg<"ph">,  DwarfRegNum<[3]>;   // P high
def TL  : C28xReg<"tl">,  DwarfRegNum<[36]>;   // XT low
def T   : C28xReg<"t">,   DwarfRegNum<[37]>;   // XT high
def AR0 : C28xReg<"ar0">, DwarfRegNum<[4]>;
def AR0H: C28xReg<"ar0h">, DwarfRegNum<[5]>;
def AR1 : C28xReg<"ar1">, DwarfRegNum<[6]>;
def AR1H: C28xReg<"ar1h">, DwarfRegNum<[7]>;
def AR2 : C28xReg<"ar2">, DwarfRegNum<[8]>;
def AR2H: C28xReg<"ar2h">, DwarfRegNum<[9]>;
def AR3 : C28xReg<"ar3">, DwarfRegNum<[10]>;
def AR3H: C28xReg<"ar3h">, DwarfRegNum<[11]>;
def AR4 : C28xReg<"ar4">, DwarfRegNum<[12]>;
def AR4H: C28xReg<"ar4h">, DwarfRegNum<[13]>;
def AR5 : C28xReg<"ar5">, DwarfRegNum<[14]>;
def AR5H: C28xReg<"ar5h">, DwarfRegNum<[15]>;
def AR6 : C28xReg<"ar6">, DwarfRegNum<[16]>;
def AR6H: C28xReg<"ar6h">, DwarfRegNum<[17]>;
def AR7 : C28xReg<"ar7">, DwarfRegNum<[18]>;
def AR7H: C28xReg<"ar7h">, DwarfRegNum<[19]>;

// Special purpose (not allocatable)
def SP  : C28xReg<"sp">, DwarfRegNum<[20]>;
def DP  : C28xReg<"dp">, DwarfRegNum<[21]>;
def ST0 : C28xReg<"st0">, DwarfRegNum<[22]>;
def ST1 : C28xReg<"st1">, DwarfRegNum<[23]>;

def sub_lo16 : SubRegIndex<16> { let Namespace = "C28x"; }
def sub_hi16 : SubRegIndex<16, 16> { let Namespace = "C28x"; }

//===----------------------------------------------------------------------===//
// 32-bit super-registers (placeholder; SubRegIndex TBD)
//===----------------------------------------------------------------------===//

let SubRegIndices = [sub_lo16, sub_hi16] in {
def ACC  : C28xRegWithSubregs<"acc",  [AL, AH]>, DwarfRegNum<[24]>;
def XT   : C28xRegWithSubregs<"xt",   [TL, T]>, DwarfRegNum<[25]>;
def P    : C28xRegWithSubregs<"p",    [PL, PH]>, DwarfRegNum<[38]>;
def XAR0 : C28xRegWithSubregs<"xar0", [AR0, AR0H]>, DwarfRegNum<[26]>;
def XAR1 : C28xRegWithSubregs<"xar1", [AR1, AR1H]>, DwarfRegNum<[27]>;
def XAR2 : C28xRegWithSubregs<"xar2", [AR2, AR2H]>, DwarfRegNum<[28]>;
def XAR3 : C28xRegWithSubregs<"xar3", [AR3, AR3H]>, DwarfRegNum<[29]>;
def XAR4 : C28xRegWithSubregs<"xar4", [AR4, AR4H]>, DwarfRegNum<[30]>;
def XAR5 : C28xRegWithSubregs<"xar5", [AR5, AR5H]>, DwarfRegNum<[31]>;
def XAR6 : C28xRegWithSubregs<"xar6", [AR6, AR6H]>, DwarfRegNum<[32]>;
def XAR7 : C28xRegWithSubregs<"xar7", [AR7, AR7H]>, DwarfRegNum<[33]>;
}

def PC  : C28xReg<"pc">,  DwarfRegNum<[34]>;
def RPC : C28xReg<"rpc">, DwarfRegNum<[35]>;

//===----------------------------------------------------------------------===//
// Register Classes
//===----------------------------------------------------------------------===//

// 16-bit general-purpose registers (allocatable).
def GR16 : RegisterClass<"C28x", [i16], 16,
  (add AL, AH, AR0, AR1, AR2, AR3, AR4, AR5, AR6, AR7, SP)>;

// Auxiliary registers only (AR0-AR7).  Used by "MOV T, ARn", which requires an
// AR source for the shift count.  AR7 is reserved as scratch but is included so
// post-RA expansions can stage a count into it.
def ARegs : RegisterClass<"C28x", [i16], 16,
  (add AR0, AR1, AR2, AR3, AR4, AR5, AR6, AR7)>;

// GR16 without AL.  Used as the compare RHS, which must never alias the
// fixed AL accumulator operand: the CMP expands to "mov al, lhs; cmp al, rhs",
// so an rhs allocated to AL would produce a self-compare "cmp al, al".
def GR16NoAL : RegisterClass<"C28x", [i16], 16,
  (add AH, AR0, AR1, AR2, AR3, AR4, AR5, AR6)>;

// The accumulator halves (AL/AH).  Every 16-bit ALU result must land here:
// SPRU430F only defines "op AX, loc16" (AX = AL or AH), there is no
// "op <any 16-bit reg>, <reg>" form.  Constraining the destination class lets
// the register allocator insert the required MOV copies instead of asking the
// emitter for an unencodable "add ar1, ar2".
def GR16ACC : RegisterClass<"C28x", [i16], 16, (add AL, AH)>;

// 22-bit address registers (used as pointers).
def GR32 : RegisterClass<"C28x", [i32], 32,
  (add XAR0, XAR1, XAR2, XAR3, XAR4, XAR5, XAR6, XAR7)>;

// ptr_rc is defined in Target.td as PointerLikeRegClass<0>;
// we override it below.

// 32-bit accumulator / product.
def ACC32 : RegisterClass<"C28x", [i32], 32, (add ACC, XT)>;
// MOV ACC,#imm has no XT destination form. Keep its result pinned to ACC;
// register allocation may copy it to XT with MOV_ACC_rr when needed.
def ACCOnly : RegisterClass<"C28x", [i32], 32, (add ACC)>;

// ACC32 without ACC. Used as the compare RHS: the CMP32 expansion saves ACC,
// loads LHS into ACC, then does SUBL ACC,rhs.  If rhs were ACC the subtraction
// would clobber the LHS just loaded (self-compare).  Pinning rhs to XT avoids
// that hazard.
def ACC32NoACC : RegisterClass<"C28x", [i32], 32, (add XT)>;

// Wide 32-bit class for non-pointer i32 values: data may live in ACC/XT or in
// Auxiliary registers XAR0-7 are also legal homes for long-lived i32 values.
// Arithmetic expansions still route their actual operation through ACC/XT;
// the post-RA inserter handles the required MOVL copies.  Including XAR here
// is important for expressions such as ptr + (index << 1), where the pointer,
// index, and hardware shift temporaries cannot all fit in ACC/XT.
def GPR32 : RegisterClass<"C28x", [i32], 32,
  (add ACC, XT, XAR0, XAR1, XAR2, XAR3, XAR4, XAR5, XAR6, XAR7)>;

// P as a 32-bit value.  Deliberately NOT part of GPR32: P is the product /
// scratch register used by every multiply and by several expansion sequences,
// so letting the allocator treat it as general-purpose would collide with those
// uses.  It exists only so the return convention can hand back the low half of
// an i64 in P, which is where the TI EABI puts it (see RetCC_C28x).
def PRC32 : RegisterClass<"C28x", [i32], 32, (add P)>;

// Remap ptr_rc (used by StandardPseudoInstruction) to GR32.
defm : RemapAllTargetPseudoPointerOperands<GR32>;

// TI EABI preserves the FULL XAR1/XAR2/XAR3, not AR4/AR5/AR6.
def CSR_C28x : CalleeSavedRegs<(add XAR1, XAR2, XAR3)>;
// Hardware does not save the extended auxiliary/XT register file. Include
// late-expansion scratch XAR7 and registers clobbered by ordinary callees.
def CSR_C28x_Interrupt : CalleeSavedRegs<(add XAR0, XAR1, XAR2, XAR3,
                                           XAR4, XAR5, XAR6, XAR7, XT)>;
