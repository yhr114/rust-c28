//===-- C28xISelLowering.cpp - C28x DAG Lowering Implementation ---------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28xISelLowering.h"
#include "C28x.h"
#include "C28xInstrInfo.h"
#include "C28xSubtarget.h"
#include "C28xTargetMachine.h"
#include "llvm/CodeGen/CallingConvLower.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

#define GET_CALLING_CONV_IMPL
#include "C28xGenCallingConv.inc"

C28xTargetLowering::C28xTargetLowering(const TargetMachine &TM,
                                       const C28xSubtarget &STI)
    : TargetLowering(TM, STI), STI(STI) {

  // C28x has native i16 operations.
  addRegisterClass(MVT::i16, &C28x::GR16RegClass);
  // Non-pointer i32 values use the wide class (ACC/XT/XAR); arithmetic patterns
  // constrain to ACCOnly/ACC32 and the allocator inserts MOVL copies.
  addRegisterClass(MVT::i32, &C28x::GPR32RegClass);

  computeRegisterProperties(STI.getRegisterInfo());
  setStackPointerRegisterToSaveRestore(C28x::SP);
  // C28x is a single-core MCU with no atomic RMW instructions, but an aligned
  // 16-bit load or store is indivisible on the bus, so a naturally-aligned
  // 16-bit access is a legal atomic operation.  Declaring that width makes
  // LLVM lower atomic load/store of i16/i8 to a plain MOV instead of an
  // unsupported libcall.  Wider atomics and atomic RMW stay unsupported and
  // are rejected at compile time rather than silently miscompiled.
  setMaxAtomicSizeInBitsSupported(16);
  // AtomicExpandPass drops the atomicity in IR (see shouldExpandAtomic*InIR),
  // so no ATOMIC_LOAD/STORE node should reach isel.  Do NOT mark them Expand
  // here: LegalizeDAG's expansion of an atomic load is a cmpxchg loop, which
  // this target cannot select.  Explicit fences still need an action.
  setOperationAction(ISD::ATOMIC_FENCE, MVT::Other, Expand);

  setMinFunctionAlignment(Align(2));
  setPrefFunctionAlignment(Align(2));

  setBooleanContents(ZeroOrOneBooleanContent);
  setBooleanVectorContents(ZeroOrOneBooleanContent);

  // Never inline memcpy/memmove/memset: the byte-pointer -> physical-word
  // conversion needs ACC/XAR7 scratch, and generic inline expansion runs out
  // of registers even for 2-byte copies.  Emit library calls instead; the
  // runtime crate provides memcpy/memmove/memset.
  MaxStoresPerMemset = 0;
  MaxStoresPerMemsetOptSize = 0;
  MaxStoresPerMemcpy = 0;
  MaxStoresPerMemcpyOptSize = 0;
  MaxStoresPerMemmove = 0;
  MaxStoresPerMemmoveOptSize = 0;

  setOperationAction(ISD::BR_JT, MVT::Other, Expand);
  setOperationAction(ISD::BRIND, MVT::Other, Expand);

  // i8 extending loads: MOVB zero-extends to 16 bits, so both EXTLOAD and
  // ZEXTLOAD are legal (EXTLOAD leaves upper bits undefined, which zero-ext
  // satisfies).  SEXTLOAD is expanded to EXTLOAD + sign_extend_inreg.
  setLoadExtAction(ISD::EXTLOAD, MVT::i16, MVT::i8, Legal);
  setLoadExtAction(ISD::ZEXTLOAD, MVT::i16, MVT::i8, Legal);
  setLoadExtAction(ISD::SEXTLOAD, MVT::i16, MVT::i8, Expand);
  // i8 -> i32 zero-extending load handled by LOAD8_ZEXT32_PSEUDO.
  setLoadExtAction(ISD::ZEXTLOAD, MVT::i32, MVT::i8, Legal);
  setLoadExtAction(ISD::EXTLOAD, MVT::i32, MVT::i8, Expand);
  setLoadExtAction(ISD::SEXTLOAD, MVT::i32, MVT::i8, Expand);
  // i16 -> i32 zero-extending load handled by LOAD16_ZEXT32_PSEUDO.
  setLoadExtAction(ISD::ZEXTLOAD, MVT::i32, MVT::i16, Legal);
  setLoadExtAction(ISD::EXTLOAD, MVT::i32, MVT::i16, Expand);
  setLoadExtAction(ISD::SEXTLOAD, MVT::i32, MVT::i16, Expand);
  // Bool (i1) in memory is a zero/one byte: expand to a plain i8 load and let
  // the ZeroOrOneBooleanContent i1<->i16 lowering handle the value.  Without
  // this, `core::num::i1::unchecked_neg` and other bool-loading codegen dies with
  // "Cannot select: load ... zext from i1".
  setLoadExtAction(ISD::ZEXTLOAD, MVT::i1, MVT::i8, Expand);
  setLoadExtAction(ISD::EXTLOAD, MVT::i1, MVT::i8, Expand);
  // Spilled {i32,i1} struct fields reload as a zextload whose memoryVT is i1 but
  // whose result is promoted all the way to i32 (e.g. overflowing_neg flag used
  // by br).  Expand to an i8 load + generic extension.
  setLoadExtAction(ISD::ZEXTLOAD, MVT::i32, MVT::i1, Expand);
  setLoadExtAction(ISD::ZEXTLOAD, MVT::i16, MVT::i1, Expand);
  // NOTE: EXTLOAD (anyext) must stay Legal 鈥?LLVM asserts it is never expanded.
  // i1 loads rely on the data layout treating i1 as byte-sized (see
  // C28xTargetMachine / -mtriple=c28x-ti-none), which folds them into i8 loads.

  setOperationAction(ISD::BRCOND, MVT::Other, Custom);
  setOperationAction(ISD::BR_CC, MVT::i16, Custom);
  setOperationAction(ISD::BR_CC, MVT::i32, Custom);

  // SELECT / SELECT_CC have no CMOV on C28x: SELECT_CC is lowered to a target
  // pseudo whose custom inserter expands it to BR + PHI blocks.
  setOperationAction(ISD::SELECT, MVT::i16, Custom);
  setOperationAction(ISD::SELECT, MVT::i32, Custom);
  setOperationAction(ISD::SELECT_CC, MVT::i16, Custom);
  setOperationAction(ISD::SETCC, MVT::i16, Custom);
  setOperationAction(ISD::SELECT_CC, MVT::i32, Custom);
  setOperationAction(ISD::SETCC, MVT::i32, Custom);
  // Wide integer comparisons: use the generic IntegerExpandSetCCOperands path
  // (i128 splits to i64, which expands into correct multi-word i32 compares).
  // Our Custom handlers only know how to compare a single i16/i32 and must not
  // truncate i64 operands.
  for (MVT W : {MVT::i64, MVT::i128}) {
    setOperationAction(ISD::BR_CC, W, Expand);
    setOperationAction(ISD::SETCC, W, Expand);
    setOperationAction(ISD::SELECT_CC, W, Expand);
    setOperationAction(ISD::SELECT, W, Expand);
    // Overflow-checking multiply: custom-lower via the wide multiply libcall;
    // the generic forceExpandWideMUL mis-consumes the legal i32 parts when the
    // intermediate (i64) type is itself illegal.
    setOperationAction(ISD::SMULO, W, Custom);
    setOperationAction(ISD::UMULO, W, Custom);
  }
  setOperationAction(ISD::GlobalAddress, getPointerTy(getTargetMachine().createDataLayout()), Custom);
  setOperationAction(ISD::ExternalSymbol, getPointerTy(getTargetMachine().createDataLayout()), Custom);

  setOperationAction(ISD::SDIV, MVT::i16, Expand);
  setOperationAction(ISD::UDIV, MVT::i16, Expand);
  setOperationAction(ISD::SREM, MVT::i16, Expand);
  setOperationAction(ISD::UREM, MVT::i16, Expand);
  setOperationAction(ISD::SDIV, MVT::i32, Expand);
  setOperationAction(ISD::UDIV, MVT::i32, Expand);
  setOperationAction(ISD::SREM, MVT::i32, Expand);
  setOperationAction(ISD::UREM, MVT::i32, Expand);

  setOperationAction(ISD::FADD, MVT::f32, Expand);
  setOperationAction(ISD::FSUB, MVT::f32, Expand);
  setOperationAction(ISD::FMUL, MVT::f32, Expand);
  setOperationAction(ISD::FDIV, MVT::f32, Expand);

  setOperationAction(ISD::ADD, MVT::i64, Expand);
  setOperationAction(ISD::SUB, MVT::i64, Expand);

  // i32 logic ops: AND32/OR32/XOR32_PSEUDO patterns handle them.
  // i32 shifts: Custom (constant optimized, variable -> hardware LSL/LSRL/ASRL).
  setOperationAction(ISD::SRA, MVT::i32, Custom);
  setOperationAction(ISD::SRL, MVT::i32, Custom);
  setOperationAction(ISD::SHL, MVT::i32, Custom);
  // Double-width (i64 split into i32) shifts: Custom-composed from the wide
  // variable-shift pseudos (i128 splits recurse into these).
  setOperationAction(ISD::SHL_PARTS, MVT::i32, Custom);
  setOperationAction(ISD::SRL_PARTS, MVT::i32, Custom);
  setOperationAction(ISD::SRA_PARTS, MVT::i32, Custom);
  // Byte swap (network byte order): expand to shifts/masks (no native SWPB).
  setOperationAction(ISD::BSWAP, MVT::i16, Expand);
  setOperationAction(ISD::BSWAP, MVT::i32, Expand);
  // Rotates / funnel shifts: expand to shifts and OR (no native rotate except
  // the 32-bit ROR through carry used for the byte->word address).
  setOperationAction(ISD::ROTL, MVT::i16, Expand);
  setOperationAction(ISD::ROTR, MVT::i16, Expand);
  setOperationAction(ISD::ROTL, MVT::i32, Expand);
  setOperationAction(ISD::ROTR, MVT::i32, Expand);
  setOperationAction(ISD::FSHL, MVT::i32, Expand);
  setOperationAction(ISD::FSHR, MVT::i32, Expand);
  // i16 shifts: Custom (promote to i32, shift, truncate).
  setOperationAction(ISD::SHL, MVT::i16, Custom);
  setOperationAction(ISD::SRL, MVT::i16, Custom);
  setOperationAction(ISD::SRA, MVT::i16, Custom);
  // Mul: i16 Custom (promote to i32), i32 Expand (libcall __mulsi3).
  setOperationAction(ISD::MUL, MVT::i16, Custom);
  setOperationAction(ISD::MUL, MVT::i32, Custom);
  setOperationAction(ISD::MULHU, MVT::i16, Custom);
  setOperationAction(ISD::MULHS, MVT::i16, Custom);
  setOperationAction(ISD::MULHU, MVT::i32, Custom);
  setOperationAction(ISD::MULHS, MVT::i32, Custom);
  // Bit counting: no native CLZ/CTZ/POP -> generic expansion.
  for (MVT VT : {MVT::i16, MVT::i32}) {
    setOperationAction(ISD::CTLZ, VT, Expand);
    setOperationAction(ISD::CTLZ_ZERO_POISON, VT, Expand);
    setOperationAction(ISD::CTTZ, VT, Expand);
    setOperationAction(ISD::CTTZ_ZERO_POISON, VT, Expand);
    setOperationAction(ISD::CTPOP, VT, Expand);
    // No hardware divide on F28035: compiler_builtins division routines.
    setOperationAction(ISD::SDIV, VT, Expand);
    setOperationAction(ISD::UDIV, VT, Expand);
    setOperationAction(ISD::SREM, VT, Expand);
    setOperationAction(ISD::UREM, VT, Expand);
    setOperationAction(ISD::SDIVREM, VT, Expand);
    setOperationAction(ISD::UDIVREM, VT, Expand);
  }
  // 16x16 -> 32 (lo,hi) and 32x32 -> 64 (lo,hi) products, used by parse / i64.
  setOperationAction(ISD::UMUL_LOHI, MVT::i16, Custom);
  setOperationAction(ISD::SMUL_LOHI, MVT::i16, Custom);
  setOperationAction(ISD::UMUL_LOHI, MVT::i32, Custom);
  setOperationAction(ISD::SMUL_LOHI, MVT::i32, Custom);
  // Wide multiply: expand to MUL + shifts.
  setOperationAction(ISD::UMUL_LOHI, MVT::i32, Expand);
  setOperationAction(ISD::SMUL_LOHI, MVT::i32, Expand);
  setOperationAction(ISD::MULHU, MVT::i32, Expand);
  setOperationAction(ISD::MULHS, MVT::i32, Expand);
  // Divide-remainder: expand to div + rem.
  setOperationAction(ISD::UDIVREM, MVT::i32, Expand);
  setOperationAction(ISD::SDIVREM, MVT::i32, Expand);
  // sign_extend_inreg for i8 comparisons.
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i8, Expand);
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i16, Expand);

  // Bit counting: expand to libcall/loop.
  setOperationAction(ISD::CTTZ, MVT::i32, Expand);
  setOperationAction(ISD::CTLZ, MVT::i32, Expand);
  setOperationAction(ISD::CTPOP, MVT::i32, Expand);
  // Extends to i32 expand (C28x has no native i32 register file).
  setOperationAction(ISD::ANY_EXTEND, MVT::i32, Expand);
  setOperationAction(ISD::ZERO_EXTEND, MVT::i32, Expand);
  setOperationAction(ISD::SIGN_EXTEND, MVT::i32, Expand);

  setOperationAction(ISD::VASTART, MVT::Other, Expand);
  setOperationAction(ISD::VAARG, MVT::Other, Expand);

  // Stack operations.
  setOperationAction(ISD::STACKSAVE, MVT::Other, Expand);
  setOperationAction(ISD::STACKRESTORE, MVT::Other, Expand);

  // Trap / debug.
  setOperationAction(ISD::TRAP, MVT::Other, Legal);
  setOperationAction(ISD::DEBUGTRAP, MVT::Other, Expand);

  // Frame info.
  setOperationAction(ISD::FRAMEADDR, MVT::i32, Expand);
  setOperationAction(ISD::RETURNADDR, MVT::i32, Expand);

  // LLVM 23.1.1 requires explicit Libcall -> LibcallImpl mapping.
  setLibcallImpl(RTLIB::SHL_I32, RTLIB::impl___ashlsi3);
  setLibcallImpl(RTLIB::SRL_I32, RTLIB::impl___lshrsi3);
  setLibcallImpl(RTLIB::SRA_I32, RTLIB::impl___ashrsi3);
  setLibcallImpl(RTLIB::MUL_I32, RTLIB::impl___mulsi3);
  setLibcallImpl(RTLIB::SDIV_I32, RTLIB::impl___divsi3);
  setLibcallImpl(RTLIB::UDIV_I32, RTLIB::impl___udivsi3);
  setLibcallImpl(RTLIB::SREM_I32, RTLIB::impl___modsi3);
  setLibcallImpl(RTLIB::UREM_I32, RTLIB::impl___umodsi3);

  // Inline `llvm.memcpy`/`memset`/`memmove` rather than calling the TI RTS.
  // The RTS routine dereferences C word addresses; Rust code passes logical
  // byte addresses, so a libcall copies from/to the wrong memory.  Raise the
  // store-count budget so ordinary aggregate copies inline; see
  // findOptimalMemOpLowering below for the type selection.
  MaxStoresPerMemcpy = 16;
  MaxStoresPerMemcpyOptSize = 16;
  MaxStoresPerMemmove = 16;
  MaxStoresPerMemmoveOptSize = 16;
  MaxStoresPerMemset = 16;
  MaxStoresPerMemsetOptSize = 16;
}

bool C28xTargetLowering::findOptimalMemOpLowering(
    LLVMContext &Context, std::vector<EVT> &MemOps, unsigned Limit,
    const MemOp &Op, unsigned DstAS, unsigned SrcAS,
    const AttributeList &FuncAttributes, EVT *LargestVT) const {
  // Prefer the generic chooser: it understands constant sources and the
  // target's own alignment rules.
  if (TargetLowering::findOptimalMemOpLowering(Context, MemOps, Limit, Op, DstAS,
                                               SrcAS, FuncAttributes,
                                               LargestVT))
    return true;

  // Fallback.  The generic chooser walks MVT::LAST_INTEGER_VALUETYPE down to
  // the largest legal integer type and then rejects every candidate on this
  // target, so without this fallback each memcpy becomes a TI RTS libcall.
  // Emit the copy as i32 words, then one i16 word, then one i8 byte; the
  // generic expander turns the illegal i8 into an EXTLOAD/TRUNCSTORE, which is
  // the byte-offset path this backend already has.
  uint64_t Size = Op.size();
  if (Size == 0)
    return false;
  std::vector<EVT> Ops;
  while (Size >= 4) {
    Ops.push_back(MVT::i32);
    Size -= 4;
  }
  if (Size >= 2) {
    Ops.push_back(MVT::i16);
    Size -= 2;
  }
  if (Size)
    Ops.push_back(MVT::i8);
  if (Ops.size() > Limit)
    return false;
  MemOps = Ops;
  return true;
}

const char *C28xTargetLowering::getTargetNodeName(unsigned Opcode) const {
  switch (Opcode) {
  case C28xISD::RET_GLUE:    return "C28xISD::RET_GLUE";
  case C28xISD::IRET_GLUE:   return "C28xISD::IRET_GLUE";
  case C28xISD::CMP:         return "C28xISD::CMP";
  case C28xISD::BRCOND:      return "C28xISD::BRCOND";
  case C28xISD::SELECT_CC:   return "C28xISD::SELECT_CC";
  case C28xISD::CALL:        return "C28xISD::CALL";
  case C28xISD::WRAPPER:     return "C28xISD::WRAPPER";
  case C28xISD::SRL32:       return "C28xISD::SRL32";
  default:                   return nullptr;
  }
}

MVT C28xTargetLowering::getTypeForExtLoad(EVT VT) const {
  if (VT == MVT::i8) return MVT::i16;
  return VT.getSimpleVT();
}

// Emit a CMP node; returns glue flag (no chain 鈥?ordered via glue).
SDValue C28xTargetLowering::EmitCMP(SDValue LHS, SDValue RHS,
                                    ISD::CondCode CC, const SDLoc &DL,
                                    SelectionDAG &DAG) const {
  // i16 compares truncate to i16 (CMP16_PSEUDO path).
  // i32 compares stay i32 鈥?CMP32_PSEUDO uses SUBL which sets flags on the
  // full 32-bit value.  Truncating i32 to i16 here would silently compare only
  // the low half, producing wrong results for values > 65535.
  if (LHS.getValueType() != MVT::i16 && LHS.getValueType() != MVT::i32)
    LHS = DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, LHS);
  if (RHS.getValueType() != MVT::i16 && RHS.getValueType() != MVT::i32)
    RHS = DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, RHS);
  SDValue Cmp = DAG.getNode(C28xISD::CMP, DL,
                           DAG.getVTList(MVT::Glue),
                           {LHS, RHS});
  return Cmp.getValue(0);
}

static unsigned condToEnc(ISD::CondCode CC) {
  switch (CC) {
  case ISD::SETEQ:              return 0;  // EQ
  case ISD::SETNE:              return 1;  // NEQ
  case ISD::SETGT:              return 2;  // GT  (signed >)
  case ISD::SETGE:              return 3;  // GEQ (signed >=)
  case ISD::SETLT:              return 4;  // LT  (signed <)
  case ISD::SETLE:              return 5;  // LEQ (signed <=)
  case ISD::SETUGT:             return 6;  // HI  (unsigned >)
  case ISD::SETUGE:             return 7;  // HIS (unsigned >=)
  case ISD::SETULT:             return 8;  // LO  (unsigned <)
  case ISD::SETULE:             return 9;  // LOS (unsigned <=)
  default:
    report_fatal_error("C28x: unsupported condition code");
  }
}


SDValue C28xTargetLowering::LowerShiftParts(SDNode *N,
                                            SelectionDAG &DAG) const {
  SDLoc DL(N);
  MVT VT = MVT::i32;
  SDValue Lo = N->getOperand(0);
  SDValue Hi = N->getOperand(1);
  SDValue ShAmt = N->getOperand(2);
  if (ShAmt.getValueType() != VT)
    ShAmt = DAG.getNode(ISD::ANY_EXTEND, DL, VT, ShAmt);

  bool IsSHL = N->getOpcode() == ISD::SHL_PARTS;
  bool IsSRA = N->getOpcode() == ISD::SRA_PARTS;

  // Split the amount: low five bits (a32 = amount & 31) and the ">=32" flag
  // (bit 5).  The amount only carries meaning for 0..63.
  SDValue A32 = DAG.getNode(ISD::AND, DL, VT, ShAmt,
                            DAG.getConstant(31, DL, VT));
  SDValue Bit32 = DAG.getNode(ISD::AND, DL, VT, ShAmt,
                              DAG.getConstant(32, DL, VT));
  EVT CCVT = getSetCCResultType(DAG.getDataLayout(), *DAG.getContext(), VT);
  // Big  = (ShAmt & 32) != 0  (amount in 32..63); Zero = (ShAmt == 0).
  SDValue BigCC = DAG.getSetCC(DL, CCVT, Bit32,
                               DAG.getConstant(0, DL, VT), ISD::SETNE);
  SDValue ZeroCC = DAG.getSetCC(DL, CCVT, ShAmt,
                                DAG.getConstant(0, DL, VT), ISD::SETEQ);
  // Complement count 32 - a32 (1..31 on the selected nonzero/small path).
  SDValue Rev = DAG.getNode(ISD::SUB, DL, VT,
                            DAG.getConstant(32, DL, VT), A32);

  SDValue SmallLo, SmallHi, BigLo, BigHi;
  if (IsSHL) {
    // Small: Lo' = Lo << a ; Hi' = (Hi << a) | (Lo >>u (32-a)).
    SDValue ShLo = DAG.getNode(C28xISD::SHL32_VAR, DL, VT, Lo, A32);
    SDValue ShHi = DAG.getNode(C28xISD::SHL32_VAR, DL, VT, Hi, A32);
    SDValue Cross = DAG.getNode(C28xISD::SRL32_VAR, DL, VT, Lo, Rev);
    SmallLo = ShLo;
    SmallHi = DAG.getNode(ISD::OR, DL, VT, ShHi, Cross);
    // Big: Lo' = 0 ; Hi' = Lo << (a-32) = Lo << a32.
    BigLo = DAG.getConstant(0, DL, VT);
    BigHi = DAG.getNode(C28xISD::SHL32_VAR, DL, VT, Lo, A32);
  } else {
    unsigned RightVar = IsSRA ? C28xISD::SRA32_VAR : C28xISD::SRL32_VAR;
    // Small: Lo' = (Lo >>u a) | (Hi << (32-a)) ; Hi' = Hi >> a.
    SDValue SrLo = DAG.getNode(C28xISD::SRL32_VAR, DL, VT, Lo, A32);
    SDValue SrHi = DAG.getNode(RightVar, DL, VT, Hi, A32);
    SDValue Cross = DAG.getNode(C28xISD::SHL32_VAR, DL, VT, Hi, Rev);
    SmallLo = DAG.getNode(ISD::OR, DL, VT, SrLo, Cross);
    SmallHi = SrHi;
    // Big: Lo' = Hi >> (a-32) = Hi >> a32 ; Hi' = 0 (SRL) / sign (SRA).
    BigLo = DAG.getNode(RightVar, DL, VT, Hi, A32);
    if (IsSRA)
      BigHi = DAG.getNode(C28xISD::SRA32_VAR, DL, VT, Hi,
                          DAG.getConstant(31, DL, VT));
    else
      BigHi = DAG.getConstant(0, DL, VT);
  }

  // Pick Big vs Small, then force the unchanged value when ShAmt == 0.
  SDValue LoP = DAG.getNode(ISD::SELECT, DL, VT, BigCC, BigLo, SmallLo);
  SDValue HiP = DAG.getNode(ISD::SELECT, DL, VT, BigCC, BigHi, SmallHi);
  LoP = DAG.getNode(ISD::SELECT, DL, VT, ZeroCC, Lo, LoP);
  HiP = DAG.getNode(ISD::SELECT, DL, VT, ZeroCC, Hi, HiP);

  return DAG.getMergeValues({LoP, HiP}, DL);
}

// Build a hardware 16x16 -> 32 product.  The low 16 bits are identical for
// signed/unsigned, so the unsigned primitive also backs the i32 low result.
static SDValue makeProd16(SelectionDAG &DAG, SDLoc DL, SDValue A, SDValue B,
                         bool IsSigned) {
  assert(A.getValueType() == MVT::i16 && B.getValueType() == MVT::i16);
  unsigned Op = IsSigned ? C28xISD::SMUL16_32 : C28xISD::UMUL16_32;
  return DAG.getNode(Op, DL, MVT::i32, A, B);
}

// Low and high 16-bit halves of an i32 value.
static void split16(SelectionDAG &DAG, SDLoc DL, SDValue X,
                    SDValue &Lo, SDValue &Hi) {
  Lo = DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, X);
  SDValue T = DAG.getNode(ISD::SRL, DL, MVT::i32, X,
                          DAG.getConstant(16, DL, MVT::i32));
  Hi = DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, T);
}

SDValue C28xTargetLowering::LowerMul(SDNode *N, SelectionDAG &DAG) const {
  SDLoc DL(N);
  unsigned Opc = N->getOpcode();
  bool IsHiU = Opc == ISD::MULHU;
  bool IsHiS = Opc == ISD::MULHS;
  SDValue LHS = N->getOperand(0);
  SDValue RHS = N->getOperand(1);
  if (LHS.getValueType() == MVT::i16) {
    if (IsHiU || IsHiS) {
      SDValue P = makeProd16(DAG, DL, LHS, RHS, IsHiS);
      unsigned Sh = IsHiS ? ISD::SRA : ISD::SRL;
      SDValue T = DAG.getNode(Sh, DL, MVT::i32, P,
                              DAG.getConstant(16, DL, MVT::i32));
      return DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, T);
    }
    // Low 16 of the product.
    SDValue P = makeProd16(DAG, DL, LHS, RHS, /*signed*/ false);
    return DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, P);
  }
  if (IsHiU || IsHiS) {
    // High 32 of a 32x32 -> 64 product: build the (lo,hi) node and take hi.
    unsigned Pair = IsHiS ? ISD::SMUL_LOHI : ISD::UMUL_LOHI;
    EVT RTs[] = {MVT::i32, MVT::i32};
    SDValue Ops[] = {LHS, RHS};
    SDValue PairN = DAG.getNode(Pair, DL, RTs, Ops);
    return PairN.getValue(1);
  }
  // i32 multiply, low 32 via four unsigned 16x16 partial products.  The
  // aH*bH term never reaches the low 32, so it is omitted.
  SDValue aL, aH, bL, bH;
  split16(DAG, DL, LHS, aL, aH);
  split16(DAG, DL, RHS, bL, bH);
  SDValue pLL = makeProd16(DAG, DL, aL, bL, false);
  SDValue pHL = makeProd16(DAG, DL, aH, bL, false);
  SDValue pLH = makeProd16(DAG, DL, aL, bH, false);
  SDValue Cross = DAG.getNode(ISD::ADD, DL, MVT::i32, pHL, pLH);
  SDValue Cross16 = DAG.getNode(ISD::SHL, DL, MVT::i32, Cross,
                                DAG.getConstant(16, DL, MVT::i32));
  return DAG.getNode(ISD::ADD, DL, MVT::i32, pLL, Cross16);
}

SDValue C28xTargetLowering::LowerMulLoHi(SDNode *N, SelectionDAG &DAG) const {
  SDLoc DL(N);
  bool IsSigned = N->getOpcode() == ISD::SMUL_LOHI;
  SDValue LHS = N->getOperand(0);
  SDValue RHS = N->getOperand(1);

  if (LHS.getValueType() == MVT::i16) {
    SDValue P = makeProd16(DAG, DL, LHS, RHS, IsSigned);
    SDValue Lo = DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, P);
    SDValue T = DAG.getNode(ISD::SRL, DL, MVT::i32, P,
                            DAG.getConstant(16, DL, MVT::i32));
    SDValue Hi = DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, T);
    return DAG.getMergeValues({Lo, Hi}, DL);
  }

  // 32x32 -> 64.  Compute the unsigned product with carry tracking, then
  // correct the high word for signed operands.
  SDValue aL, aH, bL, bH;
  split16(DAG, DL, LHS, aL, aH);
  split16(DAG, DL, RHS, bL, bH);
  SDValue pLL = makeProd16(DAG, DL, aL, bL, false);
  SDValue pHL = makeProd16(DAG, DL, aH, bL, false);
  SDValue pLH = makeProd16(DAG, DL, aL, bH, false);
  SDValue pHH = makeProd16(DAG, DL, aH, bH, false);

  SDValue shlHL = DAG.getNode(ISD::SHL, DL, MVT::i32, pHL,
                              DAG.getConstant(16, DL, MVT::i32));
  SDValue low1 = DAG.getNode(ISD::ADD, DL, MVT::i32, pLL, shlHL);
  EVT CCVT = getSetCCResultType(DAG.getDataLayout(), *DAG.getContext(),
                                MVT::i32);
  SDValue c1 = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i32,
                           DAG.getSetCC(DL, CCVT, low1, pLL, ISD::SETULT));
  SDValue shlLH = DAG.getNode(ISD::SHL, DL, MVT::i32, pLH,
                              DAG.getConstant(16, DL, MVT::i32));
  SDValue Low = DAG.getNode(ISD::ADD, DL, MVT::i32, low1, shlLH);
  SDValue c2 = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i32,
                           DAG.getSetCC(DL, CCVT, Low, low1, ISD::SETULT));
  SDValue Hi = DAG.getNode(ISD::ADD, DL, MVT::i32, pHH,
                           DAG.getNode(ISD::SRL, DL, MVT::i32, pHL,
                                       DAG.getConstant(16, DL, MVT::i32)));
  Hi = DAG.getNode(ISD::ADD, DL, MVT::i32, Hi,
                   DAG.getNode(ISD::SRL, DL, MVT::i32, pLH,
                               DAG.getConstant(16, DL, MVT::i32)));
  Hi = DAG.getNode(ISD::ADD, DL, MVT::i32, Hi,
                   DAG.getNode(ISD::ADD, DL, MVT::i32, c1, c2));

  if (IsSigned) {
    // signed = unsigned - (a<0 ? b : 0) - (b<0 ? a : 0) in the high word.
    SDValue Zero = DAG.getConstant(0, DL, MVT::i32);
    SDValue aNeg = DAG.getSetCC(DL, CCVT, LHS, Zero, ISD::SETLT);
    SDValue bNeg = DAG.getSetCC(DL, CCVT, RHS, Zero, ISD::SETLT);
    SDValue ca = DAG.getNode(ISD::SELECT, DL, MVT::i32, aNeg, RHS, Zero);
    SDValue cb = DAG.getNode(ISD::SELECT, DL, MVT::i32, bNeg, LHS, Zero);
    Hi = DAG.getNode(ISD::SUB, DL, MVT::i32, Hi,
                     DAG.getNode(ISD::ADD, DL, MVT::i32, ca, cb));
  }
  return DAG.getMergeValues({Low, Hi}, DL);
}


SDValue C28xTargetLowering::LowerOperation(SDValue Op,
                                          SelectionDAG &DAG) const {
  switch (Op.getOpcode()) {
  case ISD::BR_CC:
  case ISD::BRCOND: {
    SDLoc DL(Op);
    SDValue Chain, LHS, RHS, TrueBB;
    ISD::CondCode CC;
    if (Op.getOpcode() == ISD::BR_CC) {
      Chain = Op.getOperand(0);
      CC = cast<CondCodeSDNode>(Op.getOperand(1))->get();
      LHS = Op.getOperand(2);
      RHS = Op.getOperand(3);
      TrueBB = Op.getOperand(4);
    } else {
      SDValue Cond = Op.getOperand(1);
      Chain = Op.getOperand(0);
      TrueBB = Op.getOperand(2);
      if (Cond.getOpcode() == ISD::SETCC) {
        LHS = Cond.getOperand(0);
        RHS = Cond.getOperand(1);
        CC = cast<CondCodeSDNode>(Cond.getOperand(2))->get();
      } else {
        // Condition is a boolean value (e.g. masked i1). Compare against 0.
        LHS = Cond;
        RHS = DAG.getConstant(0, DL, Cond.getValueType());
        CC = ISD::SETNE;
      }
    }
    unsigned CondEnc = condToEnc(CC);
    SDValue CCOp = DAG.getConstant(CondEnc, DL, MVT::i16);
    return DAG.getNode(C28xISD::BRCOND, DL, MVT::Other,
                      {Chain, TrueBB, CCOp, LHS, RHS});
  }
  case ISD::GlobalAddress: {
    const GlobalAddressSDNode *GA = cast<GlobalAddressSDNode>(Op);
    SDLoc GA_DL(Op);
    EVT PtrVT = getPointerTy(DAG.getDataLayout());
    // TI relocates the bare symbol in physical WORD units. WRAPPER doubles
    // that address. Apply the Rust BYTE offset afterwards, including odd
    // and negative offsets; it must never be folded into the TI relocation.
    SDValue Target = DAG.getTargetGlobalAddress(GA->getGlobal(), GA_DL, PtrVT, 0);
    SDValue Base = DAG.getNode(C28xISD::WRAPPER, GA_DL, PtrVT, Target);
    int64_t Off = GA->getOffset();
    if (Off == 0)
      return Base;
    // Offsets may be negative; LLVM 23 has no int64 getConstant overload, so
    // build the negative case through an explicitly-signed APInt.
    SDValue OffVal = (Off >= 0)
        ? DAG.getConstant((uint64_t)Off, GA_DL, PtrVT)
        : DAG.getConstant(APInt(PtrVT.getSizeInBits(), Off, true),
                          GA_DL, PtrVT);
    return DAG.getNode(ISD::ADD, GA_DL, PtrVT, Base, OffVal);
  }
  case ISD::ExternalSymbol: {
    const ExternalSymbolSDNode *ES = cast<ExternalSymbolSDNode>(Op);
    SDLoc ES_DL(Op);
    EVT PtrVT = getPointerTy(DAG.getDataLayout());
    SDValue Target = DAG.getTargetExternalSymbol(ES->getSymbol(), PtrVT);
    return DAG.getNode(C28xISD::WRAPPER, ES_DL, PtrVT, Target);
  }
  case ISD::SELECT: {
    // Convert select cond, true, false -> select_cc cond, 0, true, false, SETNE
    SDValue Cond = Op.getOperand(0);
    SDValue TrueVal = Op.getOperand(1);
    SDValue FalseVal = Op.getOperand(2);
    SDLoc DL(Op);
    EVT VT = Cond.getValueType();
    SDValue Zero = DAG.getConstant(0, DL, VT);
    return DAG.getSelectCC(DL, Cond, Zero, TrueVal, FalseVal, ISD::SETNE);
  }
  case ISD::SELECT_CC: {
    SDValue LHS = Op.getOperand(0);
    SDValue RHS = Op.getOperand(1);
    SDValue TrueVal = Op.getOperand(2);
    SDValue FalseVal = Op.getOperand(3);
    ISD::CondCode CC = cast<CondCodeSDNode>(Op.getOperand(4))->get();
    SDLoc DL(Op);
    unsigned CondEnc = condToEnc(CC);
    SDValue CondOp = DAG.getConstant(CondEnc, DL, MVT::i16);
    SDValue Ops[] = {TrueVal, FalseVal, CondOp, LHS, RHS};
    return DAG.getNode(C28xISD::SELECT_CC, DL, Op.getValueType(), Ops);
  }
  case ISD::SETCC: {
    SDValue LHS = Op.getOperand(0);
    SDValue RHS = Op.getOperand(1);
    ISD::CondCode CC = cast<CondCodeSDNode>(Op.getOperand(2))->get();
    SDLoc DL(Op);
    unsigned CondEnc = condToEnc(CC);
    SDValue CondOp = DAG.getConstant(CondEnc, DL, MVT::i16);
    SDValue One = DAG.getConstant(1, DL, Op.getValueType());
    SDValue Zero = DAG.getConstant(0, DL, Op.getValueType());
    SDValue Ops[] = {One, Zero, CondOp, LHS, RHS};
    return DAG.getNode(C28xISD::SELECT_CC, DL, Op.getValueType(), Ops);
  }
  case ISD::SHL_PARTS:
  case ISD::SRL_PARTS:
  case ISD::SRA_PARTS:
    return LowerShiftParts(Op.getNode(), DAG);
  case ISD::UMUL_LOHI:
  case ISD::SMUL_LOHI:
    return LowerMulLoHi(Op.getNode(), DAG);
  case ISD::SHL:
  case ISD::SRL:
  case ISD::SRA: {
    SDLoc DL(Op);
    SDValue LHS = Op.getOperand(0);
    SDValue Amt = Op.getOperand(1);
    EVT VT = Op.getValueType();
    // i16 shifts: promote to i32, shift, truncate.
    if (VT == MVT::i16) {
      // Right shifts can move the upper half into the observable low half.
      // Preserve the i16 sign for SRA and clear the upper half for SRL;
      // ANY_EXTEND is only safe for SHL, whose upper bits are discarded.
      unsigned ExtOp = Op.getOpcode() == ISD::SRA ? ISD::SIGN_EXTEND
                     : Op.getOpcode() == ISD::SRL ? ISD::ZERO_EXTEND
                     : ISD::ANY_EXTEND;
      SDValue Ext = DAG.getNode(ExtOp, DL, MVT::i32, LHS);
      SDValue Amt32 = (Amt.getValueType() == MVT::i32) ? Amt :
          DAG.getNode(ISD::ANY_EXTEND, DL, MVT::i32, Amt);
      SDValue Shift = DAG.getNode(Op.getOpcode(), DL, MVT::i32, Ext, Amt32);
      return DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, Shift);
    }
    // Normalize the amount to i32.
    if (Amt.getValueType() != MVT::i32)
      Amt = DAG.getNode(ISD::ANY_EXTEND, DL, MVT::i32, Amt);
    // i32 constant shifts: route through the hardware T-count shift pseudo so
    // any count is a few instructions instead of being unrolled one bit per
    // ADD (SHL) / ROR (SRL).  The VAR pseudo postRA materializes the constant
    // count into T (MOV T,AR7) then runs LSLL/LSRL/ASRL ACC,T.
    if (ConstantSDNode *C = dyn_cast<ConstantSDNode>(Amt)) {
      unsigned A = (unsigned)C->getZExtValue();
      if (A == 0)
        return LHS; // shift by zero is identity
      if (Op.getOpcode() == ISD::SRA) {
        // Arithmetic shift by >= 31 replicates the sign bit across all 32 bits.
        A = std::min(A, 31u);
      } else if (A >= 32) {
        // Logical/left shift by the width (or more) yields zero.
        return DAG.getConstant(0, DL, MVT::i32);
      }
      unsigned Opc = Op.getOpcode() == ISD::SHL ? C28xISD::SHL32_VAR
                   : Op.getOpcode() == ISD::SRL ? C28xISD::SRL32_VAR
                   : C28xISD::SRA32_VAR;
      return DAG.getNode(Opc, DL, MVT::i32, LHS,
                         DAG.getConstant(A, DL, MVT::i32));
    }
    // i32 variable shift: mask the amount to 0..31 and use the hardware
    // LSLL/LSRL/ASRL ACC,T through the wide variable-shift pseudo.
    SDValue Masked = DAG.getNode(ISD::AND, DL, MVT::i32, Amt,
                                 DAG.getConstant(31, DL, MVT::i32));
    unsigned Opc = Op.getOpcode() == ISD::SHL ? C28xISD::SHL32_VAR
                 : Op.getOpcode() == ISD::SRL ? C28xISD::SRL32_VAR
                 : C28xISD::SRA32_VAR;
    return DAG.getNode(Opc, DL, MVT::i32, LHS, Masked);
  }
  case ISD::MUL:
  case ISD::MULHU:
  case ISD::MULHS:
    return LowerMul(Op.getNode(), DAG);
  case ISD::SMULO:
  case ISD::UMULO:
    return LowerXMULO(Op.getNode(), DAG);
  default:
    break;
  }
  report_fatal_error("C28x: unsupported operation to lower");
}

SDValue C28xTargetLowering::LowerXMULO(SDNode *N, SelectionDAG &DAG) const {
  EVT VT = N->getValueType(0);
  bool Signed = (N->getOpcode() == ISD::SMULO);
  SDLoc dl(N);
  SDValue A = N->getOperand(0), B = N->getOperand(1);
  EVT BoolVT = N->getValueType(1);

  // Multiply two i64 values into four i32 parts (low->high) via __multi3.
  auto mul64 = [&](SDValue X, SDValue Y, SDValue P[4]) {
    SDValue ZX = DAG.getNode(ISD::ZERO_EXTEND, dl, MVT::i128, X);
    SDValue ZY = DAG.getNode(ISD::ZERO_EXTEND, dl, MVT::i128, Y);
    RTLIB::LibcallImpl Impl =
        DAG.getLibcalls().getLibcallImpl(RTLIB::MUL_I128);
    MakeLibCallOptions O;
    O.setIsSigned(false);
    O.setIsPostTypeLegalization(true);
    SDValue R = makeLibCall(DAG, Impl, MVT::i128, {ZX, ZY}, O, dl).first;
    assert(R.getOpcode() == ISD::MERGE_VALUES && R.getNumOperands() == 4 &&
           "expected four i32 parts from __multi3");
    for (unsigned i = 0; i < 4; ++i)
      P[i] = R.getOperand(i);
  };
  auto pair64 = [&](SDValue Lo, SDValue Hi) {
    return DAG.getNode(ISD::BUILD_PAIR, dl, MVT::i64, Lo, Hi);
  };
  auto pair128 = [&](SDValue Lo, SDValue Hi) {
    return DAG.getNode(ISD::BUILD_PAIR, dl, MVT::i128, Lo, Hi);
  };

  SDValue Lo, Hi;
  if (VT == MVT::i64) {
    SDValue P[4];
    mul64(A, B, P);
    Lo = pair64(P[0], P[1]);
    Hi = pair64(P[2], P[3]);
  } else {
    assert(VT == MVT::i128 && "unexpected XMULO width");
    // Split operands into i64 halves.
    SDValue ALo = DAG.getNode(ISD::TRUNCATE, dl, MVT::i64, A);
    SDValue AHi = DAG.getNode(ISD::TRUNCATE, dl, MVT::i64,
                    DAG.getNode(ISD::SRL, dl, MVT::i128, A,
                      DAG.getShiftAmountConstant(64, MVT::i128, dl)));
    SDValue BLo = DAG.getNode(ISD::TRUNCATE, dl, MVT::i64, B);
    SDValue BHi = DAG.getNode(ISD::TRUNCATE, dl, MVT::i64,
                    DAG.getNode(ISD::SRL, dl, MVT::i128, B,
                      DAG.getShiftAmountConstant(64, MVT::i128, dl)));
    SDValue p0[4], p1[4], p2[4], p3[4];
    mul64(ALo, BLo, p0);
    mul64(AHi, BLo, p1);
    mul64(ALo, BHi, p2);
    mul64(AHi, BHi, p3);
    auto mk128 = [&](SDValue q[4]) {
      return pair128(pair64(q[0], q[1]), pair64(q[2], q[3]));
    };
    SDValue v0 = mk128(p0);
    SDValue v1 = mk128(p1);
    SDValue v2 = mk128(p2);
    SDValue v3 = mk128(p3);

    SDValue Zero64 = DAG.getConstant(0, dl, MVT::i64);
    SDValue Zero128 = DAG.getConstant(0, dl, MVT::i128);
    EVT CarryVT = getSetCCResultType(DAG.getDataLayout(), *DAG.getContext(),
                                     MVT::i128);

    // Accumulate the unsigned 256-bit product in (Lo128, Hi128), without ever
    // forming an i256 value.
    Lo = v0;
    Hi = Zero128;

    auto addShifted64 = [&](SDValue q[4]) {
      // q << 64: low128 addend = (0, q.lo64); q.hi64 accumulates into Hi.
      SDValue qLo = pair64(q[0], q[1]);
      SDValue qHi = pair64(q[2], q[3]);
      SDValue AddLo = pair128(Zero64, qLo);
      SDValue NewLo = DAG.getNode(ISD::ADD, dl, MVT::i128, Lo, AddLo);
      SDValue Carry = DAG.getSetCC(dl, CarryVT, NewLo, AddLo, ISD::SETULT);
      Lo = NewLo;
      Hi = DAG.getNode(ISD::ADD, dl, MVT::i128, Hi,
             DAG.getNode(ISD::ZERO_EXTEND, dl, MVT::i128, Carry));
      Hi = DAG.getNode(ISD::ADD, dl, MVT::i128, Hi,
             DAG.getNode(ISD::ZERO_EXTEND, dl, MVT::i128, qHi));
    };
    addShifted64(p1);
    addShifted64(p2);
    // p3 << 128 lands entirely in Hi (added last; the unsigned high half always
    // fits in 128 bits).
    Hi = DAG.getNode(ISD::ADD, dl, MVT::i128, Hi, v3);

    if (Signed) {
      // Signed product = unsigned product, correcting the high half by
      // subtracting the other operand whenever an input is negative.
      SDValue ANeg = DAG.getSetCC(dl, CarryVT, A, Zero128, ISD::SETLT);
      SDValue Corr1 = DAG.getSelect(dl, MVT::i128, ANeg, B, Zero128);
      SDValue BNeg = DAG.getSetCC(dl, CarryVT, B, Zero128, ISD::SETLT);
      SDValue Corr2 = DAG.getSelect(dl, MVT::i128, BNeg, A, Zero128);
      Hi = DAG.getNode(ISD::SUB, dl, MVT::i128, Hi, Corr1);
      Hi = DAG.getNode(ISD::SUB, dl, MVT::i128, Hi, Corr2);
    }
  }

  // Overflow flag.
  SDValue Ovf;
  if (Signed) {
    SDValue Sign = DAG.getNode(ISD::SRA, dl, VT, Lo,
                    DAG.getShiftAmountConstant(VT.getScalarSizeInBits() - 1,
                                               VT, dl));
    Ovf = DAG.getSetCC(dl, BoolVT, Hi, Sign, ISD::SETNE);
  } else {
    SDValue Zero = DAG.getConstant(0, dl, VT);
    Ovf = DAG.getSetCC(dl, BoolVT, Hi, Zero, ISD::SETNE);
  }
  return DAG.getMergeValues({Lo, Ovf}, dl);
}

void C28xTargetLowering::ReplaceNodeResults(SDNode *N,
                                            SmallVectorImpl<SDValue> &Results,
                                            SelectionDAG &DAG) const {
  switch (N->getOpcode()) {
  case ISD::SMULO:
  case ISD::UMULO: {
    SDValue R = LowerXMULO(N, DAG); // MERGE_VALUES: value, overflow
    assert(R.getOpcode() == ISD::MERGE_VALUES && R.getNumOperands() == 2);
    Results.push_back(R.getOperand(0));
    Results.push_back(R.getOperand(1));
    return;
  }
  default:
    TargetLowering::ReplaceNodeResults(N, Results, DAG);
  }
}


//===----------------------------------------------------------------------===//
// Custom C28x argument calling convention.
//
// The TI C28x EABI (verified against cl2000 -v28 --abi=eabi disassembly) uses a
// slot model with dedicated pools for pointers, 32-bit and 16-bit integers:
//
//   Pointer pool:  sret -> XAR6; pointer args -> XAR4, XAR5; overflow -> stack
//   32-bit pool:   first i32 -> ACC; overflow -> stack (4 bytes)
//   16-bit slots:  AL, AH, AR4, AR5 (shared with the pointer pool's AR4/AR5)
//
// The critical mixed rule (confirmed by oracle): whenever the argument list
// contains ANY 32-bit argument, the first 32-bit argument takes ACC, and ALL
// 16-bit arguments skip slots 0-1 (AL/AH) entirely, starting at AR4.  This
// prevents a 16-bit argument from stealing AL/AH and overlapping ACC.
//
//   (i16 a, i32 b)          -> a=AR4, b=ACC
//   (i32 a, i16 b)          -> a=ACC, b=AR4
//   (i16 a, i16 b, i32 c)   -> a=AR4, b=AR5, c=ACC
//   (i32 a, i16 b, i16 c)   -> a=ACC, b=AR4, c=AR5
//   (i16 a, i32 b, i16 c)   -> a=AR4, b=ACC, c=AR5
//
// Pointer arguments (references, raw pointers, function pointers, and the
// by-value struct pointer produced for aggregate arguments) never use ACC:
//   (ptr a, i32 b)          -> a=XAR4, b=ACC
//   (ptr a, ptr b)          -> a=XAR4, b=XAR5
//   (ptr a, i16 b)          -> a=XAR4, b=AL        (no i32: AL/AH stay free)
//   (i16 a, ptr p, i32 b)   -> a=AR5, p=XAR4, b=ACC (AR4 taken by pointer)
//   sret (hidden return buffer) -> XAR6
// Indirect calls load the callee from a pointer register: LCR *XARn.
//
// The generated CC_C28x from C28xCallingConv.td uses independent CCIfType
// lists, so a leading i16 allocates AL (marking ACC as an alias), which then
// blocks the later i32 from ACC and wrongly pushes it to the stack.  This
// custom function implements the correct slot model.
//===----------------------------------------------------------------------===//

namespace {
struct C28xCCAllocState {
  bool HasI32Arg = false;  // pre-scanned: does the arg list contain i32?
  bool ACCTaken = false;   // has ACC been handed to the first i32 arg?
  unsigned Next16Slot = 0;  // index into the 16-bit slot table (0..3, then stack)
  unsigned PtrSlotsUsed = 0; // pre-scanned pointer args (reserve XAR4/XAR5)
};
static thread_local C28xCCAllocState C28xCCState;
} // namespace

// 16-bit argument slots in allocation order.  When HasI32Arg is true, the
// counter starts at slot 2 (AR4) so AL/AH stay reserved for ACC.
static const MCPhysReg C28x16Slots[] = {
  C28x::AL, C28x::AH, C28x::AR4, C28x::AR5
};

static bool CC_C28x_Custom(unsigned ValNo, MVT ValVT, MVT LocVT,
                           CCValAssign::LocInfo LocInfo,
                           ISD::ArgFlagsTy ArgFlags, Type *OrigTy,
                           CCState &State) {
  // Pointer pool.  A pointer argument is any argument whose ISel type is a
  // pointer: references, raw pointers, function pointers and the implicit
  // struct-by-value pointer.  ISD::ArgFlagsTy::isPointer() is set by
  // SelectionDAGBuilder for both outgoing call operands and incoming formal
  // arguments (SelectionDAGBuilder.cpp: setPointer() when ArgTy->isPointerTy()).
  //
  // The hidden sret pointer (struct return buffer) has a dedicated register,
  // XAR6, separate from the XAR4/XAR5 argument pool (verified: cl2000
  // materialises the return-buffer address with MOVL XAR6,#sym before LCR).
  if (ArgFlags.isSRet()) {
    if (!State.isAllocated(C28x::XAR6)) {
      State.AllocateReg(C28x::XAR6);
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, C28x::XAR6, LocVT, LocInfo));
      return false;
    }
    // A second sret cannot happen in well-formed IR; fall through to the
    // pointer pool instead of failing the whole function.
  }

  if (ArgFlags.isPointer()) {
    static const MCPhysReg PtrSlots[] = {C28x::XAR4, C28x::XAR5};
    for (MCPhysReg Reg : PtrSlots) {
      if (!State.isAllocated(Reg)) {
        State.AllocateReg(Reg); // marks Reg + aliases (AR4/AR5 subregs)
        State.addLoc(
            CCValAssign::getReg(ValNo, ValVT, Reg, LocVT, LocInfo));
        return false;
      }
    }
    // Out of pointer registers -> stack (4 bytes, 2-byte aligned).  The
    // pointer never falls back to ACC: TI passes pointers in XAR4/XAR5 only.
    int64_t Off = State.AllocateStack(4, Align(4));
    State.addLoc(CCValAssign::getMem(ValNo, ValVT, Off, LocVT, LocInfo));
    return false;
  }

  if (LocVT == MVT::i32) {
    if (!C28xCCState.ACCTaken) {
      C28xCCState.ACCTaken = true;
      State.AllocateReg(C28x::ACC); // marks ACC + aliases AL/AH
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, C28x::ACC, LocVT, LocInfo));
      return false;
    }
    // Second+ 32-bit argument -> stack (4 bytes, 2-byte aligned).
    int64_t Off = State.AllocateStack(4, Align(4));
    State.addLoc(CCValAssign::getMem(ValNo, ValVT, Off, LocVT, LocInfo));
    return false;
  }

  if (LocVT == MVT::i16) {
    // If there's an i32 argument, AL/AH are reserved for ACC; start at AR4.
    if (C28xCCState.HasI32Arg && C28xCCState.Next16Slot < 2)
      C28xCCState.Next16Slot = 2;
    // Skip slots taken by the pointer pool.  Pointers reserve XAR4/XAR5
    // before any 16-bit argument is placed (oracle: a pointer always lands in
    // XAR4 even when an earlier i16 argument exists), so the first
    // PtrSlotsUsed pointer slots are occupied regardless of argument order.
    // XAR4/XAR5 alias AR4/AR5, i.e. 16-bit slots 2 and 3.
    while (C28xCCState.Next16Slot < 4) {
      unsigned Slot = C28xCCState.Next16Slot;
      bool PtrReserved = Slot >= 2 && (Slot - 2) < C28xCCState.PtrSlotsUsed;
      if (!PtrReserved && !State.isAllocated(C28x16Slots[Slot]))
        break;
      C28xCCState.Next16Slot++;
    }
    if (C28xCCState.Next16Slot < 4) {
      MCPhysReg Reg = C28x16Slots[C28xCCState.Next16Slot++];
      State.AllocateReg(Reg); // marks Reg + aliases
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, Reg, LocVT, LocInfo));
      return false;
    }
    // Out of 16-bit registers -> stack (2 bytes).
    int64_t Off = State.AllocateStack(2, Align(2));
    State.addLoc(CCValAssign::getMem(ValNo, ValVT, Off, LocVT, LocInfo));
    return false;
  }

  return true; // unhandled type
}

SDValue C28xTargetLowering::LowerCall(CallLoweringInfo &CLI,
                                      SmallVectorImpl<SDValue> &InVals) const {
  SelectionDAG &DAG = CLI.DAG;
  SDLoc &DL = CLI.DL;
  SmallVectorImpl<ISD::OutputArg> &Outs = CLI.Outs;
  SmallVectorImpl<SDValue> &OutVals = CLI.OutVals;
  SmallVectorImpl<ISD::InputArg> &Ins = CLI.Ins;
  SDValue &Chain = CLI.Chain;
  SDValue Callee = CLI.Callee;
  CallingConv::ID CallConv = CLI.CallConv;
  bool IsVarArg = CLI.IsVarArg;

  // C28x does not implement sibcall/tail-call lowering.  A tail call is only an
  // optimization, so lower it as an ordinary call that returns InVals to this
  // frame (otherwise SelectionDAGBuilder asserts that a tail call produced a
  // return value).
  CLI.IsTailCall = false;

  // Memory libcalls (c28x_memcpy / c28x_memmove / c28x_memset / c28x_memcmp /
  // c28x_bcmp) are implemented by our runtime crate and receive 32-bit logical
  // BYTE addresses, matching Rust's pointer model (see C28X_MEMORY_MODEL.md).
  // Constant-size copies are expanded inline by findOptimalMemOpLowering; only
  // a runtime-size copy reaches this call.  No byte->word address conversion is
  // performed here: the pointer arguments are passed through unchanged so the
  // byte-address implementation dereferences them correctly.  (Earlier code
  // converted these to TI C WORD addresses, which only matched TI's rts2800
  // memcpy; that corrupted every Rust-side runtime-size copy because our
  // runtime memcpy is byte-address.)

  MachineFunction &MF = DAG.getMachineFunction();
  SmallVector<CCValAssign, 16> ArgLocs;
  CCState CCInfo(CallConv, IsVarArg, MF, ArgLocs, *DAG.getContext());
  // Pre-scan: if any outgoing INTEGER argument is i32, reserve AL/AH for ACC.
  // Pointer arguments also carry LocVT i32 but use the XAR4/XAR5/XAR6 pool,
  // so they must NOT trigger the 16-bit skip rule.  Reserve the pointer slots
  // up front: TI places pointer arguments in XAR4/XAR5 even when an earlier
  // 16-bit argument exists (the i16 then moves to AR5).
  C28xCCState = C28xCCAllocState();
  for (const ISD::OutputArg &Out : Outs) {
    if (Out.VT == MVT::i32 && !Out.Flags.isPointer() && !Out.Flags.isSRet())
      C28xCCState.HasI32Arg = true;
    if (Out.Flags.isPointer())
      C28xCCState.PtrSlotsUsed++;
  }
  CCInfo.AnalyzeCallOperands(Outs, CC_C28x_Custom);

  // Narrow IR arguments occupy an i16 ABI slot. Do not leak the upper bits
  // of a promoted truncation (e.g. trunc i16 0x8000 to i8) into the callee.
  // AExt permits either extension, so use zero extension unless the IR
  // explicitly requests sign extension.
  SmallVector<SDValue, 16> CallVals(OutVals.begin(), OutVals.end());
  for (unsigned I = 0; I != Outs.size(); ++I) {
    EVT ArgVT = Outs[I].ArgVT;
    if (CallVals[I].getValueType() != MVT::i16 || !ArgVT.isScalarInteger() ||
        ArgVT.getSizeInBits() >= 16)
      continue;
    if (Outs[I].Flags.isSExt())
      CallVals[I] = DAG.getNode(ISD::SIGN_EXTEND_INREG, DL, MVT::i16,
                               CallVals[I], DAG.getValueType(ArgVT));
    else
      CallVals[I] = DAG.getZeroExtendInReg(CallVals[I], DL, ArgVT);
  }

  // Compute total outgoing stack area (bytes).
  unsigned StackBytes = 0;
  for (const CCValAssign &VA : ArgLocs) {
    if (VA.isMemLoc()) {
      unsigned End = VA.getLocMemOffset() + VA.getLocVT().getStoreSize();
      StackBytes = std::max(StackBytes, End);
    }
  }

  // TI callers must present an even SP, including odd numbers of u16 args.
  StackBytes = (StackBytes + 3) & ~3U;

  // Reserve outgoing arg area on the stack.  The area is [SP-StackWords..SP-1]
  // of the ADJUSTED SP (post-ADJCALLSTACKDOWN), which places the first stack
  // word at SP_entry-3 -- the position measured for TI's own callers (see
  // tools/probe-ti-stack.c).
  // NOTE (tried and reverted 2026-10-20): reserving StackBytes + 4 to make room
  // for the two-word return address also requires ALL the stack-argument
  // store offsets to move, and desynchronises ADJCALLSTACKDOWN/UP; the arg
  // positions are already correct without it.
  SDValue Glue;
  if (StackBytes > 0)
    Chain = DAG.getCALLSEQ_START(Chain, StackBytes, 0, DL);

  // Pass 1: stack arguments via target pseudo (post-RA address formation).
  // TI EABI layout (measured on target with tools/probe-ti-stack.c + DSS
  // dumps): the caller places the FIRST stack word at SP-1 (the return
  // address is pushed ABOVE it by LCR, ending at SP_entry-1/-2), later words
  // follow downward.  Writing them at SP-(StackWords-w) instead put the
  // arguments on top of the return address (observed: the second i32 of
  // make_pair never arrived, which is why the sret self-check failed).
  unsigned StackWords = StackBytes / 2;
  if (StackBytes > 0) {
    for (unsigned I = 0, E = ArgLocs.size(); I != E; ++I) {
      CCValAssign &VA = ArgLocs[I];
      if (!VA.isMemLoc()) continue;
      int SignedOff = -1 - (int)(VA.getLocMemOffset() / 2);
      // Encode the signed offset as its 16-bit two's-complement pattern.
      SDValue WordOff =
          DAG.getConstant((uint16_t)(int16_t)SignedOff, DL, MVT::i16);
      SDValue Val = CallVals[I];
      if (VA.getLocVT() == MVT::i32) {
        // A 32-bit stack argument occupies two words; STORE_STK16 stores one.
        // Measured TI layout on target (driver probe rust_stk32_echo, value
        // 0x12345678): the HIGH half sits at the first word (offset o, the
        // one closest to the return address) and the LOW half one word below
        // it -- byte-wise that is the value's low byte at the lower address,
        // matching the C28x MOVL long access the TI callees use.
        SDValue Lo = DAG.getNode(ISD::TRUNCATE, DL, MVT::i16, Val);
        SDValue Hi = DAG.getNode(
            ISD::TRUNCATE, DL, MVT::i16,
            DAG.getNode(ISD::SRL, DL, MVT::i32, Val,
                        DAG.getConstant(16, DL, MVT::i32)));
        // The low half sits one word BELOW the high half (the stack grows up,
        // so the next word of the argument is at a lower address).
        SDValue WordOffLo = DAG.getConstant(
            (uint16_t)(int16_t)(SignedOff - 1), DL, MVT::i16);
        Chain = DAG.getNode(C28xISD::STORE_STK16, DL, MVT::Other, Chain, Hi,
                            WordOff);
        Chain = DAG.getNode(C28xISD::STORE_STK16, DL, MVT::Other, Chain, Lo,
                            WordOffLo);
      } else {
        Chain = DAG.getNode(C28xISD::STORE_STK16, DL, MVT::Other, Chain, Val,
                            WordOff);
      }
    }
  }

  // Pass 2: register arguments (glue-serialised, chain from stack stores).
  for (unsigned I = 0, E = ArgLocs.size(); I != E; ++I) {
    CCValAssign &VA = ArgLocs[I];
    if (!VA.isRegLoc()) continue;
    Chain = DAG.getCopyToReg(Chain, DL, VA.getLocReg(), CallVals[I], Glue);
    Glue = Chain.getValue(1);
  }

  if (Callee.getOpcode() == ISD::GlobalAddress) {
    const GlobalValue *GV = cast<GlobalAddressSDNode>(Callee)->getGlobal();
    Callee = DAG.getTargetGlobalAddress(GV, DL,
                                       getPointerTy(DAG.getDataLayout()));
  }
  if (Callee.getOpcode() == ISD::ExternalSymbol) {
    const char *Sym = cast<ExternalSymbolSDNode>(Callee)->getSymbol();
    Callee = DAG.getTargetExternalSymbol(Sym,
                                         getPointerTy(DAG.getDataLayout()));
  }

  SmallVector<SDValue, 8> Ops;
  Ops.push_back(Chain);
  Ops.push_back(Callee);
  Ops.push_back(DAG.getRegisterMask(STI.getRegisterInfo()->getCallPreservedMask(MF, CallConv)));
  for (const CCValAssign &VA : ArgLocs)
    if (VA.isRegLoc())
      Ops.push_back(DAG.getRegister(VA.getLocReg(), VA.getLocVT()));
  if (Glue) Ops.push_back(Glue);
  SDValue Call = DAG.getNode(C28xISD::CALL, DL,
                             DAG.getVTList(MVT::Other, MVT::Glue), Ops);
  Chain = Call.getValue(0);
  Glue = Call.getValue(1);

  // Release outgoing arg area. CALLSEQ_END propagates the call's glue so the
  // result copies are glued to CALLSEQ_END (not directly to the CALL), which
  // keeps the scheduler's glue clusters acyclic.
  if (StackBytes > 0) {
    Chain = DAG.getCALLSEQ_END(Chain, StackBytes, 0, Glue, DL);
    Glue = Chain.getValue(1);
  }

  SmallVector<CCValAssign, 4> RVLocs;
  CCState RVInfo(CallConv, IsVarArg, MF, RVLocs, *DAG.getContext());
  RVInfo.AnalyzeCallResult(Ins, RetCC_C28x);
  for (unsigned I = 0, E = RVLocs.size(); I != E; ++I) {
    CCValAssign &VA = RVLocs[I];
    SDValue Res = DAG.getCopyFromReg(Chain, DL, VA.getLocReg(),
                                     VA.getLocVT(), Glue);
    InVals.push_back(Res);
    Chain = Res.getValue(1);
    Glue = Res.getValue(2);
  }
  return Chain;
}

SDValue C28xTargetLowering::LowerFormalArguments(
    SDValue Chain, CallingConv::ID CallConv, bool IsVarArg,
    const SmallVectorImpl<ISD::InputArg> &Ins, const SDLoc &DL,
    SelectionDAG &DAG, SmallVectorImpl<SDValue> &InVals) const {
  if (IsVarArg)
    report_fatal_error("C28x does not support variadic functions");

  MachineFunction &MF = DAG.getMachineFunction();
  MachineRegisterInfo &MRI = MF.getRegInfo();
  SmallVector<CCValAssign, 8> ArgLocs;
  CCState CCInfo(CallConv, IsVarArg, MF, ArgLocs, *DAG.getContext());
  // Pre-scan: if any formal INTEGER argument is i32, reserve AL/AH for ACC.
  // Pointer formals carry LocVT i32 as well but use the pointer pool.
  C28xCCState = C28xCCAllocState();
  for (const ISD::InputArg &In : Ins) {
    if (In.VT == MVT::i32 && !In.Flags.isPointer() && !In.Flags.isSRet())
      C28xCCState.HasI32Arg = true;
    if (In.Flags.isPointer())
      C28xCCState.PtrSlotsUsed++;
  }
  CCInfo.AnalyzeFormalArguments(Ins, CC_C28x_Custom);

  for (const CCValAssign &VA : ArgLocs) {
    EVT LocVT = VA.getLocVT();
    if (VA.isRegLoc()) {
      const TargetRegisterClass *RC = LocVT == MVT::i32
                                          ? &C28x::GPR32RegClass
                                          : &C28x::GR16RegClass;
      Register VReg = MRI.createVirtualRegister(RC);
      MRI.addLiveIn(VA.getLocReg(), VReg);
      InVals.push_back(DAG.getCopyFromReg(Chain, DL, VReg, LocVT));
      continue;
    }
    assert(VA.isMemLoc() && "unsupported C28x argument location");
    unsigned Size = LocVT.getStoreSize();
    int FI = MF.getFrameInfo().CreateFixedObject(Size, VA.getLocMemOffset(), true);
    if (LocVT == MVT::i32) {
      // A 32-bit stack argument occupies two words, and the caller writes the
      // HIGH half at the first word (closest to the return address) and the
      // LOW half one word BELOW it (measured: rust_stk32_echo with
      // 0x12345678 reads hi at SP_entry-3, lo at SP_entry-4).  The generic
      // 32-bit frame load reads its low word at the base and its high word
      // one word UP, so anchoring the fixed object at byte offset+2 -- the
      // LOW word -- makes the +1 land exactly on the high half.  Anchoring at
      // offset+0 instead read the RETURN ADDRESS as the high half (measured:
      // the sret sample's `len` came back with a code address).
      int FI =
          MF.getFrameInfo().CreateFixedObject(2, VA.getLocMemOffset() + 2, true);
      SDValue FIN = DAG.getFrameIndex(FI, getPointerTy(DAG.getDataLayout()));
      InVals.push_back(DAG.getLoad(MVT::i32, DL, Chain, FIN,
                                   MachinePointerInfo::getFixedStack(MF, FI)));
      continue;
    }
    SDValue FIN = DAG.getFrameIndex(FI, getPointerTy(DAG.getDataLayout()));
    InVals.push_back(DAG.getLoad(LocVT, DL, Chain, FIN,
                                 MachinePointerInfo::getFixedStack(MF, FI)));
  }
  return Chain;
}

bool C28xTargetLowering::CanLowerReturn(CallingConv::ID CallConv,
                                        MachineFunction &MF, bool IsVarArg,
                                        const SmallVectorImpl<ISD::OutputArg> &Outs,
                                        LLVMContext &Context, const Type *RetTy) const {
  SmallVector<CCValAssign, 4> RVLocs;
  CCState CCInfo(CallConv, IsVarArg, MF, RVLocs, Context);
  bool Ok = CCInfo.CheckReturn(Outs, RetCC_C28x);
  return Ok;
}

SDValue C28xTargetLowering::LowerReturn(
    SDValue Chain, CallingConv::ID CallConv, bool IsVarArg,
    const SmallVectorImpl<ISD::OutputArg> &Outs,
    const SmallVectorImpl<SDValue> &OutVals, const SDLoc &DL,
    SelectionDAG &DAG) const {
  MachineFunction &MF = DAG.getMachineFunction();
  SmallVector<CCValAssign, 4> RVLocs;
  CCState CCInfo(CallConv, IsVarArg, MF, RVLocs, *DAG.getContext());
  CCInfo.AnalyzeReturn(Outs, RetCC_C28x);

  SDValue Glue;
  SmallVector<SDValue, 4> RetOps{Chain};
  for (unsigned I = 0; I != RVLocs.size(); ++I) {
    const CCValAssign &VA = RVLocs[I];
    Chain = DAG.getCopyToReg(Chain, DL, VA.getLocReg(), OutVals[I], Glue);
    Glue = Chain.getValue(1);
    RetOps[0] = Chain;
    RetOps.push_back(DAG.getRegister(VA.getLocReg(), VA.getLocVT()));
  }
  if (Glue) RetOps.push_back(Glue);
  // Interrupt handlers return with IRET after software context restoration.
  // Triggered by the c28x-interrupt calling convention (CC 92) or the
  // LLVM "interrupt" function attribute.
  bool IsInterrupt =
      static_cast<unsigned>(CallConv) == C28xCC::Interrupt ||
      MF.getFunction().hasFnAttribute("interrupt");
  unsigned RetNode = IsInterrupt ? C28xISD::IRET_GLUE : C28xISD::RET_GLUE;
  return DAG.getNode(RetNode, DL, MVT::Other, RetOps);
}

MachineBasicBlock *C28xTargetLowering::EmitInstrWithCustomInserter(MachineInstr &MI,
                                                      MachineBasicBlock *BB) const {
  const C28xInstrInfo &TII = *STI.getInstrInfo();
  switch (MI.getOpcode()) {
  default:
    return nullptr;
  case C28x::SELECT_CC_PSEUDO:
  case C28x::SELECT_CC32_PSEUDO:
  case C28x::SELECT_WIDE_CC16_PSEUDO:
  case C28x::SELECT_WIDE_CC32_PSEUDO: {
    MachineFunction &MF = *BB->getParent();
    const DebugLoc &DL = MI.getDebugLoc();
    Register Dst = MI.getOperand(0).getReg();
    Register TrueVal = MI.getOperand(1).getReg();
    Register FalseVal = MI.getOperand(2).getReg();
    unsigned Cond = MI.getOperand(3).getImm();

    // Insert the false and merge blocks IMMEDIATELY AFTER BB (not at the end
    // of the function).  FinalizeISel jumps its block iterator to the returned
    // merge block; if the new blocks were appended at the end, that jump would
    // skip every original block between BB and the end, leaving any
    // SELECT_CC_PSEUDO in those blocks unexpanded (it reached the AsmPrinter,
    // which then failed with "Cannot print this instruction").
    MachineFunction::iterator InsertPt = ++BB->getIterator();
    MachineBasicBlock *FalseBB = MF.CreateMachineBasicBlock(BB->getBasicBlock());
    MachineBasicBlock *EndBB = MF.CreateMachineBasicBlock(BB->getBasicBlock());
    // A select can split the setup of an outgoing call. New blocks inherit
    // the live call area, otherwise PEI (and MachineVerifier) assumes zero
    // on entry and addresses incoming arguments/spills at the wrong SP.
    int CallFrameBytes = BB->getCallFrameSize();
    for (const MachineInstr &I : *BB) {
      if (&I == &MI) break;
      if (TII.isFrameInstr(I)) CallFrameBytes -= TII.getSPAdjust(I);
    }
    FalseBB->setCallFrameSize(CallFrameBytes);
    EndBB->setCallFrameSize(CallFrameBytes);
    MF.insert(InsertPt, FalseBB);
    MF.insert(InsertPt, EndBB);

    // Move all instructions following the select into EndBB.
    auto MIIt = MI.getIterator();
    auto AfterMI = MIIt;
    ++AfterMI;
    if (AfterMI != BB->end())
      EndBB->splice(EndBB->begin(), BB, AfterMI, BB->end());

    // splice() moves the instructions (including any terminators that follow
    // the select, e.g. the switch dispatch branches) but it does NOT move the
    // CFG successor edges.  Without this, a switch whose discriminant is the
    // result of this select keeps its successor edges on the old block while
    // the branch instructions physically land in EndBB, producing blocks with
    // branch MIs but no successor edges (and spurious edges on the old block),
    // which trips LiveVariables' "Can't find reaching def for virtreg".
    // Transfer any pre-existing successors (and update PHI references) to
    // EndBB, the block that now contains those terminators.
    EndBB->transferSuccessorsAndUpdatePHIs(BB);

    // New CFG: BB --condition true--> EndBB, BB --fallthrough--> FalseBB,
    // FalseBB --fallthrough--> EndBB.
    BB->addSuccessor(FalseBB);
    BB->addSuccessor(EndBB);
    FalseBB->addSuccessor(EndBB);

    assert(Cond < 10 && "invalid C28x condition code");
    // On true branch to EndBB; on false fall through to FalseBB.
    unsigned BranchOp = (MI.getOpcode() == C28x::SELECT_CC32_PSEUDO ||
                         MI.getOpcode() == C28x::SELECT_WIDE_CC32_PSEUDO)
                            ? C28x::CMPBR32_PSEUDO : C28x::CMPBR16_PSEUDO;
    BuildMI(BB, DL, TII.get(BranchOp)).addMBB(EndBB)
        .addReg(MI.getOperand(4).getReg())
        .addReg(MI.getOperand(5).getReg()).addImm(Cond);

    // EndBB merges the two values directly with a PHI: FalseVal arrives via
    // FalseBB, TrueVal arrives directly from BB.  No intermediate value copies
    // are needed (the blocks are adjacent and contain no clobtering code).
    BuildMI(*EndBB, EndBB->begin(), DL, TII.get(TargetOpcode::PHI), Dst)
        .addReg(FalseVal).addMBB(FalseBB)
        .addReg(TrueVal).addMBB(BB);

    BB->erase(MI);
    return EndBB;
  }
  }
}

