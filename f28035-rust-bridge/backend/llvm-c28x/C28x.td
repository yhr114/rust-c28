//===-- C28x.td - Main TableGen entry point for C28x backend -------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

include "llvm/Target/Target.td"

//===----------------------------------------------------------------------===//
// Processor and Subtarget Features
//===----------------------------------------------------------------------===//

def C28xGeneric : ProcessorModel<"c28x", NoSchedModel, []>;

//===----------------------------------------------------------------------===//
// Register File
//===----------------------------------------------------------------------===//

include "C28xRegisterInfo.td"

//===----------------------------------------------------------------------===//
// Instruction Set
//===----------------------------------------------------------------------===//

include "C28xInstrFormats.td"
include "C28xInstrInfo.td"

def C28xInstrInfo : InstrInfo;

//===----------------------------------------------------------------------===//
// Calling Convention
//===----------------------------------------------------------------------===//

include "C28xCallingConv.td"

//===----------------------------------------------------------------------===//
// Assembly Printer
//===----------------------------------------------------------------------===//

def C28xAsmWriter : AsmWriter {
  string AsmStreamName = "asm";
}

//===----------------------------------------------------------------------===//
// Target Declaration (must come last; references InstrInfo)
//===----------------------------------------------------------------------===//

def C28x : Target {
  let InstructionSet = C28xInstrInfo;
}
