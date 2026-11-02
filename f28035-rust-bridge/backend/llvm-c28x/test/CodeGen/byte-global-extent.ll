; RUN: llc -mtriple=c28x-ti-none -filetype=obj -data-sections %s -o %t
; RUN: llvm-readobj --sections %t | FileCheck %s
; A scalar bool/u8 must occupy a complete TI word, and odd arrays retain
; their final byte. Internal packed-byte offsets remain unchanged.
@byte_a = global i8 0, align 1
@byte_b = global i8 0, align 1
@init_byte = global i8 7, align 1
@odd_array = global [3 x i8] [i8 1, i8 2, i8 3], align 1
@common_byte = common global i8 0, align 1
; CHECK: Name: .bss.byte_a
; CHECK: Size: 2
; CHECK: Name: .bss.byte_b
; CHECK: Size: 2
; CHECK: Name: .data.init_byte
; CHECK: Size: 2
; CHECK: Name: .data.odd_array
; CHECK: Size: 4
