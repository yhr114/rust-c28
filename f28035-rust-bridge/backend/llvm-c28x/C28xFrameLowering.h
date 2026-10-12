//===-- C28xFrameLowering.h - C28x Frame Information -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XFRAMELOWERING_H
#define LLVM_LIB_TARGET_C28X_C28XFRAMELOWERING_H

#include "llvm/CodeGen/TargetFrameLowering.h"

namespace llvm {

class C28xSubtarget;

class C28xFrameLowering : public TargetFrameLowering {
public:
  explicit C28xFrameLowering(const C28xSubtarget &STI);

  void emitPrologue(MachineFunction &MF, MachineBasicBlock &MBB) const override;
  void emitEpilogue(MachineFunction &MF, MachineBasicBlock &MBB) const override;

  // Save/restore CSRs with hardware PUSH/POP (called by PEI).
  bool spillCalleeSavedRegisters(MachineBasicBlock &MBB,
                                 MachineBasicBlock::iterator MI,
                                 ArrayRef<CalleeSavedInfo> CSI,
                                 const TargetRegisterInfo *TRI) const override;
  bool restoreCalleeSavedRegisters(MachineBasicBlock &MBB,
                                   MachineBasicBlock::iterator MI,
                                   MutableArrayRef<CalleeSavedInfo> CSI,
                                   const TargetRegisterInfo *TRI) const override;

  MachineBasicBlock::iterator eliminateCallFramePseudoInstr(
      MachineFunction &MF, MachineBasicBlock &MBB,
      MachineBasicBlock::iterator MI) const override;
  bool hasReservedCallFrame(const MachineFunction &MF) const override { return false; }
  bool hasFPImpl(const MachineFunction &MF) const override { return false; }
};

} // namespace llvm

#endif
