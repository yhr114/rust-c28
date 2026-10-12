; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O3 < %s | FileCheck %s

; 7 i16 args: AL, AR0, AR1, AR2, AR3 in regs, args 6 and 7 on the stack.
; After the outgoing area is raised (ADDB SP,#2), the stack arguments live at
; NEGATIVE offsets from the current SP: arg6 at SP-2, arg7 at SP-1.  This is
; the TI ABI layout (verified against cl2000: MOVB *-SP[k]).  Storing them at
; SP+0/SP+1 (above the allocation) silently corrupts memory and feeds the callee
; garbage, so the negative offsets are asserted.
declare i16 @sum(i16, i16, i16, i16, i16, i16, i16)

define i16 @many(i16 %a) {
  %r = call i16 @sum(i16 %a, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7)
  ret i16 %r
}

; CHECK: addb sp, #2
; CHECK: movz ar7, sp
; CHECK: subb xar7, #2
; CHECK: mov *xar7
; CHECK: movz ar7, sp
; CHECK: subb xar7, #1
; CHECK: mov *xar7
; CHECK: lcr sum
; CHECK: subb sp, #2
