//===-- C28xTargetMachine.cpp - C28x Target Machine ----------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28xTargetMachine.h"
#include "C28x.h"
#include "C28xPassConfig.h"
#include "llvm/CodeGen/TargetLoweringObjectFileImpl.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Compiler.h"

using namespace llvm;

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void LLVMInitializeC28xTarget() {
  RegisterTargetMachine<C28xTargetMachine> X(getTheC28xTarget());
}

C28xTargetMachine::C28xTargetMachine(const Target &T, const Triple &TT,
                                     StringRef CPU, StringRef FS,
                                     const TargetOptions &Options,
                                     std::optional<Reloc::Model> RM,
                                     std::optional<CodeModel::Model> CM,
                                     CodeGenOptLevel OL, bool JIT)
    : CodeGenTargetMachineImpl(
          // FROZEN ABI (see ABI_FREEZE.md): 32-bit logical byte pointers.
          // u16 = one C28x word; u32/i32/f32 and pointers = two words aligned
          // to 4 logical bytes. The old p:16:16 addressed only 64Ki logical
          // bytes (32K words) — smaller than the F28035's 128Ki flash. This
          // matches the verified packed-byte runtime (C28X_RUST_ABI.md).
          T, "e-m:e-p:32:32-i1:8:8-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16",
          TT, CPU, FS, Options, RM.value_or(Reloc::Static),
          getEffectiveCodeModel(CM, CodeModel::Small), OL),
      TLOF(std::make_unique<TargetLoweringObjectFileELF>()),
      Subtarget(TT, CPU, FS, *this) {
  initAsmInfo();
}

C28xTargetMachine::~C28xTargetMachine() = default;

TargetPassConfig *C28xTargetMachine::createPassConfig(PassManagerBase &PM) {
  return new C28xPassConfig(*this, PM);
}
