//===-- C28xInstPrinter.cpp - C28x assembly instruction printing ---------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28xInstPrinter.h"
#include "C28xMCTargetDesc.h"
#include "llvm/MC/MCAsmInfo.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Triple.h"

using namespace llvm;

#define PRINT_ALIAS_INSTR
#include "C28xGenAsmWriter.inc"

void C28xInstPrinter::printRegName(raw_ostream &O, MCRegister Reg) {
  O << getRegisterName(Reg);
}

void C28xInstPrinter::printOperand(const MCInst *MI, unsigned OpNo,
                                   raw_ostream &O, const char *Modifier) {
  const MCOperand &MO = MI->getOperand(OpNo);
  if (MO.isReg()) {
    // MOVZ spells ARn but defines the full XARn (including zeroed high bits).
    MCRegister Reg = MO.getReg();
    if (MI->getOpcode() == C28x::MOVL_XAR_AR && OpNo == 0)
      Reg = MRI.getSubReg(Reg, C28x::sub_lo16);
    O << getRegisterName(Reg);
    return;
  }
  if (MO.isImm()) {
    O << formatImm(MO.getImm());
    return;
  }
  if (MO.isExpr()) {
    MAI.printExpr(O, *MO.getExpr());
    return;
  }
  llvm_unreachable("Unknown operand type in C28xInstPrinter");
}

void C28xInstPrinter::printInst(const MCInst *MI, uint64_t Address,
                                StringRef Annot, const MCSubtargetInfo &STI,
                                raw_ostream &O) {
  printInstruction(MI, Address, O);
  printAnnotation(O, Annot);
}

MCInstPrinter *llvm::createC28xMCInstPrinter(const Triple &T,
                                             unsigned SyntaxVariant,
                                             const MCAsmInfo &MAI,
                                             const MCInstrInfo &MII,
                                             const MCRegisterInfo &MRI) {
  return new C28xInstPrinter(MAI, MII, MRI);
}
