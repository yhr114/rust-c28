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
#include "llvm/IR/GlobalVariable.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Target/TargetLoweringObjectFile.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

void C28xAsmPrinter::emitGlobalVariable(const GlobalVariable *GV) {
  // TI places addressable data in 16-bit words. A one-byte ELF input section
  // otherwise occupies zero words and aliases the following section. Keep
  // packed bytes WITHIN an object, but give each global a whole-word extent.
  if (!GV->hasInitializer() || GV->hasAvailableExternallyLinkage() ||
      GV->isThreadLocal() || GV->getName().starts_with("llvm.")) {
    AsmPrinter::emitGlobalVariable(GV);
    return;
  }
  const auto &DL = GV->getDataLayout();
  auto Kind = TargetLoweringObjectFile::getKindForGlobal(GV, TM);
  const Align Alignment = std::max(Align(2), getGVAlignment(GV, DL));
  uint64_t Size = alignTo(std::max(uint64_t(1), GV->getGlobalSize(DL)), 2);
  if (Kind.isCommon()) {
    emitVisibility(getSymbol(GV), GV->getVisibility(), false);
    OutStreamer->emitCommonSymbol(getSymbol(GV), Size, Alignment);
    return;
  }
  auto *Section = getObjFileLowering().SectionForGlobal(GV, Kind, TM);
  if (Kind.isBSSLocal() && Section == getObjFileLowering().getBSSSection()) {
    OutStreamer->emitLocalCommonSymbol(getSymbol(GV), Size, Alignment);
    return;
  }
  OutStreamer->switchSection(Section);
  OutStreamer->emitValueToAlignment(Align(2));
  AsmPrinter::emitGlobalVariable(GV);
  OutStreamer->emitValueToAlignment(Align(2));
}

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
