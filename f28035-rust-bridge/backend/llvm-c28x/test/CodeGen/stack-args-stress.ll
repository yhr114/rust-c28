target triple = "c28x-ti-none"

; Stack-argument stress: the argument words must be reachable from EVERY basic
; block that uses them, not just the entry block.  Frame-index addressing in
; C28xRegisterInfo::eliminateFrameIndex compensates the LIVE SP (pushes since
; the prologue), and that compensation used to be computed per basic block, so
; an access in a successor block was off by the prologue's callee-saved push.
;
; ABI shape: a,b -> AL,AH; c -> AR4; d -> AR5; e -> stack; f (i32) -> stack.
; Expected results (originally host checked by the archived B-2 ABI sample):
;   bb_stack_even = 1 + 6*4 + 2*16     = 57   (a, f from the else block)
;   bb_stack_odd  = 5 + 7*4 + 6*16 + ... = 133 ((e, *p... use the other block)

define i32 @bb_stack(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e, i32 %f) {
entry:
  %av = zext i16 %a to i32
  %bv = zext i16 %b to i32
  %cv = zext i16 %c to i32
  %dv = zext i16 %d to i32
  %ev = zext i16 %e to i32
  %odd = and i16 %a, 1
  %cond = icmp ne i16 %odd, 0
  br i1 %cond, label %then, label %else

then:
  ; e and f are read HERE, one basic block away from the prologue.
  %t = add i32 %ev, %f
  br label %join

else:
  %u = add i32 %av, %f
  br label %join

join:
  %r = phi i32 [ %t, %then ], [ %u, %else ]
  ; ...and combined with register args so the sum mixes both classes.
  %s1 = add i32 %r, %bv
  %s2 = add i32 %s1, %cv
  %s3 = add i32 %s2, %dv
  ret i32 %s3
}

; Nested calls: this function has its own stack arguments AND makes a call
; whose outgoing area is written on the stack.  The outgoing words must not
; land on top of this function's incoming arguments (which sit just above the
; frame) or its locals.

define i32 @inner(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e, i32 %f) {
  %av = zext i16 %a to i32
  %ev = zext i16 %e to i32
  %t = add i32 %av, %f
  %u = add i32 %t, %ev
  ret i32 %u
}

define i32 @outer(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e, i32 %f) {
entry:
  %av = zext i16 %a to i32
  %ev = zext i16 %e to i32
  %fv = mul i32 %f, 3
  %s0 = add i32 %av, %ev
  ; The call writes 3 stack words while %f and %e are still needed afterwards.
  %s1 = call i32 @inner(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e, i32 %f)
  %s2 = add i32 %s0, %s1
  %s3 = add i32 %s2, %fv
  ret i32 %s3
}

; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 -verify-machineinstrs -filetype=asm < %s | FileCheck %s

; CHECK-LABEL: bb_stack:
; CHECK: push
; CHECK: addb sp
; CHECK: lcr
; CHECK-LABEL: inner:
; CHECK: lcr
; CHECK-LABEL: outer:
; CHECK: adb
; CHECK: sbb
