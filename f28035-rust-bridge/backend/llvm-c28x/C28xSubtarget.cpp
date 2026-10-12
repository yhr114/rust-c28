//===-- C28xSubtarget.cpp - C28x Subtarget Information ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28xSubtarget.h"
#include "C28x.h"
#include "llvm/CodeGen/LibcallLoweringInfo.h"
#include "llvm/CodeGen/SelectionDAGTargetInfo.h"
#include "llvm/MC/TargetRegistry.h"

#define DEBUG_TYPE "c28x-subtarget"

using namespace llvm;

#define GET_SUBTARGETINFO_TARGET_DESC
#define GET_SUBTARGETINFO_CTOR
#include "C28xGenSubtargetInfo.inc"

const SelectionDAGTargetInfo *C28xSubtarget::getSelectionDAGInfo() const {
  // C28x currently uses only the generic SelectionDAG target-info hooks.
  static const SelectionDAGTargetInfo TSI;
  return &TSI;
}

void C28xSubtarget::initLibcallLoweringInfo(LibcallLoweringInfo &Info) const {
  // Provide the standard C memory routines; the runtime crate implements them.
  Info.setLibcallImpl(RTLIB::MEMCPY, RTLIB::impl_memcpy);
  Info.setLibcallImpl(RTLIB::MEMMOVE, RTLIB::impl_memmove);
  Info.setLibcallImpl(RTLIB::MEMSET, RTLIB::impl_memset);

  // F28035 has no hardware divide.  These compiler_builtins routines are
  // provided by the c28x build of compiler_builtins.
  const struct {
    const RTLIB::Libcall Op;
    const RTLIB::LibcallImpl Impl;
  } LibraryCalls[] = {
      {RTLIB::MUL_I16, RTLIB::impl___mulhi3},
      {RTLIB::MUL_I32, RTLIB::impl___mulsi3},
      {RTLIB::SDIV_I16, RTLIB::impl___divhi3},
      {RTLIB::UDIV_I16, RTLIB::impl___udivhi3},
      {RTLIB::SREM_I16, RTLIB::impl___modhi3},
      {RTLIB::UREM_I16, RTLIB::impl___umodhi3},
      {RTLIB::SDIV_I32, RTLIB::impl___divsi3},
      {RTLIB::UDIV_I32, RTLIB::impl___udivsi3},
      {RTLIB::SREM_I32, RTLIB::impl___modsi3},
      {RTLIB::UREM_I32, RTLIB::impl___umodsi3},
      {RTLIB::SDIVREM_I16, RTLIB::impl___divmodhi4},
      {RTLIB::UDIVREM_I16, RTLIB::impl___udivmodhi4},
      {RTLIB::SDIVREM_I32, RTLIB::impl___divmodsi4},
      {RTLIB::UDIVREM_I32, RTLIB::impl___udivmodsi4},
      // 64-bit (di) integer helpers (no generic divmod di routine; the type
      // legalizer requests the standalone div/rem).
      {RTLIB::MUL_I64, RTLIB::impl___muldi3},
      {RTLIB::SDIV_I64, RTLIB::impl___divdi3},
      {RTLIB::UDIV_I64, RTLIB::impl___udivdi3},
      {RTLIB::SREM_I64, RTLIB::impl___moddi3},
      {RTLIB::UREM_I64, RTLIB::impl___umoddi3},
      // 128-bit (ti) integer helpers.
      {RTLIB::MUL_I128, RTLIB::impl___multi3},
      {RTLIB::SDIV_I128, RTLIB::impl___divti3},
      {RTLIB::UDIV_I128, RTLIB::impl___udivti3},
      {RTLIB::SREM_I128, RTLIB::impl___modti3},
      {RTLIB::UREM_I128, RTLIB::impl___umodti3},
      // Bit-count helpers (CTTZ is open-coded in terms of CTLZ by TLI).
      {RTLIB::CTLZ_I32, RTLIB::impl___clzsi2},
      {RTLIB::CTLZ_I64, RTLIB::impl___clzdi2},
      {RTLIB::CTLZ_I128, RTLIB::impl___clzti2},
      {RTLIB::CTPOP_I32, RTLIB::impl___popcountsi2},
      {RTLIB::CTPOP_I64, RTLIB::impl___popcountdi2},
      {RTLIB::CTPOP_I128, RTLIB::impl___popcountti2},
  };
  for (const auto &LC : LibraryCalls)
    Info.setLibcallImpl(LC.Op, LC.Impl);
}

C28xSubtarget::C28xSubtarget(const Triple &TT, StringRef CPU, StringRef FS,
                             const TargetMachine &TM)
    : C28xGenSubtargetInfo(TT, CPU, /*TuneCPU=*/CPU, FS), FrameLowering(*this),
      InstrInfo(*this), TLInfo(TM, *this) {
  StringRef CPUName = CPU.empty() ? StringRef("c28x") : CPU;
  ParseSubtargetFeatures(CPUName, CPUName, FS);
}
