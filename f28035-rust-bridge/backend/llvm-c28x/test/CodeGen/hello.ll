; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x < %s | FileCheck %s
;
; Minimal ABI and integer-selection smoke test.
define i16 @add(i16 %lhs, i16 %rhs) {
entry:
  %sum = add i16 %lhs, %rhs
  ret i16 %sum
}

; CHECK-LABEL: add:
; CHECK: add
; CHECK: lretr
