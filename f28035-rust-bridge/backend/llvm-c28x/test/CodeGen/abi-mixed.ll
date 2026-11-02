target triple = "c28x-ti-none"

; Test mixed i16/i32 argument allocation per TI EABI.
; Oracle: cl2000 -v28 --abi=eabi -k (O0) / -o2 disassembly (2026-10-20):
;   If any i32 arg exists: first i32 -> ACC, i16 args -> AR4, AR5, stack
;   If no i32 arg: i16 args -> AL, AH, AR4, AR5
;   Second and later i32 -> stack

; (i16 a, i32 b) -> a=AR4, b=ACC
define i16 @f_i16_i32(i16 %a, i32 %b) {
  %b.trunc = trunc i32 %b to i16
  %r = add i16 %a, %b.trunc
  ret i16 %r
}

; (i32 a, i16 b) -> a=ACC, b=AR4
define i32 @f_i32_i16(i32 %a, i16 %b) {
  %b.ext = zext i16 %b to i32
  %r = add i32 %a, %b.ext
  ret i32 %r
}

; (i16 a, i16 b, i32 c) -> a=AR4, b=AR5, c=ACC
define i16 @f_i16_i16_i32(i16 %a, i16 %b, i32 %c) {
  %c.trunc = trunc i32 %c to i16
  %t = add i16 %a, %b
  %r = add i16 %t, %c.trunc
  ret i16 %r
}

; (i32 a, i16 b, i16 c) -> a=ACC, b=AR4, c=AR5
define i32 @f_i32_i16_i16(i32 %a, i16 %b, i16 %c) {
  %b.ext = zext i16 %b to i32
  %c.ext = zext i16 %c to i32
  %t = add i32 %a, %b.ext
  %r = add i32 %t, %c.ext
  ret i32 %r
}

; (i16 a, i32 b, i16 c) -> a=AR4, b=ACC, c=AR5
define i16 @f_i16_i32_i16(i16 %a, i32 %b, i16 %c) {
  %b.trunc = trunc i32 %b to i16
  %t = add i16 %a, %b.trunc
  %r = add i16 %t, %c
  ret i16 %r
}

; (i32 a, i32 b) -> a=ACC, b=stack
define i32 @f_i32_i32(i32 %a, i32 %b) {
  %r = add i32 %a, %b
  ret i32 %r
}

; (i16 a, i32 b, i32 c) -> a=AR4, b=ACC, c=stack
define i32 @f_i16_i32_i32(i16 %a, i32 %b, i32 %c) {
  %a.ext = zext i16 %a to i32
  %t = add i32 %b, %c
  %r = add i32 %t, %a.ext
  ret i32 %r
}

; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 -verify-machineinstrs -filetype=asm < %s | FileCheck %s

; CHECK-LABEL: f_i16_i32:
; CHECK: movl xar7, acc
; CHECK: mov al, ar4

; CHECK-LABEL: f_i32_i16:
; CHECK: movz ar0, ar4
; CHECK: movl xt, acc

; CHECK-LABEL: f_i16_i16_i32:
; CHECK: movl xar7, acc
; CHECK: mov al, ar4
; CHECK: add al, ar5

; CHECK-LABEL: f_i32_i16_i16:
; CHECK: movz ar{{[0-9]}}, ar4
; CHECK: movz ar{{[0-9]}}, ar5
; CHECK: movl xt, acc

; CHECK-LABEL: f_i16_i32_i16:
; CHECK: movl xar7, acc
; CHECK: mov al, ar4
; CHECK: add al, ar5

; CHECK-LABEL: f_i32_i32:
; CHECK: addb sp, #{{[0-9]+}}

; CHECK-LABEL: f_i16_i32_i32:
; CHECK: addb sp, #{{[0-9]+}}
; CHECK: movz ar0, ar4
