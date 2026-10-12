//===-- C28xTargetInfo.cpp - C28x Target Implementation ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "TargetInfo/C28xTargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Compiler.h"
using namespace llvm;

Target &llvm::getTheC28xTarget() {
  static Target TheC28xTarget;
  return TheC28xTarget;
}

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void
LLVMInitializeC28xTargetInfo() {
  RegisterTarget<Triple::c28x> X(getTheC28xTarget(), "c28x",
                                   "TI TMS320C28x [experimental]", "C28x");
}
