; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 -verify-machineinstrs -filetype=asm < %s | FileCheck %s

; C28x uses a hidden i32 pointer for aggregate returns.  This is the ABI shape
; emitted by LLVM for an ordinary Rust/C aggregate return: the callee writes
; through sret and returns void; the caller owns the result storage.
; Oracle (cl2000 -v28 --abi=eabi, 2026-10-20): the hidden return-buffer pointer
; is passed in XAR6 (driver: MOVL XAR6,#sym before LCR), so the callee receives
; it from XAR6 and the caller moves its buffer pointer into XAR6 before LCR.

%Pair = type { i16, i8, i8 }

define void @make_pair(ptr sret(%Pair) %out, i16 %a, i16 %b) {
entry:
  %x = getelementptr %Pair, ptr %out, i32 0, i32 0
  store i16 %a, ptr %x, align 2
  %y = getelementptr %Pair, ptr %out, i32 0, i32 1
  store i8 17, ptr %y, align 1
  %z = getelementptr %Pair, ptr %out, i32 0, i32 2
  store i8 34, ptr %z, align 1
  ret void
}

define void @use_pair(ptr %out) {
entry:
  call void @make_pair(ptr sret(%Pair) %out, i16 7, i16 9)
  ret void
}

; CHECK-LABEL: make_pair:
; CHECK: movl acc, xar6
; CHECK: mov *xar7, al
; CHECK: movb *+xar7[ar0], al
; CHECK-LABEL: use_pair:
; CHECK: movl xar6, xar4
; CHECK: lcr make_pair
