//===-- C28xInstrInfo.td - C28x Instruction Definitions ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// MOV family
//===----------------------------------------------------------------------===//

def C28xretglue : SDNode<"C28xISD::RET_GLUE", SDTNone,
                          [SDNPHasChain, SDNPOptInGlue, SDNPVariadic]>;

// Compare: (chain, lhs, rhs) with out-glue carrying flags.
def SDT_C28xCmp : SDTypeProfile<0, 2, [SDTCisSameAs<0, 1>]>;
def C28xcmp : SDNode<"C28xISD::CMP", SDT_C28xCmp,
                     [SDNPOutGlue]>;

// Conditional branch: (chain, dst, cond, glue).
def SDT_C28xBrcond : SDTypeProfile<0, 2,
                                   [SDTCisVT<0, OtherVT>,
                                    SDTCisVT<1, i16>]>;
def C28xbrcond : SDNode<"C28xISD::BRCOND", SDT_C28xBrcond,
                        [SDNPHasChain, SDNPInGlue]>;

// Select based on flags: (i16 true, i16 false, i16 cond, glue) -> i16.
def SDT_C28xSelectCC : SDTypeProfile<1, 3,
  [SDTCisVT<0, i16>, SDTCisSameAs<1, 0>, SDTCisSameAs<2, 0>, SDTCisVT<3, i16>]>;
def C28xselectcc : SDNode<"C28xISD::SELECT_CC", SDT_C28xSelectCC,
                          [SDNPInGlue]>;

// Direct call: (chain, callee, glue).
def SDT_C28xCall : SDTypeProfile<0, -1, [SDTCisVT<0, iPTR>]>;
def C28xcall : SDNode<"C28xISD::CALL", SDT_C28xCall,
                      [SDNPHasChain, SDNPOutGlue, SDNPOptInGlue, SDNPVariadic]>;
def SDT_C28xWrapper : SDTypeProfile<1, 1,
  [SDTCisSameAs<0, 1>, SDTCisPtrTy<0>]>;
def C28xWrapper : SDNode<"C28xISD::WRAPPER", SDT_C28xWrapper>;

// Stack-relative store: (chain, i16 value, i16 word-offset) -> chain.
// Expanded post-RA to MOVZ XAR7,SP + ADDB + MOV *XAR7.
def SDT_C28xStoreStk : SDTypeProfile<1, 3,
  [SDTCisVT<0, OtherVT>, SDTCisVT<1, i16>, SDTCisVT<2, i16>, SDTCisVT<3, i16>]>;
def C28xstorestk : SDNode<"C28xISD::STORE_STK16", SDT_C28xStoreStk,
                          [SDNPHasChain, SDNPMayStore]>;

let isCodeGenOnly = 1, Defs = [SP], Uses = [SP] in {
def ADJCALLSTACKDOWN : C28xPseudo<(outs),
                                  (ins i32imm:$amt1, i32imm:$amt2)>;
def ADJCALLSTACKUP : C28xPseudo<(outs),
                                (ins i32imm:$amt1, i32imm:$amt2)>;
}

// Pseudo: store i16 to SP + word_off*2.  Expanded post-RA.
def STORE_STK16 : C28xPseudo<(outs), (ins i16imm:$off, GR16:$src)> {
  let mayStore = 1;
  let hasCtrlDep = 1;
}

// Pseudo: trap / abort.  C28x has no hardware trap/halt instruction, so this is
// expanded post-RA to an infinite self-loop (`b ., unc`).  Used by the panic
// abort path (core::process::abort_immediate -> llvm.trap).
def TRAP : C28xPseudo<(outs), (ins)> {
  let hasSideEffects = 1;
}
def : Pat<(trap), (TRAP)>;

def MOV16rr : C28xInst<(outs GR16:$dst), (ins GR16:$src),
  "mov $dst, $src", []>;

def MOV32rr : C28xInst<(outs GR32:$dst), (ins GR32:$src),
  "movl $dst, $src", []>;

// Zero-extend loc16 to the full XAR destination with MOVZ, not MOVL.
// The printer spells the destination ARn; the MI defines the entire XARn.
def MOVL_XAR_AR : C28xInst<(outs GR32:$dst), (ins GR16:$src),
  "movz $dst, $src", [(set GR32:$dst, (i32 (zext GR16:$src)))]>;

def MOV_ACC_rr : C28xInst<(outs ACC32:$dst), (ins ACC32:$src),
  "movl $dst, $src", []>;

// Constant materialisation. The destination may be any 16-bit general-purpose
// register; the assembler picks one of three verified encodings (see
// C28xMCCodeEmitter.cpp):
//   MOVB AX,#8bit    = 1001 101A CCCC CCCC            (AX = AL/AH, 0..255)
//   MOV loc16,#0     = 0010 1011 LLLL LLLL
//   MOV loc16,#16bit = 0010 1000 LLLL LLLL + literal word
// Keeping the destination a plain GR16 (rather than forcing AL/AH) matters:
// pinning constants to the accumulator starved the register allocator and
// made it spill live loop values to the stack.
def MOV16_imm : C28xInst<(outs GR16:$dst), (ins i16imm:$src),
  "mov $dst, #$src",
  [(set GR16:$dst, imm:$src)]>;

def MOV_ACC_imm : C28xInst<(outs ACCOnly:$dst), (ins i32immop:$src),
  "mov acc, #$src",
  []>;

def : Pat<(i32 imm16s:$src), (MOV_ACC_imm imm16s:$src)>;

def MOV_ind_store : C28xInst<(outs), (ins GR32:$ptr, GR16:$src),
  "mov *$ptr, $src",
  []>;

def MOV_ind_load : C28xInst<(outs GR16:$dst), (ins GR32:$ptr),
  "mov $dst, *$ptr",
  []>;

// 32-bit indirect load: MOVL ACC, *XARn = 0x06xx
def MOVL_ACC_ind_load : C28xInst<(outs ACC32:$dst), (ins GR32:$ptr),
  "movl $dst, *$ptr",
  []>;

// 32-bit indirect store: two 16-bit stores (AL then AH).
// These are emitted by the post-RA expander, not directly by the DAG.
def MOV_ind_store_AL : C28xInst<(outs), (ins GR32:$ptr),
  "mov *$ptr, al", []> { let Uses = [AL]; }
def MOV_ind_store_AH : C28xInst<(outs), (ins GR32:$ptr),
  "mov *$ptr, ah", []> { let Uses = [AH]; }

// 8-bit byte access: MOVB AL,*XARn = 0xC6xx, MOVB *XARn,AL = 0x3Cxx.
// C28x hardware uses byte addressing: XARn holds byte address, LSB selects
// low/high byte within the 16-bit word. Only one byte is touched, so adjacent
// data is preserved.
def MOVB_ind_load_AL : C28xInst<(outs GR16:$dst), (ins GR32:$ptr),
  "movb $dst, *$ptr", []>;
def MOVB_ind_store_AL : C28xInst<(outs), (ins GR32:$ptr),
  "movb *$ptr, al", []> { let Uses = [AL]; }

// Materialize a 32-bit logical byte address (FROZEN ABI, see ABI_FREEZE.md).
// The 16-bit MOV16ga global patterns were removed: they could only express
// 64Ki logical bytes (32K words), smaller than the F28035's 128Ki flash.
def MOV16ga : C28xInst<(outs GR16:$dst), (ins i16imm:$ga),
  "mov $dst, $ga", []>;

// MOVL XARn, #22bit — bare constants only (MMIO byte addresses).  Global
// symbols go through MOVL_XAR_ga so they emerge as logical byte addresses.
def MOVL_XAR_imm : C28xInst<(outs GR32:$dst), (ins i22imm:$src),
  "movl $dst, #$src",
  []>;

// Pseudo: materialise a global/external symbol as a logical byte address
// (ABI L1-1: byte_addr = word_addr * 2).  Expands post-RA to:
//   MOVL XARn, #word_addr   (22-bit word address from linker)
//   MOVL ACC, XARn          ; ACC = word_addr
//   ADD  ACC, ACC           ; ACC <<= 1  (byte address)
//   MOVL XARn, ACC
def MOVL_XAR_ga : C28xPseudo<(outs GR32:$dst), (ins i22imm:$ga),
  [(set GR32:$dst, (C28xWrapper tglobaladdr:$ga))]>;
def : Pat<(i32 (texternalsym:$ga)), (MOVL_XAR_ga texternalsym:$ga)>;

// A *bare* 32-bit constant used as an address — MMIO registers, i.e. the
// inttoptr(i32 N) form.  Same instruction as the symbol case above, but the
// value is self-contained so no relocation is involved.
//
// Without this pattern any literal address fails with
//   LLVM ERROR: Cannot select: t1: i32 = Constant<4160>
// because i32's register class is ACC32 and nothing could produce an i32 in the
// GR32 (XARn) class that the load/store address operand demands.
//
// imm22 (not imm) so a value too wide for MOVL XARn,#22bit is rejected here
// rather than reaching the encoder.
let AddedComplexity = 10 in
def : Pat<(i32 imm22:$src), (MOVL_XAR_imm imm22:$src)>;

// Arbitrary 32-bit constant core: build it in physical ACC from two 16-bit
// immediates (MOV AL,#lo; MOV AH,#hi).  Allocated to ACC only.
def MOV32_imm32_CORE : C28xPseudo<(outs ACCOnly:$dst), (ins i32imm:$val), []>;

// Wide arbitrary 32-bit constant: dst in GPR32.  Pre-RA custom inserter builds
// the value in the ACC core then copies it to dst, so a large constant can land
// in XT/XAR instead of pinning ACC.  (Constants that fit imm16s/imm22 still use
// the shorter MOV_ACC_imm / MOVL_XAR_imm patterns.)
def MOV32_imm32 : C28xPseudo<(outs GPR32:$dst), (ins i32imm:$val), []>;

def MOVL_XAR_ACC : C28xInst<(outs GR32:$dst), (ins ACC32:$src),
  "movl $dst, $src",
  []>;

// XARn -> ACC (32-bit, via MOVL loc32,XARn with loc32=@ACC).
// Verified: MOVL ACC, XAR0 = 3AA9, MOVL ACC, XAR7 = 06A7.
def MOVL_ACC_XAR : C28xInst<(outs ACC32:$dst), (ins GR32:$src),
  "movl $dst, $src", []>;

//===----------------------------------------------------------------------===//
// ADD / SUB
//===----------------------------------------------------------------------===//

def ADD_ACC_imm : C28xInst<(outs), (ins i16imm:$src),
  "add acc, #$src",
  []>;

def ADD_ACC_mem : C28xInst<(outs), (ins mem_direct:$src),
  "add acc, $src",
  []>;

def SUB_ACC_imm : C28xInst<(outs), (ins i16imm:$src),
  "sub acc, #$src",
  []>;

let Defs = [SP], Uses = [SP] in {
def ADDB_SP : C28xInst<(outs), (ins i16imm:$words),
  "addb sp, #$words", []>;
def SUBB_SP : C28xInst<(outs), (ins i16imm:$words),
  "subb sp, #$words", []>;
}

// Real reg-reg ALU16 instructions.  C28x only encodes "OP AX, loc16" with the
// destination in an accumulator half, so these are tied ($dst=$lhs) and pinned
// to GR16ACC.  They carry NO SelectionDAG pattern: normal values must live in
// the wide GR16 class (otherwise long-lived arithmetic results starve the
// allocator by occupying AL/AH for their whole live range).  The wide
// *_PSEUDO below is selected instead and expanded post-RA, which stages the
// operands and then emits these real instructions.
def ADD16rr : C28xInst<(outs GR16ACC:$dst), (ins GR16ACC:$lhs, GR16:$rhs),
  "add $dst, $rhs", []> {
  let isCodeGenOnly = 1;
  let Constraints = "$dst = $lhs";
}

def SUB16rr : C28xInst<(outs GR16ACC:$dst), (ins GR16ACC:$lhs, GR16:$rhs),
  "sub $dst, $rhs", []> {
  let isCodeGenOnly = 1;
  let Constraints = "$dst = $lhs";
}

// Wide 16-bit ALU pseudos: dst/lhs/rhs all live in GR16.  Post-RA expansion
// (C28xInstrInfo.cpp) uses the reserved AR7 scratch and an accumulator half.
def ADD16_PSEUDO : C28xPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
  [(set GR16:$dst, (add GR16:$lhs, GR16:$rhs))]>;
def SUB16_PSEUDO : C28xPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
  [(set GR16:$dst, (sub GR16:$lhs, GR16:$rhs))]>;


// 32-bit ADD/SUB operate on the accumulator only (ACC, not XT).  $dst/$lhs
// are pinned to ACCOnly so the register allocator cannot assign them to XT;
// $rhs remains ACC32 because "ADD ACC,loc32" can read XT as well.
// No DAG pattern: normal i32 values live in the wide GPR32 class; the wide
// ADD32_PSEUDO below is selected and pre-RA inserts the required ACC copies.
def ADD32rr : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$lhs, ACC32:$rhs),
  "add acc, $rhs", []> {
  let isCodeGenOnly = 1;
  let Constraints = "$dst = $lhs";
}

def SUB32rr : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$lhs, ACC32:$rhs),
  "sub acc, $rhs", []> {
  let isCodeGenOnly = 1;
  let Constraints = "$dst = $lhs";
  let Defs = [ST0];
}

// Wide 32-bit ALU pseudos: dst/lhs/rhs all live in GPR32 (ACC/XT/XAR0-7).
// No pre-RA custom inserter: expandPostRAPseudo arranges ACC=Lhs, XT=Rhs using
// the reserved XAR7 as a parking register (PUSH/POP around live values), so the
// allocator never pins ACC staging temps (that pinning exhausted registers in
// the large float functions).
def ADD32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GPR32:$lhs, GPR32:$rhs),
  [(set GPR32:$dst, (add GPR32:$lhs, GPR32:$rhs))]>;
def SUB32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GPR32:$lhs, GPR32:$rhs),
  [(set GPR32:$dst, (sub GPR32:$lhs, GPR32:$rhs))]>;


// 32-bit ADD/SUB with immediate.  Encoding chosen by emitter:
//   ADDB ACC, #imm8  = 0x0900 | imm8  (single word)
//   ADD  ACC, #imm16 = 0xFF10, imm16  (two words)
def ADD32imm : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$lhs, i32immop:$src),
  "add acc, #$src",
  []> {
  let Constraints = "$dst = $lhs";
}

def SUB32imm : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$lhs, i32immop:$src),
  "sub acc, #$src",
  []> {
  let Constraints = "$dst = $lhs";
}

// Constants outside the signed/unsigned 16-bit immediate range (e.g.
// 0x7FFFFFFF, -100000).  Fold the constant directly into the add/sub so it is
// never materialised as a standalone GPR32 that collides with the accumulator
// (which produced "ran out of registers").  Pre-RA custom inserter stages the
// variable into XT (add) / parks it (sub), builds the constant in ACC from two
// 16-bit halves, and runs the accumulator op.
def ADD32imm32 : C28xPseudo<(outs GPR32:$dst),
                            (ins GPR32:$lhs, i32imm:$val), []>;
def SUB32imm32 : C28xPseudo<(outs GPR32:$dst),
                            (ins GPR32:$lhs, i32imm:$val), []>;
def immNot16 : ImmLeaf<i32, [{ return !(isInt<16>(Imm) || isUInt<16>(Imm)); }]>;
def : Pat<(i32 (add GPR32:$lhs, immNot16:$val)),
          (ADD32imm32 GPR32:$lhs, immNot16:$val)>;
def : Pat<(i32 (add immNot16:$val, GPR32:$lhs)),
          (ADD32imm32 GPR32:$lhs, immNot16:$val)>;
def : Pat<(i32 (sub GPR32:$lhs, immNot16:$val)),
          (SUB32imm32 GPR32:$lhs, immNot16:$val)>;

// 16-bit-range immediate: still route through the GPR32 post-RA pseudo so the
// result is not pinned to the accumulator before allocation (two such values
// live together, e.g. operands of CMP32, caused "ran out of registers").
def : Pat<(i32 (add GPR32:$lhs, imm16s:$src)),
          (ADD32imm32 GPR32:$lhs, imm16s:$src)>;
def : Pat<(i32 (add imm16s:$src, GPR32:$lhs)),
          (ADD32imm32 GPR32:$lhs, imm16s:$src)>;
def : Pat<(i32 (sub GPR32:$lhs, imm16s:$src)),
          (SUB32imm32 GPR32:$lhs, imm16s:$src)>;

//===----------------------------------------------------------------------===//
// Logical
//===----------------------------------------------------------------------===//

def AND16rr : C28xInst<(outs GR16ACC:$dst), (ins GR16ACC:$lhs, GR16:$rhs),
  "and $dst, $rhs", []> {
  let isCodeGenOnly = 1;
  let Constraints = "$dst = $lhs";
}

def OR16rr : C28xInst<(outs GR16ACC:$dst), (ins GR16ACC:$lhs, GR16:$rhs),
  "or $dst, $rhs", []> {
  let isCodeGenOnly = 1;
  let Constraints = "$dst = $lhs";
}

def XOR16rr : C28xInst<(outs GR16ACC:$dst), (ins GR16ACC:$lhs, GR16:$rhs),
  "xor $dst, $rhs", []> {
  let isCodeGenOnly = 1;
  let Constraints = "$dst = $lhs";
}

def AND16_PSEUDO : C28xPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
  [(set GR16:$dst, (and GR16:$lhs, GR16:$rhs))]>;
def OR16_PSEUDO : C28xPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
  [(set GR16:$dst, (or GR16:$lhs, GR16:$rhs))]>;
def XOR16_PSEUDO : C28xPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
  [(set GR16:$dst, (xor GR16:$lhs, GR16:$rhs))]>;


// Post-RA 32-bit logic half-op pseudos (ACC dst tied, rhs in ACC32).  These
// are emitted by the custom inserter of the wide pseudos below (never selected
// directly) and expand to 16-bit ALU ops on AL/AH halves using AR0 scratch.
// If rhs == ACC (self-op): AND/OR are no-ops, XOR clears ACC.
def AND32_HALF_PSEUDO : C28xPseudo<(outs ACCOnly:$dst), (ins ACCOnly:$lhs, ACC32:$rhs),
  []> {
  let Constraints = "$dst = $lhs";
}
def OR32_HALF_PSEUDO : C28xPseudo<(outs ACCOnly:$dst), (ins ACCOnly:$lhs, ACC32:$rhs),
  []> {
  let Constraints = "$dst = $lhs";
}
def XOR32_HALF_PSEUDO : C28xPseudo<(outs ACCOnly:$dst), (ins ACCOnly:$lhs, ACC32:$rhs),
  []> {
  let Constraints = "$dst = $lhs";
}

// Wide 32-bit logical pseudos (GPR32).  No pre-RA custom inserter: they reach
// post-RA and expandPostRAPseudo stages the operands with PUSH/POP and the
// reserved XAR7 scratch (plus a borrowed AR0).  Doing the ACC half-word work
// post-RA avoids pinning a chain of tied-ACC half ops that exhausted registers
// in the float bit-twiddling code.
def AND32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GPR32:$lhs, GPR32:$rhs),
  [(set GPR32:$dst, (and GPR32:$lhs, GPR32:$rhs))]>;
def OR32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GPR32:$lhs, GPR32:$rhs),
  [(set GPR32:$dst, (or GPR32:$lhs, GPR32:$rhs))]>;
def XOR32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GPR32:$lhs, GPR32:$rhs),
  [(set GPR32:$dst, (xor GPR32:$lhs, GPR32:$rhs))]>;

//===----------------------------------------------------------------------===//
// Shift (constant immediate only)
//===----------------------------------------------------------------------===//

def LSL16 : C28xInst<(outs GR16ACC:$dst), (ins GR16ACC:$src, i16imm:$amt),
  "lsl $dst, #$amt",
  [(set GR16ACC:$dst, (shl GR16ACC:$src, (i16 imm:$amt)))]> {
  let Constraints = "$dst = $src";
}

def LSR16 : C28xInst<(outs GR16ACC:$dst), (ins GR16ACC:$src, i16imm:$amt),
  "lsr $dst, #$amt",
  [(set GR16ACC:$dst, (srl GR16ACC:$src, (i16 imm:$amt)))]> {
  let Constraints = "$dst = $src";
}

// 32-bit ACC rotate through carry.  Used with CLRC C to implement logical
// right-shift by 1 (byte address -> word address).
// Verified: ROR ACC = FF52, CLRC C = 2908.
def ROR_ACC : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$src),
  "ror acc", []> { let Constraints = "$dst = $src"; }
def ROL_ACC : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$src),
  "rol acc", []> { let Constraints = "$dst = $src"; }
def CLRC_C : C28xInst<(outs), (ins), "clrc c", []>;
def SETC_C : C28xInst<(outs), (ins), "setc c", []>;

// Hardware variable-count 32-bit shifts.  The shift count is taken from the
// five least significant bits of the T register (upper half of XT),
// T(4:0) = 0..31; higher bits are ignored.  Verified with asm2000/dis2000:
//   LSL ACC,T = FF50   LSRL ACC,T = 5622   ASRL ACC,T = 5610.
// ASRL fills the high bits with the sign bit; LSRL zero-fills.
def LSL_ACC_T  : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$src),
  "lsl acc,t", []> { let Constraints = "$dst = $src"; }
def LSRL_ACC_T : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$src),
  "lsrl acc,t", []> { let Constraints = "$dst = $src"; }
def ASRL_ACC_T : C28xInst<(outs ACCOnly:$dst), (ins ACCOnly:$src),
  "asrl acc,t", []> { let Constraints = "$dst = $src"; }
// Load T (the upper half of XT) from an auxiliary register.  Used to stage the
// count ahead of the variable shifts.  Verified: MOV T,AR0 = 2DA0 (low byte is
// the @ARn loc16 code 0xA0|n).
// Load T (the upper half of XT) from any loc16.  Used to stage the shift
// count or a multiply operand.  Verified: MOV T,AR0 = 2DA0 / AL = 2DA9 /
// AH = 2DA8 (low byte is the loc16 register code).
def MOV_T : C28xInst<(outs), (ins GR16:$src), "mov t, $src", []>;

// Hardware 16x16 -> 32 multiply, result straight into ACC.
//   MPY  ACC,T,loc16 = 0x1200 | loc  (signed)
//   MPYU ACC,T,loc16 = 0x3600 | loc  (unsigned)
def MPY_ACC_T  : C28xInst<(outs ACCOnly:$dst), (ins GR16:$src),
                          "mpy acc, t, $src", []>;
def MPYU_ACC_T : C28xInst<(outs ACCOnly:$dst), (ins GR16:$src),
                          "mpyu acc, t, $src", []>;

// 16x16 -> 32 product pseudo (postRA): MOV T,a ; MPY(U) ACC,T,b ; route dst.
def UMUL16_32_PSEUDO : C28xPseudo<(outs GPR32:$dst),
                                  (ins GR16:$a, GR16:$b), []> {
  let Defs = [ACC, XT];
}
def SMUL16_32_PSEUDO : C28xPseudo<(outs GPR32:$dst),
                                  (ins GR16:$a, GR16:$b), []> {
  let Defs = [ACC, XT];
}

// 32-bit logical right-shift core: post-RA expands in physical ACC to
// N * (CLRC_C; ROR_ACC).  Only ever allocated to ACC (ACCOnly in/out).
def SRL32_CORE : C28xPseudo<(outs ACCOnly:$dst), (ins ACCOnly:$src, i16imm:$amt), []> {
  let Constraints = "$dst = $src";
}

// Wide constant SRL: operands/result in GPR32 (ACC/XT/XAR).  Pre-RA custom
// inserter stages src into ACC, runs SRL32_CORE, copies the result to dst so
// long-lived shifted values can park in XT/XAR instead of pinning ACC.
def SRL32_PSEUDO : C28xPseudo<(outs GPR32:$dst),
                              (ins GPR32:$src, i16imm:$amt), []>;

// Wide variable i32 shifts.  Operands/result are GPR32 (ACC/XT/XAR); the
// amount must be masked to 0..31 by the DAG lowering.  Post-RA expansion
// stages the count into T (via reserved XAR7), stages src into ACC, and runs
// the hardware LSL/LSRL/ASRL ACC,T, routing the result to dst.  ACC and XT
// (which holds T) are clobbered.
def SHL32_VAR_PSEUDO : C28xPseudo<(outs GPR32:$dst),
  (ins GPR32:$src, GPR32:$amt), []> {
  let Defs = [ACC, XT];
}
def SRL32_VAR_PSEUDO : C28xPseudo<(outs GPR32:$dst),
  (ins GPR32:$src, GPR32:$amt), []> {
  let Defs = [ACC, XT];
}
def SRA32_VAR_PSEUDO : C28xPseudo<(outs GPR32:$dst),
  (ins GPR32:$src, GPR32:$amt), []> {
  let Defs = [ACC, XT];
}

// i32 multiply: post-RA expands to shift-and-add.
def MUL32_PSEUDO : C28xPseudo<(outs ACCOnly:$dst), (ins ACCOnly:$src, GR32:$rhs), []>;

//===----------------------------------------------------------------------===//
// Extend / Truncate
//===----------------------------------------------------------------------===//

// Zero-extend core: post-RA builds the value in physical ACC (MOV AL,src;
// MOV AH,#0).  Allocated to ACC only.
def ZEXT16_32_CORE : C28xPseudo<(outs ACCOnly:$dst), (ins GR16:$src), []>;

// Wide zero/any extend: dst in GPR32.  Pre-RA custom inserter stages src into
// the ACC core, then copies to dst, so the extended value can live in XT/XAR
// instead of pinning ACC (a pinned ACCOnly zext reloaded as an ADD rhs made
// allocation impossible: ADD rhs can only be ACC or XT).
def ZEXT16_32 : C28xPseudo<(outs GPR32:$dst), (ins GR16:$src),
  [(set GPR32:$dst, (zext GR16:$src))]>;

// any_extend i16->i32: high bits undefined, zero-extend is valid.
def : Pat<(i32 (anyext GR16:$src)), (ZEXT16_32 GR16:$src)>;

// Sign-extension support (verified against TI cl2000/asm2000):
//   SETC SXM        = 0x3B01  (set sign-extension mode)
//   MOV  ACC,reg16  = 0x8500 | loc16(reg)  (sign-extends when SXM=1)
//   MOVU ACC,reg16  = 0x0E00 | loc16(reg)  (zero-extends)
def SETC_SXM : C28xInst<(outs), (ins), "setc sxm", []>;
def MOV_ACC_GR16 : C28xInst<(outs ACCOnly:$dst), (ins GR16:$src),
  "mov acc, $src", []> { let isCodeGenOnly = 1; }
def MOVU_ACC_GR16 : C28xInst<(outs ACCOnly:$dst), (ins GR16:$src),
  "movu acc, $src", []> { let isCodeGenOnly = 1; }

// Sign-extend GR16 -> wide i32.  Post-RA: SETC SXM; MOV ACC,Src; route to Dst.
def SEXT16_32 : C28xPseudo<(outs GPR32:$dst), (ins GR16:$src),
  [(set GPR32:$dst, (sext GR16:$src))]>;

// Truncate wide i32 -> i16 (low half).  Input is GPR32; postRA parks Src in
// reserved XAR7 then MOV Dst,AR7.  No pre-RA ACC32 pin (that pinning produced
// many acc32 staging copies in the f64 decimal code).
def TRUNC32_16 : C28xPseudo<(outs GR16:$dst), (ins GPR32:$src),
  [(set GR16:$dst, (trunc GPR32:$src))]>;

//===----------------------------------------------------------------------===//
// CMP / Branch
//===----------------------------------------------------------------------===//

def CMP_AL_imm : C28xInst<(outs), (ins i16imm:$src),
  "cmp al, #$src",
  []>;

// Real compare: "cmp al, rhs".  LHS must be copied into AL before this.
// The RHS must not be AL (GR16NoAL), otherwise this degrades to "cmp al, al".
let Uses = [AL], Defs = [ST0] in
def CMP_AL_rr : C28xInst<(outs), (ins GR16NoAL:$src),
  "cmp al, $src",
  []>;

// Real branches (MBB-relative, emitted after pseudo expansion).
// Every C28x branch mnemonic takes an explicit condition in TI assembly
// syntax: asm2000 rejects a bare "B label" with "Expecting condition code as
// operand", so the unconditional form spells out UNC.
let isBranch = 1, isTerminator = 1, Uses = [ST0] in {
let isBarrier = 1 in
def B_JMP : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, unc", []>;
def B_EQ : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, eq", []>;
def B_NE : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, neq", []>;
def B_LT : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, lt", []>;
def B_GT : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, gt", []>;
def B_GE : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, geq", []>;
def B_LE : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, leq", []>;
def B_HI : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, hi", []>;
def B_HIS : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, his", []>;
def B_LO : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, lo", []>;
def B_LOS : C28xInst<(outs), (ins brtarget:$dst),
  "b $dst, los", []>;
}

// Pseudo compare: lowered in expandPostRAPseudo to
//   mov al, lhs ; cmp al, rhs
// rhs is GR16NoAL so the allocator never places it in AL (self-compare hazard);
// the pseudo also defines AL because the expansion clobbers it.
def CMP16_PSEUDO : C28xPseudo<(outs), (ins GR16:$lhs, GR16NoAL:$rhs),
  [(C28xcmp GR16:$lhs, GR16NoAL:$rhs)]> {
  let hasSideEffects = 1;
  let Defs = [AL, ST0];
}

// 32-bit compare.  Operands are wide GPR32; postRA parks Lhs in XAR7, arranges
// XT=Rhs, ACC=Lhs and finishes with SUBL ACC,XT (N/Z flags consumed by the
// following branch).  Both ACC and XT are clobbered.  No pre-RA ACC32 pin.
def CMP32_PSEUDO : C28xPseudo<(outs), (ins GPR32:$lhs, GPR32:$rhs),
  [(C28xcmp GPR32:$lhs, GPR32:$rhs)]> {
  let Defs = [ACC, XT, ST0];
  let hasSideEffects = 1;
}
def C28x_COND_EQ : PatLeaf<(i16 0)>;
def C28x_COND_NE : PatLeaf<(i16 1)>;
def C28x_COND_GT : PatLeaf<(i16 2)>;
def C28x_COND_GE : PatLeaf<(i16 3)>;
def C28x_COND_LT : PatLeaf<(i16 4)>;
def C28x_COND_LE : PatLeaf<(i16 5)>;
def C28x_COND_HI : PatLeaf<(i16 6)>;
def C28x_COND_HIS : PatLeaf<(i16 7)>;
def C28x_COND_LO : PatLeaf<(i16 8)>;
def C28x_COND_LOS : PatLeaf<(i16 9)>;

// Pseudo conditional branches: selected by condition constant, expanded in
// expandPostRAPseudo to the concrete b <cc>, dst.
let isBranch = 1, isTerminator = 1, Uses = [ST0] in {
def B_EQ_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_EQ)]>;
def B_NE_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_NE)]>;
def B_GT_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_GT)]>;
def B_GE_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_GE)]>;
def B_LT_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_LT)]>;
def B_LE_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_LE)]>;
def B_HI_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_HI)]>;
def B_HIS_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_HIS)]>;
def B_LO_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_LO)]>;
def B_LOS_p : C28xPseudo<(outs), (ins brtarget:$dst),
  [(C28xbrcond bb:$dst, C28x_COND_LOS)]>;
}

// Pseudo unconditional branch.
def B_JMP_Pseudo : C28xPseudo<(outs), (ins brtarget:$dst),
  [(br bb:$dst)]> {
  let isBranch = 1;
  let isTerminator = 1;
  let isBarrier = 1;
}

//===----------------------------------------------------------------------===//
// Call / Return
//===----------------------------------------------------------------------===//

def LCR : C28xInst<(outs), (ins i22imm:$dst),
  "lcr $dst",
  []> {
  let isCall = 1;
  // Caller-saved registers per TI C28x EABI: AL/ACC, XT, AR0-AR3, XAR0-XAR3.
  // AR4-AR6 / XAR4-XAR6 are callee-saved (preserved by the callee).
  let Defs = [AL, AH, ACC, XT, AR0, AR1, AR2, AR3, XAR0, XAR1, XAR2, XAR3];
}

// Callee addresses are iPTR (i32) per SDT_C28xCall; the hardware consumes
// the 22-bit word address held in the low bits.
def : Pat<(C28xcall (i32 tglobaladdr:$dst)),
          (LCR tglobaladdr:$dst)>;
def : Pat<(C28xcall (i32 texternalsym:$dst)),
          (LCR texternalsym:$dst)>;

// Indirect call through a function pointer.
// Function pointers are byte addresses (ABI L1-1); LCR *XARn loads XARn
// directly into PC which expects a WORD address.  The pseudo converts:
//   MOVL ACC, XARn / CLRC C / ROR ACC / MOVL XAR7, ACC / LCR *XAR7
def LCR_IND : C28xPseudo<(outs), (ins GR32:$dst),
  [(C28xcall GR32:$dst)]> {
  let isCall = 1;
  let Defs = [AL, AH, ACC, XT, AR0, AR1, AR2, AR3, XAR0, XAR1, XAR2, XAR3, XAR7];
}

// Real indirect call: LCR *XARn = 0x3E60|n (1-word).
// Verified: LCR *XAR0=3E60, *XAR4=3E64, *XAR7=3E67.
def LCR_IND_REAL : C28xInst<(outs), (ins GR32:$dst),
  "lcr *$dst", []> {
  let isCall = 1;
  let Defs = [AL, AH, ACC, XT, AR0, AR1, AR2, AR3, XAR0, XAR1, XAR2, XAR3];
}

let isReturn = 1, isTerminator = 1, isBarrier = 1 in
def LRETR : C28xInst<(outs), (ins), "lretr", [(C28xretglue)]>;

//===----------------------------------------------------------------------===//
// PUSH / POP
//===----------------------------------------------------------------------===//

def PUSH_AL : C28xInst<(outs), (ins), "push al", []>;
def POP_AL  : C28xInst<(outs), (ins), "pop al",  []>;
def PUSH_ACC : C28xInst<(outs), (ins), "push acc", []> {
  let Uses = [SP, ACC];
  let Defs = [SP];
  let mayStore = 1;
}
def POP_ACC : C28xInst<(outs), (ins), "pop acc", []> {
  let Uses = [SP];
  let Defs = [SP, ACC, ST0];
  let mayLoad = 1;
}
def PUSH_AR0 : C28xInst<(outs), (ins), "push ar0", []>;
def POP_AR0  : C28xInst<(outs), (ins), "pop ar0",  []>;
def PUSH_AR4 : C28xInst<(outs), (ins), "push ar4", []>;
def POP_AR4  : C28xInst<(outs), (ins), "pop ar4",  []>;
def PUSH_AR5 : C28xInst<(outs), (ins), "push ar5", []>;
def POP_AR5  : C28xInst<(outs), (ins), "pop ar5",  []>;
def PUSH_AR6 : C28xInst<(outs), (ins), "push ar6", []>;
def POP_AR6  : C28xInst<(outs), (ins), "pop ar6",  []>;

//===----------------------------------------------------------------------===//
// Multiply
//===----------------------------------------------------------------------===//

def MPY16ind : C28xInst<(outs), (ins GR32:$ptr),
  "mpy p, *$ptr",
  []>;

def MOVP_ACC_P : C28xInst<(outs), (ins),
  "movp acc, p",
  []>;

//===----------------------------------------------------------------------===//
// Scratch address materialization (XAR7 is reserved as scratch)
//===----------------------------------------------------------------------===//

// mov al, sp
def MOV_AL_SP : C28xInst<(outs GR16:$dst), (ins),
  "mov $dst, sp", []> {
  let Uses = [SP];
}

// add al, #imm
def ADD_AL_imm : C28xInst<(outs GR16:$dst), (ins i16imm:$src),
  "add $dst, #$src", []>;

// movz ar7, <loc16>  (load scratch pointer register, zero-extended)
//
// The mnemonic must be MOVZ, not "mov xar7, al": asm2000 -v28 rejects
// "mov xar7, al" with [E0004] Illegal operand combination, and the semantics
// we need here are exactly SPRU430F's "MOVZ ARn, loc16 - Load Lower Half of
// XARn and Clear Upper Half". The encoder emits 0x8000 | loc16.
def MOV_XAR7_AL : C28xInst<(outs), (ins GR16:$src),
  "movz ar7, $src", []> {
  let Defs = [XAR7];
}

// Stack address without clobbering AL (MOVZ AR7,SP = 0x80AD).
def MOVZ_XAR7_SP : C28xInst<(outs), (ins), "movz ar7, sp", []> {
  let Defs = [XAR7];
  let Uses = [SP];
}

def SUBB_XAR7_imm : C28xInst<(outs), (ins i16imm:$words),
  "subb xar7, #$words", []> {
  let Defs = [XAR7];
  let Uses = [XAR7];
}

// ADDB XAR7, #7bit — bump XAR7 to next word (32-bit load/store second half).
// Verified: ADDB XAR7, #1 = DF01.
def ADDB_XAR7_imm : C28xInst<(outs), (ins i16imm:$words),
  "addb xar7, #$words", []> {
  let Defs = [XAR7];
  let Uses = [XAR7];
}

//===----------------------------------------------------------------------===//
// Pseudo load / store (i16 through XAR7 scratch)
//===----------------------------------------------------------------------===//

def LOAD16_PSEUDO : C28xPseudo<(outs GR16:$dst), (ins GR32:$ptr),
  [(set GR16:$dst, (load GR32:$ptr))]>;
// Zero-extending i16 load to i32: load into AL, clear AH.
def LOAD16_ZEXT32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GR32:$ptr),
  [(set GPR32:$dst, (zextloadi16 GR32:$ptr))]>;

def STORE16_PSEUDO : C28xPseudo<(outs), (ins GR32:$ptr, GR16:$src),
  [(store GR16:$src, GR32:$ptr)]>;

// i32 value truncated to i16 in memory (arises when an i64 store is split and
// a 32-bit piece is narrowed): extract the low 16 bits, then store.
def : Pat<(truncstorei16 GPR32:$src, GR32:$ptr),
          (STORE16_PSEUDO GR32:$ptr, (TRUNC32_16 GPR32:$src))>;

// i32 load/store through a GR32 pointer (XARn).
// Expanded in post-RA: two 16-bit loads into AL/AH (load) or stores from AL/AH.
// ACCOnly because the expansion touches only AL/AH (sub-regs of ACC), never XT.
// Spill XT directly to stack — allocator sees no ACC clobber.
// Post-RA expands to: push acc; movl acc, xt; store32 fi; pop acc.
def STORE32_XT_PSEUDO : C28xPseudo<(outs), (ins i32imm:$fi), []> {
  let mayStore = 1;
  let Defs = [];
}
// Reload from stack directly into XT — allocator sees no ACC clobber.
// Post-RA expands to: push acc; load32 acc; movl xt, acc; pop acc.
def LOAD32_XT_PSEUDO : C28xPseudo<(outs), (ins i32imm:$fi), []> {
  let mayLoad = 1;
  let Defs = [XT];
}
def LOAD32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GR32:$ptr),
  [(set GPR32:$dst, (load GR32:$ptr))]>;
// Wide source (GPR32 = ACC/XT/XAR0-7): the post-RA expansion stages the value
// into ACC with PUSH/POP and the reserved XAR7 scratch, so the allocator never
// has to pin an ACCOnly value at the store (that pinning deadlocked on back-to-
// back 32-bit struct stores).
def STORE32_PSEUDO : C28xPseudo<(outs), (ins GR32:$ptr, GPR32:$src),
  [(store GPR32:$src, GR32:$ptr)]>;

// i8 load/store through a GR32 pointer. i8 values are promoted to GR16 (AL).
// Expanded in post-RA to MOVB_ind_load_AL / MOVB_ind_store_AL.
def LOAD8_PSEUDO : C28xPseudo<(outs GR16:$dst), (ins GR32:$ptr),
  [(set GR16:$dst, (zextloadi8 GR32:$ptr))]>;
// Also match any-extending i8 loads (MOVB zero-extends, which satisfies
// the undefined upper bits of EXTLOAD).
def : Pat<(extloadi8 GR32:$ptr), (LOAD8_PSEUDO GR32:$ptr)>;
def LOAD8_ZEXT32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GR32:$ptr),
  [(set GPR32:$dst, (zextloadi8 GR32:$ptr))]>;
def STORE8_PSEUDO : C28xPseudo<(outs), (ins GR32:$ptr, GR16:$src),
  [(truncstorei8 GR16:$src, GR32:$ptr)]>;
// i32 value truncated to i8: truncate to low 16 bits then store low 8 bits.
// Use the TRUNC32_16 pseudo (post-RA routed for ACC/XT/XAR) rather than
// EXTRACT_SUBREG, which the InstrEmitter cannot constrain when the source
// register class was narrowed to GR16.
def : Pat<(truncstorei8 GPR32:$src, GR32:$ptr),
          (STORE8_PSEUDO GR32:$ptr, (TRUNC32_16 GPR32:$src))>;

// i1 zero-extending load to i16: load byte, mask low bit with AND 1.
def : Pat<(zextloadi1 GR32:$ptr),
          (AND16rr (LOAD8_PSEUDO GR32:$ptr), (MOV16_imm 1))>;
def : Pat<(extloadi1 GR32:$ptr),
          (AND16rr (LOAD8_PSEUDO GR32:$ptr), (MOV16_imm 1))>;
// i1 zero/any-extending load to i32: a bool lives as 0/1 in a byte, so reuse
// the i8->i32 byte load+zext.  Needed by spilled {i32,i1} struct fields
// (e.g. overflowing_neg flag) that reload straight into an i32.
def LOAD1_ZEXT32_PSEUDO : C28xPseudo<(outs GPR32:$dst), (ins GR32:$ptr),
  [(set GPR32:$dst, (zextloadi1 GR32:$ptr))]>;
def : Pat<(extloadi1 GR32:$ptr), (LOAD1_ZEXT32_PSEUDO GR32:$ptr)>;

// Materialize a frame-index pointer into GR16; the TargetFrameIndex operand
// is rewritten by eliminateFrameIndex.
def MOV32fi : C28xPseudo<(outs GR32:$dst), (ins brtarget:$ptr), []>;
def MOV32fi_off : C28xPseudo<(outs GR32:$dst), (ins brtarget:$ptr, i16imm:$off), []>;

// Pseudo SELECT_CC: (true, false, flag) -> dst.
// Expanded in expandPostRAPseudo to two basic blocks with conditional branch.
let usesCustomInserter = 1 in
def SELECT_CC_PSEUDO : C28xPseudo<(outs GR16:$dst),
  (ins GR16:$trueval, GR16:$falseval, i16imm:$cond), []>;
