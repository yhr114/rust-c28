//===-- C28xFrameLowering.cpp - C28x Frame Information ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28x.h"
#include "C28xFrameLowering.h"
#include "C28xISelLowering.h"
#include "MCTargetDesc/C28xMCTargetDesc.h"
#include "C28xSubtarget.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/IR/Function.h"

using namespace llvm;

static bool isC28xInterrupt(const MachineFunction &MF) {
  return static_cast<unsigned>(MF.getFunction().getCallingConv()) ==
             C28xCC::Interrupt || MF.getFunction().hasFnAttribute("interrupt");
}

void C28xFrameLowering::determineCalleeSaves(MachineFunction &MF,
                                          BitVector &SavedRegs,
                                          RegScavenger *RS) const {
  TargetFrameLowering::determineCalleeSaves(MF, SavedRegs, RS);
  if (isC28xInterrupt(MF))
    for (unsigned R : {C28x::XAR0, C28x::XAR1, C28x::XAR2, C28x::XAR3,
                       C28x::XAR4, C28x::XAR5, C28x::XAR6, C28x::XAR7, C28x::XT})
      SavedRegs.set(R);
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
C28xFrameLowering::C28xFrameLowering(const C28xSubtarget &STI)
    : TargetFrameLowering(TargetFrameLowering::StackGrowsUp,
                          Align(4), 0) {}

uint64_t C28xFrameLowering::getFrameAllocationWords(const MachineFunction &MF) {
  // Entry SP and every full-width CSR push are even. Keep a guard word, then
  // round the local allocation to two TI words so all call boundaries and
  // transient MOVL pushes remain even-aligned (TI EABI SPRU514, 7.3.1).
  uint64_t Words = (MF.getFrameInfo().getStackSize() + 1) / 2 + 1;
  return (Words + 1) & ~uint64_t(1);
}

// PEI calls this to spill CSRs.  We emit hardware PUSH instructions in
// prologue order (XAR1, XAR2, XAR3). Returning true tells PEI we handled it
// and it must NOT also emit store-to-stack.
bool C28xFrameLowering::spillCalleeSavedRegisters(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI,
    ArrayRef<CalleeSavedInfo> CSI, const TargetRegisterInfo *TRI) const {
  const auto &TII = *MBB.getParent()->getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL;
  if (isC28xInterrupt(*MBB.getParent()))
    BuildMI(MBB, MI, DL, TII.get(C28x::IRQ_ENTER));
  for (const CalleeSavedInfo &CS : CSI) {
    BuildMI(MBB, MI, DL, TII.get(C28x::PUSH32))
        .addReg(CS.getReg(), RegState::Kill);
  }
  return true; // we handled all spills
}

// PEI does NOT reverse the list before calling this; stack is LIFO so
// we must iterate in reverse.
bool C28xFrameLowering::restoreCalleeSavedRegisters(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI,
    MutableArrayRef<CalleeSavedInfo> CSI, const TargetRegisterInfo *TRI) const {
  const auto &TII = *MBB.getParent()->getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL;
  for (int i = CSI.size() - 1; i >= 0; --i) {
    BuildMI(MBB, MI, DL, TII.get(C28x::POP32), CSI[i].getReg());
  }
  return true;
}

void C28xFrameLowering::emitPrologue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  const auto &TII = *MF.getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL;

  // Only adjust SP for the local frame.  CSR PUSH was inserted by
  // spillCalleeSavedRegisters at MBB.begin(); we must place ADDB_SP
  // AFTER those PUSHes so the stack layout is:
  //   push xar1 / push xar2 ... (full-width CSR save)
  //   addb sp, #local            (local frame)
  // Always reserve at least the guard word, even when the function owns no
  // locals.  The post-RA expansions push ACC (`MOVL *SP++, ACC`, a 32-bit push
  // that touches the words at and just under SP), so a frame-less function used
  // to push onto its own return address: rust_mode's 2*x path overwrote the
  // high return-address word with the accumulator and LRETR jumped to
  // 0x0014_8023 (observed on target: results 40,0,0,0,40 and PC off in ROM).
  {
    // PUSH ACC writes into the word immediately below the current SP on this
    // target.  Keep one unaddressed word between locals and transient pushes.
    uint64_t StackWords = getFrameAllocationWords(MF);
    // Skip past the PUSH instructions that PEI already inserted.
    auto InsertPt = MBB.begin();
    while (InsertPt != MBB.end() &&
           (InsertPt->getOpcode() == C28x::PUSH32 ||
            InsertPt->getOpcode() == C28x::IRQ_ENTER))
      ++InsertPt;
    emitSPAdjust(TII, MBB, InsertPt, DL, /*IsAdd=*/true, StackWords);
  }
}

void C28xFrameLowering::emitEpilogue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  const auto &TII = *MF.getSubtarget<C28xSubtarget>().getInstrInfo();
  DebugLoc DL;

  MachineBasicBlock::iterator InsertPt = MBB.getFirstTerminator();

  // Deallocate local frame BEFORE the POP instructions (LIFO order):
  //   subb sp, #local
  //   pop xar2 / pop xar1 ...
  //   lretr
  // restoreCalleeSavedRegisters already inserted POP right before InsertPt;
  // walk backwards past them so SUBB_SP lands above the POPs.
  {
    // Must mirror emitPrologue exactly: the guard word is always reserved, so
    // it is always released here too.
    uint64_t StackWords = getFrameAllocationWords(MF);
    while (InsertPt != MBB.begin() &&
           std::prev(InsertPt)->getOpcode() == C28x::POP32)
      --InsertPt;
    emitSPAdjust(TII, MBB, InsertPt, DL, /*IsAdd=*/false, StackWords);
  }
  if (isC28xInterrupt(MF))
    BuildMI(MBB, MBB.getFirstTerminator(), DL, TII.get(C28x::IRQ_LEAVE));
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
