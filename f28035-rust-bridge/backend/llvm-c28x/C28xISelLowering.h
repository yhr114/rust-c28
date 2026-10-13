//===-- C28xISelLowering.h - C28x DAG Lowering Interface ---------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XISELLOWERING_H
#define LLVM_LIB_TARGET_C28X_C28XISELLOWERING_H

#include "llvm/CodeGen/TargetLowering.h"

namespace llvm {

class C28xSubtarget;

/// C28x-specific calling convention IDs.
/// LLVM reserves 64..95 (FirstTargetCC..FirstTargetCC+31) for targets.
namespace C28xCC {
enum : unsigned {
  Interrupt = 92, // FirstTargetCC+28, avoids X86_StdCall=64 overlap
};
} // namespace C28xCC

namespace C28xISD {
enum NodeType : unsigned {
  FIRST_NUMBER = ISD::BUILTIN_OP_END,
  RET_GLUE,
  IRET_GLUE, // interrupt return: restores full hardware context (IRET)
  CMP,
  BRCOND,
  SELECT_CC,
  CALL,
  WRAPPER,
  SRL32,   // logical right shift i32 by constant
  ADD32,   // add/sub ACC with either register (XT) or immediate
  SUB32,
  MOVI32,  // materialize i32 constant into ACC
  STORE_STK16, // store i16 to SP+off*2 (post-RA pseudo)
  SHL32_VAR, SRL32_VAR, SRA32_VAR, // variable i32 shifts (post-RA loop)
  MUL32, // i32 multiply (post-RA loop)
  UMUL16_32, // unsigned 16x16 -> 32 product (hardware MPYU)
  SMUL16_32, // signed   16x16 -> 32 product (hardware MPY)
};
} // namespace C28xISD

class C28xTargetLowering : public TargetLowering {
  const C28xSubtarget &STI;
public:
  explicit C28xTargetLowering(const TargetMachine &TM,
                             const C28xSubtarget &STI);

  const char *getTargetNodeName(unsigned Opcode) const override;

  MVT getTypeForExtLoad(EVT VT) const;

  SDValue LowerOperation(SDValue Op, SelectionDAG &DAG) const override;

  void ReplaceNodeResults(SDNode *N, SmallVectorImpl<SDValue> &Results,
                          SelectionDAG &DAG) const override;

  MachineBasicBlock *EmitInstrWithCustomInserter(MachineInstr &MI,
                                                MachineBasicBlock *MBB) const override;

  /// Emit a CMP node. Returns the glue flag.
  SDValue EmitCMP(SDValue LHS, SDValue RHS, ISD::CondCode CC,
                  const SDLoc &DL, SelectionDAG &DAG) const;

  /// Custom-lower ISD::SHL_PARTS / SRL_PARTS / SRA_PARTS (a 64-bit shift split
  /// into two i32 parts) using the wide variable-shift pseudos.
  SDValue LowerShiftParts(SDNode *N, SelectionDAG &DAG) const;
  SDValue LowerMul(SDNode *N, SelectionDAG &DAG) const;
  SDValue LowerMulLoHi(SDNode *N, SelectionDAG &DAG) const;
  SDValue LowerXMULO(SDNode *N, SelectionDAG &DAG) const;

  SDValue LowerFormalArguments(
      SDValue Chain, CallingConv::ID CallConv, bool IsVarArg,
      const SmallVectorImpl<ISD::InputArg> &Ins, const SDLoc &DL,
      SelectionDAG &DAG, SmallVectorImpl<SDValue> &InVals) const override;

  SDValue LowerCall(CallLoweringInfo &CLI,
                    SmallVectorImpl<SDValue> &InVals) const override;

  SDValue LowerReturn(
      SDValue Chain, CallingConv::ID CallConv, bool IsVarArg,
      const SmallVectorImpl<ISD::OutputArg> &Outs,
      const SmallVectorImpl<SDValue> &OutVals, const SDLoc &DL,
      SelectionDAG &DAG) const override;

  bool CanLowerReturn(CallingConv::ID CallConv, MachineFunction &MF,
                      bool IsVarArg,
                      const SmallVectorImpl<ISD::OutputArg> &Outs,
                      LLVMContext &Context, const Type *RetTy) const override;
};

} // namespace llvm

#endif
