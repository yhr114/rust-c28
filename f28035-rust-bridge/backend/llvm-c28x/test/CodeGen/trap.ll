; The trap must loop on its own branch instruction, never the function entry.
; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 -filetype=obj %s -o %t
; RUN: llvm-objdump -s -j .text %t | FileCheck %s
; CHECK: 02feefff 0000
declare void @llvm.trap()
define void @abort_now() {
  call void @llvm.trap()
  unreachable
}
