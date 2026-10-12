//===-- C28xMCTargetDesc.cpp - C28x Target Descriptions ----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28xMCTargetDesc.h"
#include "C28xAsmBackend.h"
#include "C28xInstPrinter.h"
#include "C28xMCAsmInfo.h"
#include "TargetInfo/C28xTargetInfo.h"
#include "llvm/MC/MCAsmInfo.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCInstPrinter.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Compiler.h"
#include "llvm/TargetParser/Triple.h"

using namespace llvm;

#define GET_INSTRINFO_MC_DESC
#include "C28xGenInstrInfo.inc"
#define GET_SUBTARGETINFO_MC_DESC
#include "C28xGenSubtargetInfo.inc"
#define GET_REGINFO_MC_DESC
#include "C28xGenRegisterInfo.inc"

static MCInstrInfo *createC28xMCInstrInfo() {
  auto *Info = new MCInstrInfo();
  InitC28xMCInstrInfo(Info);
  return Info;
}

static MCRegisterInfo *createC28xMCRegisterInfo(const Triple &) {
  auto *Info = new MCRegisterInfo();
  InitC28xMCRegisterInfo(Info, C28x::RPC);
  return Info;
}

static MCSubtargetInfo *createC28xMCSubtargetInfo(const Triple &TT,
                                                  StringRef CPU,
                                                  StringRef FS) {
  if (CPU.empty())
    CPU = "c28x";
  return createC28xMCSubtargetInfoImpl(TT, CPU, CPU, FS);
}

static MCAsmInfo *createC28xMCAsmInfo(const MCRegisterInfo &MRI,
                                       const Triple &TT,
                                       const MCTargetOptions &Options) {
  return new C28xMCAsmInfo(TT, Options);
}

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void
LLVMInitializeC28xTargetMC() {
  Target &T = getTheC28xTarget();
  TargetRegistry::RegisterMCAsmInfo(T, createC28xMCAsmInfo);
  TargetRegistry::RegisterMCInstrInfo(T, createC28xMCInstrInfo);
  TargetRegistry::RegisterMCRegInfo(T, createC28xMCRegisterInfo);
  TargetRegistry::RegisterMCSubtargetInfo(T, createC28xMCSubtargetInfo);
  TargetRegistry::RegisterMCInstPrinter(T, createC28xMCInstPrinter);
  TargetRegistry::RegisterMCCodeEmitter(T, createC28xMCCodeEmitter);
  TargetRegistry::RegisterMCAsmBackend(T, createC28xMCAsmBackend);
}
