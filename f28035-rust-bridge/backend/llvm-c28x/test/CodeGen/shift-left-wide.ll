; RUN: llc -mtriple=c28x-none-elf -verify-machineinstrs < %s | FileCheck %s
; Counts 16..31 require LSLL (563B), not legacy LSL (FF50, T low 4 bits).
define i32 @left_wide(i32 %x, i32 %count) {
; CHECK-LABEL: left_wide:
; CHECK: lsll acc,t
 %masked = and i32 %count, 31
 %v = shl i32 %x, %masked
 ret i32 %v
}
