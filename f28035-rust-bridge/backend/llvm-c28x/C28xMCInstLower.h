//===-- C28xMCInstLower.h - Lower MachineInstr to MCInst -----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XMCINSTLOWER_H
#define LLVM_LIB_TARGET_C28X_C28XMCINSTLOWER_H

#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/Compiler.h"

namespace llvm {

class AsmPrinter;
class MachineBasicBlock;
class MachineInstr;
class MachineOperand;
class MCInst;
class MCSymbol;

class C28xMCInstLower {
  AsmPrinter &AP;

public:
  C28xMCInstLower(AsmPrinter &AP);

  void Initialize(MCSymbol *ContextSymbol);

  void Lower(const MachineInstr *MI, MCInst &OutMI) const;

private:
  MCSymbol *GetGlobalAddressSymbol(const MachineOperand &MO) const;
};

} // namespace llvm

#endif
