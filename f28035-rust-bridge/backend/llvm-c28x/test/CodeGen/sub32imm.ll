; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; A negative 32-bit addend must not be encoded as `ADD ACC, #imm16`.
;
; `ADD ACC,#16bit` (0xFF10) and `SUB ACC,#16bit` (0xFF00) ZERO-extend their
; immediate; they do not sign-extend it.  Hardware-verified on F28035:
; ACC=0x0808 followed by `ADD ACC,#0xFFFE` produces 0x0001_0806, not
; 0x0000_0806.  The stray 1<<16 survives the byte->word `>>1` that follows
; every address computation, so the result lands 0x8000 words away:
;
;   slice::Iter::next_back    self.end = self.end.sub(1)
;     end (byte) 0x0808 -> ADD ACC,#0xFFFE -> 0x10806 -> >>1 -> word 0x8403
;     (correct is 0x0403, i.e. the last slice element)
;
; Hardware symptom: every DoubleEndedIterator path read code memory instead of
; the slice —
;   core-ex group B : last() -> 32941 (want 8)   => group result 11191 (want 80)
;   core-ex group B2: rev()  -> 54532 (want 20)
; The fix rewrites a negative addend as the opposite operation on its
; magnitude (|Val| <= 32768 always fits the 16-bit field), and the emitter
; keeps a defensive flip so a future producer cannot reintroduce the encoding.
;
; gep_minus1(p) = p - 1 element  (the next_back shape: GEP with index -1)
define ptr @gep_minus1(ptr %p) {
  %q = getelementptr i16, ptr %p, i32 -1
  ret ptr %q
}
;   addb sp, #2      word FE02
;   movl acc, xar4   word A9A8        ACC = p
;   sub acc, #2      word FF00 0002   (was add acc, #65534 = FF10 FFFE)
;   movl xar0, acc   word A98E
;   subb sp, #2      word FE82
;
; CHECK: 02fe
; CHECK: a9a8
; CHECK: ff000002
; CHECK: a98e

; add_neg_big(a) = a + (-1000) — a negative addend outside the 8-bit ADDB form
; must also flip to `SUB ACC, #1000`.
define i32 @add_neg_big(i32 %a) {
  %r = add i32 %a, -1000
  ret i32 %r
}
;   addb sp, #2      word FE02
;   movl acc, xar4   word A9A8
;   sub acc, #1000   word FF00 03E8   (was add acc, #64536 = FF10 FC18)
;   movl xar0, acc   word A98E
;
; CHECK: 02fe
; CHECK: a9a8
; CHECK: ff0003e8
; CHECK: a98e

; add_pos_big(a) = a + 1000 — positive addends keep the ADD encoding, which is
; what zero-extension is correct for.
define i32 @add_pos_big(i32 %a) {
  %r = add i32 %a, 1000
  ret i32 %r
}
;   add acc, #1000   word FF10 03E8
;
; CHECK: 02fe
; CHECK: a9a8
; CHECK: ff1003e8
; CHECK: a98e
