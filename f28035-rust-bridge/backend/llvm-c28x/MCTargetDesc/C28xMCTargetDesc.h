//===-- C28xMCTargetDesc.h - C28x Target Descriptions -----------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_MCTARGETDESC_C28XMCTARGETDESC_H
#define LLVM_LIB_TARGET_C28X_MCTARGETDESC_C28XMCTARGETDESC_H

#include "llvm/MC/MCFixup.h"
#include "llvm/Support/DataTypes.h"

namespace llvm {
class Target;
class MCInstrInfo;
class MCContext;
class MCCodeEmitter;
class MCAsmInfo;
class MCAsmBackend;
class MCInstPrinter;
class MCRegisterInfo;
class MCSubtargetInfo;
class MCTargetOptions;
class Triple;

Target &getTheC28xTarget();

MCCodeEmitter *createC28xMCCodeEmitter(const MCInstrInfo &MCII,
                                         MCContext &Ctx);

MCAsmBackend *createC28xMCAsmBackend(const Target &T,
                                     const MCSubtargetInfo &STI,
                                     const MCRegisterInfo &MRI,
                                     const MCTargetOptions &Opts);

MCInstPrinter *createC28xMCInstPrinter(const Triple &T, unsigned SyntaxVariant,
                                       const MCAsmInfo &MAI,
                                       const MCInstrInfo &MII,
                                       const MCRegisterInfo &MRI);
} // namespace llvm

namespace llvm {
namespace C28x {
// Target fixup kinds. FK_C28x_ABS22 covers the two-word 22-bit absolute
// address forms (LCR #sym, MOVL XARn, #sym): word0 low 6 bits = addr[21:16],
// word1 = addr[15:0].  Maps to TI R_C28X_ABS22_BR (=20) on object emission.
enum Fixups {
  FK_C28x_16_ABS = FirstTargetFixupKind,
  FK_C28x_ABS22,
  FK_C28x_BRANCH,
  NumTargetFixupKinds
};
} // namespace C28x
} // namespace llvm

#define GET_REGINFO_ENUM
#include "C28xGenRegisterInfo.inc"

#define GET_INSTRINFO_ENUM
#define GET_INSTRINFO_MC_HELPER_DECLS
#include "C28xGenInstrInfo.inc"

#define GET_SUBTARGETINFO_ENUM
#include "C28xGenSubtargetInfo.inc"

#endif
