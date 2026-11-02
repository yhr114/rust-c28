//===-- C28xInstrInfo.cpp - C28x Instruction Information -----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "C28x.h"
#include "C28xInstrInfo.h"
#include "C28xSubtarget.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/LivePhysRegs.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/Support/ErrorHandling.h"

#define GET_INSTRINFO_CTOR_DTOR
#include "C28xGenInstrInfo.inc"

using namespace llvm;

C28xInstrInfo::C28xInstrInfo(const C28xSubtarget &STI)
    : C28xGenInstrInfo(STI, RI, C28x::ADJCALLSTACKDOWN, C28x::ADJCALLSTACKUP) {}

void C28xInstrInfo::copyPhysReg(MachineBasicBlock &MBB,
                                MachineBasicBlock::iterator I,
                                const DebugLoc &DL, Register DestReg,
                                Register SrcReg, bool KillSrc,
                                bool RenamableDest,
                                bool RenamableSrc) const {
  if (DestReg == SrcReg)
    return;

  // XARn -> XARm has NO register-to-register 32-bit MOVL on C28x.  The
  // encoding previously used here (MOV32rr: "<XARn opcode> | 0xA0|m") is
  // "MOVL XARn, @ARm", and @ARm is *register-direct memory addressing* — it
  // loads from the address held in ARm, it does not copy the register.
  // Hardware evidence (2026-10-27, b1-u32-compose probe): comparing a
  // composed u32 against a 32-bit literal failed 10/10 because the value was
  // moved into the compare register with this instruction; the same compare
  // against a runtime value (no XAR->XAR copy) passed.
  // Expand through the stack instead: PUSH32/POP32 preserve all 32 bits and
  // clobber neither ACC nor XT.
  if (C28x::GR32RegClass.contains(DestReg) &&
      C28x::GR32RegClass.contains(SrcReg)) {
    BuildMI(MBB, I, DL, get(C28x::PUSH32))
        .addReg(SrcReg, getKillRegState(KillSrc));
    BuildMI(MBB, I, DL, get(C28x::POP32), DestReg);
    return;
  }

  // Same trap for XT -> XARn: the loc32 register-direct code for XT (0xAC)
  // means "@XT" (memory at the address in XT), not the XT register.
  if (C28x::GR32RegClass.contains(DestReg) && SrcReg == C28x::XT) {
    BuildMI(MBB, I, DL, get(C28x::PUSH32))
        .addReg(SrcReg, getKillRegState(KillSrc));
    BuildMI(MBB, I, DL, get(C28x::POP32), DestReg);
    return;
  }

  // A full-width move must retain all 32 bits. Never derive subregisters
  // from enum arithmetic: TableGen register numbers are not an ABI.
  unsigned Opcode = 0;
  if (C28x::ACC32RegClass.contains(DestReg, SrcReg))
    Opcode = C28x::MOV_ACC_rr;
  else if (C28x::GR32RegClass.contains(DestReg) &&
           C28x::ACC32RegClass.contains(SrcReg))
    Opcode = C28x::MOVL_XAR_ACC;
  else if (C28x::ACC32RegClass.contains(DestReg) &&
           C28x::GR32RegClass.contains(SrcReg))
    Opcode = C28x::MOVL_ACC_XAR;
  if (Opcode) {
    BuildMI(MBB, I, DL, get(Opcode), DestReg)
        .addReg(SrcReg, getKillRegState(KillSrc));
    return;
  }

  // Obtain a loc16-readable source. Cross-width copies truncate to the low
  // half; explicitly named T is the high half of XT. XAR7 is reserved.
  Register Source16 = SrcReg;
  if (SrcReg == C28x::ACC)
    Source16 = C28x::AL;
  else if (C28x::GR32RegClass.contains(SrcReg))
    Source16 = RI.getSubReg(SrcReg, C28x::sub_lo16);
  else if (SrcReg == C28x::XT || SrcReg == C28x::TL) {
    BuildMI(MBB, I, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
        .addReg(C28x::XT);
    Source16 = C28x::AR7;
  } else if (SrcReg == C28x::T) {
    BuildMI(MBB, I, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, I, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
        .addReg(C28x::XT);
    BuildMI(MBB, I, DL, get(C28x::MOV16rr), C28x::AR7)
        .addReg(C28x::AH);
    BuildMI(MBB, I, DL, get(C28x::POP_ACC));
    Source16 = C28x::AR7;
  }
  if (!C28x::GR16RegClass.contains(Source16) &&
      Source16 != C28x::PL && Source16 != C28x::PH)
    report_fatal_error("C28x: unsupported physical register copy source");

  if (C28x::GR32RegClass.contains(DestReg)) {
    BuildMI(MBB, I, DL, get(C28x::MOVL_XAR_AR), DestReg).addReg(Source16);
  } else if (C28x::ACC32RegClass.contains(DestReg)) {
    // Zero-extension must reach the actual destination, including XT,
    // without destroying an unrelated value in ACC.
    BuildMI(MBB, I, DL, get(C28x::MOVL_XAR_AR), C28x::XAR7).addReg(Source16);
    BuildMI(MBB, I, DL, get(C28x::MOVL_ACC_XAR), DestReg).addReg(C28x::XAR7);
  } else if (DestReg == C28x::TL || DestReg == C28x::T) {
    // Updating one XT half must preserve its other half and live ACC.
    if (Source16 != C28x::AR7)
      BuildMI(MBB, I, DL, get(C28x::MOV16rr), C28x::AR7).addReg(Source16);
    BuildMI(MBB, I, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, I, DL, get(C28x::MOV_ACC_rr), C28x::ACC).addReg(C28x::XT);
    BuildMI(MBB, I, DL, get(C28x::MOV16rr),
            DestReg == C28x::TL ? C28x::AL : C28x::AH).addReg(C28x::AR7);
    BuildMI(MBB, I, DL, get(C28x::MOV_ACC_rr), C28x::XT).addReg(C28x::ACC);
    BuildMI(MBB, I, DL, get(C28x::POP_ACC));
  } else if (C28x::GR16RegClass.contains(DestReg) ||
             DestReg == C28x::PL || DestReg == C28x::PH) {
    if (DestReg != Source16)
      BuildMI(MBB, I, DL, get(C28x::MOV16rr), DestReg).addReg(Source16);
  } else {
    report_fatal_error("C28x: unsupported physical register copy destination");
  }
}

static bool isCondBranchPseudo(unsigned Op) {
  return Op == C28x::B_EQ_p || Op == C28x::B_NE_p || Op == C28x::B_GT_p ||
         Op == C28x::B_GE_p || Op == C28x::B_LT_p || Op == C28x::B_LE_p ||
         Op == C28x::B_HI_p || Op == C28x::B_HIS_p || Op == C28x::B_LO_p ||
         Op == C28x::B_LOS_p;
}

// Real conditional branches (after ExpandPostRAPseudos).
static bool isRealCondBranch(unsigned Op) {
  return Op == C28x::B_EQ || Op == C28x::B_NE || Op == C28x::B_GT ||
         Op == C28x::B_GE || Op == C28x::B_LT || Op == C28x::B_LE ||
         Op == C28x::B_HI || Op == C28x::B_HIS || Op == C28x::B_LO ||
         Op == C28x::B_LOS;
}

static bool isAnyCondBranch(unsigned Op) {
  return isCondBranchPseudo(Op) || isRealCondBranch(Op);
}

static bool isAnyUncondJump(unsigned Op) {
  return Op == C28x::B_JMP || Op == C28x::B_JMP_Pseudo;
}

void C28xInstrInfo::storeRegToStackSlot(MachineBasicBlock &MBB,
                                        MachineBasicBlock::iterator I,
                                        Register SrcReg, bool IsKill, int FI,
                                        const TargetRegisterClass *RC,
                                        Register VReg,
                                        MachineInstr::MIFlag Flags) const {
  DebugLoc DL;
  if (I != MBB.end())
    DL = I->getDebugLoc();
  // Pick the store width from the register class RC, NOT from SrcReg: during
  // live-range splitting (InlineSpiller) SrcReg is a freshly created virtual
  // register and never matches a physical-reg class test, so dispatching on
  // SrcReg wrongly routed every 32-bit spill through the 16-bit store.
  bool Want32 = RC && RC->getSizeInBits() >= 32;
  if (Want32) {
    // Emit the spill with the virtual register as the source operand.
    // Do NOT stage the value through physical ACC with an explicit COPY:
    // InlineSpiller inserts this sequence after LiveIntervals has finished
    // computing physical-register liveranges, so a COPY def of $acc here
    // never gets a live segment and a following $acc use trips the machine
    // verifier ("No live segment at use").  Keeping a vreg operand lets
    // VirtRegRewriter substitute the physical register and the post-RA
    // STORE32_PSEUDO expansion stage it into ACC at that point (it already
    // handles ACC/XT/XARn and residual vreg sources).
    BuildMI(MBB, I, DL, get(C28x::STORE32_PSEUDO))
        .addFrameIndex(FI)
        .addReg(SrcReg, getKillRegState(IsKill))
        .setMIFlag(Flags);
  } else {
    BuildMI(MBB, I, DL, get(C28x::STORE16_PSEUDO))
        .addFrameIndex(FI)
        .addReg(SrcReg, getKillRegState(IsKill))
        .setMIFlag(Flags);
  }
}

void C28xInstrInfo::loadRegFromStackSlot(MachineBasicBlock &MBB,
                                         MachineBasicBlock::iterator I,
                                         Register DstReg, int FI,
                                         const TargetRegisterClass *RC,
                                         Register VReg, unsigned SubReg,
                                         MachineInstr::MIFlag Flags) const {
  DebugLoc DL;
  if (I != MBB.end())
    DL = I->getDebugLoc();
  // Pick the load width from RC/SubReg, NOT from DstReg: during live-range
  // splitting (InlineSpiller) DstReg is a freshly created virtual register
  // and never matches a physical-reg class test, so a dispatch on DstReg
  // wrongly emitted a 16-bit LOAD for a 32-bit value (the reload vreg then
  // collided on the single ACC, producing "ran out of registers").
  bool Want32 = (SubReg == 0) && RC && RC->getSizeInBits() >= 32;
  if (Want32) {
    // Emit the reload with the destination virtual register directly.
    // Do NOT stage through physical ACC with a COPY (see the matching
    // storeRegToStackSlot comment: a COPY into/out of $acc inserted after
    // LiveIntervals has no live segment and trips the machine verifier).
    // The post-RA LOAD32_PSEUDO expansion loads into ACC and routes to the
    // physical destination VirtRegRewriter chose.
    BuildMI(MBB, I, DL, get(C28x::LOAD32_PSEUDO), DstReg)
        .addFrameIndex(FI)
        .setMIFlag(Flags);
  } else {
    // 16-bit (or sub-register) reload.
    BuildMI(MBB, I, DL, get(C28x::LOAD16_PSEUDO), DstReg)
        .addFrameIndex(FI)
        .setMIFlag(Flags);
  }
}

static unsigned realOpcodeFromCondEnc(unsigned Enc);

bool C28xInstrInfo::expandPostRAPseudo(MachineInstr &MI) const {
  MachineBasicBlock &MBB = *MI.getParent();
  const DebugLoc &DL = MI.getDebugLoc();
  const bool SaveScratchXAR0 =
      MBB.computeRegisterLiveness(&RI, C28x::XAR0, MI) !=
      MachineBasicBlock::LQR_Dead;

  // Route a result held in physical ACC to the (physical) destination reg.
  auto RouteFromACC = [&](Register Dst) {
    if (Dst == C28x::ACC)
      return;
    if (Dst == C28x::XT)
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT)
          .addReg(C28x::ACC);
    else
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), Dst)
          .addReg(C28x::ACC);
  };
  // Is ACC provably dead at MI?  True only when the nearest earlier reference
  // to ACC in this block is a killing use (e.g. fast-isel spilling a live-in
  // ACC parameter to XT with `movl xt, acc` kill).  Expansions that clobber
  // ACC must save it unless this returns true: the forward scan below answers
  // "is ACC needed later", which is NOT the same question — a later def can
  // hide a live incoming value and would otherwise drop the save.
  auto AccProvablyDead = [&]() {
    if (MI.getIterator() == MBB.begin())
      return false;
    bool LowDead = false, HighDead = false;
    for (auto It = std::prev(MI.getIterator());; --It) {
      for (const MachineOperand &Op : It->operands()) {
        if (!Op.isReg())
          continue;
        Register R = Op.getReg();
        bool Low = R && RI.regsOverlap(R, C28x::AL) && !LowDead;
        bool High = R && RI.regsOverlap(R, C28x::AH) && !HighDead;
        if (!Low && !High) continue;
        if (Op.isDef() || !Op.isKill()) return false;
        LowDead |= Low;
        HighDead |= High;
      }
      if (LowDead && HighDead) return true;
      if (It == MBB.begin())
        return false;
    }
  };
  auto AccLiveThrough = [&](Register DefinedByMI = Register()) {
    // We are about to use ACC as scratch.  Preserve it only if a later
    // instruction reads ACC (or one of its AL/AH aliases) before redefining
    // it.  A backward live-in check misclassifies killed incoming arguments,
    // so a provably-dead ACC short-circuits to "no save".
    if (AccProvablyDead())
      return false;
    // ACC must hold a value at MI; only skip on a definite Dead (a missed save
    // is silent wrong code, the remaining spurious save is benign).
    if (MBB.computeRegisterLiveness(&RI, C28x::ACC, MI, 200) ==
        MachineBasicBlock::LQR_Dead) {
      bool HasDef = false;
      for (auto It = MBB.begin(); !HasDef && It != MI.getIterator(); ++It)
        for (const MachineOperand &Op : It->operands())
          if (Op.isReg() && Op.isDef() &&
              RI.regsOverlap(Op.getReg(), C28x::ACC)) {
            HasDef = true;
            break;
          }
      if (!HasDef)
        return false;
    }
    // A narrow load may define AL or AH while the OTHER half survives.
    // Ignore the result half: subsequent uses there refer to the new load,
    // not an old value that needs saving (which may be undefined).
    bool LowDefined = DefinedByMI && RI.regsOverlap(DefinedByMI, C28x::AL);
    bool HighDefined = DefinedByMI && RI.regsOverlap(DefinedByMI, C28x::AH);
    for (auto It = std::next(MI.getIterator()); It != MBB.end(); ++It) {
      for (const MachineOperand &Op : It->operands()) {
        if (!Op.isReg() || !Op.isUse())
          continue;
        Register R = Op.getReg();
        if ((R && RI.regsOverlap(R, C28x::AL) && !LowDefined) ||
            (R && RI.regsOverlap(R, C28x::AH) && !HighDefined))
          return true;
      }
      for (const MachineOperand &Op : It->operands()) {
        if (!Op.isReg() || !Op.isDef())
          continue;
        Register R = Op.getReg();
        if (R && RI.regsOverlap(R, C28x::AL))
          LowDefined = true;
        if (R && RI.regsOverlap(R, C28x::AH))
          HighDefined = true;
      }
      if (LowDefined && HighDefined)
        return false;
    }
    for (const MachineBasicBlock *Succ : MBB.successors())
      for (const auto &LiveIn : Succ->liveins()) {
        Register R = LiveIn.PhysReg;
        if ((!LowDefined && RI.regsOverlap(R, C28x::AL)) ||
            (!HighDefined && RI.regsOverlap(R, C28x::AH)))
          return true;
      }
    return false;
  };
  auto EmitIndexedByteAddress = [&](Register Ptr) {
    // XAR7 receives the physical word address.  AR0 is the 0/1 byte offset
    // consumed by MOVB's indexed form; the low bit of XARn itself does not
    // select a byte lane on C28x.
    BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC).addReg(Ptr);
    BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
        .addReg(C28x::ACC);
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AR0).addImm(1);
    BuildMI(MBB, MI, DL, get(C28x::AND16rr), C28x::AL)
        .addReg(C28x::AL).addReg(C28x::AR0);
    BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AR0).addReg(C28x::AL);
    BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
        .addReg(C28x::XAR7);
    BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
    BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC)
        .addReg(C28x::ACC);
    BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
        .addReg(C28x::ACC);
  };
  // Bring a wide (GPR32) physical value into physical ACC.
  auto LoadWideToACC = [&](Register Src) {
    if (Src == C28x::ACC)
      return;
    if (Src == C28x::XT)
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
          .addReg(C28x::XT);
    else
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
          .addReg(Src);
  };

  switch (MI.getOpcode()) {
  case C28x::TRAP: {
    // Loop at this instruction, not at the MBB entry. The latter may have no
    // emitted label, and would repeat preceding side effects/prologue pushes.
    BuildMI(MBB, MI, DL, get(C28x::B_SELF));
    MBB.erase(MI);
    return true;
  }
  case C28x::IRET: {
    // Software context and NASP are emitted by frame lowering. IRET restores
    // the interrupted hardware frame, including the pre-interrupt INTM state.
    BuildMI(MBB, MI, DL, get(C28x::IRET_Real));
    MBB.erase(MI);
    return true;
  }
  case C28x::ZEXT16_32_CORE: {
    // Build zero-extended value in ACC: MOV AL, src; MOV AH, #0.
    Register Src = MI.getOperand(1).getReg();
    BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AL).addReg(Src);
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH).addImm(0);
    MBB.erase(MI);
    return true;
  }
  case C28x::MOV32_imm32_CORE: {
    // Build arbitrary 32-bit constant in ACC: MOV AL,#lo16; MOV AH,#hi16.
    int32_t Val = (int32_t)MI.getOperand(1).getImm();
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AL)
        .addImm(Val & 0xFFFF);
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH)
        .addImm((Val >> 16) & 0xFFFF);
    MBB.erase(MI);
    return true;
  }
  case C28x::MOV32_imm32: {
    // Arbitrary 32-bit constant -> Dst (wide), built in ACC then routed.
    Register Dst = MI.getOperand(0).getReg();
    int32_t Val = (int32_t)MI.getOperand(1).getImm();
    LivePhysRegs Live(RI);
    Live.addLiveOuts(MBB);
    for (auto I = MBB.end(); I != MI.getIterator();) {
      --I;
      if (&*I != &MI)
        Live.stepBackward(*I);
    }
    bool Save = Dst != C28x::ACC &&
                !Live.available(MBB.getParent()->getRegInfo(), C28x::ACC);
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AL)
        .addImm(Val & 0xFFFF);
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH)
        .addImm((Val >> 16) & 0xFFFF);
    RouteFromACC(Dst);
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::TRUNC32_16: {
    // Dst (GR16) = low half of wide Src.  Park Src in XAR7, MOV Dst,AR7.
    Register Dst = MI.getOperand(0).getReg();
    Register Src = MI.getOperand(1).getReg();

    if (Src == C28x::XAR7) {
      // already
    } else if (Src == C28x::ACC) {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
    } else if (C28x::GR32RegClass.contains(Src)) {
      // XARn -> XAR7 has no register-to-register 32-bit MOVL on C28x; the
      // MOV32rr opcode encodes "MOVL XAR7, @ARn" (a 32-bit memory read from
      // the address in ARn), NOT a copy. Stage via the stack instead.
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(Src);
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR7);
    } else { // XT
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
          .addReg(C28x::XT);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    }
    if (Dst != C28x::AR7)
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), Dst).addReg(C28x::AR7);
    MBB.erase(MI);
    return true;
  }
  case C28x::ZEXT16_32: {
    // Zero-extend GR16 Src -> wide Dst: AL=Src, AH=0.
    Register Dst = MI.getOperand(0).getReg();
    Register Src = MI.getOperand(1).getReg();
    bool Save = Dst != C28x::ACC;
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    if (Src != C28x::AL)
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AL).addReg(Src);
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH).addImm(0);
    RouteFromACC(Dst);
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::SEXT16_32: {
    // Sign-extend GR16 Src -> wide Dst: SETC SXM; MOV ACC,Src; route.
    Register Dst = MI.getOperand(0).getReg();
    Register Src = MI.getOperand(1).getReg();
    bool Save = Dst != C28x::ACC;
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, MI, DL, get(C28x::SETC_SXM));
    BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_GR16), C28x::ACC).addReg(Src);
    RouteFromACC(Dst);
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::SHL32_VAR_PSEUDO:
  case C28x::SRL32_VAR_PSEUDO:
  case C28x::SRA32_VAR_PSEUDO: {
    // Wide variable i32 shift.  Stage the count into T (via reserved XAR7),
    // stage Src into ACC, run the hardware LSLL/LSRL/ASRL ACC,T, route result.
    Register Dst = MI.getOperand(0).getReg();
    Register Src = MI.getOperand(1).getReg();
    Register Amt = MI.getOperand(2).getReg();
    bool IsSHL = MI.getOpcode() == C28x::SHL32_VAR_PSEUDO;
    bool IsSRA = MI.getOpcode() == C28x::SRA32_VAR_PSEUDO;
    bool Save = Dst != C28x::ACC && AccLiveThrough();
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));

    // XAR7 = Amt (wide).
    if (Amt == C28x::XAR7) {
      // already there
    } else if (Amt == C28x::ACC) {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
    } else if (Amt == C28x::XT) {
      // Staging XT through ACC must not destroy an ACC source before
      // LoadWideToACC(Src), which is a no-op when Src is already ACC.
      if (Src == C28x::ACC)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
          .addReg(C28x::XT);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
      if (Src == C28x::ACC)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    } else { // XARn
      // MOV32rr would encode "MOVL XAR7, @ARn" (memory read), not a copy.
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(Amt);
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR7);
    }
    // Capture Src before writing T: T aliases the upper half of XT, so
    // setting the count first would corrupt any Src allocated to XT.
    LoadWideToACC(Src);
    BuildMI(MBB, MI, DL, get(C28x::MOV_T)).addReg(C28x::AR7);

    // Shift ACC by T's low five bits.
    if (IsSHL)
      BuildMI(MBB, MI, DL, get(C28x::LSLL_ACC_T), C28x::ACC).addReg(C28x::ACC);
    else if (IsSRA)
      BuildMI(MBB, MI, DL, get(C28x::ASRL_ACC_T), C28x::ACC).addReg(C28x::ACC);
    else
      BuildMI(MBB, MI, DL, get(C28x::LSRL_ACC_T), C28x::ACC).addReg(C28x::ACC);

    RouteFromACC(Dst);
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::UMUL16_32_PSEUDO:
  case C28x::SMUL16_32_PSEUDO: {
    // 16x16 -> 32 product.  T = a; MPY(U) ACC,T,b; route wide result.
    Register Dst = MI.getOperand(0).getReg();
    Register A = MI.getOperand(1).getReg();
    Register B = MI.getOperand(2).getReg();
    bool Unsigned = MI.getOpcode() == C28x::UMUL16_32_PSEUDO;
    bool Save = Dst != C28x::ACC;
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, MI, DL, get(C28x::MOV_T)).addReg(A);
    unsigned MOp = Unsigned ? C28x::MPYU_ACC_T : C28x::MPY_ACC_T;
    BuildMI(MBB, MI, DL, get(MOp), C28x::ACC).addReg(B);
    RouteFromACC(Dst);
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::SRL32_PSEUDO: {
    // Constant logical right shift of wide Src -> wide Dst.
    Register Dst = MI.getOperand(0).getReg();
    Register Src = MI.getOperand(1).getReg();
    unsigned Amt = MI.getOperand(2).getImm();
    bool Save = Dst != C28x::ACC;
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    LoadWideToACC(Src);
    for (unsigned i = 0; i < Amt; ++i) {
      BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
      BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC).addReg(C28x::ACC);
    }
    RouteFromACC(Dst);
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::ADD32imm32:
  case C28x::SUB32imm32: {
    // Dst = Lhs +/- large constant.  Park Lhs in XAR7, build constant in ACC,
    // move constant to XT, restore Lhs to ACC, run ADD/SUB ACC,XT.
    bool IsAdd = MI.getOpcode() == C28x::ADD32imm32;
    Register Dst = MI.getOperand(0).getReg();
    Register Lhs = MI.getOperand(1).getReg();
    int32_t Val = (int32_t)MI.getOperand(2).getImm();

    // `ADD ACC,#16bit` / `SUB ACC,#16bit` ZERO-extend their immediate; they do
    // not sign-extend it.  Hardware-verified on F28035: ACC=0x0808 with
    // `ADD ACC,#0xFFFE` yields 0x0001_0806, not 0x0000_0806.  Expressing a
    // negative constant as a negative immediate therefore leaves a stray
    // 1<<16 in the accumulator, which survives the byte->word `>>1` that
    // follows every address computation:
    //
    //   slice::Iter::next_back  self.end.sub(1)
    //     end(byte)=0x0808 -> 0x10806 -> >>1 -> word 0x8403 (want 0x0403)
    //
    // i.e. `iter().last()` / `.rev()` read from code memory instead of the
    // slice.  Rewrite a negative addend as the opposite operation on the
    // magnitude, which is always representable in 16 bits (|Val| <= 32768).
    if (Val < 0) {
      IsAdd = !IsAdd;
      Val = -Val;
    }

    // Pointer-update peephole:
    //
    //   %xt = COPY %xarN
    //   %xt = ADD32imm32 %xt, imm
    //   %xarN = COPY %xt
    //
    // is commonly produced for a byte-store GEP.  Keep the address in its
    // XAR register instead of routing it through XT.  ACC must still be
    // saved because the following byte store consumes AL as its data value.
    // This is deliberately limited to the exact copy/update/copy shape so
    // ordinary integer arithmetic and live-register cases are untouched.
    if (MI.getOpcode() == C28x::ADD32imm32 && Dst == C28x::XT &&
        Lhs == C28x::XT && Val >= -32768 && Val <= 65535) {
      auto It = MI.getIterator();
      if (It != MBB.begin()) {
        auto PrevIt = std::prev(It);
        auto NextIt = std::next(It);
        if (PrevIt->isCopy() && NextIt != MBB.end() && NextIt->isCopy() &&
            PrevIt->getOperand(0).getReg() == C28x::XT &&
            NextIt->getOperand(1).getReg() == C28x::XT) {
          Register Ptr = PrevIt->getOperand(1).getReg();
          Register Out = NextIt->getOperand(0).getReg();
          if (C28x::GR32RegClass.contains(Ptr) && Out == Ptr) {
            BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
            BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
                .addReg(Ptr);
            BuildMI(MBB, MI, DL, get(C28x::ADD32imm), C28x::ACC)
                .addReg(C28x::ACC).addImm(Val);
            BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), Ptr)
                .addReg(C28x::ACC);
            BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
            MBB.erase(*NextIt);
            MBB.erase(*PrevIt);
            MBB.erase(MI);
            return true;
          }
        }
      }
    }

    bool Save = Dst != C28x::ACC && AccLiveThrough();
    // Fast path: constant fits the real accumulator immediate instruction
    // (-32768..65535).  Stage Lhs into ACC, run add/sub acc,#Val, route result.
    if (Val >= -32768 && Val <= 65535) {
      if (Save)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      LoadWideToACC(Lhs);
      if (IsAdd)
        BuildMI(MBB, MI, DL, get(C28x::ADD32imm), C28x::ACC)
            .addReg(C28x::ACC).addImm(Val);
      else
        BuildMI(MBB, MI, DL, get(C28x::SUB32imm), C28x::ACC)
            .addReg(C28x::ACC).addImm(Val);
      RouteFromACC(Dst);
      if (Save)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      MBB.erase(MI);
      return true;
    }
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));

    // XAR7 = Lhs.
    if (Lhs == C28x::ACC) {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
    } else if (Lhs == C28x::XT) {
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
          .addReg(C28x::XT);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    } else {
      // MOV32rr would encode "MOVL XAR7, @ARn" (memory read), not a copy.
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(Lhs);
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR7);
    }

    // Build constant in ACC then move to XT.
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AL)
        .addImm(Val & 0xFFFF);
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH)
        .addImm((Val >> 16) & 0xFFFF);
    BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT)
        .addReg(C28x::ACC);
    // Restore Lhs to ACC.
    BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
        .addReg(C28x::XAR7);
    if (IsAdd)
      BuildMI(MBB, MI, DL, get(C28x::ADD32rr), C28x::ACC)
          .addReg(C28x::ACC).addReg(C28x::XT);
    else
      BuildMI(MBB, MI, DL, get(C28x::SUB32rr), C28x::ACC)
          .addReg(C28x::ACC).addReg(C28x::XT);
    RouteFromACC(Dst);
    if (Save)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::ADJCALLSTACKDOWN:
  case C28x::ADJCALLSTACKUP: {
    unsigned Bytes = MI.getOperand(0).getImm();
    unsigned Words = (Bytes + 1) / 2;
    bool IsDown = MI.getOpcode() == C28x::ADJCALLSTACKDOWN;
    unsigned Opc = IsDown ? C28x::ADDB_SP : C28x::SUBB_SP;
    // 7-bit SP immediate (0..127): emit in chunks.
    while (Words > 0) {
      unsigned Chunk = Words > 127 ? 127 : Words;
      BuildMI(MBB, MI, DL, get(Opc)).addImm(Chunk);
      Words -= Chunk;
    }
    MBB.erase(MI);
    return true;
  }
  case C28x::STORE_STK16: {
    int WordOff = (int)(int16_t)(uint16_t)MI.getOperand(0).getImm();
    Register Src = MI.getOperand(1).getReg();
    // XAR7 is the address scratch, so a value that already lives in XAR7 must
    // be moved out BEFORE the address is materialised (otherwise the store
    // would write the low half of SP).
    const bool StagedToAh = Src == C28x::AR7;
    if (StagedToAh)
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AH).addReg(Src);
    BuildMI(MBB, MI, DL, get(C28x::MOVZ_XAR7_SP));
    // XAR7 = SP + WordOff.  ADDB/SUBB XAR7 take a 7-bit immediate, so chunk.
    if (WordOff > 0) {
      unsigned R = (unsigned)WordOff;
      while (R) {
        unsigned C = std::min(R, 127u);
        BuildMI(MBB, MI, DL, get(C28x::ADDB_XAR7_imm)).addImm(C);
        R -= C;
      }
    } else if (WordOff < 0) {
      unsigned R = (unsigned)(-WordOff);
      while (R) {
        unsigned C = std::min(R, 127u);
        BuildMI(MBB, MI, DL, get(C28x::SUBB_XAR7_imm)).addImm(C);
        R -= C;
      }
    }
    if (StagedToAh) {
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_store_AH)).addReg(C28x::XAR7);
    } else if (Src == C28x::AL || Src == C28x::AH) {
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_store)).addReg(C28x::XAR7).addReg(Src);
    } else if (C28x::ARegsRegClass.contains(Src)) {
      // Store straight from the AR register.  Staging through AH instead
      // silently destroys the high half of a live ACC: measured on target,
      // a u32 argument parked in ACC across the call setup lost its high
      // half to this staging, so the callee summed garbage (the Rust caller
      // of rust_stack_args passed ACC=0x0005_0006 instead of 6).
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_store_AR)).addReg(C28x::XAR7).addReg(Src);
    } else {
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AH).addReg(Src);
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_store)).addReg(C28x::XAR7).addReg(C28x::AH);
    }
    MBB.erase(MI);
    return true;
  }
  case C28x::CMPBR16_PSEUDO:
  case C28x::CMPBR32_PSEUDO: {
    unsigned CompareOp = MI.getOpcode() == C28x::CMPBR32_PSEUDO
                             ? C28x::CMP32_PSEUDO : C28x::CMP16_PSEUDO;
    auto Compare = BuildMI(MBB, MI, DL, get(CompareOp))
        .addReg(MI.getOperand(1).getReg()).addReg(MI.getOperand(2).getReg());
    expandPostRAPseudo(*Compare);
    BuildMI(MBB, MI, DL, get(realOpcodeFromCondEnc(MI.getOperand(3).getImm())))
        .addMBB(MI.getOperand(0).getMBB());
    MBB.erase(MI);
    return true;
  }
  case C28x::CMP16_PSEUDO: {
    Register LHS = MI.getOperand(0).getReg();
    Register RHS = MI.getOperand(1).getReg();
    // CMP_AL_rr compares RHS against AL; move LHS into AL only when needed.
    if (LHS != C28x::AL)
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AL).addReg(LHS);
    BuildMI(MBB, MI, DL, get(C28x::CMP_AL_rr)).addReg(RHS);
    MBB.erase(MI);
    return true;
  }
  case C28x::CMP32_PSEUDO: {
    // Arrange XT=Rhs, ACC=Lhs via reserved XAR7, then SUBL ACC,XT for flags.
    Register Lhs = MI.getOperand(0).getReg();
    Register Rhs = MI.getOperand(1).getReg();

    // XAR7 = Lhs.
    if (Lhs == C28x::XAR7) {
      // already
    } else if (Lhs == C28x::ACC) {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
    } else if (Lhs == C28x::XT) {
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
          .addReg(C28x::XT);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    } else {
      // MOV32rr would encode "MOVL XAR7, @ARn" (memory read), not a copy.
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(Lhs);
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR7);
    }

    // ACC = Rhs.
    if (Rhs == C28x::ACC) {
      // already
    } else if (Rhs == C28x::XT) {
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
          .addReg(C28x::XT);
    } else {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
          .addReg(Rhs);
    }
    // XT = Rhs.
    BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT)
        .addReg(C28x::ACC);
    // ACC = Lhs.
    BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
        .addReg(C28x::XAR7);
    // Compare: SUBL sets N/Z in ST0; result in ACC is discarded.
    BuildMI(MBB, MI, DL, get(C28x::SUB32rr), C28x::ACC)
        .addReg(C28x::ACC).addReg(C28x::XT);
    MBB.erase(MI);
    return true;
  }
  case C28x::ADD32_PSEUDO:
  case C28x::SUB32_PSEUDO: {
    // Wide 32-bit add/sub, fully expanded post-RA.  Liveness-lean sequence:
    // the pseudo declares Defs=[ACC,XT], so the allocator has already moved
    // every live value out of ACC/XT -- the old unconditional PUSH_ACC/POP_ACC
    // staging (an outer ACC save plus an ACC round-trip to move XAR7 into XT)
    // pushed dead values and cost ~10 instructions where 6 suffice, with two
    // dead stack words on top.  Order matters: park LHS in the reserved XAR7
    // first, then build XT=Rhs while ACC is free, then reload ACC=Lhs.  The
    // one corner that still needs a transient push is Lhs==XT && Rhs==ACC
    // (each operand lives in the register the other's staging clobbers).
    // Lhs/Rhs are never XAR7: the register is reserved as scratch.
    bool IsAdd = MI.getOpcode() == C28x::ADD32_PSEUDO;
    Register Dst = MI.getOperand(0).getReg();
    Register Lhs = MI.getOperand(1).getReg();
    Register Rhs = MI.getOperand(2).getReg();

    // XAR7 = Lhs.
    bool AccHoldsLhs = false;
    if (Lhs == C28x::ACC) {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
      AccHoldsLhs = true;
    } else if (Lhs == C28x::XT) {
      if (Rhs == C28x::ACC) {
        // Both operands sit in registers the other's staging clobbers:
        // save Rhs, park Lhs in XAR7, restore Rhs straight into XT.
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
        BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
            .addReg(C28x::XT);
        BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
            .addReg(C28x::ACC);
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
        BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT)
            .addReg(C28x::ACC);
      } else {
        BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
            .addReg(C28x::XT);
        BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
            .addReg(C28x::ACC);
        AccHoldsLhs = true;
      }
    } else {
      // MOV32rr would encode "MOVL XAR7, @ARn" (memory read), not a copy.
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(Lhs);
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR7);
    }

    // XT = Rhs, unless already there or staged by the corner above.  ACC
    // holds nothing live here, so the XAR->XT staging needs no push/pop;
    // Rhs==ACC moves directly and does NOT clobber ACC.
    const bool CornerLhsXtRhsAcc = (Lhs == C28x::XT && Rhs == C28x::ACC);
    if (!CornerLhsXtRhsAcc && Rhs != C28x::XT) {
      if (Rhs == C28x::ACC) {
        BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT)
            .addReg(C28x::ACC);
      } else {
        BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
            .addReg(Rhs);
        BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT)
            .addReg(C28x::ACC);
        AccHoldsLhs = false; // ACC was overwritten with Rhs
      }
    }

    // ACC = Lhs (already there when the Lhs staging passed through ACC).
    if (!AccHoldsLhs)
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
          .addReg(C28x::XAR7);

    if (IsAdd)
      BuildMI(MBB, MI, DL, get(C28x::ADD32rr), C28x::ACC)
          .addReg(C28x::ACC).addReg(C28x::XT);
    else
      BuildMI(MBB, MI, DL, get(C28x::SUB32rr), C28x::ACC)
          .addReg(C28x::ACC).addReg(C28x::XT);

    // Route result to Dst.
    if (Dst == C28x::ACC) {
      // already
    } else if (Dst == C28x::XT) {
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT)
          .addReg(C28x::ACC);
    } else {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), Dst)
          .addReg(C28x::ACC);
    }

    MBB.erase(MI);
    return true;
  }
  case C28x::AND32_PSEUDO:
  case C28x::OR32_PSEUDO:
  case C28x::XOR32_PSEUDO: {
    // Wide 32-bit logical op, fully expanded post-RA (no pre-RA ACC pinning).
    // Result is computed in ACC then routed to Dst.  XAR7 is the reserved
    // scratch; AR0 is borrowed (push/pop) to hold one Rhs half at a time.
    unsigned Op = MI.getOpcode();
    Register Dst = MI.getOperand(0).getReg();
    Register Lhs = MI.getOperand(1).getReg();
    Register Rhs = MI.getOperand(2).getReg();

    // If Rhs is in ACC but Lhs is not, park Rhs in XAR7 so loading Lhs into
    // ACC does not lose it.
    Register RhsR = Rhs;
    if (Rhs == C28x::ACC && Lhs != C28x::ACC) {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
      RhsR = C28x::XAR7;
    } else if (Rhs == C28x::XAR0) {
      // XAR0 can only hold a DYING Rhs operand here (the pseudo defs XAR0,
      // so no live-across value is assigned there).  The half extraction
      // below writes AR0 — the low half of XAR0 — between the two Rhs reads,
      // so a materialized constant in XAR0 would be zeroed before the second
      // EmitLoadRhs() and the op would degenerate to Lhs&0.  Park Rhs in the
      // reserved XAR7 scratch first.  Hardware symptom: is_some lowers to
      // `and i32 tag, 1` with the 1 in XAR0 and returned 0 for Some(5).
      // MOV32rr would encode "MOVL XAR7, @AR0" (memory read), not a copy.
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR7);
      RhsR = C28x::XAR7;
    }

    // Preserve a live ACC unless the result itself lands in ACC.
    bool SaveACC = (Dst != C28x::ACC);
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));

    // Bring Lhs into ACC.
    if (Lhs == C28x::ACC) {
      // already
    } else if (Lhs == C28x::XT) {
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
          .addReg(C28x::XT);
    } else {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
          .addReg(Lhs);
    }

    unsigned Op16;
    switch (Op) {
    case C28x::AND32_PSEUDO: Op16 = C28x::AND16rr; break;
    case C28x::OR32_PSEUDO:  Op16 = C28x::OR16rr;  break;
    default:                 Op16 = C28x::XOR16rr; break;
    }

    // Bring RhsR into ACC (ACC currently holds Lhs) for one half extraction.
    auto EmitLoadRhs = [&]() {
      if (RhsR == C28x::ACC) {
        // already in ACC (self-op)
      } else if (RhsR == C28x::XT) {
        BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
            .addReg(C28x::XT);
      } else {
        BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
            .addReg(RhsR);
      }
    };

    if (SaveScratchXAR0)

      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
    // High half: extract Rhs high into AR0, apply to AH.  EmitLoadRhs()
    // overwrites ACC with Rhs, so Lhs (currently in ACC) must be saved and
    // restored around each half — same discipline as the *_HALF_PSEUDO
    // expansion below.  Without this the op degenerates to Rhs&Rhs (==Rhs):
    // observed on hardware as is_some reading 0 for Some (is_some lowers to
    // `and i32 tag, 1` with tag in ACC and the constant 1 in XAR0).
    BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    EmitLoadRhs();
    BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AR0).addReg(C28x::AH);
    BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    BuildMI(MBB, MI, DL, get(Op16), C28x::AH)
        .addReg(C28x::AH).addReg(C28x::AR0);
    // Low half: extract Rhs low into AR0, apply to AL.
    BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    EmitLoadRhs();
    BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AR0).addReg(C28x::AL);
    BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    BuildMI(MBB, MI, DL, get(Op16), C28x::AL)
        .addReg(C28x::AL).addReg(C28x::AR0);
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR0);

    // Route result (in ACC) to Dst.
    if (Dst == C28x::ACC) {
      // already
    } else if (Dst == C28x::XT) {
      BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT)
          .addReg(C28x::ACC);
    } else {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), Dst)
          .addReg(C28x::ACC);
    }
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));

    MBB.erase(MI);
    return true;
  }
  case C28x::AND32_HALF_PSEUDO:
  case C28x::OR32_HALF_PSEUDO:
  case C28x::XOR32_HALF_PSEUDO: {
    // 32-bit logic: split into AL/AH 16-bit ops, using AR0 as scratch.
    // dst=lhs=ACC (tied). rhs is ACC32 (ACC or XT).
    unsigned Op = MI.getOpcode();
    Register Rhs = MI.getOperand(2).getReg();
    // Self-operation: rhs == ACC.
    if (Rhs == C28x::ACC) {
      if (Op == C28x::XOR32_HALF_PSEUDO) {
        // ACC ^ ACC = 0
        BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_imm), C28x::ACC).addImm(0);
      }
      // AND/OR: no-op (ACC unchanged).
      MBB.erase(MI);
      return true;
    }
    // rhs is XT.  Expand to half-16 ops.
    unsigned Op16;
    switch (Op) {
    case C28x::AND32_HALF_PSEUDO: Op16 = C28x::AND16rr; break;
    case C28x::OR32_HALF_PSEUDO:  Op16 = C28x::OR16rr;  break;
    default:                       Op16 = C28x::XOR16rr; break;
    }
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
    // High half: AR0 = RHS high (AH of XT)
    BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC).addReg(Rhs);
    BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AR0).addReg(C28x::AH);
    BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    BuildMI(MBB, MI, DL, get(Op16), C28x::AH).addReg(C28x::AH).addReg(C28x::AR0);
    // Low half: AR0 = RHS low (AL of XT)
    BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC).addReg(Rhs);
    BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AR0).addReg(C28x::AL);
    BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    BuildMI(MBB, MI, DL, get(Op16), C28x::AL).addReg(C28x::AL).addReg(C28x::AR0);
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR0);
    MBB.erase(MI);
    return true;
  }
  case C28x::SRL32_CORE: {
    // Logical right shift by N in physical ACC: N * (CLRC C; ROR ACC).
    unsigned Amt = MI.getOperand(2).getImm();
    for (unsigned i = 0; i < Amt; ++i) {
      BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
      BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC).addReg(C28x::ACC);
    }
    MBB.erase(MI);
    return true;
  }
  case C28x::STORE32_XT_PSEUDO: {
    // Spill XT to stack: push acc; movl acc,xt; store32 fi; pop acc.
    int FI = MI.getOperand(0).getIndex();
    BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC).addReg(C28x::XT);
    BuildMI(MBB, MI, DL, get(C28x::STORE32_PSEUDO))
        .addFrameIndex(FI).addReg(C28x::ACC);
    BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::LOAD32_XT_PSEUDO: {
    // Reload from stack into XT: push acc; load32 acc; movl xt,acc; pop acc.
    int FI = MI.getOperand(0).getIndex();
    BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, MI, DL, get(C28x::LOAD32_PSEUDO), C28x::ACC)
        .addFrameIndex(FI);
    BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::XT).addReg(C28x::ACC);
    BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::B_EQ_p:
  case C28x::B_NE_p:
  case C28x::B_GT_p:
  case C28x::B_GE_p:
  case C28x::B_LT_p:
  case C28x::B_LE_p:
  case C28x::B_HI_p:
  case C28x::B_HIS_p:
  case C28x::B_LO_p:
  case C28x::B_LOS_p: {
    MachineBasicBlock *Dst = MI.getOperand(0).getMBB();
    unsigned RealOp;
    switch (MI.getOpcode()) {
  case C28x::B_EQ_p: RealOp = C28x::B_EQ; break;
    case C28x::B_NE_p: RealOp = C28x::B_NE; break;
    case C28x::B_GT_p: RealOp = C28x::B_GT; break;
    case C28x::B_GE_p: RealOp = C28x::B_GE; break;
    case C28x::B_LT_p: RealOp = C28x::B_LT; break;
    case C28x::B_LE_p: RealOp = C28x::B_LE; break;
    case C28x::B_HI_p: RealOp = C28x::B_HI; break;
    case C28x::B_HIS_p: RealOp = C28x::B_HIS; break;
    case C28x::B_LO_p: RealOp = C28x::B_LO; break;
    default:           RealOp = C28x::B_LOS; break;
    }
    BuildMI(MBB, MI, DL, get(RealOp)).addMBB(Dst);
    MBB.erase(MI);
    return true;
  }
  case C28x::B_JMP_Pseudo: {
    MachineBasicBlock *Dst = MI.getOperand(0).getMBB();
    BuildMI(MBB, MI, DL, get(C28x::B_JMP)).addMBB(Dst);
    MBB.erase(MI);
    return true;
  }
  case C28x::LCR_IND: {
    // Function pointer is a byte address (ABI L1-1); LCR *XARn loads XARn
    // directly into PC which expects a WORD address.  Convert byte->word.
    // PUSH/POP ACC preserves call arguments that may be in ACC/AL.
    Register Ptr = MI.getOperand(0).getReg();
    BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC).addReg(Ptr);
    BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
    BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC).addReg(C28x::ACC);
    BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7).addReg(C28x::ACC);
    BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    auto Call = BuildMI(MBB, MI, DL, get(C28x::LCR_IND_REAL))
                    .addReg(C28x::XAR7);
    // Keep argument liveness and any call-preserved mask on the replacement.
    for (const MachineOperand &Op : MI.operands())
      if (Op.isRegMask() || (Op.isReg() && Op.isImplicit() && Op.isUse()))
        Call->addOperand(*MBB.getParent(), Op);
    MBB.erase(MI);
    return true;
  }
  case C28x::MOVL_XAR_ga: {
    // Materialise a global/external symbol as a logical byte address.
    // Linker supplies a 22-bit WORD address; ABI L1-1 requires byte
    // addresses, so double it. ACC is doubling scratch.
    // Only PUSH/POP ACC when it is already live (defined earlier in the
    // block or a live-in); otherwise the verifier flags an undefined read.
    Register Dst = MI.getOperand(0).getReg();
    bool ACCLive = MBB.isLiveIn(C28x::ACC) || MBB.isLiveIn(C28x::AL) ||
                   MBB.isLiveIn(C28x::AH);
    if (!ACCLive) {
      for (auto K = MI.getIterator(); K != MBB.begin(); ) {
        --K;
        if (K->modifiesRegister(C28x::ACC, &RI)) { ACCLive = true; break; }
      }
    }
    if (ACCLive)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    auto MIB = BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_imm), Dst);
    MIB->addOperand(MI.getOperand(1));
    BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC).addReg(Dst);
    // Double via left rotate through carry (lane = 0): CLRC C; ROL ACC.
    BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
    BuildMI(MBB, MI, DL, get(C28x::ROL_ACC), C28x::ACC).addReg(C28x::ACC);
    BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), Dst).addReg(C28x::ACC);
    if (ACCLive)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::ADD16_PSEUDO:
  case C28x::SUB16_PSEUDO:
  case C28x::AND16_PSEUDO:
  case C28x::OR16_PSEUDO:
  case C28x::XOR16_PSEUDO: {
    // Wide 16-bit ALU: dst/lhs/rhs may be any GR16.  C28x only encodes
    // "OP AX, loc16" with the result in an accumulator half.  AR7 is the
    // reserved scratch register; stage RHS there, run the op in the
    // accumulator half that matches Dst (no result copy when Dst is AL/AH),
    // and move the result out only when Dst is an ARn.
    unsigned Pseudo = MI.getOpcode();
    Register Dst = MI.getOperand(0).getReg();
    Register Lhs = MI.getOperand(1).getReg();
    Register Rhs = MI.getOperand(2).getReg();

    unsigned Op16;
    switch (Pseudo) {
    case C28x::ADD16_PSEUDO: Op16 = C28x::ADD16rr; break;
    case C28x::SUB16_PSEUDO: Op16 = C28x::SUB16rr; break;
    case C28x::AND16_PSEUDO: Op16 = C28x::AND16rr; break;
    case C28x::OR16_PSEUDO:  Op16 = C28x::OR16rr;  break;
    default:                  Op16 = C28x::XOR16rr; break;
    }

    // Keep accumulator-half operands in their native form whenever possible.
    // The C28x AL/AH register-direct encodings are valid loc16 operands and
    // avoid an unnecessary AR7 staging move.  Stage only the one aliasing
    // case where copying Lhs into the working accumulator half would
    // overwrite RHS first. Non-accumulator destinations compute in AL too.
    bool DstIsAcc = (Dst == C28x::AL || Dst == C28x::AH);
    Register WorkReg = DstIsAcc ? Dst : Register(C28x::AL);
    bool NeedStage = Rhs == WorkReg && Lhs != WorkReg;
    Register RhsReg = Rhs;
    if (NeedStage) {
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_AR), C28x::XAR7).addReg(Rhs);
      RhsReg = C28x::AR7;
    }

    if (DstIsAcc) {
      // Work directly in Dst's accumulator half.  The other half is never
      // written, so any live-through value there is preserved.
      if (Lhs != Dst)
        BuildMI(MBB, MI, DL, get(C28x::MOV16rr), Dst).addReg(Lhs);
      BuildMI(MBB, MI, DL, get(Op16), Dst)
          .addReg(Dst).addReg(RhsReg);
    } else {
      // Dst is AR0-6.  AL may hold a live-through value, so preserve ACC
      // around the computation and move the result to Dst before POP.
      // Only save when ACC (AL/AH) is actually live through this expansion;
      // an unconditional PUSH_ACC would read an undefined ACC when the value
      // is dead, which the machine verifier rejects.
      bool SaveACC = AccLiveThrough();
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      if (Lhs != C28x::AL)
        BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AL).addReg(Lhs);
      BuildMI(MBB, MI, DL, get(Op16), C28x::AL)
          .addReg(C28x::AL).addReg(RhsReg);
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), Dst).addReg(C28x::AL);
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    }
    MBB.erase(MI);
    return true;
  }
  case C28x::LOAD16_PSEUDO: {
    Register Dst = MI.getOperand(0).getReg();
    MachineOperand PtrOp = MI.getOperand(1);
    if (!PtrOp.isFI()) {
      // Rust data pointers are logical byte addresses (ABI L1-1). Convert to
      // the C28x word address consumed by MOV *XARn.
      Register Ptr = PtrOp.getReg();
      // Fast path: the result lands directly in an accumulator half (Dst) and
      // the other half is dead, so we can clobber all of ACC to move the
      // pointer into XAR7 and leave the loaded value in Dst — no PUSH/POP.
      Register OtherHalf = 0;
      if (Dst == C28x::AL) OtherHalf = C28x::AH;
      else if (Dst == C28x::AH) OtherHalf = C28x::AL;
      if (OtherHalf &&
          MBB.computeRegisterLiveness(&RI, OtherHalf, MI) ==
              MachineBasicBlock::LQR_Dead) {
        BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC).addReg(Ptr);
        BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
        BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC).addReg(C28x::ACC);
        BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
            .addReg(C28x::ACC);
        BuildMI(MBB, MI, DL, get(C28x::MOV_ind_load), Dst)
            .addReg(C28x::XAR7);
        MBB.erase(MI);
        return true;
      }
      bool SaveACC = AccLiveThrough(Dst);
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
       BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC).addReg(Ptr);
       BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
       BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC).addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_load), C28x::AL)
          .addReg(C28x::XAR7);
      // The address is dead after the load. Reuse its low half for the value
      // while POP restores unrelated live AL/AH, then write only Dst.
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AR7).addReg(C28x::AL);
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), Dst).addReg(C28x::AR7);
      MBB.erase(MI);
      return true;
    }
    // FI operands are rewritten by eliminateFrameIndex.
    return false;
  }
  case C28x::STORE16_PSEUDO: {
    MachineOperand PtrOp = MI.getOperand(0);
    Register Src = MI.getOperand(1).getReg();
    if (!PtrOp.isFI()) {
      Register Ptr = PtrOp.getReg();
      // Save an AL/AH source because address conversion clobbers it.  For a
      // source in another register, preserve ACC only if it is live through
      // this expansion; otherwise an unconditional push would read garbage.
      bool SourceInAcc = (Src == C28x::AL || Src == C28x::AH);
      bool SaveACC = SourceInAcc || AccLiveThrough();
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
       // Rust logical byte address -> C28x word address.
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC).addReg(Ptr);
       BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
       BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC).addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7).addReg(C28x::ACC);
      if (SourceInAcc && SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      // MOV *XARn, AX requires source in AL/AH.
      Register StgSrc = Src;
      if (Src != C28x::AL && Src != C28x::AH) {
        BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AL).addReg(Src);
        StgSrc = C28x::AL;
      }
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_store))
          .addReg(C28x::XAR7)
          .addReg(StgSrc);
      if (!SourceInAcc && SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      MBB.erase(MI);
      return true;
    }
    return false;
  }
  case C28x::LOAD32_PSEUDO: {
    MachineOperand PtrOp = MI.getOperand(1);
    if (!PtrOp.isFI()) {
      Register Dst = MI.getOperand(0).getReg();
      Register Ptr = PtrOp.getReg();
      // The load result itself is the only live value that must survive this
      // expansion.  ACC may have been killed by the allocator immediately
      // before the reload; saving it here would read an undefined physical
      // register.  ACC preservation is handled by the surrounding value
      // copies when it is genuinely live.
      bool Save = Dst != C28x::ACC && AccLiveThrough();
      if (Save)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
       // Rust logical byte address -> C28x word address.
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC).addReg(Ptr);
       BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
       BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC).addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7).addReg(C28x::ACC);
      // Load low word into AL, then high word from the NEXT word into AH.
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_load), C28x::AL)
          .addReg(C28x::XAR7);
      BuildMI(MBB, MI, DL, get(C28x::ADDB_XAR7_imm)).addImm(1);
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_load), C28x::AH)
          .addReg(C28x::XAR7);
      // Result in ACC; route to Dst.
      RouteFromACC(Dst);
      if (Save)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      MBB.erase(MI);
      return true;
    }
    return false;
  }
  case C28x::STORE32_PSEUDO: {
    MachineOperand PtrOp = MI.getOperand(0);
    if (!PtrOp.isFI()) {
      Register Ptr = PtrOp.getReg();
      Register Src = MI.getOperand(1).getReg();
      // We clobber ACC and the reserved scratch XAR7.  Ptr and Src are only
      // read, never modified.
      // The source is first materialised in ACC and then saved below.  Do not
      // save the pre-existing ACC: in spill-heavy blocks it can be undefined
      // after a kill, and the store expansion is allowed to clobber it.
      bool PreserveAcc = AccLiveThrough();
      if (PreserveAcc)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      // Bring the wide 32-bit value (ACC/XT/XARn) into ACC.
      if (Src == C28x::ACC) {
        // already in ACC
      } else if (Src == C28x::XT) {
        BuildMI(MBB, MI, DL, get(C28x::MOV_ACC_rr), C28x::ACC)
            .addReg(C28x::XT); // movl acc, xt
      } else if (C28x::GR32RegClass.contains(Src)) {
        BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
            .addReg(Src); // movl acc, xar
      } else {
        // Unexpected non-physical source post-RA: emit a routed COPY.
        BuildMI(MBB, MI, DL, get(TargetOpcode::COPY), C28x::ACC)
            .addReg(Src);
      }
      // Moving the address into XAR7 also uses ACC, so stash the value.
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
       // Rust logical byte address -> C28x word address.
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
          .addReg(Ptr);
       BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
       BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC)
           .addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7)
          .addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      // Store AL to *XAR7, then AH to *(XAR7+1).
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_store_AL))
          .addReg(C28x::XAR7);
      BuildMI(MBB, MI, DL, get(C28x::ADDB_XAR7_imm)).addImm(1);
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_store_AH))
          .addReg(C28x::XAR7);
      if (PreserveAcc)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      MBB.erase(MI);
      return true;
    }
    return false;
  }
  case C28x::LOAD8_PSEUDO: {
    Register Dst = MI.getOperand(0).getReg();
    MachineOperand PtrOp = MI.getOperand(1);
    if (!PtrOp.isFI()) {
      Register Ptr = PtrOp.getReg();
      bool SaveACC = AccLiveThrough(Dst);
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      if (SaveScratchXAR0)
        BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
      EmitIndexedByteAddress(Ptr);
      BuildMI(MBB, MI, DL, get(C28x::MOVB_ind_load_index_AL), C28x::AL)
          .addReg(C28x::XAR7);
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AR7).addReg(C28x::AL);
      if (SaveScratchXAR0)
        BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR0);
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), Dst).addReg(C28x::AR7);
      MBB.erase(MI);
      return true;
    }
    return false;
  }
  case C28x::LOAD8_GLOBAL_PSEUDO:
  case C28x::LOAD8_GLOBAL_ZEXT32_PSEUDO: {
    const bool Wide = MI.getOpcode() == C28x::LOAD8_GLOBAL_ZEXT32_PSEUDO;
    Register Dst = MI.getOperand(0).getReg();
    bool SaveACC = Wide
        ? !RI.regsOverlap(Dst, C28x::ACC) && AccLiveThrough()
        : AccLiveThrough(Dst);
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
    auto Sym = BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_imm), C28x::XAR7);
    Sym->addOperand(MI.getOperand(1));
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AR0)
        .addImm(MI.getOperand(2).getImm());
    BuildMI(MBB, MI, DL, get(C28x::MOVB_ind_load_index_AL), C28x::AL)
        .addReg(C28x::XAR7);
    if (Wide)
      BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH).addImm(0);
    else
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AR7).addReg(C28x::AL);
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR0);
    if (Wide)
      RouteFromACC(Dst);
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    if (!Wide)
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), Dst).addReg(C28x::AR7);
    MBB.erase(MI);
    return true;
  }
  case C28x::STORE8_GLOBAL_PSEUDO: {
    Register Src = MI.getOperand(2).getReg();
    // Staging a non-AL source is itself a clobber. Preserve before that move,
    // so e.g. exchange(false -> true) returns the old AL, not the new byte.
    bool SaveACC = Src != C28x::AL && AccLiveThrough();
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    if (Src != C28x::AL)
      BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AL).addReg(Src);
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
    auto Sym = BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_imm), C28x::XAR7);
    Sym->addOperand(MI.getOperand(0));
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AR0)
        .addImm(MI.getOperand(1).getImm());
    BuildMI(MBB, MI, DL, get(C28x::MOVB_ind_store_index_AL))
        .addReg(C28x::XAR7);
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR0);
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::LOAD8_ZEXT32_PSEUDO: {
    Register Dst = MI.getOperand(0).getReg();
    Register Ptr = MI.getOperand(1).getReg();
    bool SaveACC = Dst != C28x::ACC && AccLiveThrough();
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
    EmitIndexedByteAddress(Ptr);
    BuildMI(MBB, MI, DL, get(C28x::MOVB_ind_load_index_AL), C28x::AL)
        .addReg(C28x::XAR7);
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH).addImm(0);
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR0);
    RouteFromACC(Dst);
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }
  case C28x::LOAD1_ZEXT32_PSEUDO: {
    Register Dst = MI.getOperand(0).getReg();
    Register Ptr = MI.getOperand(1).getReg();
    bool SaveACC = Dst != C28x::ACC && AccLiveThrough();
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
    EmitIndexedByteAddress(Ptr);
    BuildMI(MBB, MI, DL, get(C28x::MOVB_ind_load_index_AL), C28x::AL)
        .addReg(C28x::XAR7);
    BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH).addImm(0);
    if (SaveScratchXAR0)
      BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR0);
    RouteFromACC(Dst);
    if (SaveACC)
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
    MBB.erase(MI);
    return true;
  }

  case C28x::LOAD16_ZEXT32_PSEUDO: {
    // Zero-extending i16 load to i32: load word into AL, clear AH.
    Register Dst = MI.getOperand(0).getReg();
    MachineOperand PtrOp = MI.getOperand(1);
    if (!PtrOp.isFI()) {
      Register Ptr = PtrOp.getReg();
      // Preserve ACC unless it is provably dead.  The forward "needed later"
      // heuristic is not sufficient here: an incoming ACC argument can be
      // live at this point while a later def hides it, and dropping the save
      // silently corrupts that argument (observed on hardware: a mixed
      // (i16,ptr,i32) callee returned a+*p+*p instead of a+*p+b).
      bool SaveAcc = !AccProvablyDead();
      if (SaveAcc)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
       // Rust logical byte address -> C28x word address.
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC).addReg(Ptr);
       BuildMI(MBB, MI, DL, get(C28x::CLRC_C));
       BuildMI(MBB, MI, DL, get(C28x::ROR_ACC), C28x::ACC).addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7).addReg(C28x::ACC);
      BuildMI(MBB, MI, DL, get(C28x::MOV_ind_load), C28x::AL)
          .addReg(C28x::XAR7);
      BuildMI(MBB, MI, DL, get(C28x::MOV16_imm), C28x::AH).addImm(0);
      // Park full 32-bit result in XAR7, restore saved ACC, bring result back
      // into ACC, then route to the (any GPR32) destination.
      BuildMI(MBB, MI, DL, get(C28x::MOVL_XAR_ACC), C28x::XAR7).addReg(C28x::ACC);
      if (SaveAcc)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      BuildMI(MBB, MI, DL, get(C28x::MOVL_ACC_XAR), C28x::ACC)
          .addReg(C28x::XAR7);
      RouteFromACC(Dst);
      MBB.erase(MI);
      return true;
    }
    // FI operands are rewritten by eliminateFrameIndex.
    return false;
  }

  case C28x::STORE8_PSEUDO: {
    MachineOperand PtrOp = MI.getOperand(0);
    Register Src = MI.getOperand(1).getReg();
    if (!PtrOp.isFI()) {
      Register Ptr = PtrOp.getReg();
      bool SaveACC = Src != C28x::AL && AccLiveThrough();
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      if (Src != C28x::AL)
        BuildMI(MBB, MI, DL, get(C28x::MOV16rr), C28x::AL).addReg(Src);
      if (SaveScratchXAR0)
        BuildMI(MBB, MI, DL, get(C28x::PUSH32)).addReg(C28x::XAR0);
      BuildMI(MBB, MI, DL, get(C28x::PUSH_ACC));
      EmitIndexedByteAddress(Ptr);
      BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      BuildMI(MBB, MI, DL, get(C28x::MOVB_ind_store_index_AL))
          .addReg(C28x::XAR7);
      if (SaveScratchXAR0)
        BuildMI(MBB, MI, DL, get(C28x::POP32), C28x::XAR0);
      if (SaveACC)
        BuildMI(MBB, MI, DL, get(C28x::POP_ACC));
      MBB.erase(MI);
      return true;
    }
    return false;
  }
  default:
    break;
  }
  return false;
}

// Condition encodings kept in sync with LowerBR_CC and expandPostRAPseudo.
// Works for both pseudo (pre-ExpandPostRAPseudos) and real branches.
static unsigned condEncFromAnyBranch(unsigned Op) {
  switch (Op) {
  default: return 0;
  case C28x::B_EQ_p:  case C28x::B_EQ:  return 0;
  case C28x::B_NE_p:  case C28x::B_NE:  return 1;
  case C28x::B_GT_p:  case C28x::B_GT:  return 2;
  case C28x::B_GE_p:  case C28x::B_GE:  return 3;
  case C28x::B_LT_p:  case C28x::B_LT:  return 4;
  case C28x::B_LE_p:  case C28x::B_LE:  return 5;
  case C28x::B_HI_p:  case C28x::B_HI:  return 6;
  case C28x::B_HIS_p: case C28x::B_HIS: return 7;
  case C28x::B_LO_p:  case C28x::B_LO:  return 8;
  case C28x::B_LOS_p: case C28x::B_LOS: return 9;
  }
}

// insertBranch runs in post-RA phase (after ExpandPostRAPseudos), so it must
// emit REAL branch instructions, not the _p pseudos.
static unsigned realOpcodeFromCondEnc(unsigned Enc) {
  switch (Enc) {
  default:
  case 0: return C28x::B_EQ;
  case 1: return C28x::B_NE;
  case 2: return C28x::B_GT;
  case 3: return C28x::B_GE;
  case 4: return C28x::B_LT;
  case 5: return C28x::B_LE;
  case 6: return C28x::B_HI;
  case 7: return C28x::B_HIS;
  case 8: return C28x::B_LO;
  case 9: return C28x::B_LOS;
  }
}

// Branch analysis follows the TargetInstrInfo contract exactly:
//   unconditional branch to X   -> TBB = X, FBB = nullptr, Cond = []
//   conditional branch to X     -> TBB = X, FBB = nullptr, Cond = [cc]
//   [cond branch to X][jmp Y]   -> TBB = X, FBB = Y,       Cond = [cc]
// A return (or any other terminator) is reported as "unanalyzable" (true) so
// generic code treats the block as an opaque barrier rather than assuming a
// fall-through.
//
// Getting this backwards is not cosmetic. MachineBasicBlock::getFallThrough()
// reads "TBB == nullptr" as "this block ends in no branch, so control always
// falls through". Parking an unconditional branch's target in FBB (instead of
// TBB) therefore made every jump block look like a fall-through block, and
// BranchFolding responded by inserting a compensating jump each time it
// revisited the block. That is what produced the repeated "b LBB1_1" in the
// loop test.
bool C28xInstrInfo::analyzeBranch(MachineBasicBlock &MBB,
                                  MachineBasicBlock *&TBB,
                                  MachineBasicBlock *&FBB,
                                  SmallVectorImpl<MachineOperand> &Cond,
                                  bool AllowModify) const {
  TBB = FBB = nullptr;
  Cond.clear();

  // Before post-RA expansion the comparison is part of the terminator. Keep
  // it opaque to branch folding: the legacy [cc] format cannot represent its
  // operands. In particular, do not misread [CMPBR][JMP] as a plain JMP.
  for (const MachineInstr &I : MBB.terminators())
    if (I.getOpcode() == C28x::CMPBR16_PSEUDO ||
        I.getOpcode() == C28x::CMPBR32_PSEUDO)
      return true;

  auto I = MBB.getLastNonDebugInstr();
  if (I == MBB.end())
    return false;

  if (isAnyUncondJump(I->getOpcode())) {
    MachineBasicBlock *UncondTarget = I->getOperand(0).getMBB();

    // Walk back over debug instructions: the instruction before the jump may
    // be the conditional branch that feeds it.
    auto Prev = I;
    bool HasPrev = false;
    while (Prev != MBB.begin()) {
      --Prev;
      if (!Prev->isDebugInstr()) {
        HasPrev = true;
        break;
      }
    }

    if (HasPrev && isAnyCondBranch(Prev->getOpcode())) {
      TBB = Prev->getOperand(0).getMBB();
      FBB = UncondTarget;
      Cond.push_back(
          MachineOperand::CreateImm(condEncFromAnyBranch(Prev->getOpcode())));
      return false;
    }

    // Plain unconditional branch: the target is TBB, not FBB.
    TBB = UncondTarget;
    return false;
  }

  if (isAnyCondBranch(I->getOpcode())) {
    TBB = I->getOperand(0).getMBB();
    Cond.push_back(
        MachineOperand::CreateImm(condEncFromAnyBranch(I->getOpcode())));
    return false;
  }

  return I->isTerminator();
}

unsigned C28xInstrInfo::removeBranch(MachineBasicBlock &MBB,
                                     int *BytesRemoved) const {
  unsigned Count = 0;
  while (!MBB.empty()) {
    MachineInstr &I = MBB.back();
    if (!isAnyUncondJump(I.getOpcode()) && !isAnyCondBranch(I.getOpcode()))
      break;
    MBB.erase(MBB.getLastNonDebugInstr());
    ++Count;
  }
  if (BytesRemoved)
    *BytesRemoved = 0;
  return Count;
}

unsigned C28xInstrInfo::insertBranch(MachineBasicBlock &MBB,
                                     MachineBasicBlock *TBB,
                                     MachineBasicBlock *FBB,
                                     ArrayRef<MachineOperand> Cond,
                                     const DebugLoc &DL,
                                     int *BytesAdded) const {
  unsigned Count = 0;
  if (!Cond.empty() && FBB) {
    // Conditional branch to TBB, unconditional to FBB.
    unsigned Enc = Cond[0].isImm() ? Cond[0].getImm() : 0;
    BuildMI(&MBB, DL, get(realOpcodeFromCondEnc(Enc))).addMBB(TBB);
    BuildMI(&MBB, DL, get(C28x::B_JMP)).addMBB(FBB);
    Count = 2;
  } else if (!Cond.empty()) {
    unsigned Enc = Cond[0].isImm() ? Cond[0].getImm() : 0;
    BuildMI(&MBB, DL, get(realOpcodeFromCondEnc(Enc))).addMBB(TBB);
    Count = 1;
  } else if (TBB) {
    BuildMI(&MBB, DL, get(C28x::B_JMP)).addMBB(TBB);
    Count = 1;
  }
  if (BytesAdded)
    *BytesAdded = 0;
  return Count;
}
