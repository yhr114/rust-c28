; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; 32-bit logical AND/OR/XOR must keep Lhs while extracting the Rhs halves.
;
; Regression for the AND32/OR32/XOR32_PSEUDO post-RA expansion: it brought Lhs
; into ACC, then EmitLoadRhs() overwrote ACC with Rhs before the 16-bit halves
; were applied, so the expansion computed Rhs&Rhs (== Rhs) — and the middle
; `MOV AR0, AH` clobbered XAR0 (the materialized constant register) on the way.
; Hardware symptom: Option::is_some (which lowers to `and i32 tag, 1`) lost the
; tag through the clobbered ACC and returned 0 for Some(5):
;   core-ex group E: some_of(1)=0 (want 1), none_of(1)=1 (want 0),
;   core-ex group A: core_ex_option=138 (want 140).
; The fix pushes/pops Lhs around each EmitLoadRhs() call, matching the
; *_HALF_PSEUDO discipline.
;
; and32_imm(a) = a & 1  (is_some shape: Lhs in ACC, Rhs a materialized const)
define i32 @and32_imm(i32 %a) {
entry:
  %r = and i32 %a, 1
  ret i32 %r
}
;   movl xar0, #1    word 008D 0100   Rhs = 1 (dying operand in XAR0)
;   movl xar7, xar0  word A0C5        park Rhs in reserved XAR7 (shield:
;                                       the AR0 half writes below zero XAR0)
;   push ar0         word A022         borrow AR0
;   push acc         word BD1E         save Lhs
;   movl acc, xar7   word A9C3         ACC = Rhs
;   mov ar0, ah      word A097         AR0 = Rhs high
;   pop acc          word BE06         ACC = Lhs
;   and ah, ar0      word A0CF         AH = Lhs.h & Rhs.h
;   push acc         word BD1E         save Lhs
;   movl acc, xar7   word A9C3         ACC = Rhs (XAR7 untouched)
;   mov ar0, al      word A096         AR0 = Rhs low
;   pop acc          word BE06         ACC = Lhs
;   and al, ar0      word A0CE         AL = Lhs.l & Rhs.l
;   pop ar0          word A02A
;
; CHECK: 008d0100
; CHECK-SAME: a0c5
; CHECK: a022
; CHECK: bd1e
; CHECK: a9c3
; CHECK: a097
; CHECK: be06
; CHECK: a0cf
; CHECK: bd1e
; CHECK: a9c3
; CHECK: a096
; CHECK: be06
; CHECK: a0ce
; CHECK: a02a

; and32_regs(a, b) = a & b  (distinct GPR32 operands: both come from the
; stack, Rhs is staged through XT — the other side of the same expansion).
define i32 @and32_regs(i32 %a, i32 %b) {
entry:
  %r = and i32 %a, %b
  ret i32 %r
}

; or32_regs(a, b) = a | b — same expansion family, must not degenerate to
; Rhs (the old bug made OR return Rhs for any operands).
define i32 @or32_regs(i32 %a, i32 %b) {
entry:
  %r = or i32 %a, %b
  ret i32 %r
}

; xor32_regs(a, b) = a ^ b — the old expansion returned 0 for any operands
; (Rhs^Rhs), which silently zeroed every mask computation.
define i32 @xor32_regs(i32 %a, i32 %b) {
entry:
  %r = xor i32 %a, %b
  ret i32 %r
}
