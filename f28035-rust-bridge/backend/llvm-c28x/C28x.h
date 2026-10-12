//===-- C28x.h - Top-level interface for C28x representation ------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28X_H
#define LLVM_LIB_TARGET_C28X_C28X_H

#include "MCTargetDesc/C28xMCTargetDesc.h"
#include "llvm/Target/TargetMachine.h"

namespace llvm {

class Target;
class C28xTargetMachine;
class FunctionPass;

// getTheC28xTarget - The C28x target.
Target &getTheC28xTarget();

FunctionPass *createC28xISelDag(C28xTargetMachine &TM,
                                CodeGenOptLevel OptLevel);

} // namespace llvm

#endif
