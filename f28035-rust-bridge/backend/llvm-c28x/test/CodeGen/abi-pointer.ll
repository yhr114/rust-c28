target triple = "c28x-ti-none"

; TI EABI pointer-pool ABI tests.
; Oracle: cl2000 -v28 --abi=eabi -o2 disassembly (2026-10-20, CGT 25.11.1):
;   pointer args  -> XAR4, XAR5, then stack (never ACC)
;   sret (hidden struct-return buffer) -> XAR6
;   i32           -> ACC (first), then stack
;   i16           -> AL/AH when no i32; AR4/AR5 when an i32 exists,
;                   with the pointer slots pre-reserved (XAR4/XAR5 alias
;                   AR4/AR5, so an i16 moves to AR5 when a pointer is present)
; Indirect calls lower to LCR *XARn after a logical-byte -> word conversion.

; (ptr a, i32 b) -> a=XAR4, b=ACC
define i32 @f_ptr_i32(ptr %a, i32 %b) {
  %va = load i32, ptr %a
  %r = add i32 %va, %b
  ret i32 %r
}

; (ptr a, ptr b) -> a=XAR4, b=XAR5
define i32 @f_ptr_ptr(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %r = add i32 %va, %vb
  ret i32 %r
}

; (ptr a, i16 b) -> a=XAR4, b=AL (no i32: AL/AH stay free)
define i32 @f_ptr_i16(ptr %a, i16 %b) {
  %bex = zext i16 %b to i32
  %va = load i32, ptr %a
  %r = add i32 %va, %bex
  ret i32 %r
}

; (i16 a, ptr p, i32 b) -> a=AR5, p=XAR4, b=ACC
define i32 @f_i16_ptr_i32(i16 %a, ptr %p, i32 %b) {
  %aex = zext i16 %a to i32
  %va = load i32, ptr %p
  %r = add i32 %va, %b
  %r2 = add i32 %r, %aex
  ret i32 %r2
}

; (ptr a, ptr b, ptr c) -> a=XAR4, b=XAR5, c=stack
define i32 @f_3ptr(ptr %a, ptr %b, ptr %c) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %vc = load i32, ptr %c
  %r = add i32 %va, %vb
  %r2 = add i32 %r, %vc
  ret i32 %r2
}

; (i32 a, ptr p, i32 b) -> a=ACC, p=XAR4, b=stack
define i32 @f_i32_ptr_i32(i32 %a, ptr %p, i32 %b) {
  %va = load i32, ptr %p
  %r = add i32 %va, %a
  %r2 = add i32 %r, %b
  ret i32 %r2
}

; Function pointer argument (ptr -> XAR4) with an indirect call (LCR *XARn).
define i32 @f_fnptr(ptr %fp, i32 %v) {
  %r = call i32 %fp(i32 %v)
  ret i32 %r
}

; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 -verify-machineinstrs -filetype=asm < %s | FileCheck %s

; CHECK-LABEL: f_ptr_i32:
; CHECK: movl xt, acc
; CHECK: movl acc, xar4

; CHECK-LABEL: f_ptr_ptr:
; CHECK: movl acc, xar4
; CHECK: movl acc, xar5

; CHECK-LABEL: f_ptr_i16:
; CHECK: movz ar{{[0-9]}}, al
; CHECK: movl acc, xar4

; CHECK-LABEL: f_i16_ptr_i32:
; CHECK: movl xt, acc
; CHECK: movz ar{{[0-9]}}, ar5
; CHECK: movl acc, xar4

; CHECK-LABEL: f_3ptr:
; CHECK: addb sp, #{{[0-9]+}}
; CHECK: movl acc, xar4
; CHECK: movl acc, xar5

; CHECK-LABEL: f_i32_ptr_i32:
; CHECK: addb sp, #
; CHECK: movl xt, acc
; CHECK: movl acc, xar4

; CHECK-LABEL: f_fnptr:
; CHECK: movl acc, xar4
; CHECK: lcr *xar
