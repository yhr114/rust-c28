; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; Regression guard for the "applyFixup double offset" bug (fixed 2026-09-28).
;
; MCAssembler::layout() hands applyFixup a pointer that is *already* advanced to
; the fixup site:
;     auto *Data = reinterpret_cast<uint8_t *>(
;         F.getContents().data() + Fixup.getOffset());   // MCAssembler.cpp
; The backend used to add Fixup.getOffset() a second time, so with two branches
; in one fragment the first offset landed on the second branch's placeholder and
; the second write ran off the end of the fragment. A single-branch function
; (branch.ll) never exposed it because the shifted store still fell inside the
; fragment. This test asserts both branch offsets land on their own word.
;
; Expected .text (13 words), all words cross-checked with TI asm2000/dis2000:
;   word 0  54A0  CMP AL,@AR0
;   word 1  FFE0  B <1+8>,NEQ          (condition field 0000 = NEQ)
;   word 2  0008  offset = target word 9 - branch word 1
;   word 3  92A0  MOV AL,@AR0
;   word 4  54A1  CMP AL,@AR1
;   word 5  FFE0  B <5+6>,NEQ
;   word 6  0006  offset = target word 11 - branch word 5
;   word 7  9A01  MOVB AL,#1
;   word 8  0006  LRETR
;   word 9  9A03  MOVB AL,#3
;   word 10 0006  LRETR
;   word 11 9A02  MOVB AL,#2
;   word 12 0006  LRETR
;
; Before the fix this produced ...FFE0 0000 92A0 54A1 FF08... (offset written
; one byte pair too far right) instead of ...FFE0 0008 92A0 54A1 FFE0...
define i16 @two(i16 %a, i16 %b, i16 %c) {
entry:
  %x = icmp eq i16 %a, %b
  br i1 %x, label %t, label %f
t:
  %y = icmp eq i16 %b, %c
  br i1 %y, label %tt, label %tf
tt:
  ret i16 1
tf:
  ret i16 2
f:
  ret i16 3
}

; CHECK: a054e0ff0800a092a154e0ff0600019a0600039a0600029a0600
