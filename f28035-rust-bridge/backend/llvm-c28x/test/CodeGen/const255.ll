; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; Immediate boundary: `ret i16 255` must lower to  MOVB AL,#255 (word 0x9AFF,
; bytes FF 9A) + LRETR (word 0x0006, bytes 06 00), i.e. .text bytes
; ff 9a 06 00. Verifies the imm8 field is an UNSIGNED byte and is not
; sign-extended into the opcode byte.
;
; Encoding oracle: TI cl2000 -v28 on `int g255(void){return 255;}` emits
;   MOVB AL, #0xff ; LRETR  -> 9aff 0006  (dis2000), memory "ff 9a 06 00".
define i16 @const255() {
entry:
  ret i16 255
}

; CHECK: ff9a0600
