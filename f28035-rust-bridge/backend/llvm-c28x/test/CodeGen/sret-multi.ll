target triple = "c28x-ti-none"
define { i32, i32 } @mk(i32 %a, i32 %b) {
  %s = insertvalue { i32, i32 } undef, i32 %a, 0
  %r = insertvalue { i32, i32 } %s, i32 %b, 1
  ret { i32, i32 } %r
}
define i32 @use1(i32 %a, i32 %b) {
  %r = call { i32, i32 } @mk(i32 %a, i32 %b)
  %p = extractvalue { i32, i32 } %r, 0
  ret i32 %p
}
define i32 @use2(i32 %a, i32 %b) {
  %r = call { i32, i32 } @mk(i32 %a, i32 %b)
  %q = extractvalue { i32, i32 } %r, 1
  ret i32 %q
}

; Minimal reproduction of the open Rust multi-value struct return defect
; ({i32,i32} -> sret lowering): the caller's read-back computes a wrong value
; (see WORK_LOG 2026-10-20 "sret 残留定位").  Both use1 and use2 must return
; their argument (0x1111 / 0x2222); today the generated code does not.
; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 -verify-machineinstrs -filetype=asm < %s | FileCheck %s

; CHECK-LABEL: use1:
; CHECK: lcr mk
; CHECK: lretr
; CHECK-LABEL: use2:
; CHECK: lcr mk
; CHECK: lretr
