//===-- C28xAsmPrinter.cpp - C28x Assembly Printer ---------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28x.h"
#include "C28xAsmPrinter.h"
#include "C28xMCInstLower.h"
#include "C28xSubtarget.h"
#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

void C28xAsmPrinter::emitInstruction(const MachineInstr *MI) {
  C28xMCInstLower MCIL(*this);
  MCInst TmpInst;
  MCIL.Lower(MI, TmpInst);
  OutStreamer->emitInstruction(TmpInst, getSubtargetInfo());
}

// Force static initialization.
extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void
LLVMInitializeC28xAsmPrinter() {
  RegisterAsmPrinter<C28xAsmPrinter> X(getTheC28xTarget());
  (void)X;
}
