; Calls and frame accesses must preserve asynchronous interrupted state.
; RUN: llc -mtriple=c28x-ti-none -O0 -verify-machineinstrs %s -o - | FileCheck %s
declare void @irq_body()
define cc 92 void @irq_handler() {
entry:
  %p = alloca i32, align 4
  store volatile i32 305419896, ptr %p
  call void @irq_body()
  %v = load volatile i32, ptr %p
  %c = icmp eq i32 %v, 305419896
  br i1 %c, label %done, label %again
again:
  call void @irq_body()
  br label %done
done:
  ret void
}
; CHECK: asp
; CHECK: push xt
; CHECK: nasp
; CHECK: iret
