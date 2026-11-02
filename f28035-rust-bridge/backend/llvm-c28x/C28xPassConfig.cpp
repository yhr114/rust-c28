//===-- C28xPassConfig.cpp - C28x Code Generator Pipeline ---------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28xPassConfig.h"
#include "C28xTargetMachine.h"
#include "C28xISelDAGToDAG.h"
#include "llvm/CodeGen/Passes.h"
#include "llvm/CodeGen/TargetPassConfig.h"
#include "llvm/Support/CodeGen.h"

using namespace llvm;

C28xPassConfig::C28xPassConfig(C28xTargetMachine &TM, PassManagerBase &PM)
    : TargetPassConfig(TM, PM) {}

C28xTargetMachine &C28xPassConfig::getC28xTargetMachine() const {
  return const_cast<C28xTargetMachine &>(
      static_cast<const C28xTargetMachine &>(*TM));
}

void C28xPassConfig::addIRPasses() {
  // AtomicExpandPass is what applies C28xTargetLowering::shouldExpandAtomic*
  // InIR, i.e. the decision that an aligned 16-bit atomic load/store on this
  // single-core part is just a MOV.  The generic pipeline does not add it for
  // this target, so without this every `load atomic` reached instruction
  // selection as an ATOMIC_LOAD node and died with "Cannot select".
  addPass(createAtomicExpandLegacyPass());
  TargetPassConfig::addIRPasses();
}

bool C28xPassConfig::addInstSelector() {
  addPass(createC28xISelDag(getC28xTargetMachine(), getOptLevel()));
  return false;
}
