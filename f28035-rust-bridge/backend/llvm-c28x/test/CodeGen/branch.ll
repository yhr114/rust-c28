; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; L2 control-flow emission smoke test (contract L1-2, ABI_FREEZE.md):
; this is the first object-level test that exercises a *two-word* instruction
; plus a target fixup.
;
; choose(a, b) -> cmp al, ar0      ; CMP AL,@AR0  word 54A0
;                 b LBB0_2, neq    ; word 1 = FFE0 (1111 1111 1110 0000)
;                                  ; word 2 = 0004 (target word 5 minus the
;                                  ;          branch's own word 1)
;                 mov al, #1       ; word 9A01
;                 lretr            ; word 0006
;               LBB0_2:
;                 mov al, #0       ; word 9A00
;                 lretr            ; word 0006
;
; Encoding oracle: TI asm2000 -v28 / dis2000 agree on every word, and on the
; branch offset convention ("B 204,UNC" for a branch at word 0 targeting word
; 204 -> FFEF 00CC; "B 202,EQ" for a branch at word 2 targeting word 204).
; Little-endian word order means the low byte is stored first.
define i16 @choose(i16 %a, i16 %b) {
entry:
  %c = icmp eq i16 %a, %b
  br i1 %c, label %yes, label %no
yes:
  ret i16 1
no:
  ret i16 0
}

; CHECK: a054e0ff0400019a0600009a0600
