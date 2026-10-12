; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; L2 object-emission smoke test (contract L1-2, ABI_FREEZE.md):
; 16-bit register-register ADD/SUB target the accumulator (C28x has no
; general-purpose register arithmetic).
;   add(i16,i16) -> ADD AL,@AR0 (word 0x94A0, bytes A0 94) + LRETR (bytes 06 00)
;   sub(i16,i16) -> SUB AL,@AR0 (word 0x9EA0, bytes A0 9E) + LRETR (bytes 06 00)
;
; Encoding oracle: TI asm2000 -v28 / dis2000 and cl2000 agree on these words:
;   ADD AL,@AR0 -> 94a0    SUB AL,@AR0 -> 9ea0    LRETR -> 0006
; Little-endian word order means the low byte is stored first ("A0 94").
define i16 @add(i16 %a, i16 %b) {
entry:
  %r = add i16 %a, %b
  ret i16 %r
}

define i16 @sub(i16 %a, i16 %b) {
entry:
  %r = sub i16 %a, %b
  ret i16 %r
}

; CHECK: a0940600
; CHECK: a09e0600
