//===-- C28xAsmBackend.h - C28x Assembler Backend -------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_MCTARGETDESC_C28XASMBACKEND_H
#define LLVM_LIB_TARGET_C28X_MCTARGETDESC_C28XASMBACKEND_H

#include "llvm/MC/MCAsmBackend.h"

namespace llvm {
class MCSubtargetInfo;
class MCTargetOptions;
class MCRegisterInfo;
class Target;

MCAsmBackend *createC28xMCAsmBackend(const Target &T,
                                     const MCSubtargetInfo &STI,
                                     const MCRegisterInfo &MRI,
                                     const MCTargetOptions &Opts);
} // namespace llvm

#endif
