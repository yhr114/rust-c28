; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; 16-bit ALU ops must target AL/AH: C28x is an accumulator machine and has no
; general-purpose register arithmetic (SPRU430F §6). The destination register
; class is GR16ACC, so the allocator is forced to route intermediates through
; the accumulator and to insert explicit MOVs.
;
; Registered regression for the GR16ACC constraint: before it, four() asked for
; "add ar1, ar2", which has no encoding at all, and the emitter failed closed.
;
; four(a,b,c,d) = (a + b) + (c + d)
;   mov ah, ar1     ; AH = b            word 93A1
;   add ah, ar2     ; AH = AH + c       word 95A2
;   add al, ar0     ; AL = AL + a       word 94A0
;   add al, ah      ; AL = AL + AH      word 94A8   (ADD AL,@AH)
;   lretr                              word 0006
;
; Encoding oracle: TI asm2000 -v28 / dis2000 produce exactly these words for
; the same instruction text, and dis2000 round-trips the LLVM object byte for
; byte.
define i16 @four(i16 %a, i16 %b, i16 %c, i16 %d) {
entry:
  %t1 = add i16 %a, %b
  %t2 = add i16 %c, %d
  %r  = add i16 %t1, %t2
  ret i16 %r
}

; chain(a,b,c) = (a - b) & c
;   sub al, ar0     ; word 9EA0
;   and al, ar1     ; word CEA1
;   lretr           ; word 0006
define i16 @chain(i16 %a, i16 %b, i16 %c) {
entry:
  %t1 = sub i16 %a, %b
  %t2 = and i16 %t1, %c
  ret i16 %t2
}

; CHECK: a193 a295 a094 a894 0600
; CHECK-SAME: a09e a1ce 0600
