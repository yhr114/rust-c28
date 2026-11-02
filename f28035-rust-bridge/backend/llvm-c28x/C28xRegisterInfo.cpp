//===-- C28xRegisterInfo.cpp - C28x Register Information ----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28x.h"
#include "C28xInstrInfo.h"
#include "C28xISelLowering.h"
#include "C28xFrameLowering.h"
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
  if (MF && (static_cast<unsigned>(MF->getFunction().getCallingConv()) ==
                 C28xCC::Interrupt || MF->getFunction().hasFnAttribute("interrupt")))
    return CSR_C28x_Interrupt_SaveList;
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
  // SPAdj belongs to the live outgoing call area, not the object's offset.
  // Convert it once to physical words below, for fixed arguments AND locals.
  int64_t Offset = MFI.getObjectOffset(FI);
  // MOV32fi_off carries an additional byte offset (logical address space).
  if (MI.getOpcode() == C28x::MOV32fi_off)
    Offset += MI.getOperand(2).getImm();

  // The upward-growing SP points one word above the last allocated local.
  // LLVM frame offsets are logical bytes; SUBB XAR7 uses C28x words.
  // DeltaFromSP = bytes from current SP down to the object (positive).
  // DeltaWords  = ceil(DeltaFromSP / 2) — the word offset from SP.
  // Lane        = DeltaFromSP & 1 — 0=low byte, 1=high byte (for i8 objects).
  int64_t DeltaFromSP = int64_t(MFI.getStackSize()) - Offset;
  const bool IsFixedObject = MFI.isFixedObjectIndex(FI);
  if (!IsFixedObject && DeltaFromSP <= 0) {
    // Fail closed: every non-fixed (local) object must sit BELOW the guard
    // word the prologue reserves at SP-1.  An object at or above SP is not
    // covered by the allocated frame, and clamping the distance to a fake
    // "1" would silently redirect every load/store of this object to the
    // wrong stack word.  Diagnose with the offending function and frame
    // indices instead of emitting corrupt addressing.
    report_fatal_error(
        Twine("C28x: frame object FI=") + Twine(FI) + " of function '" +
        MF.getName() +
        "' is not below SP (object offset=" + Twine(Offset) +
        ", stack size=" + Twine(MFI.getStackSize()) +
        ", delta from SP=" + Twine(DeltaFromSP) +
        "); the frame layout must reserve every local below the guard word");
  }
  // The prologue reserves one extra word above the local frame.  Transient
  // PUSH/POP sequences may touch SP-1, so no frame index may name that word.
  //
  // Measured TI EABI layout (tools/probe-ti-stack.c + dss-probe-stkargs.js):
  // the call pushes a TWO-word return address, the first stack-argument word
  // sits at SP_entry-3 and later words follow downward (verified with 1 and 4
  // stack words; the Rust callee's argument registers arrive correctly).
  //
  // Frame-index addressing reads the LIVE SP (MOVZ XAR7, SP), so every word
  // the prologue or a transient adjustment has moved SP by at THIS point must
  // be added to the offset. Three sources:
  //   * callee-saved pushes of the prologue - they shift SP permanently, so
  //     an access in a SUCCESSOR block must count them too (a per-block
  //     backward scan used to miss them, reading one word off whenever a
  //     branch block touched the frame);
  //   * transient PUSH/POP pairs, scanned in the emitted block prefix;
  //   * the live outgoing call area, tracked by PEI's SPAdj (logical bytes,
  //     negative for our upward stack), including predecessor call setups.
  // The prologue allocation is already in the base offset. Do not count
  // real call-frame ADDB/SUBB instructions again on top of SPAdj.
  int64_t LivePushWords = -int64_t(SPAdj) / 2;
  MachineBasicBlock *MBB0 = MI.getParent();
  const bool IsEntryBlock = MBB0 == &MF.front();
  const uint64_t FrameAllocWords = C28xFrameLowering::getFrameAllocationWords(MF);
  const int64_t AlignmentPadWords =
      FrameAllocWords - ((uint64_t(MFI.getStackSize()) + 1) / 2 + 1);
  for (auto It = MBB0->begin(); It != MBB0->end(); ++It) {
    if (&*It == &MI)
      break;
    switch (It->getOpcode()) {
    case C28x::PUSH32:
    case C28x::PUSH_ACC:
      // PUSH ACC is a 32-bit push (MOVL *SP++, ACC): it moves SP by TWO words.
      LivePushWords += 2;
      break;
    case C28x::POP32:
    case C28x::POP_ACC:
      LivePushWords -= 2;
      break;
    case C28x::PUSH_AL:
    case C28x::PUSH_AR0:
    case C28x::PUSH_AR4:
    case C28x::PUSH_AR5:
    case C28x::PUSH_AR6:
      ++LivePushWords;
      break;
    case C28x::POP_AL:
    case C28x::POP_AR0:
    case C28x::POP_AR4:
    case C28x::POP_AR5:
    case C28x::POP_AR6:
      --LivePushWords;
      break;
    // ADDB/SUBB from outgoing call frames are already included in SPAdj.
    // This also handles a call area opened in a predecessor block. The
    // prologue's own allocation is included in FrameAllocWords instead.
    default:
      break;
    }
  }
  if (!IsEntryBlock) {
    // The prologue's callee-saved pushes shifted SP for the whole function,
    // so every successor block inherits them.
    for (const MachineInstr &I : MF.front()) {
      switch (I.getOpcode()) {
      case C28x::IRQ_ENTER:
        continue; // ASP establishes the aligned ISR frame base before saves.
      case C28x::PUSH32:
      case C28x::PUSH_ACC:
        LivePushWords += 2; // 32-bit push: SP moves two words
        continue;
      case C28x::PUSH_AL:
      case C28x::PUSH_AR0:
      case C28x::PUSH_AR4:
      case C28x::PUSH_AR5:
      case C28x::PUSH_AR6:
        ++LivePushWords;
        continue;
      default:
        break;
      }
      break; // first non-push ends the prologue's push run
    }
  }

  int64_t DeltaWords;
  // Byte lane of the object's first byte.  Fixed (stack-argument) objects are
  // addressed from the incoming area's own base, so their lane follows the
  // object offset; locals follow the distance down from SP.
  int64_t Lane = IsFixedObject ? (Offset & 1) : (DeltaFromSP & 1);
  if (IsFixedObject) {
    // First stack word at SP_entry-3, later words downward (measured).
    // FrameWords must equal what emitPrologue actually allocated --
    // ceil(StackSize/2) plus the one guard word, where the guard word is
    // reserved even when the function owns no locals.
    const int64_t FrameWords = FrameAllocWords;
    DeltaWords = FrameWords + 3 + Offset / 2 + LivePushWords;
  } else {
    DeltaWords = (DeltaFromSP + 1) / 2 + 1 + AlignmentPadWords + LivePushWords;
  }


  MachineBasicBlock &MBB = *MI.getParent();

  // Frame-index address materialisation uses ACC as a temporary.  Preserve it
  // only when a defined value is actually live through this instruction.  A
  // spill-heavy block can have ACC live-in but already killed immediately
  // before the frame access; an unconditional PUSH_ACC would read an undefined
  // physical register and fail MachineVerifier.
  auto PreserveAcc = [&]() {
    // The value that needs preserving is the value live *after* this pseudo:
    // frame-index materialisation overwrites ACC.  Looking backwards is
    // incorrect for an incoming ACC argument that is killed by the first
    // MOVL_XAR_ACC.  Scan forward until the first ACC alias use/def instead.
    bool LowDefined = false, HighDefined = false;
    for (auto It = std::next(II); It != MBB.end(); ++It) {
      for (const MachineOperand &Op : It->operands()) {
        if (!Op.isReg() || !Op.isUse())
          continue;
        Register R = Op.getReg();
        if ((R && this->regsOverlap(R, C28x::AL) && !LowDefined) ||
            (R && this->regsOverlap(R, C28x::AH) && !HighDefined))
          return true;
      }
      for (const MachineOperand &Op : It->operands()) {
        if (!Op.isReg() || !Op.isDef())
          continue;
        Register R = Op.getReg();
        if (R && this->regsOverlap(R, C28x::AL))
          LowDefined = true;
        if (R && this->regsOverlap(R, C28x::AH))
          HighDefined = true;
      }
      if (LowDefined && HighDefined)
        return false;
    }
    // A surviving half can be consumed only on one successor of a select.
    // For example, c in AH is used on the even branch of rust_bb_args;
    // looking only inside this block silently loses that live-through half.
    for (const MachineBasicBlock *Succ : MBB.successors())
      for (const auto &LiveIn : Succ->liveins()) {
        Register R = LiveIn.PhysReg;
        if ((!LowDefined && this->regsOverlap(R, C28x::AL)) ||
            (!HighDefined && this->regsOverlap(R, C28x::AH)))
          return true;
      }
    return false;
  };

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
    bool SaveACC = PreserveAcc();
    if (SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
    wordToByte();
    // MOV32rr would encode "MOVL Dst, @AR7" (memory read), not a copy.
    BuildMI(MBB, II, DL, TII.get(C28x::PUSH32)).addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::POP32), Dst);
    if (SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD16_PSEUDO: {
    Register Dst = MI.getOperand(0).getReg();
    // XAR7 is already a word address; 16-bit load uses it directly.
    if (Dst != C28x::AL && Dst != C28x::AH) {
      bool SaveACC = PreserveAcc();
      if (SaveACC)
        BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
      BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), C28x::AL)
          .addReg(C28x::XAR7);
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), C28x::AR7).addReg(C28x::AL);
      if (SaveACC)
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
    if (C28x::ARegsRegClass.contains(Src) && Src != C28x::AR7) {
      BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_store_AR))
          .addReg(C28x::XAR7).addReg(Src);
      MI.eraseFromParent();
      return false;
    }
    Register StgSrc = Src;
    bool SaveACC = PreserveAcc();
    if (Src != C28x::AL && Src != C28x::AH) {
      if (SaveACC)
        BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), C28x::AL).addReg(Src);
      StgSrc = C28x::AL;
    }
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_store))
        .addReg(C28x::XAR7)
        .addReg(StgSrc);
    if (Src != C28x::AL && Src != C28x::AH && SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD16_ZEXT32_PSEUDO: {
    // XAR7 already holds the object's word address; load word into AL,
    // clear AH, route the 32-bit result to Dst.
    Register Dst = MI.getOperand(0).getReg();
    bool SaveACC = Dst != C28x::ACC && PreserveAcc();
    if (SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), C28x::AL)
        .addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::MOV16_imm), C28x::AH).addImm(0);
    if (Dst == C28x::XT)
      BuildMI(MBB, II, DL, TII.get(C28x::MOV_ACC_rr), C28x::XT)
          .addReg(C28x::ACC);
    else if (Dst != C28x::ACC)
      BuildMI(MBB, II, DL, TII.get(C28x::MOVL_XAR_ACC), Dst)
          .addReg(C28x::ACC);
    if (SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD8_ZEXT32_PSEUDO: {
    // XAR7 still holds the object's WORD address; the byte lane comes from the
    // frame offset parity and is folded into the instruction's displacement
    // field, so neither ACC nor AR0 has to be touched.  Converting the word
    // address into a "byte address" here used to make the plain MOVB read word
    // (word*2+lane) -- twice as far as the object -- which is why byte locals
    // and byte spills read/wrote unrelated words.
    Register Dst = MI.getOperand(0).getReg();
    bool SaveACC = Dst != C28x::ACC && PreserveAcc();
    if (SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
    BuildMI(MBB, II, DL, TII.get(C28x::MOVB_disp_load_AL), C28x::AL)
        .addReg(C28x::XAR7)
        .addImm(Lane);
    BuildMI(MBB, II, DL, TII.get(C28x::MOV16_imm), C28x::AH).addImm(0);
    if (Dst == C28x::XT)
      BuildMI(MBB, II, DL, TII.get(C28x::MOV_ACC_rr), C28x::XT)
          .addReg(C28x::ACC);
    else if (Dst != C28x::ACC)
      BuildMI(MBB, II, DL, TII.get(C28x::MOVL_XAR_ACC), Dst)
          .addReg(C28x::ACC);
    if (SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD32_PSEUDO: {
    // Load low word from *XAR7, high word from *(XAR7+1).  The reload keeps
    // its destination virtual register (loadRegFromStackSlot no longer forces
    // physical ACC), so route the value from ACC to Dst here — matching the
    // non-FI expansion in C28xInstrInfo::expandPostRAPseudo.
    Register Dst = MI.getOperand(0).getReg();
    // A spill reload into XAR4/XAR5 during call setup must not overwrite an
    // integer argument already assigned to ACC (Iter::new's four-arg call).
    bool SaveACC = Dst != C28x::ACC && PreserveAcc();
    if (SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), C28x::AL)
        .addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::ADDB_XAR7_imm)).addImm(1);
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_load), C28x::AH)
        .addReg(C28x::XAR7);
    if (Dst != C28x::ACC) {
      if (Dst == C28x::XT)
        BuildMI(MBB, II, DL, TII.get(C28x::MOV_ACC_rr), C28x::XT)
            .addReg(C28x::ACC);
      else if (C28x::GR32RegClass.contains(Dst))
        BuildMI(MBB, II, DL, TII.get(C28x::MOVL_XAR_ACC), Dst)
            .addReg(C28x::ACC);
      else
        BuildMI(MBB, II, DL, TII.get(TargetOpcode::COPY), Dst)
            .addReg(C28x::ACC);
    }
    if (SaveACC)
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    MI.eraseFromParent();
    return false;
  }
  case C28x::STORE32_PSEUDO: {
    // Stage the value into ACC (AL/AH) first.  storeRegToStackSlot no longer
    // inserts the ACC COPY before this pseudo: with vreg spill sources the
    // value can still live in XARn/XT/ACC when the frame index is eliminated
    // here, and MOV_ind_store_AL/AH consume AL/AH directly.  Preserve a
    // live-through ACC around the staging, like MOV32fi does.
    Register Src = MI.getOperand(1).getReg();
    bool SaveAcc = false;
    if (Src == C28x::ACC) {
      // value already in ACC
    } else {
      SaveAcc = PreserveAcc();
      if (SaveAcc)
        BuildMI(MBB, II, DL, TII.get(C28x::PUSH_ACC));
      if (Src == C28x::XT)
        BuildMI(MBB, II, DL, TII.get(C28x::MOV_ACC_rr), C28x::ACC)
            .addReg(C28x::XT);
      else if (C28x::GR32RegClass.contains(Src))
        BuildMI(MBB, II, DL, TII.get(C28x::MOVL_ACC_XAR), C28x::ACC)
            .addReg(Src);
      else
        BuildMI(MBB, II, DL, TII.get(TargetOpcode::COPY), C28x::ACC)
            .addReg(Src);
    }
    // Store AL to *XAR7, AH to *(XAR7+1) — adjacent words, not the same word.
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_store_AL))
        .addReg(C28x::XAR7);
    BuildMI(MBB, II, DL, TII.get(C28x::ADDB_XAR7_imm)).addImm(1);
    BuildMI(MBB, II, DL, TII.get(C28x::MOV_ind_store_AH))
        .addReg(C28x::XAR7);
    if (SaveAcc)
      BuildMI(MBB, II, DL, TII.get(C28x::POP_ACC));
    MI.eraseFromParent();
    return false;
  }
  case C28x::LOAD8_PSEUDO: {
    Register Dst = MI.getOperand(0).getReg();
    // XAR7 holds the WORD address; the lane rides in the displacement field.
    if (Dst != C28x::AL && Dst != C28x::AH) {
      BuildMI(MBB, II, DL, TII.get(C28x::MOVB_disp_load_AL), C28x::AL)
          .addReg(C28x::XAR7)
          .addImm(Lane);
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), Dst).addReg(C28x::AL);
    } else {
      BuildMI(MBB, II, DL, TII.get(C28x::MOVB_disp_load_AL), Dst)
          .addReg(C28x::XAR7)
          .addImm(Lane);
    }
    MI.eraseFromParent();
    return false;
  }
  case C28x::STORE8_PSEUDO: {
    Register Src = MI.getOperand(1).getReg();
    // No address conversion happens any more, so ACC survives untouched: the
    // value may stay in AL/AH and no save/restore pair is needed.
    Register StgSrc = Src;
    if (Src != C28x::AL && Src != C28x::AH) {
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), C28x::AL).addReg(Src);
      StgSrc = C28x::AL;
    }
    if (StgSrc == C28x::AH) {
      BuildMI(MBB, II, DL, TII.get(C28x::MOV16rr), C28x::AL).addReg(C28x::AH);
    }
    BuildMI(MBB, II, DL, TII.get(C28x::MOVB_disp_store_AL))
        .addReg(C28x::XAR7)
        .addImm(Lane);
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
