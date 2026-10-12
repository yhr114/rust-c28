; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; L2 object-emission smoke test (contract L1-2, ABI_FREEZE.md):
; 16-bit register-register AND/OR/XOR target the accumulator (C28x is an
; accumulator machine; SPRU430F §6).
;   and(i16,i16) -> AND AL,@AR0         + LRETR
;   or(i16,i16)  -> OR  AL,@AR0         + LRETR
;   xor(i16,i16) -> XOR AL,@AR0         + LRETR
;
; Encoding oracle: TI asm2000 -v28 / dis2000 and cl2000 agree on these words:
;   AND AL,@AR0 -> cea0    OR AL,@AR0 -> caa0    XOR AL,@AR0 -> 70a0
;   LRETR       -> 0006
; Little-endian word order means the low byte is stored first ("A0 CE" etc.).
define i16 @and(i16 %a, i16 %b) {
entry:
  %r = and i16 %a, %b
  ret i16 %r
}

define i16 @or(i16 %a, i16 %b) {
entry:
  %r = or i16 %a, %b
  ret i16 %r
}

define i16 @xor(i16 %a, i16 %b) {
entry:
  %r = xor i16 %a, %b
  ret i16 %r
}

; CHECK: a0ce0600
; CHECK: a0ca0600
; CHECK: a0700600
