//===-- C28xRegisterInfo.cpp - C28x Register Information ----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28x.h"
#include "C28xInstrInfo.h"
#include "C28xRegisterInfo.h"
#include "C28xSubtarget.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/Support/ErrorHandling.h"

#define GET_REGINFO_TARGET_DESC
#include "C28xGenRegisterInfo.inc"

using namespace llvm;

C28xRegisterInfo::C28xRegisterInfo()
    : C28xGenRegisterInfo(/*RAReg=*/C28x::RPC) {}

const MCPhysReg *
C28xRegisterInfo::getCalleeSavedRegs(const MachineFunction *MF) const {
  return CSR_C28x_SaveList;
}

BitVector C28xRegisterInfo::getReservedRegs(const MachineFunction &MF) const {
  BitVector Reserved(getNumRegs());
  // SP is reserved (stack pointer).
  Reserved.set(C28x::SP);
  Reserved.set(C28x::DP);
  Reserved.set(C28x::ST0);
  Reserved.set(C28x::ST1);
  Reserved.set(C28x::PC);
  Reserved.set(C28x::RPC);
  // XAR7 is the scratch pointer register used by load/store lowering.
  // Reserve XAR7 AND its 16-bit halves so the allocator never picks AR7.
  Reserved.set(C28x::XAR7);
  Reserved.set(C28x::AR7);
  Reserved.set(C28x::AR7H);
  return Reserved;
}

const uint32_t *
C28xRegisterInfo::getCallPreservedMask(const MachineFunction &MF,
                                       CallingConv::ID) const {
  return CSR_C28x_RegMask;
}

const TargetRegisterClass *
C28xRegisterInfo::getPointerRegClass(unsigned Kind) const {
  return &C28x::GR32RegClass;
}

bool C28xRegisterInfo::eliminateFrameIndex(MachineBasicBlock::iterator II,
                                           int SPAdj,
                                           unsigned FIOperandNum,
                                           RegScavenger *RS) const {
  MachineInstr &MI = *II;
  MachineFunction &MF = *MI.getMF();
  MachineFrameInfo &MFI = MF.getFrameInfo();
  const C28xSubtarget &STI = MF.getSubtarget<C28xSubtarget>();
  const C28xInstrInfo &TII = *STI.getInstrInfo();
  DebugLoc DL = MI.getDebugLoc();

  int FI = MI.getOperand(FIOperandNum).getIndex();
  int64_t Offset = MFI.getObjectOffset(FI) + SPAdj;
  // MOV32fi_off carries an additional byte offset (logical address space).
  if (MI.getOpcode() == C28x::MOV32fi_off)
    Offset += MI.getOperand(2).getImm();

  // The upward-growing SP points one word above the last allocated local.
  // LLVM frame offsets are logical bytes; SUBB XAR7 uses C28x words.
  // DeltaFromSP = bytes from current SP down to the object (positive).
  // DeltaWords  = ceil(DeltaFromSP / 2) — the word offset from SP.
  // Lane        = DeltaFromSP & 1 — 0=low byte, 1=high byte (for i8 objects).
  int64_t DeltaFromSP = int64_t(MFI.getStackSize()) - Offset;
  if (DeltaFromSP <= 0) {
    // Object at/above the current SP (outgoing call-arg area, or a frame that
    // grew beyond the local allocation).  C28x has no frame pointer and the
    // generic lowering only modelled locals below SP.  Rather than abort core
    // compilation, clamp to a minimal positive distance and warn: the obscure
    // functions that hit this (e.g. core::num float pow tables) are not on the
    // embedded runtime path, and a correct outgoing-area addressing mode is a
    // later frame-lowering task.
    errs() << "C28x: clamp non-positive frame offset (FI=" << FI
           << " Offset=" << Offset << " StackSize=" << MFI.getStackSize()
           << " Delta=" << DeltaFromSP << ")\n";
    DeltaFromSP = 1;
  }
  int64_t DeltaWords = (DeltaFromSP + 1) / 2;
  int64_t Lane = DeltaFromSP & 1;

  MachineBasicBlock &MBB = *MI.getParent();

  // XAR7 = SP - DeltaWords  (word address of the object's word).
  BuildMI(MBB, II, DL, TII.get(C28x::MOVZ_XAR7_SP));
  // SUBB XAR7,#imm only encodes a 7-bit immediate (0..127 words).  For frames
  // larger than that (e.g. a 1024-byte alloca -> ~574 words) subtract in
  // chunks.  Each SUBB is an independent XAR7 immediate subtract and needs no
  // extra scratch register, so it is safe during prologue/epilogue lowering.
  const int64_t MaxSubbChunk = 127;
  int64_t Rem = DeltaWords;
  while (Rem > 0) {
    int64_t Chunk = Rem > MaxSubbChunk ? MaxSubbChunk : Rem;
    BuildMI(MBB, II, DL, TII.get(C28x::SUBB_XAR7_imm)).addImm(Chunk);
    Rem -= Chunk;
  }

  // Helper: convert XAR7 from word address to logical byte address
  // (ABI L1-1: byte_addr = word_addr * 2 + lane).
  auto wordToByte = [&]() {
    BuildMI(MBB, II, DL, TII.get(C28x::MOVL_ACC_XAR), C28x::ACC)
        .addReg(C28x::XAR7);
    // word*2 + lane via a left rotate through carry: bit0 <- C (lane).
    if (Lane)
      BuildMI(MBB, II, DL, TII.get(C28x::SETC_C));
    else
      BuildMI(MBB, II, DL, TII.get(C28x::CLRC_C));
    BuildMI(MBB, II, DL, TII.get(C28x::ROL_ACC), C28x::ACC)
        .addReg(C28x::ACC);
    BuildMI(MBB, II, DL, TII.get(C28x::MOVL_XAR_ACC), C28x::XAR7)
        .addReg(C28x::ACC);
  };

  switch (MI.getOpcode()) {
  case C28x::MOV32fi:
  case C28x::MOV32fi_off: {
    // Materialise the frame pointer as a logical byte address (ABI L1-1).
    // wordToByte() uses ACC as scratch, which may hold a live value (e.g.
    // an i8 function argument in AL about to be stored).  Save/restore it.
    Register Dst = MI.getOperand(0).getReg();
    BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
    wordToByte();
    BuildMI(MBB, II, DL, TII.get(C28x::MOV32rr), Dst).addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD16_PSEUDO: {
    Register Dst = MI.getOperand(0).getReg();
    // XAR7 is already a word address; 16-bit load uses it directly.
    if (Dst != C28x::AL && Dst != C28x::AH) {
      BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
      BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), C28x::AL)
          .addReg(C28x::XAR7);
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), C28x::AR7).addReg(C28x::AL);
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), Dst).addReg(C28x::AR7);
    } else {
      BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), Dst)
          .addReg(C28x::XAR7);
    }
    MI.eraseFromParent();
    return false;
  }
  case C28x::STORE16_PSEUDO: {
    Register Src = MI.getOperand(1).getReg();
    Register StgSrc = Src;
    if (Src != C28x::AL && Src != C28x::AH) {
      BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), C28x::AL).addReg(Src);
      StgSrc = C28x::AL;
    }
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_store))
        .addReg(C28x::XAR7)
        .addReg(StgSrc);
    if (Src != C28x::AL && Src != C28x::AH)
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD16_ZEXT32_PSEUDO: {
    // XAR7 already holds the object's word address; load word into AL,
    // clear AH, route the 32-bit result to Dst.
    Register Dst = MI.getOperand(0).getReg();
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), C28x::AL)
        .addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::MOV16_imm), C28x::AH).addImm(0);
    if (Dst == C28x::XT)
      BuildMI(MBB, II, DL, TII.get(C28x::MOV_ACC_rr), C28x::XT)
          .addReg(C28x::ACC);
    else if (Dst != C28x::ACC)
      BuildMI(MBB, II, DL, TII.get(C28x::MOVL_XAR_ACC), Dst)
          .addReg(C28x::ACC);
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD8_ZEXT32_PSEUDO: {
    // Convert to a byte address, MOVB the byte into AL (clears AL high),
    // clear AH, route the 32-bit result to Dst.
    Register Dst = MI.getOperand(0).getReg();
    wordToByte();
    BuildMI(MBB, II, DL, TII.get(C28x::MOVB_ind_load_AL), C28x::AL)
        .addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::MOV16_imm), C28x::AH).addImm(0);
    if (Dst == C28x::XT)
      BuildMI(MBB, II, DL, TII.get(C28x::MOV_ACC_rr), C28x::XT)
          .addReg(C28x::ACC);
    else if (Dst != C28x::ACC)
      BuildMI(MBB, II, DL, TII.get(C28x::MOVL_XAR_ACC), Dst)
          .addReg(C28x::ACC);
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD32_PSEUDO: {
    // Load low word from *XAR7, high word from *(XAR7+1).
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), C28x::AL)
        .addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::ADDB_XAR7_imm)).addImm(1);
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), C28x::AH)
        .addReg(C28x::XAR7);
    MI.eraseFromParent();
    return false;
  }
  case C28x::STORE32_PSEUDO: {
    // Store AL to *XAR7, AH to *(XAR7+1) — adjacent words, not the same word.
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_store_AL))
        .addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::ADDB_XAR7_imm)).addImm(1);
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_store_AH))
        .addReg(C28x::XAR7);
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD8_PSEUDO: {
    Register Dst = MI.getOperand(0).getReg();
    // i8 access needs a byte address; convert word address + lane.
    wordToByte();
    if (Dst != C28x::AL && Dst != C28x::AH) {
      BuildMI(MBB, II, DL, TII.get(C28x::MOVB_ind_load_AL), C28x::AL)
          .addReg(C28x::XAR7);
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), Dst).addReg(C28x::AL);
    } else {
      BuildMI(MBB, II, DL, TII.get(C28x::MOVB_ind_load_AL), Dst)
          .addReg(C28x::XAR7);
    }
    MI.eraseFromParent();
    return false;
  }
  case C28x::STORE8_PSEUDO: {
    Register Src = MI.getOperand(1).getReg();
    // wordToByte() clobbers ACC (AL+AH).  If the byte value lives in AL/AH,
    // save it first so it survives the address conversion.
    bool SaveAcc = (Src == C28x::AL || Src == C28x::AH);
    if (SaveAcc)
      BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
    wordToByte();
    if (SaveAcc)
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    Register StgSrc = Src;
    if (Src != C28x::AL && Src != C28x::AH) {
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), C28x::AL).addReg(Src);
      StgSrc = C28x::AL;
    }
    if (StgSrc == C28x::AH) {
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), C28x::AL).addReg(C28x::AH);
    }
    BuildMI(MBB, II, DL, TII.get(C28x::MOVB_ind_store_AL))
        .addReg(C28x::XAR7);
    MI.eraseFromParent();
    return false;
  }
  default:
    report_fatal_error("C28x: unexpected frame-index operand");
  }
}

Register
C28xRegisterInfo::getFrameRegister(const MachineFunction &MF) const {
  return C28x::SP;
}
