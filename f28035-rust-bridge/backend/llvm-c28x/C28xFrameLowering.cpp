//===-- C28xFrameLowering.cpp - C28x Frame Information ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28x.h"
#include "C28xFrameLowering.h"
#include "MCTargetDesc/C28xMCTargetDesc.h"
#include "C28xSubtarget.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/IR/Function.h"

using namespace llvm;

// Map a callee-saved physical register to its PUSH/POP opcode.
static unsigned pushOpcodeFor(unsigned Reg) {
  switch (Reg) {
  case C28x::AR4: return C28x::PUSH_AR4;
  case C28x::AR5: return C28x::PUSH_AR5;
  case C28x::AR6: return C28x::PUSH_AR6;
  default:        return 0;
  }
}

// ADDB/SUBB SP encode only a 7-bit immediate (0..127 words).  Emit the total
// adjustment in chunks so large frames/outgoing-arg areas lower correctly.
static void emitSPAdjust(const C28xInstrInfo &TII, MachineBasicBlock &MBB,
                         MachineBasicBlock::iterator InsertPt, DebugLoc DL,
                         bool IsAdd, uint64_t Words) {
  const uint64_t MaxChunk = 127;
  unsigned Opc = IsAdd ? C28x::ADDB_SP : C28x::SUBB_SP;
  while (Words > 0) {
    uint64_t Chunk = Words > MaxChunk ? MaxChunk : Words;
    BuildMI(MBB, InsertPt, DL, TII.get(Opc)).addImm(Chunk);
    Words -= Chunk;
  }
}
static unsigned popOpcodeFor(unsigned Reg) {
  switch (Reg) {
  case C28x::AR4: return C28x::POP_AR4;
  case C28x::AR5: return C28x::POP_AR5;
  case C28x::AR6: return C28x::POP_AR6;
  default:        return 0;
  }
}

C28xFrameLowering::C28xFrameLowering(const C28xSubtarget &STI)
    : TargetFrameLowering(TargetFrameLowering::StackGrowsUp,
                          Align(2), 0) {}

// PEI calls this to spill CSRs.  We emit hardware PUSH instructions in
// prologue order (AR4, AR5, AR6).  Returning true tells PEI we handled it
// and it must NOT also emit store-to-stack.
bool C28xFrameLowering::spillCalleeSavedRegisters(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI,
    ArrayRef<CalleeSavedInfo> CSI, const TargetRegisterInfo *TRI) const {
  const auto &TII = *MBB.getParent()->getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL;
  for (const CalleeSavedInfo &CS : CSI) {
    unsigned PushOp = pushOpcodeFor(CS.getReg());
    if (PushOp)
      BuildMI(MBB, MI, DL, TII.get(PushOp));
  }
  return true; // we handled all spills
}

// PEI does NOT reverse the list before calling this; stack is LIFO so
// we must iterate in reverse: push AR4,AR5,AR6 -> pop AR6,AR5,AR4.
bool C28xFrameLowering::restoreCalleeSavedRegisters(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI,
    MutableArrayRef<CalleeSavedInfo> CSI, const TargetRegisterInfo *TRI) const {
  const auto &TII = *MBB.getParent()->getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL;
  for (int i = CSI.size() - 1; i >= 0; --i) {
    unsigned PopOp = popOpcodeFor(CSI[i].getReg());
    if (PopOp)
      BuildMI(MBB, MI, DL, TII.get(PopOp));
  }
  return true;
}

void C28xFrameLowering::emitPrologue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  MachineFrameInfo &MFI = MF.getFrameInfo();
  const auto &TII = *MF.getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL;

  // Only adjust SP for the local frame.  CSR PUSH was inserted by
  // spillCalleeSavedRegisters at MBB.begin(); we must place ADDB_SP
  // AFTER those PUSHes so the stack layout is:
  //   push ar4 / push ar5 ...   (CSR save)
  //   addb sp, #local            (local frame)
  uint64_t StackSize = MFI.getStackSize();
  if (StackSize > 0) {
    uint64_t StackWords = (StackSize + 1) / 2;
    // Skip past the PUSH instructions that PEI already inserted.
    auto InsertPt = MBB.begin();
    while (InsertPt != MBB.end() &&
           (InsertPt->getOpcode() == C28x::PUSH_AR4 ||
            InsertPt->getOpcode() == C28x::PUSH_AR5 ||
            InsertPt->getOpcode() == C28x::PUSH_AR6))
      ++InsertPt;
    emitSPAdjust(TII, MBB, InsertPt, DL, /*IsAdd=*/true, StackWords);
  }
}

void C28xFrameLowering::emitEpilogue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  MachineFrameInfo &MFI = MF.getFrameInfo();
  const auto &TII = *MF.getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL;

  MachineBasicBlock::iterator InsertPt = MBB.getFirstTerminator();

  // Deallocate local frame BEFORE the POP instructions (LIFO order):
  //   subb sp, #local
  //   pop ar4 ...
  //   lretr
  // restoreCalleeSavedRegisters already inserted POP right before InsertPt;
  // walk backwards past them so SUBB_SP lands above the POPs.
  uint64_t StackSize = MFI.getStackSize();
  if (StackSize > 0) {
    uint64_t StackWords = (StackSize + 1) / 2;
    while (InsertPt != MBB.begin() &&
           (std::prev(InsertPt)->getOpcode() == C28x::POP_AR4 ||
            std::prev(InsertPt)->getOpcode() == C28x::POP_AR5 ||
            std::prev(InsertPt)->getOpcode() == C28x::POP_AR6))
      --InsertPt;
    emitSPAdjust(TII, MBB, InsertPt, DL, /*IsAdd=*/false, StackWords);
  }
}

// PEI calls this for ADJCALLSTACKDOWN/UP.  C28x stack grows upward:
//   ADJCALLSTACKDOWN = allocate outgoing arg area -> ADDB SP, #words
//   ADJCALLSTACKUP   = deallocate                  -> SUBB SP, #words
MachineBasicBlock::iterator C28xFrameLowering::eliminateCallFramePseudoInstr(
    MachineFunction &MF, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator MI) const {
  const auto &TII = *MF.getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL = MI->getDebugLoc();
  unsigned Amount = MI->getOperand(0).getImm();
  unsigned Words = (Amount + 1) / 2;
  if (Words > 0) {
    bool IsAdd = MI->getOpcode() == C28x::ADJCALLSTACKDOWN;
    emitSPAdjust(TII, MBB, MI, DL, IsAdd, Words);
  }
  return MBB.erase(MI);
}
