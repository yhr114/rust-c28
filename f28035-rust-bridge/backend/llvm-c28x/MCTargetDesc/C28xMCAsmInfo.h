//===-- C28xMCAsmInfo.h - C28x Assembly Properties ---------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_C28X_MCTARGETDESC_C28XMCASMINFO_H
#define LLVM_LIB_TARGET_C28X_MCTARGETDESC_C28XMCASMINFO_H

#include "llvm/MC/MCAsmInfo.h"

namespace llvm {

class Triple;
class MCTargetOptions;

class C28xMCAsmInfo : public MCAsmInfo {
public:
  explicit C28xMCAsmInfo(const Triple &TT, const MCTargetOptions &Options);
};

} // namespace llvm

#endif
