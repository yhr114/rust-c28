; RUN: llc -mtriple=c28x-ti-none -verify-machineinstrs %s -o - | FileCheck %s
@byte_flag = global i8 0

; CHECK-LABEL: exchange_global:
; CHECK: push acc
; CHECK: movb
; CHECK: pop acc
define i16 @exchange_global(i8 %new) {
  %old = load volatile i8, ptr @byte_flag
  store volatile i8 %new, ptr @byte_flag
  %result = zext i8 %old to i16
  ret i16 %result
}

; CHECK-LABEL: exchange_indirect:
; CHECK: movb
define i16 @exchange_indirect(ptr %address, i8 %new) {
  %old = load volatile i8, ptr %address
  store volatile i8 %new, ptr %address
  %result = zext i8 %old to i16
  ret i16 %result
}

; CHECK-LABEL: store_keep_wide:
; CHECK: movb
define i32 @store_keep_wide(i32 %keep, i8 %new) {
  store volatile i8 %new, ptr @byte_flag
  ret i32 %keep
}
