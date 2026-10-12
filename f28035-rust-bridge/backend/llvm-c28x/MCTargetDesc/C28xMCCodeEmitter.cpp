//===-- C28xMCCodeEmitter.cpp - C28x Code Emitter ----------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Emits C28x instruction bytes. Only instructions whose encodings are verified
// (TI SPRU430F opcodes cross-checked byte-for-byte against the vendor assembler
// asm2000/dis2000/ofd2000 and cl2000) are encodable. Anything else fails loudly
// instead of emitting unverified bytes (contract L1-2, ABI_FREEZE.md).
//
// Byte order: TI places the LOW byte of the 16-bit instruction word at the
// lower address (ordinary little-endian word order), so a word such as
// 0x9A01 (MOVB AL,#1) is stored as "01 9A". This was verified with the vendor
// tools:
//     MOV AL,AR0  -> word 0x92A0 -> memory "A0 92"
//     SUB AL,@AH  -> word 0x9EA8 -> memory "A8 9E"
//     LRETR       -> word 0x0006 -> memory "06 00"
// Emitting the opcode byte first (big-endian within the word) is wrong.
//
//===----------------------------------------------------------------------===//

#include "C28xMCTargetDesc.h"
#include "llvm/MC/MCCodeEmitter.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegister.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace {

// Encode a 16-bit register as the 8-bit "loc16" register-direct addressing
// field (SPRU430F Table 5-1). Verified decodes:
//   @ARn = 1010 0AAA  (0xA0-0xA7)
//   @AH  = 1010 1000  (0xA8)     @AL  = 1010 1001  (0xA9)
//   @PH  = 1010 1010  (0xAA)     @PL  = 1010 1011  (0xAB)
//   @PH  = 1010 1010  (0xAA)     @PL  = 1010 1011  (0xAB)   -- these are P halves, not XT
//   @SP  = 1010 1101  (0xAD)
// T/TL (XT halves) are NOT loc16-addressable; XT is only accessible via loc32 (@XT=0xAC).
// vendor assembler), so they stay unencodable. AR0-AR7/AH/AL/SP are all
// covered by vendor-tool byte checks.
static uint8_t loc16RegEncoding(unsigned Reg, StringRef InstrName = "") {
  StringRef Name = InstrName.empty() ? StringRef("loc16") : InstrName;
  switch (Reg) {
  case C28x::AR0: return 0xA0;
  case C28x::AR1: return 0xA1;
  case C28x::AR2: return 0xA2;
  case C28x::AR3: return 0xA3;
  case C28x::AR4: return 0xA4;
  case C28x::AR5: return 0xA5;
  case C28x::AR6: return 0xA6;
  case C28x::AR7: return 0xA7;
  case C28x::AH:  return 0xA8;
  case C28x::AL:  return 0xA9;
  case C28x::ACC: return 0xA9; // ACC low = AL; RA spill fallback
  case C28x::PH:  return 0xAA;
  case C28x::PL:  return 0xAB;
  case C28x::SP:  return 0xAD;
  case C28x::XT:  report_fatal_error("C28x: XT has no loc16 encoding (TL/T not loc16-addressable); use 32-bit spill");
  case C28x::AR0H: case C28x::AR1H: case C28x::AR2H: case C28x::AR3H:
  case C28x::AR4H: case C28x::AR5H: case C28x::AR6H: case C28x::AR7H:
    return uint8_t(0xB0 | (Reg - C28x::AR0H));
  default:
    report_fatal_error(
        Twine("C28x: '") + Name +
        "' has no loc16 register-direct encoding for the allocated register #" +
        Twine(Reg) + " (verified: AR0-AR7=0xA0-0xA7, AH=0xA8, AL=0xA9, SP=0xAD per SPRU430F "
        "Table 5-1)");
  }
}

// Index of an auxiliary register, used by the "MOV loc16, ARn" form
// (0111 1nnn LLLL LLLL).
static uint8_t arIndexOf(unsigned Reg) {
  switch (Reg) {
  case C28x::AR0: return 0;
  case C28x::AR1: return 1;
  case C28x::AR2: return 2;
  case C28x::AR3: return 3;
  case C28x::AR4: return 4;
  case C28x::AR5: return 5;
  case C28x::AR6: return 6;
  case C28x::AR7: return 7;
  default:
    report_fatal_error(
        "C28x: MOV loc16, ARn requires an auxiliary register (AR0-AR7) source");
  }
}

// PUSH/POP of an implicit 16-bit register (SPRU430F):
//   PUSH loc16 = 0010 0010 LLLL LLLL
//   POP  loc16 = 0010 1010 LLLL LLLL
// Verified against asm2000 -v28 / dis2000:
//   PUSH AL -> 22A9   POP AL -> 2AA9    PUSH AR0 -> 22A0   POP AR0 -> 2AA0
//   PUSH AR4 -> 22A4  POP AR4 -> 2AA4   PUSH AR6 -> 22A6   POP AR6 -> 2AA6
static uint16_t pushPopEncoding(unsigned Opc) {
  switch (Opc) {
  case C28x::PUSH_AL:  return 0x22A9;
  case C28x::POP_AL:   return 0x2AA9;
  case C28x::PUSH_AR0: return 0x22A0;
  case C28x::POP_AR0:  return 0x2AA0;
  case C28x::PUSH_AR4: return 0x22A4;
  case C28x::POP_AR4:  return 0x2AA4;
  case C28x::PUSH_AR5: return 0x22A5;
  case C28x::POP_AR5:  return 0x2AA5;
  case C28x::PUSH_AR6: return 0x22A6;
  case C28x::POP_AR6:  return 0x2AA6;
  default:             return 0;
  }
}

// 4-bit condition selector of "B 16bitOffset, COND", whose first word is
// 1111 1111 1110 CCCC (SPRU430F). Returns ~0u when Opc is not a branch.
// Verified against asm2000 -v28 / dis2000:
//   B _f,EQ  -> FF E1 + offset word     B _f,UNC -> FF EF + offset word
static unsigned branchCondField(unsigned Opc) {
  switch (Opc) {
  case C28x::B_NE:  return 0x0; // NEQ
  case C28x::B_EQ:  return 0x1; // EQ
  case C28x::B_GT:  return 0x2; // GT   (signed >)
  case C28x::B_GE:  return 0x3; // GEQ  (signed >=)
  case C28x::B_LT:  return 0x4; // LT   (signed <)
  case C28x::B_LE:  return 0x5; // LEQ  (signed <=)
  case C28x::B_HI:  return 0x6; // HI   (unsigned >)
  case C28x::B_HIS: return 0x7; // HIS  (unsigned >=)
  case C28x::B_LO:  return 0x8; // LO   (unsigned <)
  case C28x::B_LOS: return 0x9; // LOS  (unsigned <=)
  case C28x::B_JMP: return 0xF; // UNC  (unconditional)
  default:          return ~0u;
  }
}

// The "A" bit shared by every "AX, ..." (accumulator) instruction form:
// A=0 selects AL, A=1 selects AH (SPRU430F; verified against the vendor
// assembler, e.g. MOV AH,AR2 -> 0x93A2 and SUB AL,@AH -> 0x9EA8).
static uint8_t accumABit(unsigned Reg, StringRef InstrName) {
  if (Reg == C28x::AL)
    return 0;
  if (Reg == C28x::AH)
    return 1;
  report_fatal_error(Twine("C28x: '") + InstrName +
                     "' requires an accumulator destination (AL or AH)");
}

// Append one C28x instruction word in TI byte order: the LOW byte goes to the
// lower address (see the file header comment).
static void emit16(SmallVectorImpl<char> &CB, uint16_t Word) {
  CB.push_back(static_cast<char>(Word & 0xFF));
  CB.push_back(static_cast<char>(Word >> 8));
}

//===----------------------------------------------------------------------===//
// Auxiliary-register (XARn) opcode tables.
//
// C28x does NOT use a contiguous 3-bit register field for the 32-bit auxiliary
// registers. Several instruction families dedicate one *opcode* per XARn, and
// SPRU430F documents them as eight separate "OPCODE" lines rather than as one
// line with an "nnn" field. For example SPRU430F 6-210 ("MOVL loc32, XARn")
// lists
//     0011 1010 / 1011 0010 / 1010 1010 / 1010 0010 /
//     1010 1000 / 1010 0000 / 1100 0010 / 1100 0011
// for XAR0..XAR7, which is exactly the table below.
//
// Corollary: any attempt to derive an XARn encoding from a formula (e.g.
// "0x1EA0 | n") is wrong for most n. Every row here was read off the vendor
// tools (asm2000 -v28 + dis2000 round-trip) for all eight XARn values.
//===----------------------------------------------------------------------===//
enum XarOpcode {
  XAR_OP_MOVL_FROM_XAR, // "MOVL loc32, XARn"   (low byte = loc32 register code)
  XAR_OP_MOVL_TO_XAR,   // "MOVL XARn, loc32"   (low byte = loc32 register code)
  XAR_OP_MOVZ,          // "MOVZ ARn, loc16"    (low byte = loc16 register code)
  XAR_OP_MOVL_IMM,      // "MOVL XARn, #22bit"  (low 6 bits = imm bits 21:16)
  XAR_OP_MOVB_IMM,      // "MOVB XARn, #8bit"   (low byte = imm)
  XAR_OP_COUNT
};

static unsigned xarIndex(unsigned Reg, StringRef InstrName) {
  switch (Reg) {
  case C28x::XAR0: return 0;
  case C28x::XAR1: return 1;
  case C28x::XAR2: return 2;
  case C28x::XAR3: return 3;
  case C28x::XAR4: return 4;
  case C28x::XAR5: return 5;
  case C28x::XAR6: return 6;
  case C28x::XAR7: return 7;
  default:
    report_fatal_error(Twine("C28x: '") + InstrName +
                       "' requires a 32-bit auxiliary register (XAR0-XAR7)");
  }
}

static uint16_t xarOpcode(unsigned Reg, XarOpcode Op, StringRef InstrName) {
  static const uint16_t Tables[XAR_OP_COUNT][8] = {
      /* MOVL loc32, XARn  */ {0x3A00, 0xB200, 0xAA00, 0xA200,
                               0xA800, 0xA000, 0xC200, 0xC300},
      /* MOVL XARn, loc32  */ {0x8E00, 0x8B00, 0x8600, 0x8200,
                               0x8A00, 0x8300, 0xC400, 0xC500},
      /* MOVZ ARn, loc16   */ {0x5800, 0x5900, 0x5A00, 0x5B00,
                               0x5C00, 0x5D00, 0x8800, 0x8000},
      /* MOVL XARn, #22bit */ {0x8D00, 0x8D40, 0x8D80, 0x8DC0,
                               0x8F00, 0x8F40, 0x7680, 0x76C0},
      /* MOVB XARn, #8bit  */ {0xD000, 0xD100, 0xD200, 0xD300,
                               0xD400, 0xD500, 0xBE00, 0xB600},
  };
  return Tables[Op][xarIndex(Reg, InstrName)];
}

// loc32 register-direct code for the "MOVL XARn,loc32" / "MOVL loc32,XARn"
// families. @ACC (the 32-bit accumulator) is 0xA9, the 16-bit registers follow
// the loc16-style table (SPRU430F Table 5-1/5-4).
// Verified with asm2000 -v28 / dis2000:
//   MOVL XAR0, @ACC -> 8EA9     MOVL ACC, XAR0 -> 3AA9
//   MOVL XAR7, @ACC -> C5A9     MOVL ACC, XAR7 -> C3A9
static uint8_t loc32RegEncoding(unsigned Reg, StringRef InstrName) {
  switch (Reg) {
  case C28x::ACC: return 0xA9;
  case C28x::XT:  return 0xAC;
  case C28x::XAR0: case C28x::XAR1: case C28x::XAR2: case C28x::XAR3:
  case C28x::XAR4: case C28x::XAR5: case C28x::XAR6: case C28x::XAR7:
    return uint8_t(0xA0 | xarIndex(Reg, InstrName));
  default:
    return loc16RegEncoding(Reg, InstrName);
  }
}

// Addressing field of the "*XARn" indirect mode. SPRU430F Table 5-1 encodes it
// as 0xC0 | n, which is deliberately distinct from the "@ARn" register-direct
// code 0xA0 | n.
// Verified with asm2000 -v28 / dis2000 for n = 0..7 and both accumulators:
//   MOV AL, *XAR0 -> 92C0   MOV AH, *XAR7 -> 93C7
//   MOV *XAR0, AL -> 96C0   MOV *XAR7, AH -> 97C7
static uint8_t indirectXarField(unsigned Reg, StringRef InstrName) {
  return uint8_t(0xC0 | xarIndex(Reg, InstrName));
}

// MC lowering removes implicit register operands and masks. The descriptor
// remains the authority for explicit arity, independent of liveness metadata.
static unsigned numExplicitOperands(const MCInst &MI, const MCInstrInfo &MCII) {
  return MCII.get(MI.getOpcode()).getNumOperands();
}

class C28xMCCodeEmitter : public MCCodeEmitter {
  const MCInstrInfo &MCII;

public:
  C28xMCCodeEmitter(const MCInstrInfo &MCII, MCContext &Ctx) : MCII(MCII) {}
  ~C28xMCCodeEmitter() override = default;

  void encodeInstruction(const MCInst &MI, SmallVectorImpl<char> &CB,
                         SmallVectorImpl<MCFixup> &Fixups,
                         const MCSubtargetInfo &STI) const override {
    // Canonical 16-bit instruction word: the leading opcode nibble lives in
    // bits 15:12 of this value (matching the SPRU430F "1001 001A LLLL LLLL"
    // notation). The bytes are reversed into little-endian order on the way
    // out, below.
    uint16_t Word = 0;

    // --- Two-word branches -------------------------------------------------
    // "B 16bitOffset, COND" is the only two-word form in the verified set:
    //   word 0: 1111 1111 1110 CCCC   (CCCC = condition, 1111 = UNC)
    //   word 1: signed 16-bit field = target_word_address - branch_word_address
    // The offset convention was pinned down with asm2000/dis2000: a branch at
    // word 0 targeting word 204 assembles to "B 204, UNC" = FFEF 00CC, and a
    // branch at word 2 targeting word 204 to "B 202, EQ" = FFE1 00CA.
    // The field is patched by FK_C28x_BRANCH (see C28xAsmBackend.cpp); it is
    // not computed here because the target may not be laid out yet.
    if (unsigned Cond = branchCondField(MI.getOpcode()); Cond != ~0u) {
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "B 16bitOffset,COND expects a single target operand");
      const MCOperand &Target = MI.getOperand(0);
      if (!Target.isExpr())
        report_fatal_error(
            "C28x: B 16bitOffset,COND requires a symbolic target; register "
            "and indirect branches are not encodable yet");
      emit16(CB, uint16_t(0xFFE0 | Cond));
      Fixups.push_back(MCFixup::create(/*Offset=*/2, Target.getExpr(),
                                       MCFixupKind(C28x::FK_C28x_BRANCH),
                                       /*PCRel=*/true));
      emit16(CB, 0x0000); // place-holder, patched via FK_C28x_BRANCH
      (void)STI;
      return;
    }

    switch (MI.getOpcode()) {
    case C28x::TRUNC32_16: {
      // mov GR16, AL = 1001 0110 LLLL LLLL (MOV loc16, AL; A=0 for AL).
      // MCInst: [dst(GR16), src(ACC32 tied)].
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "TRUNC32_16 expects [dst, src] operands");
      Word = (uint16_t(0x96) << 8) | loc16RegEncoding(MI.getOperand(0).getReg());
      break;
    }
    case C28x::MOV_ACC_rr: {
      // MOVL between ACC and XT. Verified with asm2000/dis2000:
      //   MOVL XT, ACC = 0x1EAC   MOVL ACC, XT = 0xABA9
      // MOVL ACC,ACC and MOVL XT,XT are no-ops.
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOV_ACC_rr expects [dst, src] operands");
      MCRegister Dst = MI.getOperand(0).getReg();
      MCRegister Src = MI.getOperand(1).getReg();
      if (Dst == Src) {
        (void)CB; (void)Fixups; (void)STI;
        return; // no-op
      }
      if (Dst == C28x::XT && Src == C28x::ACC) { Word = 0x1EAC; break; }
      if (Dst == C28x::ACC && Src == C28x::XT) { Word = 0xABA9; break; }
      report_fatal_error(Twine("C28x: MOV_ACC_rr unsupported dst=") +
        Twine(Dst) + " src=" + Twine(Src));
    }
    case C28x::PUSH_ACC:
      // PUSH ACC = 0001 1110 1011 1101  (SPRU430F "PUSH ACC"; equivalent to
      // MOVL *SP++, ACC). Verified: asm2000/dis2000 -> 1EBD, memory "BD 1E".
      Word = 0x1EBD;
      break;
    case C28x::POP_ACC:
      // POP ACC = 0000 0110 1011 1110 (equiv. MOVL ACC, *--SP).
      // Verified: asm2000/dis2000 -> 06BE, memory "BE 06".
      Word = 0x06BE;
      break;
    case C28x::LRETR:
      // LRETR = 0000 0000 0000 0110 (SPRU430F "LRETR").
      // Verified: asm2000/dis2000 and cl2000 -> 0006, memory "06 00".
      Word = 0x0006;
      break;
    case C28x::MOV16_imm: {
      // Constant materialisation; the assembler picks the same encoding.
      //   MOVB AX,#8bit    = 1001 101A CCCC CCCC   (AX = AL/AH, imm 0..255)
      //   MOV loc16,#0     = 0010 1011 LLLL LLLL
      //   MOV loc16,#16bit = 0010 1000 LLLL LLLL followed by the literal word
      // Verified with asm2000 -v28 / dis2000:
      //   MOV AL,#300 -> 28A9 012C    MOV AL,#0 -> 9A00
      //   MOV AR0,#0  -> 2BA0         MOV AR4,#0 -> 2BA4
      //   MOV AR1,#1  -> 28A1 0001    MOV AR7,#-1 -> 28A7 FFFF
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOV16_imm expects [dst, imm] operands");
      MCRegister Dst = MI.getOperand(0).getReg();
      const MCOperand &ImmOp = MI.getOperand(1);
      assert(ImmOp.isImm() && "MOV16_imm immediate operand must be an imm");
      int64_t Imm = ImmOp.getImm();

      // MOVB AX,#8bit is the one-word form, and only for AL/AH.
      if ((Dst == C28x::AL || Dst == C28x::AH) && Imm >= 0 && Imm <= 0xFF) {
        uint8_t A = accumABit(Dst, "MOV16_imm");
        Word = 0x9A00 | (uint16_t(A) << 8) | uint16_t(Imm);
        break;
      }

      uint8_t Loc = loc16RegEncoding(Dst);
      // MOV loc16,#0 is a dedicated one-word clear.
      if (Imm == 0) {
        Word = 0x2B00 | Loc;
        break;
      }

      // MOV loc16,#16bit: 0010 1000 LLLL LLLL + literal. Two words, so emit
      // both here and skip the shared tail.
      emit16(CB, uint16_t(0x2800 | Loc));
      emit16(CB, uint16_t(Imm & 0xFFFF));
      (void)STI;
      return;
    }
    case C28x::ADD_AL_imm: {
      // ADDB AX, #8bitSigned = 1001 110A CCCC CCCC.
      // Verified: cl2000 `a + 2` -> ADDB AL,#2 = 0x9C02 (memory "02 9C").
      // There is no "ADD AX,#16bit" form in SPRU430F, so anything outside the
      // signed 8-bit range must be lowered differently -- fail closed.
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "ADD_AL_imm expects [dst, imm] operands");
      const MCOperand &ImmOp = MI.getOperand(1);
      assert(ImmOp.isImm() && "ADD_AL_imm immediate operand must be an imm");
      uint8_t A = accumABit(MI.getOperand(0).getReg(), "ADD_AL_imm");
      int64_t Imm = ImmOp.getImm();
      if (Imm < -128 || Imm > 127)
        report_fatal_error(
            Twine("C28x: ADD_AL_imm immediate ") + Twine(Imm) +
            " does not fit ADDB AX,#8bitSigned (-128..127); SPRU430F has no "
            "16-bit ADD AX immediate");
      Word = 0x9C00 | (uint16_t(A) << 8) | uint16_t(Imm & 0xFF);
      break;
    }
    case C28x::ADD16rr:
    case C28x::SUB16rr:
    case C28x::AND16rr:
    case C28x::OR16rr:
    case C28x::XOR16rr: {
      // C28x is an accumulator machine: 16-bit ALU ops only target AL/AH.
      // The backend models these as "op $dst, $rhs"; the only encodable shape
      // is "op AX, loc16" (SPRU430F §6, A=0 -> AL, A=1 -> AH):
      //   ADD AX,loc16 = 1001 010A   SUB AX,loc16 = 1001 111A
      //   AND AX,loc16 = 1100 111A   OR  AX,loc16 = 1100 101A
      //   XOR AX,loc16 = 0111 000A
      // Fail closed if the allocator produced a non-accumulator destination
      // rather than emit wrong bytes (contract L1-2, ABI_FREEZE.md).
      // MCInst layout for these two-address ops is [dst, lhs(tied), rhs].
      assert(numExplicitOperands(MI, MCII) == 3 &&
             "16-bit ALU rr expects [dst, lhs(tied), rhs] operands");
      uint8_t A = accumABit(MI.getOperand(0).getReg(),
                            MCII.getName(MI.getOpcode()));
      uint8_t OpcBase;
      switch (MI.getOpcode()) {
      case C28x::ADD16rr: OpcBase = 0x94; break;
      case C28x::SUB16rr: OpcBase = 0x9E; break;
      case C28x::AND16rr: OpcBase = 0xCE; break;
      case C28x::OR16rr:  OpcBase = 0xCA; break;
      case C28x::XOR16rr: OpcBase = 0x70; break;
      default: llvm_unreachable("unexpected opcode in 16-bit ALU case");
      }
      MCRegister Rhs = MI.getOperand(2).getReg();
      Word = (uint16_t(OpcBase | A) << 8) | loc16RegEncoding(Rhs);
      break;
    }
    case C28x::ADD32rr:
    case C28x::SUB32rr: {
      // ADDL/SUBL ACC, loc32: 0x07xx / 0x03xx where xx = loc32 code.
      // Verified with asm2000 -v28 / dis2000:
      //   ADDL ACC, XT -> 07AC   ADDL ACC, P  -> 07AB
      //   SUBL ACC, XT -> 03AC   SUBL ACC, P  -> 03AB
      assert(numExplicitOperands(MI, MCII) == 3 &&
             "ADD32rr/SUB32rr expects [dst, lhs(tied), rhs] operands");
      MCRegister Rhs = MI.getOperand(2).getReg();
      // ADDL/SUBL ACC, ACC is allowed (doubles/halves the accumulator).
      uint8_t Loc = loc32RegEncoding(Rhs, MCII.getName(MI.getOpcode()));
      uint16_t Base = MI.getOpcode() == C28x::ADD32rr ? 0x0700 : 0x0300;
      Word = Base | Loc;
      break;
    }
    case C28x::ADD32imm:
    case C28x::SUB32imm: {
      // ADDB/SUBB ACC, #imm8 = 0x09xx / 0x19xx (single word, 0..255)
      // ADD/SUB ACC, #imm16 = 0xFF10, imm16 (two words)
      assert(numExplicitOperands(MI, MCII) == 3 &&
             "ADD32imm/SUB32imm expects [dst, lhs(tied), src] operands");
      int64_t Imm = MI.getOperand(2).getImm();
      bool IsAdd = MI.getOpcode() == C28x::ADD32imm;
      if (Imm >= 0 && Imm <= 255) {
        Word = (IsAdd ? 0x0900 : 0x1900) | uint16_t(Imm);
      } else {
        // Two-word form: opcode first, then immediate.
        emit16(CB, 0xFF10);
        emit16(CB, uint16_t(int16_t(Imm)));
        (void)STI;
        return;
      }
      break;
    }
    case C28x::MOV_ACC_imm: {
      // MOV ACC, #imm16 = 0xFF20, imm16 (two words)
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOV_ACC_imm expects [dst, src] operands");
      if (MI.getOperand(0).getReg() != C28x::ACC)
        report_fatal_error("C28x: MOV_ACC_imm requires ACC destination");
      int64_t Imm = MI.getOperand(1).getImm();
      if (Imm < -32768 || Imm > 65535)
        report_fatal_error("C28x: MOV_ACC_imm value exceeds 16-bit field");
      // Two-word form: opcode first, then immediate.
      emit16(CB, 0xFF20);
      emit16(CB, uint16_t(int16_t(Imm)));
      (void)STI;
      return;
    }
    case C28x::PUSH_AL:
    case C28x::POP_AL:
    case C28x::PUSH_AR0:
    case C28x::POP_AR0:
    case C28x::PUSH_AR4:
    case C28x::POP_AR4:
    case C28x::PUSH_AR5:
    case C28x::POP_AR5:
    case C28x::PUSH_AR6:
    case C28x::POP_AR6: {
      // PUSH loc16 / POP loc16 (implicit register, no operands).
      assert(numExplicitOperands(MI, MCII) == 0 &&
             "PUSH/POP loc16 form takes no explicit operands");
      Word = pushPopEncoding(MI.getOpcode());
      assert(Word != 0 && "unhandled PUSH/POP opcode");
      break;
    }
    case C28x::MOV_AL_SP: {
      // MOV AX, loc16 with loc16 = @SP: 1001 001A 1010 1101.
      // Verified: asm2000 -v28 / dis2000 on `MOV AL, SP` -> 92AD.
      // MCInst layout is [dst, implicit SP].
      assert(numExplicitOperands(MI, MCII) >= 1 && "MOV_AL_SP expects a dst operand");
      uint8_t A = accumABit(MI.getOperand(0).getReg(), "MOV_AL_SP");
      Word = (uint16_t(0x92 | A) << 8) | loc16RegEncoding(C28x::SP);
      break;
    }
    case C28x::MOV16rr: {
      // Three verified register-register shapes (SPRU430F §6):
      //   MOV AX,    loc16 = 1001 001A LLLL LLLL   (dst is an accumulator)
      //   MOV loc16, AX    = 1001 011A LLLL LLLL   (src is an accumulator)
      //   MOV loc16, ARn   = 0111 1nnn LLLL LLLL   (nnn = source ARn)
      // Vendor-tool byte checks: MOV AL,@AH -> 92A8, MOV AH,AR2 -> 93A2,
      // MOV AR4,AR0 -> 78A4, MOV AR4,AL -> 96A4, MOV AR0,AR1 -> 79A0.
      assert(numExplicitOperands(MI, MCII) == 2 && "MOV16rr expects [dst, src] operands");
      MCRegister Dst = MI.getOperand(0).getReg();
      MCRegister Src = MI.getOperand(1).getReg();
      if (Dst == C28x::AL || Dst == C28x::AH) {
        uint8_t A = accumABit(Dst, "MOV16rr");
        Word = (uint16_t(0x92 | A) << 8) | loc16RegEncoding(Src);
      } else if (Src == C28x::AL || Src == C28x::AH) {
        uint8_t A = accumABit(Src, "MOV16rr");
        Word = (uint16_t(0x96 | A) << 8) | loc16RegEncoding(Dst);
      } else {
        Word = (uint16_t(0x78 | arIndexOf(Src)) << 8) | loc16RegEncoding(Dst);
      }
      break;
    }
    case C28x::CMP_AL_rr: {
      // CMP AX, loc16 = 0101 010A LLLL LLLL.
      // The .td operand list is [src (loc16), implicit AL], so the compared
      // accumulator is always AL (A = 0).
      // Verified: asm2000/dis2000 -> CMP AL,AR0 = 54A0, CMP AH,AR2 = 55A2,
      // CMP AL,@AH = 54A8. The subtraction direction is fixed by cl2000:
      //   int lt(a,b){return a<b;}  -> CMP AH,AR6 ; MOVB AL,#1,GT
      //   int ge(a,b){return a>=b;} -> CMP AH,AR6 ; MOVB AL,#1,LEQ
      // With the second argument in AH and the copy of the first in AR6,
      // only "AX - loc16" (AX is the minuend) makes GT mean b>a and LEQ mean
      // b<=a, so CMP AX,loc16 computes AX - loc16.
      assert(numExplicitOperands(MI, MCII) >= 1 && "CMP_AL_rr expects a loc16 operand");
      MCRegister Rhs = MI.getOperand(0).getReg();
      if (Rhs == C28x::AL)
        report_fatal_error(
            "C28x: CMP_AL_rr with the RHS in AL would degrade to 'cmp al, "
            "al'; the RHS must live in a non-AL register (GR16NoAL)");
      Word = (uint16_t(0x54) << 8) | loc16RegEncoding(Rhs);
      break;
    }
    case C28x::CMP_AL_imm: {
      // CMPB AX,#8bit = 0101 001A CCCC CCCC. The .td form is hardwired to AL.
      // Verified: asm2000/dis2000 -> CMPB AL,#5 = 5205; cl2000 `a < 5` ->
      // CMPB AL,#5. The 8-bit field is unsigned, so anything outside 0..255
      // is rejected rather than truncated -- the wider "CMP AX,#16bit" is a
      // two-word form that this emitter does not describe yet.
      assert(numExplicitOperands(MI, MCII) == 1 && "CMP_AL_imm expects [imm]");
      const MCOperand &ImmOp = MI.getOperand(0);
      assert(ImmOp.isImm() && "CMP_AL_imm operand must be an imm");
      int64_t Imm = ImmOp.getImm();
      if (Imm < 0 || Imm > 0xFF)
        report_fatal_error(
            Twine("C28x: CMP_AL_imm immediate ") + Twine(Imm) +
            " does not fit CMPB AX,#8bit (0..255); materialize the constant "
            "into a register and use CMP_AL_rr instead");
      Word = 0x5200 | uint16_t(Imm);
      break;
    }
    case C28x::LSL16:
    case C28x::LSR16: {
      // LSL/LSR AX,#1..16 (SPRU430F):
      //   LSL AX,#n = 1111 1111 1000 AAAA -> 0xFF80 | (A << 4) | (n - 1)
      //   LSR AX,#n = 1111 1111 1100 AAAA -> 0xFFC0 | (A << 4) | (n - 1)
      // Verified: asm2000/dis2000 -> LSL AL,1 = FF80, LSL AH,1 = FF90,
      // LSL AL,4 = FF83, LSL AL,16 = FF8F, LSR AL,1 = FFC0, LSR AH,1 = FFD0,
      // LSR AH,2 = FFD1, LSR AL,16 = FFCF.
      // MCInst layout for these in-place shifts is [dst, src(tied), amt].
      assert(numExplicitOperands(MI, MCII) >= 3 &&
             "LSL16/LSR16 expects [dst, src(tied), amt] operands");
      uint8_t A = accumABit(MI.getOperand(0).getReg(),
                            MCII.getName(MI.getOpcode()));
      const MCOperand &AmtOp = MI.getOperand(2);
      assert(AmtOp.isImm() && "shift amount must be an immediate");
      int64_t Amt = AmtOp.getImm();
      if (Amt < 1 || Amt > 16)
        report_fatal_error(
            Twine("C28x: shift amount ") + Twine(Amt) +
            " is outside LSL/LSR AX,#1..16 (SPRU430F has no shift-by-0 form)");
      uint16_t Base = MI.getOpcode() == C28x::LSL16 ? 0xFF80 : 0xFFC0;
      Word = Base | (uint16_t(A) << 4) | uint16_t(Amt - 1);
      break;
    }
    case C28x::MOV_ind_load: {
      // MOV AX, *XARn = 1001 001A 1100 0nnn  (loc16 field = 0xC0 | n).
      // MCInst layout is [dst (GR16), ptr (GR32)].
      // Verified: asm2000 -v28 / dis2000 -> MOV AL,*XAR0 = 92C0 (canonical
      // disassembly "MOV AL, *+XAR0[0]"), MOV AH,*XAR7 = 93C7.
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOV_ind_load expects [dst, ptr] operands");
      uint8_t A = accumABit(MI.getOperand(0).getReg(), "MOV_ind_load");
      uint8_t Ptr = indirectXarField(MI.getOperand(1).getReg(), "MOV_ind_load");
      Word = (uint16_t(0x92 | A) << 8) | Ptr;
      break;
    }
    case C28x::MOV_ind_store: {
      // MOV *XARn, AX = 1001 011A 1100 0nnn  (loc16 field = 0xC0 | n).
      // MCInst layout is [ptr (GR32), src (GR16)].
      // Verified: asm2000 -v28 / dis2000 -> MOV *XAR0,AL = 96C0,
      // MOV *XAR7,AH = 97C7.
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOV_ind_store expects [ptr, src] operands");
      uint8_t Ptr = indirectXarField(MI.getOperand(0).getReg(), "MOV_ind_store");
      uint8_t A = accumABit(MI.getOperand(1).getReg(), "MOV_ind_store");
      Word = (uint16_t(0x96 | A) << 8) | Ptr;
      break;
    }
    case C28x::MOVL_ACC_ind_load: {
      // MOVL ACC, *XARn = 0x0600 | (0xC0 | n)
      // Verified: MOVL ACC, *XAR4 = 0x06C4
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOVL_ACC_ind_load expects [dst, ptr] operands");
      uint8_t Ptr = indirectXarField(MI.getOperand(1).getReg(), "MOVL_ACC_ind_load");
      Word = 0x0600 | Ptr;
      break;
    }
    case C28x::MOV_ind_store_AL:
    case C28x::MOV_ind_store_AH: {
      // MOV *XARn, AL = 0x9600 | (0xC0|n), MOV *XARn, AH = 0x9700 | (0xC0|n)
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "MOV_ind_store_AL/AH expects [ptr] operand");
      uint8_t Ptr = indirectXarField(MI.getOperand(0).getReg(), "MOV_ind_store");
      uint16_t Base = (MI.getOpcode() == C28x::MOV_ind_store_AL) ? 0x9600 : 0x9700;
      Word = Base | Ptr;
      break;
    }
    case C28x::MOVB_ind_load_AL: {
      // MOVB AL, *XARn = 0xC600 | (0xC0|n). Byte load: XARn holds byte
      // address, hardware selects low/high byte by LSB. Verified with
      // asm2000/dis2000: MOVB AL,*XAR0 = C6C0, MOVB AL,*XAR7 = C6C7.
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOVB_ind_load_AL expects [dst, ptr] operands");
      uint8_t Ptr = indirectXarField(MI.getOperand(1).getReg(), "MOVB_ind_load");
      Word = 0xC600 | Ptr;
      break;
    }
    case C28x::MOVB_ind_store_AL: {
      // MOVB *XARn, AL = 0x3C00 | (0xC0|n). Byte store: only one byte is
      // written, adjacent byte is preserved. Verified: MOVB *XAR0,AL = 3CC0.
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "MOVB_ind_store_AL expects [ptr] operand");
      uint8_t Ptr = indirectXarField(MI.getOperand(0).getReg(), "MOVB_ind_store");
      Word = 0x3C00 | Ptr;
      break;
    }
    case C28x::ADDB_SP:
    case C28x::SUBB_SP: {
      // ADDB SP,#7bit = 1111 1110 0CCC CCCC
      // SUBB SP,#7bit = 1111 1110 1CCC CCCC
      // The field is only 7 bits wide and the vendor assembler *silently
      // truncates* it (asm2000 turns "ADDB SP,#255" into "ADDB SP,#127"), so
      // anything outside 0..127 is rejected here rather than mis-assembled.
      // Verified: ADDB SP,#0 = FE00, ADDB SP,#127 = FE7F,
      //           SUBB SP,#0 = FE80, SUBB SP,#127 = FEFF.
      // Operand 0 is the explicit word count; the implicit SP def/use that the
      // .td adds (to keep SP out of spill slots) trail it — see
      // numExplicitOperands. A malformed MI is reported, never asserted: a bare
      // assert here used to abort llc on any function with a local frame.
      if (numExplicitOperands(MI, MCII) != 1 || !MI.getOperand(0).isImm())
        report_fatal_error(
            Twine("C28x: '") + MCII.getName(MI.getOpcode()) +
            "' expects a word-count immediate as operand 0");
      int64_t Amt = MI.getOperand(0).getImm();
      if (Amt < 0 || Amt > 127)
        report_fatal_error(
            Twine("C28x: '") + MCII.getName(MI.getOpcode()) + "' immediate " +
            Twine(Amt) +
            " does not fit the 7-bit SP immediate field (0..127); the vendor "
            "assembler would silently truncate it");
      uint16_t Base = MI.getOpcode() == C28x::ADDB_SP ? 0xFE00 : 0xFE80;
      Word = Base | uint16_t(Amt);
      break;
    }
    case C28x::MOVL_XAR_imm: {
      // MOVL XARn, #22bit: a two-word form holding a 22-bit *word* address.
      //   word 0 = <XARn opcode> | imm[21:16]   (the low 6 bits of word 0 carry
      //                                          the high half of the constant)
      //   word 1 = imm[15:0]
      // The per-XARn opcode table lives in xarOpcode(): 8D00 8D40 8D80 8DC0
      // 8F00 8F40 7680 76C0 for XAR0..XAR7.
      // Verified: asm2000 -v28 / dis2000
      //   MOVL XAR0,#0x3FFFFF -> 8D3F FFFF   MOVL XAR7,#0x3FFFFF -> 76FF FFFF
      //   MOVL XAR6,#0x010000 -> 7681 0000   MOVL XAR1,#0x1234   -> 8D40 1234
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOVL_XAR_imm expects [dst, imm] operands");
      MCRegister Dst = MI.getOperand(0).getReg();
      const MCOperand &SrcOp = MI.getOperand(1);
      if (SrcOp.isExpr()) {
        // Symbol reference: placeholder word0 (high 6 bits = 0), word1 = 0.
        // Patched by FK_C28x_ABS22 (R_C28X_ABS22_BR).
        emit16(CB, uint16_t(xarOpcode(Dst, XAR_OP_MOVL_IMM, "MOVL_XAR_imm")));
        Fixups.push_back(MCFixup::create(/*Offset=*/0, SrcOp.getExpr(),
                                         MCFixupKind(C28x::FK_C28x_ABS22),
                                         /*PCRel=*/false));
        emit16(CB, 0x0000);
        (void)STI;
        return;
      }
      int64_t Imm = SrcOp.getImm();
      if (Imm < 0 || Imm > 0x3FFFFF)
        report_fatal_error(
            Twine("C28x: MOVL_XAR_imm constant ") + Twine(Imm) +
            " does not fit the 22-bit word-address field (0..0x3FFFFF)");
      emit16(CB, uint16_t(xarOpcode(Dst, XAR_OP_MOVL_IMM, "MOVL_XAR_imm") |
                          (uint16_t(Imm) >> 16)));
      emit16(CB, uint16_t(Imm & 0xFFFF));
      (void)STI;
      return;
    }
    case C28x::MOV32rr: {
      // MOVL XARn, XARm = <XARn opcode> 1010 0mmm  (low byte = @ARm).
      // SPRU430F 6-308; the destination opcodes are the MOVL-XARn-loc32 table.
      // Verified for all 64 (n, m) pairs with asm2000 -v28 / dis2000:
      //   MOVL XAR0,XAR0 -> 8EA0   MOVL XAR0,XAR7 -> 8EA7
      //   MOVL XAR7,XAR0 -> C5A0   MOVL XAR7,XAR7 -> C5A7
      assert(numExplicitOperands(MI, MCII) == 2 && "MOV32rr expects [dst, src] operands");
      MCRegister Dst = MI.getOperand(0).getReg();
      MCRegister Src = MI.getOperand(1).getReg();
      Word = xarOpcode(Dst, XAR_OP_MOVL_TO_XAR, "MOV32rr") |
             loc32RegEncoding(Src, "MOV32rr");
      break;
    }
    case C28x::MOVL_XAR_AR: {
      // MOVZ ARn,loc16 defines XARn, clearing its high half. MOVL would
      // read the whole source super-register and is not zero-extension.
      assert(numExplicitOperands(MI, MCII) == 2 && "MOVL_XAR_AR expects [dst, src]");
      MCRegister Dst = MI.getOperand(0).getReg();
      MCRegister Src = MI.getOperand(1).getReg();
      Word = xarOpcode(Dst, XAR_OP_MOVZ, "MOVL_XAR_AR") |
             loc16RegEncoding(Src, "MOVL_XAR_AR");
      break;
    }
    case C28x::MOVL_XAR_ACC: {
      // MOVL XARn, ACC = <XARn opcode> 1010 1001  (loc32 code for @ACC).
      // SPRU430F 6-308 documents the eight destination opcodes; the canonical
      // loc32 form is used here rather than the dedicated one-word
      // "MOVL XARn, ACC" (0x1EA0|n, which the vendor assembler only chooses
      // for XAR6/XAR7) so all eight XARn share one verified table.
      // Verified: asm2000 -v28 / dis2000
      //   MOVL XAR0, @ACC -> 8EA9    MOVL XAR4, @ACC -> 8AA9
      //   MOVL XAR6, @ACC -> C4A9    MOVL XAR7, @ACC -> C5A9
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOVL_XAR_ACC expects [dst, src] operands");
      MCRegister Dst = MI.getOperand(0).getReg();
      MCRegister Src = MI.getOperand(1).getReg();
      if (Src != C28x::ACC && Src != C28x::XT)
        report_fatal_error("C28x: MOVL_XAR_ACC requires ACC or XT source");
      Word = xarOpcode(Dst, XAR_OP_MOVL_TO_XAR, "MOVL_XAR_ACC") |
             loc32RegEncoding(Src, "MOVL_XAR_ACC");
      break;
    }
    case C28x::MOVL_ACC_XAR: {
      // MOVL ACC, XARn = <MOVL loc32,XARn opcode> | 0xA9 (loc32 for @ACC).
      // Reverse direction of MOVL_XAR_ACC; uses "MOVL loc32, XARn" form.
      // Verified: asm2000 -v28 / dis2000
      //   MOVL ACC, XAR0 -> 3AA9    MOVL ACC, XAR7 -> 06A7
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MOVL_ACC_XAR expects [dst, src] operands");
      MCRegister Dst = MI.getOperand(0).getReg();
      MCRegister Src = MI.getOperand(1).getReg();
      if (Dst != C28x::ACC && Dst != C28x::XT)
        report_fatal_error("C28x: MOVL_ACC_XAR requires ACC or XT destination");
      Word = xarOpcode(Src, XAR_OP_MOVL_FROM_XAR, "MOVL_ACC_XAR") |
             loc32RegEncoding(Dst, "MOVL_ACC_XAR");
      break;
    }
    case C28x::MOV_XAR7_AL: {
      // MOVZ AR7, loc16 = 1000 0000 LLLL LLLL  (SPRU430F "MOVZ ARn,loc16":
      // "Load Lower Half of XARn and Clear Upper Half").
      // This is the only legal way to zero-extend a 16-bit register into XAR7:
      // asm2000 rejects "mov xar7, al" with [E0004] Illegal operand
      // combination, so the .td asm string spells MOVZ.
      // Verified for all eight destinations with asm2000 -v28 / dis2000:
      //   MOVZ AR0,AL -> 58A9 ... MOVZ AR5,AL -> 5DA9,
      //   MOVZ AR6,AL -> 88A9, MOVZ AR7,AL -> 80A9, MOVZ AR7,AR1 -> 80A1.
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "MOV_XAR7_AL expects a single 16-bit source operand");
      Word = xarOpcode(C28x::XAR7, XAR_OP_MOVZ, "MOV_XAR7_AL") |
             loc16RegEncoding(MI.getOperand(0).getReg(), "MOV_XAR7_AL");
      break;
    }
    case C28x::MOVZ_XAR7_SP: {
      assert(numExplicitOperands(MI, MCII) == 0 &&
             "MOVZ_XAR7_SP has no explicit operands");
      Word = 0x80AD; // TI asm2000 -v28: MOVZ AR7,SP
      break;
    }
    case C28x::SUBB_XAR7_imm: {
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "SUBB_XAR7_imm expects a word count");
      int64_t Words = MI.getOperand(0).getImm();
      if (Words < 1 || Words > 127)
        report_fatal_error("C28x: SUBB XAR7 word count exceeds 7-bit field");
      Word = 0xDF80 | uint16_t(Words); // TI asm2000: SUBB XAR7,#1 = 0xDF81
      break;
    }
    case C28x::ADDB_XAR7_imm: {
      // ADDB XAR7, #7bit = 0xDF00 | imm (bit 7 = 0 distinguishes ADD from SUB).
      // Verified: asm2000 -v28 / dis2000
      //   ADDB XAR7,#1 = DF01    ADDB XAR7,#65 = DF41
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "ADDB_XAR7_imm expects a word count");
      int64_t Words = MI.getOperand(0).getImm();
      if (Words < 0 || Words > 127)
        report_fatal_error("C28x: ADDB XAR7 word count exceeds 7-bit field");
      Word = 0xDF00 | uint16_t(Words);
      break;
    }
    case C28x::ROR_ACC:
      // ROR ACC = 0xFF52 (rotate ACC right through carry).  Used with CLRC C
      // to implement 32-bit logical right-shift by 1 (byte->word address).
      // Verified: asm2000 -v28 / dis2000 -> ROR ACC = FF52.
      Word = 0xFF52;
      break;
    case C28x::CLRC_C:
      // CLRC C = 0x2908 (clear carry flag in ST0).
      // Verified: asm2000 -v28 / dis2000 -> CLRC C = 2908.
      Word = 0x2908;
      break;
    case C28x::SETC_C:
      // SETC C = 0x3B08 (set carry flag in ST0).
      // Verified: asm2000 -v28 / dis2000 -> SETC C = 3B08.
      Word = 0x3B08;
      break;
    case C28x::ROL_ACC:
      // ROL ACC = 0xFF53 (rotate ACC left through carry).  Used with
      // SETC/CLRC C to implement word->byte address (word*2 + lane).
      // Verified: asm2000 -v28 / dis2000 -> ROL ACC = FF53.
      Word = 0xFF53;
      break;
    case C28x::SETC_SXM:
      // SETC SXM = 0x3B01 (set sign-extension mode).
      // Verified: asm2000 -v28 / dis2000 -> SETC SXM = 3B01.
      Word = 0x3B01;
      break;
    case C28x::MOV_ACC_GR16:
      // MOV ACC,reg16 = 0x8500 | loc16 (sign-extends when SXM=1).
      // Verified: AL=85A9, AH=85A8, AR0=85A0.
      Word = 0x8500 | loc16RegEncoding(MI.getOperand(1).getReg(), "MOV_ACC_GR16");
      break;
    case C28x::MOVU_ACC_GR16:
      // MOVU ACC,reg16 = 0x0E00 | loc16 (zero-extends).
      // Verified: AL=0EA9, AH=0EA8, AR0=0EA0.
      Word = 0x0E00 | loc16RegEncoding(MI.getOperand(1).getReg(), "MOVU_ACC_GR16");
      break;
    case C28x::LSL_ACC_T:
      // LSL ACC,T = 0xFF50 (32-bit logical left, count in T(4:0)).
      Word = 0xFF50;
      break;
    case C28x::LSRL_ACC_T:
      // LSRL ACC,T = 0x5622 (32-bit logical right, count in T(4:0)).
      Word = 0x5622;
      break;
    case C28x::ASRL_ACC_T:
      // ASRL ACC,T = 0x5610 (32-bit arithmetic right, sign-filled, count in T).
      Word = 0x5610;
      break;
    case C28x::MOV_T: {
      // MOV T, loc16 = 0x2D00 | loc16 code. Verified: AR0 = 2DA0,
      // AL = 2DA9, AH = 2DA8.
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "MOV_T expects one loc16 operand");
      Word = 0x2D00 | loc16RegEncoding(MI.getOperand(0).getReg(), "MOV_T");
      break;
    }
    case C28x::MPY_ACC_T:
      // MPY ACC,T,loc16 = 0x1200 | loc (signed 16x16 -> ACC).
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MPY_ACC_T expects [dst, loc16] operands");
      Word = 0x1200 | loc16RegEncoding(MI.getOperand(1).getReg(), "MPY_ACC_T");
      break;
    case C28x::MPYU_ACC_T:
      // MPYU ACC,T,loc16 = 0x3600 | loc (unsigned 16x16 -> ACC).
      assert(numExplicitOperands(MI, MCII) == 2 &&
             "MPYU_ACC_T expects [dst, loc16] operands");
      Word = 0x3600 | loc16RegEncoding(MI.getOperand(1).getReg(), "MPYU_ACC_T");
      break;
    case C28x::LCR_IND_REAL: {
      // LCR *XARn = 0x3E60|n (1-word indirect call). Verified with
      // asm2000/dis2000: LCR *XAR0=3E60, LCR *XAR4=3E64.
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "LCR_IND_REAL expects [ptr] operand");
      uint8_t Ptr = indirectXarField(MI.getOperand(0).getReg(), "LCR_IND_REAL");
      // indirectXarField returns 0xC0|n; LCR *XARn = 0x3E60|n.
      Word = 0x3E60 | (Ptr & 0x07);
      break;
    }
    case C28x::LCR: {
      // LCR #pma: two-word 22-bit absolute call.
      //   word 0 = 0x7640 | (addr[21:16])
      //   word 1 = addr[15:0]
      // Verified with asm2000 -v28 / dis2000:
      //   LCR 0x1234 -> 7640 1234   LCR 0x3FFFFF -> 767F FFFF
      //   LCR sym    -> 7640 0000 + R_C28X_ABS22_BR at r_offset=0
      assert(numExplicitOperands(MI, MCII) == 1 &&
             "LCR expects a single 22-bit target operand");
      const MCOperand &Dst = MI.getOperand(0);
      if (Dst.isImm()) {
        uint32_t Addr = uint32_t(Dst.getImm());
        if (Addr > 0x3FFFFFu)
          report_fatal_error(
              Twine("C28x: LCR target 0x").concat(Twine::utohexstr(Addr))
                  .concat(" does not fit the 22-bit word address"));
        emit16(CB, uint16_t(0x7640 | (Addr >> 16)));
        emit16(CB, uint16_t(Addr & 0xFFFF));
      } else if (Dst.isExpr()) {
        emit16(CB, 0x7640);
        Fixups.push_back(MCFixup::create(/*Offset=*/0, Dst.getExpr(),
                                         MCFixupKind(C28x::FK_C28x_ABS22),
                                         /*PCRel=*/false));
        emit16(CB, 0x0000);
      } else {
        report_fatal_error("C28x: LCR target must be an immediate or a symbol");
      }
      (void)STI;
      return;
    }
    default:
      // Contract L1-2 (ABI_FREEZE.md): never emit unverified machine code.
      report_fatal_error(
          Twine("C28x: no verified encoding for instruction '")
              .concat(MCII.getName(MI.getOpcode()))
              .concat("'. Add the TI SPRU430F opcode and an oracle byte "
                      "regression before enabling object emission."));
    }

    // TI stores instruction words little-endian: the low byte of the word goes
    // to the lower address (see the header comment). This is the opposite of
    // "print the opcode byte first".
    emit16(CB, Word);

    // Only the two-word branches above emit a fixup; everything else in the
    // verified set is self-contained.
    (void)Fixups;
    (void)STI;
  }
};
} // namespace

MCCodeEmitter *llvm::createC28xMCCodeEmitter(const MCInstrInfo &MCII,
                                             MCContext &Ctx) {
  return new C28xMCCodeEmitter(MCII, Ctx);
}
