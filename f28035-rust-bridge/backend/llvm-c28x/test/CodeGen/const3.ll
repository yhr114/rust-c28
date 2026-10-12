; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; Object-emission smoke test (contract L1-2, ABI_FREEZE.md):
; `ret i16 3` must lower to  MOVB AL,#3 (word 0x9A03, bytes 03 9A)
;                      +  LRETR (word 0x0006, bytes 06 00)
; i.e. .text bytes 03 9a 06 00.
;
; Encoding oracle: TI cl2000 -v28 on `int g3(void){return 3;}` emits exactly
;   MOVB AL, #0x3 ; LRETR   -> 9a03 0006  (dis2000), memory "03 9a 06 00".
; Note: there is no "MOV AL,#8bit" opcode in SPRU430F; the 8-bit immediate
; form is MOVB AX,#8bit = 1001 101A CCCC CCCC.
define i16 @const3() {
entry:
  ret i16 3
}

; CHECK: 039a0600
