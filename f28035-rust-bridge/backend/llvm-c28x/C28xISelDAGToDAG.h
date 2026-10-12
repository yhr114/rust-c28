//===-- C28xISelDAGToDAG.h - A DAG-DAG Instruction Selector -------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XISELDAGTODAG_H
#define LLVM_LIB_TARGET_C28X_C28XISELDAGTODAG_H

#include "C28x.h"
#include "C28xSubtarget.h"
#include "C28xTargetMachine.h"
#include "llvm/CodeGen/SelectionDAGISel.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/Support/Debug.h"

namespace llvm {

class C28xDAGToDAGISel : public SelectionDAGISel {
public:
  C28xDAGToDAGISel(C28xTargetMachine &TM, CodeGenOptLevel OptLevel)
      : SelectionDAGISel(TM, OptLevel) {}

  StringRef getPassName() const {
    return "C28x DAG->DAG Pattern Instruction Selection";
  }

  void Select(SDNode *N) override;

  // Include the auto-generated code.
  #include "C28xGenDAGISel.inc"
};

} // namespace llvm

#endif
