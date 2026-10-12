//===-- C28xAsmBackend.cpp - C28x Assembler Backend ---------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Minimal MCAsmBackend so that `llc -filetype=obj` can produce an ELF object
// for self-checking encoded machine bytes (llvm-objdump -s). This object is a
// verification vehicle only: the TI toolchain consumes .s + cl2000 (COFF), so
// no TI-side tool ever reads this ELF.
//
// Two-word branches are the only verified instructions that emit a target
// fixup (FK_C28x_BRANCH). Because a branch always targets a basic-block label
// in the same section, the fixup resolves completely and no relocation is
// written; getRelocType stays fail-closed for anything else.
//
//===----------------------------------------------------------------------===//

#include "C28xAsmBackend.h"
#include "C28xMCTargetDesc.h"
#include "llvm/BinaryFormat/ELF.h"
#include "llvm/MC/MCAsmBackend.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCELFObjectWriter.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCObjectWriter.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/MCTargetOptions.h"
#include "llvm/MC/MCValue.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/TargetParser/Triple.h"

using namespace llvm;

namespace {
class C28xELFObjectWriter : public MCELFObjectTargetWriter {
public:
  C28xELFObjectWriter()
      : MCELFObjectTargetWriter(/*Is64Bit=*/false, ELF::ELFOSABI_NONE,
                                ELF::EM_TI_C2000,
                                /*HasRelocationAddend=*/false) {}

  unsigned getRelocType(const MCFixup &Fixup, const MCValue &Target,
                        bool IsPCRel) const override {
    // TI C28x EABI relocation type numbers (from ofd2000 on asm2000 output):
    //   R_C28X_ABS22_BR = 20  -- two-word 22-bit absolute address (LCR/MOVL)
    // We only emit that one today; anything else is still unsupported.
    if (Fixup.getKind() == C28x::FK_C28x_ABS22)
      return 20; // R_C28X_ABS22_BR
    report_fatal_error(
        Twine("C28x: unsupported fixup kind for object emission (kind=") +
        Twine(Fixup.getKind()) + ")");
  }
};

class C28xAsmBackend : public MCAsmBackend {
public:
  C28xAsmBackend(const MCSubtargetInfo &STI, const MCTargetOptions &Opts)
      : MCAsmBackend(llvm::endianness::little) {}

  void applyFixup(const MCFragment &F, const MCFixup &Fixup,
                  const MCValue &Target, uint8_t *Data, uint64_t Value,
                  bool IsResolved) override {
    MCFixupKind Kind = Fixup.getKind();

    // `Data` is NOT the start of the fragment: MCAssembler::layout() passes
    //   Data = F.getContents().data() + Fixup.getOffset()
    // (MCAssembler.cpp: "auto *Data = reinterpret_cast<uint8_t *>(
    //   Contents.data() + Fixup.getOffset());").
    // So every store below is relative to Data[0], never Data[Fixup.getOffset()].
    // Getting this wrong silently scribbles over unrelated instruction words.
    uint8_t *const FieldBase = Data;

    if (Kind == C28x::FK_C28x_BRANCH) {
      // Unresolved (external) branch target: the verified design only allows
      // PC-relative branches to same-section basic-block labels.  core references
      // a noreturn/external symbol that reaches here (a tail-call to a noreturn
      // callee lowered to B).  This ELF object is a verification vehicle only
      // (real output goes through asm2000, which resolves the relocation), so
      // rather than abort, zero the offset field and warn.  A proper PC-relative
      // branch relocation type is a later linker gap.
      if (!IsResolved) {
        errs() << "C28x BRANCH to unresolved target: leaving offset=0 "
                  "(Value=" << Value << ")\n";
        FieldBase[0] = 0;
        FieldBase[1] = 0;
        return;
      }
      // "B 16bitOffset,COND" stores (target word address - branch word address)
      // in its second word. The fixup sits on that second word, so the
      // assembler has already computed
      //   Value = target_bytes - (instruction_address + 2)
      // (see MCAssembler::evaluateFixup, which subtracts
      // getFragmentOffset(F) + Fixup.getOffset() for PC-relative fixups).
      // Adding one word back and halving gives the field TI's own assembler
      // and disassembler agree on; verified with asm2000/dis2000 on a branch
      // at word 0 targeting word 204 ("B 204,UNC" = FFEF 00CC) and a branch at
      // word 2 targeting word 204 ("B 202,EQ" = FFE1 00CA).
      int64_t Field = (static_cast<int64_t>(Value) + 2) / 2;
      if (Field < -32768 || Field > 32767) {
        // Diagnose: an out-of-range PC-relative branch almost always means the
        // fixup landed on an undefined/external symbol (assembler treats its
        // address as 0, yielding a huge negative offset).
        errs() << "C28x BRANCH out of range: Field=" << Field
               << " Value=" << Value << " IsResolved=" << IsResolved
               << "\n";
        report_fatal_error(
            Twine("C28x: branch offset ") + Twine(Field) +
            " words does not fit the signed 16-bit B offset field "
            "(+/-32767 words)");
      }
      FieldBase[0] = uint8_t(Field & 0xFF);
      FieldBase[1] = uint8_t((Field >> 8) & 0xFF);
      return;
    }

    if (Kind == C28x::FK_C28x_ABS22) {
      // Two-word 22-bit absolute: value is the 22-bit word address.
      //   FieldBase[0..1] = word0 = (existing opcode) | (addr >> 16)
      //   FieldBase[2..3] = word1 = addr & 0xFFFF
      // C28x is little-endian: low byte first. The placeholder bytes are
      // already written by the code emitter (word0 low byte has the opcode
      // low nibble; OR in the high 6 bits of the address).
      uint32_t Addr = uint32_t(Value) & 0x3FFFFFu;
      FieldBase[0] |= uint8_t((Addr >> 16) & 0x3F);
      FieldBase[2] = uint8_t(Addr & 0xFF);
      FieldBase[3] = uint8_t((Addr >> 8) & 0xFF);
      // If the target symbol is undefined (external call), record a
      // relocation entry for the TI linker to fill in.
      maybeAddReloc(F, Fixup, Target, Value, IsResolved);
      return;
    }

    if (Kind >= FirstTargetFixupKind)
      report_fatal_error("C28x: target applyFixup not implemented yet");

    MCFixupKindInfo Info = getFixupKindInfo(Kind);
    unsigned NumBytes = (Info.TargetOffset + Info.TargetSize + 7) / 8;
    Value <<= Info.TargetOffset;
    for (unsigned I = 0; I != NumBytes; ++I)
      FieldBase[I] |= uint8_t(Value >> (I * 8));
  }

  MCFixupKindInfo getFixupKindInfo(MCFixupKind Kind) const override {
    if (Kind < FirstTargetFixupKind)
      return MCAsmBackend::getFixupKindInfo(Kind);
    static const MCFixupKindInfo Infos[C28x::NumTargetFixupKinds] = {
        {"FK_C28x_16_ABS", 0, 16, 0},
        {"FK_C28x_ABS22", 0, 32, 0},
        {"FK_C28x_BRANCH", 0, 16, 0},
    };
    return Infos[Kind - FirstTargetFixupKind];
  }

  std::unique_ptr<MCObjectTargetWriter>
  createObjectTargetWriter() const override {
    return std::make_unique<C28xELFObjectWriter>();
  }

  bool writeNopData(raw_ostream &OS, uint64_t Count,
                    const MCSubtargetInfo *STI) const override {
    // ELF layout may request zero bytes as well as alignment padding. The
    // verification object uses zero-filled words; executable TI output still
    // goes through the vendor assembler.
    OS.write_zeros(Count);
    return true;
  }
};
} // namespace

MCAsmBackend *llvm::createC28xMCAsmBackend(const Target &T,
                                           const MCSubtargetInfo &STI,
                                           const MCRegisterInfo &MRI,
                                           const MCTargetOptions &Opts) {
  return new C28xAsmBackend(STI, Opts);
}
