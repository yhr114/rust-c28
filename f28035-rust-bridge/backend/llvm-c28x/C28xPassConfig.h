//===-- C28xPassConfig.h - C28x Code Generator Pipeline ----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XPASSCONFIG_H
#define LLVM_LIB_TARGET_C28X_C28XPASSCONFIG_H

#include "llvm/CodeGen/TargetPassConfig.h"

namespace llvm {

class C28xTargetMachine;

class C28xPassConfig : public TargetPassConfig {
public:
  C28xPassConfig(C28xTargetMachine &TM, PassManagerBase &PM);

  C28xTargetMachine &getC28xTargetMachine() const;
  bool addInstSelector() override;
};

} // namespace llvm

#endif
