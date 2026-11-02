//===-- C28xRegisterInfo.h - C28x Register Information ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XREGISTERINFO_H
#define LLVM_LIB_TARGET_C28X_C28XREGISTERINFO_H

#include "llvm/CodeGen/TargetRegisterInfo.h"

#define GET_REGINFO_HEADER
#include "C28xGenRegisterInfo.inc"

namespace llvm {

class C28xSubtarget;

class C28xRegisterInfo : public C28xGenRegisterInfo {
public:
  C28xRegisterInfo();

  const MCPhysReg *getCalleeSavedRegs(const MachineFunction *MF) const override;
  BitVector getReservedRegs(const MachineFunction &MF) const override;
  const uint32_t *getCallPreservedMask(const MachineFunction &MF,
                                       CallingConv::ID) const override;
  const TargetRegisterClass *getPointerRegClass(unsigned Kind = 0) const override;
  // Frame addressing scans already-emitted transient pushes. LLVM 23 defaults
  // to a backward walk; use a forward walk so that scan sees the real prefix.
  bool eliminateFrameIndicesBackwards() const override { return false; }
  bool eliminateFrameIndex(MachineBasicBlock::iterator II, int SPAdj,
                           unsigned FIOperandNum,
                           RegScavenger *RS = nullptr) const override;
  Register getFrameRegister(const MachineFunction &MF) const override;
};

} // namespace llvm

#endif
