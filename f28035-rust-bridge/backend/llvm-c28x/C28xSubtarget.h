//===-- C28xSubtarget.h - C28x Subtarget Information --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XSUBTARGET_H
#define LLVM_LIB_TARGET_C28X_C28XSUBTARGET_H

#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "C28xFrameLowering.h"
#include "C28xInstrInfo.h"
#include "C28xISelLowering.h"

#define GET_SUBTARGETINFO_HEADER
#include "C28xGenSubtargetInfo.inc"

namespace llvm {

class SelectionDAGTargetInfo;

class C28xSubtarget : public C28xGenSubtargetInfo {
public:
  C28xSubtarget(const Triple &TT, StringRef CPU, StringRef FS,
                const TargetMachine &TM);

  const C28xInstrInfo *getInstrInfo() const override { return &InstrInfo; }
  const C28xRegisterInfo *getRegisterInfo() const override {
    return &InstrInfo.getRegisterInfo();
  }
  const C28xFrameLowering *getFrameLowering() const override {
    return &FrameLowering;
  }
  const C28xTargetLowering *getTargetLowering() const override {
    return &TLInfo;
  }
  const SelectionDAGTargetInfo *getSelectionDAGInfo() const override;

  void initLibcallLoweringInfo(LibcallLoweringInfo &Info) const override;

  void ParseSubtargetFeatures(StringRef CPU, StringRef TuneCPU, StringRef FS);

private:
  C28xFrameLowering FrameLowering;
  C28xInstrInfo InstrInfo;
  C28xTargetLowering TLInfo;
};

} // namespace llvm

#endif
