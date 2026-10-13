; RUN: llc -mtriple=c28x-ti-none -filetype=obj %s -o %t.o
; RUN: llvm-readobj -r %t.o | FileCheck %s
;
; Test that cross-object LCR calls produce R_C28X_ABS22_BR relocations with
; r_offset in 16-bit words (not bytes), matching cl2000/asm2000 convention.
; The TI linker expects r_offset to point to the LCR opcode word.

target triple = "c28x-ti-none"

declare i16 @callee(i16 %a)

define i16 @caller(i16 %x) {
  %r = call i16 @callee(i16 %x)
  ret i16 %r
}

; CHECK:      Relocations [
; CHECK-NEXT:   Section {{.*}} .text {
; CHECK-NEXT:     0x0 R_C28X_ABS22_BR callee
; CHECK-NEXT:   }
; CHECK-NEXT: ]
