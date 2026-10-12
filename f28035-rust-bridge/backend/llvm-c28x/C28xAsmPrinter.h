//===-- C28xAsmPrinter.h - C28x Assembly Printer --------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_C28XASMPRINTER_H
#define LLVM_LIB_TARGET_C28X_C28XASMPRINTER_H

#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/MC/MCStreamer.h"

namespace llvm {

class C28xAsmPrinter : public AsmPrinter {
public:
  C28xAsmPrinter(TargetMachine &TM, std::unique_ptr<MCStreamer> Streamer)
      : AsmPrinter(TM, std::move(Streamer)) {}

  StringRef getPassName() const override { return "C28x Assembly Printer"; }

  void emitInstruction(const MachineInstr *MI) override;
};

} // namespace llvm

#endif
