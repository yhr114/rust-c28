; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 < %s | FileCheck %s

; 5 i16 args: AL, AR0, AR1, AR2 in regs, 5th on stack.
declare void @callee(i16, i16, i16, i16, i16)

define void @caller(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e) {
  call void @callee(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e)
  ret void
}
