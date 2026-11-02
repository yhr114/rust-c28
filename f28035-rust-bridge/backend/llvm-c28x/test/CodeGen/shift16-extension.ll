; RUN: llc -mtriple=c28x-none-elf -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s
; Narrow right shifts must extend according to their signedness before the
; custom i16 -> i32 shift lowering. In particular sext i8 -> i16 is expanded
; into (x << 8) arithmetic-shift-right 8 by SelectionDAG legalization.

define i16 @extend_signed_byte(i8 %x) {
; CHECK-LABEL: name:            extend_signed_byte
; CHECK: SEXT16_32
; CHECK: SRA32_VAR_PSEUDO
  %v = sext i8 %x to i16
  ret i16 %v
}

define i16 @shift_signed_half(i16 %x, i16 %n) {
; CHECK-LABEL: name:            shift_signed_half
; CHECK: SEXT16_32
; CHECK: SRA32_VAR_PSEUDO
  %v = ashr i16 %x, %n
  ret i16 %v
}

define i16 @shift_unsigned_half(i16 %x, i16 %n) {
; CHECK-LABEL: name:            shift_unsigned_half
; CHECK: MOVL_XAR_AR %0
; CHECK: SRL32_VAR_PSEUDO
  %v = lshr i16 %x, %n
  ret i16 %v
}

declare i16 @consume_byte(i8)
define i16 @call_truncated_byte(i16 %x) {
; CHECK-LABEL: name:            call_truncated_byte
; CHECK: MOV16_imm 255
; CHECK: AND16_PSEUDO
; CHECK: LCR @consume_byte
  %byte = trunc i16 %x to i8
  %v = call i16 @consume_byte(i8 %byte)
  ret i16 %v
}
