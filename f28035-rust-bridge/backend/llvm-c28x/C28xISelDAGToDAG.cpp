//===-- C28xISelDAGToDAG.cpp - A DAG-DAG Instruction Selector ----------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the DAG->DAG instruction selector for C28x.
// It maps LLVM SelectionDAG nodes to C28x machine instructions.
//
//===----------------------------------------------------------------------===//

#include "C28xISelDAGToDAG.h"
#include "C28x.h"
#include "C28xISelLowering.h"
#include "C28xTargetMachine.h"
#include "llvm/CodeGen/SelectionDAG.h"
#include "llvm/IR/Function.h"
#include "llvm/CodeGen/SelectionDAGNodes.h"
#include <memory>

using namespace llvm;

void C28xDAGToDAGISel::Select(SDNode *N) {
  // Materialize a frame index (alloca local) into a GR16 pointer.
  if (N->getOpcode() == ISD::FrameIndex) {
    int FI = cast<FrameIndexSDNode>(N)->getIndex();
    SDValue TFI = CurDAG->getTargetFrameIndex(FI, MVT::i32);
    CurDAG->SelectNodeTo(N, C28x::MOV32fi, MVT::i32, TFI);
    return;
  }
  // Materialize an arbitrary i32 constant that does not fit the imm16s
  // (-32768..65535) or imm22 (0..0x3FFFFF) patterns, e.g. 0x7FFFFFFF.  The
  // wide MOV32_imm32 pseudo builds it from two 16-bit halves in ACC.
  if (N->getOpcode() == ISD::Constant && N->getValueType(0) == MVT::i32) {
    int64_t V = cast<ConstantSDNode>(N)->getSExtValue();
    bool Fits16 = (V >= -32768 && V <= 65535);
    bool Fits22 = (V >= 0 && V <= 0x3FFFFF);
    if (!Fits16 && !Fits22) {
      // Fail-closed: if this constant is used as a pointer (inttoptr, or as the
      // address of a load/store/atomic), it must map to a reachable 22-bit
      // physical word address.  A logical byte address B maps to word B>>1, so
      // B must be <= 0x7FFFFF; anything larger (e.g. 0x1000000) cannot be
      // addressed and must be rejected here rather than silently wrapped.
      uint32_t B = static_cast<uint32_t>(V);
      bool UsedAsPtr = false;
      for (const SDUse &U : N->uses()) {
        const SDNode *UN = U.getUser();
        unsigned OpNo = U.getOperandNo();
        if (!UN->isMachineOpcode()) {
          // The constant is an address only when it sits in the base/index
          // pointer slot of a load/store.  A constant fed as the stored VALUE
          // (store operand 1) must NOT be treated as a pointer.
          if (UN->getOpcode() == ISD::LOAD) {
            const LoadSDNode *L = cast<LoadSDNode>(UN);
            if (L->getBasePtr().getNode() == N)
              UsedAsPtr = true;
          } else if (UN->getOpcode() == ISD::STORE) {
            const StoreSDNode *S = cast<StoreSDNode>(UN);
            if (S->getBasePtr().getNode() == N)
              UsedAsPtr = true;
          }
        } else {
          // In a SelectionDAG MachineSDNode the operand list corresponds only
          // to the instruction's ins (the defs are the node's result values,
          // not operands).  Every load/store pseudo lists the pointer as its
          // first ins, so it is operand 0 (a store's value is operand 1).
          int AddrOp = -1;
          switch (UN->getMachineOpcode()) {
          case C28x::LOAD16_PSEUDO:
          case C28x::LOAD16_ZEXT32_PSEUDO:
          case C28x::LOAD32_PSEUDO:
          case C28x::LOAD8_PSEUDO:
          case C28x::LOAD8_ZEXT32_PSEUDO:
          case C28x::STORE16_PSEUDO:
          case C28x::STORE32_PSEUDO:
          case C28x::STORE8_PSEUDO:
            AddrOp = 0;
            break;
          default:
            break;
          }
          if (AddrOp >= 0 && static_cast<int>(OpNo) == AddrOp)
            UsedAsPtr = true;
        }
        if (UsedAsPtr)
          break;
      }
      if (UsedAsPtr && B > 0x7FFFFFu)
        report_fatal_error(
            "Cannot select: constant pointer 0x" + Twine::utohexstr(B) +
            " exceeds the C28x 22-bit physical word-address range "
            "(logical byte address > 0x7FFFFF)");
      SDValue ImmV = CurDAG->getTargetConstant(B, SDLoc(N), MVT::i32);
      CurDAG->SelectNodeTo(N, C28x::MOV32_imm32, MVT::i32, ImmV);
      return;
    }
  }
  // (add FrameIndex, Constant) -> MOV32fi_off (FI + byte offset)
  if (N->getOpcode() == ISD::ADD && N->getValueType(0) == MVT::i32) {
    SDValue LHS = N->getOperand(0);
    SDValue RHS = N->getOperand(1);
    if (LHS.getOpcode() == ISD::FrameIndex && isa<ConstantSDNode>(RHS)) {
      int FI = cast<FrameIndexSDNode>(LHS)->getIndex();
      int64_t Off = cast<ConstantSDNode>(RHS)->getSExtValue();
      SDValue TFI = CurDAG->getTargetFrameIndex(FI, MVT::i32);
      SDValue OffV = CurDAG->getTargetConstant(Off, SDLoc(N), MVT::i16);
      CurDAG->SelectNodeTo(N, C28x::MOV32fi_off, MVT::i32, TFI, OffV);
      return;
    }
    if (RHS.getOpcode() == ISD::FrameIndex && isa<ConstantSDNode>(LHS)) {
      int FI = cast<FrameIndexSDNode>(RHS)->getIndex();
      int64_t Off = cast<ConstantSDNode>(LHS)->getSExtValue();
      SDValue TFI = CurDAG->getTargetFrameIndex(FI, MVT::i32);
      SDValue OffV = CurDAG->getTargetConstant(Off, SDLoc(N), MVT::i16);
      CurDAG->SelectNodeTo(N, C28x::MOV32fi_off, MVT::i32, TFI, OffV);
      return;
    }
  }
  // C28xISD::SELECT_CC: (trueval, falseval, cond, glue) -> dst
  if (N->getOpcode() == C28xISD::SELECT_CC) {
    SDValue TrueVal = N->getOperand(0);
    SDValue FalseVal = N->getOperand(1);
    ConstantSDNode *CondCN = cast<ConstantSDNode>(N->getOperand(2));
    unsigned Cond = CondCN->getZExtValue();
    SDValue Glue = N->getOperand(3);
    // Build SELECT_CC_PSEUDO dst, trueval, falseval, cond
    SDValue Ops[] = {TrueVal, FalseVal,
                     CurDAG->getTargetConstant(Cond, SDLoc(N), MVT::i16),
                     Glue};
    CurDAG->SelectNodeTo(N, C28x::SELECT_CC_PSEUDO, MVT::i16, Ops);
    return;
  }
  // C28xISD::SRL32: (src, amt) -> dst
  if (N->getOpcode() == C28xISD::SRL32) {
    SDValue Src = N->getOperand(0);
    ConstantSDNode *AmtCN = cast<ConstantSDNode>(N->getOperand(1));
    SDValue Amt = CurDAG->getTargetConstant(AmtCN->getZExtValue(), SDLoc(N), MVT::i16);
    CurDAG->SelectNodeTo(N, C28x::SRL32_PSEUDO, MVT::i32, Src, Amt);
    return;
  }
  // C28xISD::SHL32_VAR/SRL32_VAR/SRA32_VAR: (src, amt) -> dst
  if (N->getOpcode() == C28xISD::SHL32_VAR || N->getOpcode() == C28xISD::SRL32_VAR || N->getOpcode() == C28xISD::SRA32_VAR) {
    unsigned Opc = C28x::SHL32_VAR_PSEUDO;
    if (N->getOpcode() == C28xISD::SRL32_VAR) Opc = C28x::SRL32_VAR_PSEUDO;
    else if (N->getOpcode() == C28xISD::SRA32_VAR) Opc = C28x::SRA32_VAR_PSEUDO;
    CurDAG->SelectNodeTo(N, Opc, MVT::i32, N->getOperand(0), N->getOperand(1));
    return;
  }
  // C28xISD::MUL32: (src, rhs) -> dst
  if (N->getOpcode() == C28xISD::MUL32) {
    CurDAG->SelectNodeTo(N, C28x::MUL32_PSEUDO, MVT::i32, N->getOperand(0), N->getOperand(1));
    return;
  }
  // C28xISD::UMUL16_32 / SMUL16_32: (i16 a, i16 b) -> i32 product
  if (N->getOpcode() == C28xISD::UMUL16_32 ||
      N->getOpcode() == C28xISD::SMUL16_32) {
    unsigned Opc = N->getOpcode() == C28xISD::UMUL16_32
                       ? C28x::UMUL16_32_PSEUDO
                       : C28x::SMUL16_32_PSEUDO;
    CurDAG->SelectNodeTo(N, Opc, MVT::i32, N->getOperand(0),
                         N->getOperand(1));
    return;
  }

  // C28xISD::STORE_STK16: (chain, i16 val, i16 word_off) -> chain
  if (N->getOpcode() == C28xISD::STORE_STK16) {
    SDValue Chain = N->getOperand(0);
    SDValue Val = N->getOperand(1);
    uint64_t Off = cast<ConstantSDNode>(N->getOperand(2))->getZExtValue();
    SDValue OffV = CurDAG->getTargetConstant(Off, SDLoc(N), MVT::i16);
    SDValue Ops[] = {OffV, Val, Chain};
    CurDAG->SelectNodeTo(N, C28x::STORE_STK16, MVT::Other, Ops);
    return;
  }
  // CALLSEQ_START -> ADJCALLSTACKDOWN
  if (N->getOpcode() == ISD::CALLSEQ_START) {
    SDValue Chain = N->getOperand(0);
    SDValue Size = N->getOperand(1);
    SDValue AmountToTop = N->getOperand(2);
    // Operands map to ins amt1=NumBytes, amt2=AmountToTop (space set up prior
    // to the pair); amt2 must be carried through, not duplicated from Size,
    // otherwise getFrameTotalSize() overcounts the setup and the verifier
    // reports an unbalanced call frame.
    SDValue Ops[] = {Size, AmountToTop, Chain};
    CurDAG->SelectNodeTo(N, C28x::ADJCALLSTACKDOWN, MVT::Other, Ops);
    return;
  }
  // CALLSEQ_END -> ADJCALLSTACKUP. Preserve the glue so the CALL, the callseq
  // node and the result copies remain one glued scheduling unit (otherwise the
  // scheduler sees a chain cycle around the call).
  if (N->getOpcode() == ISD::CALLSEQ_END) {
    SDValue Chain = N->getOperand(0);
    SDValue Size1 = N->getOperand(1);
    SDValue Size2 = N->getOperand(2);
    SmallVector<SDValue, 4> Ops;
    Ops.push_back(Size1);
    Ops.push_back(Size2);
    Ops.push_back(Chain);
    SDVTList ResVTs = CurDAG->getVTList(MVT::Other);
    if (N->getNumOperands() >= 4 &&
        N->getOperand(N->getNumOperands() - 1).getValueType() == MVT::Glue) {
      Ops.push_back(N->getOperand(N->getNumOperands() - 1));
      ResVTs = CurDAG->getVTList(MVT::Other, MVT::Glue);
    }
    CurDAG->SelectNodeTo(N, C28x::ADJCALLSTACKUP, ResVTs, Ops);
    return;
  }
  SelectCode(N);
}

namespace {
class C28xDAGToDAGISelLegacy : public SelectionDAGISelLegacy {
public:
  static char ID;
  C28xDAGToDAGISelLegacy(C28xTargetMachine &TM, CodeGenOptLevel OptLevel)
      : SelectionDAGISelLegacy(
            ID, std::make_unique<C28xDAGToDAGISel>(TM, OptLevel)) {}
};
char C28xDAGToDAGISelLegacy::ID = 0;
} // namespace

namespace llvm {
  FunctionPass *createC28xISelDag(C28xTargetMachine &TM,
                                  CodeGenOptLevel OptLevel) {
    return new C28xDAGToDAGISelLegacy(TM, OptLevel);
  }
}
