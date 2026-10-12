//===-- C28xInstrInfo.h - C28x Instruction Information ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XINSTRINFO_H
#define LLVM_LIB_TARGET_C28X_C28XINSTRINFO_H

#include "C28xRegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"

#define GET_INSTRINFO_HEADER
#include "C28xGenInstrInfo.inc"

namespace llvm {

class C28xSubtarget;

class C28xInstrInfo : public C28xGenInstrInfo {
  const C28xRegisterInfo RI;
public:
  explicit C28xInstrInfo(const C28xSubtarget &STI);

  const C28xRegisterInfo &getRegisterInfo() const { return RI; }

  void copyPhysReg(MachineBasicBlock &MBB, MachineBasicBlock::iterator I,
                   const DebugLoc &DL, Register DestReg, Register SrcReg,
                   bool KillSrc, bool RenamableDest = false,
                   bool RenamableSrc = false) const override;

  void storeRegToStackSlot(MachineBasicBlock &MBB,
                           MachineBasicBlock::iterator I, Register SrcReg,
                           bool IsKill, int FI, const TargetRegisterClass *RC,
                           Register VReg,
                           MachineInstr::MIFlag Flags) const override;
  void loadRegFromStackSlot(MachineBasicBlock &MBB,
                            MachineBasicBlock::iterator I, Register DstReg,
                            int FI, const TargetRegisterClass *RC, Register VReg,
                            unsigned SubReg,
                            MachineInstr::MIFlag Flags) const override;

  bool expandPostRAPseudo(MachineInstr &MI) const override;

  bool analyzeBranch(MachineBasicBlock &MBB, MachineBasicBlock *&TBB,
                     MachineBasicBlock *&FBB,
                     SmallVectorImpl<MachineOperand> &Cond,
                     bool AllowModify) const override;
  unsigned removeBranch(MachineBasicBlock &MBB,
                        int *BytesRemoved = nullptr) const override;
  unsigned insertBranch(MachineBasicBlock &MBB, MachineBasicBlock *TBB,
                        MachineBasicBlock *FBB, ArrayRef<MachineOperand> Cond,
                        const DebugLoc &DL,
                        int *BytesAdded = nullptr) const override;
};

} // namespace llvm

#endif
