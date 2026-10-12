//===-- C28xMCAsmInfo.cpp - C28x Assembly Properties -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28xMCAsmInfo.h"
#include "llvm/TargetParser/Triple.h"
using namespace llvm;

C28xMCAsmInfo::C28xMCAsmInfo(const Triple &TT, const MCTargetOptions &Options)
    : MCAsmInfo(Options) {
  // TI cl2000 assembly syntax.
  CommentString = ";";
  SupportsDebugInformation = false;
  MinInstAlignment = 1;
  MaxInstLength = 4;
  ExceptionsType = TT.getDefaultExceptionHandling();

  // TI directives instead of GNU ELF ones.
  GlobalDirective = "\t.global\t";
  Data8bitsDirective = "\t.byte\t";
  Data16bitsDirective = "\t.word\t";
  Data32bitsDirective = "\t.long\t";
  ZeroDirective = "\t.space\t";

  // We don't emit .file / .type / .size / .p2align / .note.GNU-stack.
  HasDotTypeDotSizeDirective = false;
  HasSingleParameterDotFile = false;
}
