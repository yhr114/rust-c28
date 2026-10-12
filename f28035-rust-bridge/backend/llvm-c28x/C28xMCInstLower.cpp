//===-- C28xMCInstLower.cpp - Lower MachineInstr to MCInst --------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28xMCInstLower.h"
#include "C28xAsmPrinter.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/IR/Mangler.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

C28xMCInstLower::C28xMCInstLower(AsmPrinter &AP) : AP(AP) {}

void C28xMCInstLower::Initialize(MCSymbol *ContextSymbol) {}

MCSymbol *C28xMCInstLower::GetGlobalAddressSymbol(const MachineOperand &MO) const {
  return AP.getSymbol(MO.getGlobal());
}

void C28xMCInstLower::Lower(const MachineInstr *MI, MCInst &OutMI) const {
  OutMI.setOpcode(MI->getOpcode());

  for (const MachineOperand &MO : MI->operands()) {
    MCOperand MCOp;
    switch (MO.getType()) {
    default:
      llvm_unreachable("unknown operand type");
    case MachineOperand::MO_Register:
      if (MO.isImplicit())
        continue;
      MCOp = MCOperand::createReg(MO.getReg());
      break;
    case MachineOperand::MO_RegisterMask:
      continue;
    case MachineOperand::MO_Immediate:
      MCOp = MCOperand::createImm(MO.getImm());
      break;
    case MachineOperand::MO_MachineBasicBlock:
      MCOp = MCOperand::createExpr(MCSymbolRefExpr::create(
          MO.getMBB()->getSymbol(), AP.OutContext));
      break;
    case MachineOperand::MO_GlobalAddress: {
      // Byte offsets are applied after WRAPPER converts the symbol to a
      // logical byte address. A residual offset here has ambiguous units:
      // reject it rather than silently interpreting bytes as TI words.
      if (MO.getOffset() != 0)
        report_fatal_error("C28x: byte offset must be lowered before symbol relocation");
      const MCSymbolRefExpr *Sym = MCSymbolRefExpr::create(
          GetGlobalAddressSymbol(MO), AP.OutContext);
      MCOp = MCOperand::createExpr(Sym);
      break;
    }
    case MachineOperand::MO_ExternalSymbol:
      MCOp = MCOperand::createExpr(MCSymbolRefExpr::create(
          AP.GetExternalSymbolSymbol(MO.getSymbolName()), AP.OutContext));
      break;
    }
    OutMI.addOperand(MCOp);
  }
}
