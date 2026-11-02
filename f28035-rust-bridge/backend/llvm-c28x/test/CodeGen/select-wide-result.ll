; RUN: llc -mtriple=c28x-none-elf -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s
; Compare width and selected value width are independent. A 32-bit result
; must retain its full value through the select/PHI, including the -1 niche.

define i32 @wide_select_cmp16(i16 %x) {
; CHECK-LABEL: name:            wide_select_cmp16
; CHECK: CMPBR16_PSEUDO
; CHECK: :gpr32 = PHI
 %c = icmp eq i16 %x, 0
 %v = select i1 %c, i32 -1, i32 305419896
 ret i32 %v
}
define i32 @wide_select_cmp32(i32 %x) {
; CHECK-LABEL: name:            wide_select_cmp32
; CHECK: CMPBR32_PSEUDO
; CHECK: :gpr32 = PHI
 %c = icmp eq i32 %x, -1
 %v = select i1 %c, i32 -1, i32 2271560481
 ret i32 %v
}
