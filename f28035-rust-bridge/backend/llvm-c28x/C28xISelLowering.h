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

  /// Expand `llvm.memcpy`/`llvm.memset`/`llvm.memmove` into plain loads and
  /// stores instead of a library call.
  ///
  /// The generic chooser rejects every candidate type on this target, so each
  /// memcpy became a call to the TI RTS `memcpy`.  That routine dereferences C
  /// word addresses while the Rust ABI passes logical byte addresses, so every
  /// in-memory aggregate copy of 4 bytes or more read and wrote the wrong
  /// memory (hardware symptom: `zip(iter, iter.skip(1))` summed 12 instead of
  /// 30 because `ZipImpl::new`'s 12-byte Skip copy came from an unrelated
  /// address; minimal repro in tools/iter-probe/parts13.rs).
  bool findOptimalMemOpLowering(LLVMContext &Context,
                                std::vector<EVT> &MemOps, unsigned Limit,
                                const MemOp &Op, unsigned DstAS, unsigned SrcAS,
                                const AttributeList &FuncAttributes,
                                EVT *LargestVT = nullptr) const override;

  /// A 16-bit word access at an even byte address is always fine on C28x: the
  /// backend converts the logical byte address to a word address with a
  /// logical shift, so only odd byte addresses need the byte-offset path.
  bool allowsMisalignedMemoryAccesses(EVT VT, unsigned AddrSpace = 0,
                                      Align Alignment = Align(1),
                                      MachineMemOperand::Flags Flags =
                                          MachineMemOperand::MONone,
                                      unsigned *Fast = nullptr) const override {
    (void)AddrSpace;
    (void)Flags;
    if (!VT.isSimple())
      return false;
    MVT SVT = VT.getSimpleVT();
    if (SVT != MVT::i16 && SVT != MVT::i32)
      return false;
    if (Alignment.value() < 2)
      return false;
    if (Fast)
      *Fast = 1;
    return true;
  }

  /// C28x is a single-core MCU with no cache and no other bus master, so an
  /// aligned 16-bit load or store is already indivisible.  Telling
  /// AtomicExpandPass to drop the atomicity in IR is the only way to get a
  /// plain MOV out of it: the generic fallbacks either emit a cmpxchg loop or
  /// call __atomic_* libcalls, and the TI runtime provides neither.
  AtomicExpansionKind shouldExpandAtomicLoadInIR(LoadInst *LI) const override {
    (void)LI;
    return AtomicExpansionKind::NotAtomic;
  }
  AtomicExpansionKind shouldExpandAtomicStoreInIR(StoreInst *SI) const override {
    (void)SI;
    return AtomicExpansionKind::NotAtomic;
  }
  bool shouldInsertFencesForAtomic(const Instruction *I) const override {
    (void)I;
    return false;
  }

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
