; Run after rebuilding the backend, not against the old llc binary:
; RUN: llc -mtriple=c28x-ti-none -verify-machineinstrs -filetype=obj %s -o %t.obj
; RUN: llc -mtriple=c28x-ti-none -verify-machineinstrs %s -o %t.s
;
; Execution oracles (on target, using Rust's logical byte addresses):
; compare32(7, 9) = 1; compare32(9, 7) = 0; compare32(7, 7) = 0.
; reverse32(7, 9) = 0; reverse32(9, 7) = 1.
; sum32(0x12340000, 0x00005678) = 0x12345678 (in either operand order).
; load_live(11), with the word at physical address 0x0820 set to 7, = 18.
; invoke(identity, 0x1234) = 0x1234.
; odd_address() - base_address() = 3 logical bytes.
; next_word() - base_address() = 6 logical bytes.
; widen(0xffff) = 65535, regardless of the incoming scratch-register high bits.
; Compile success alone is not execution validation of these oracles.
target triple = "c28x-ti-none"

@buffer = global [16 x i8] zeroinitializer, align 4

define i16 @compare32(i32 %a, i32 %b) {
  %c = icmp ult i32 %a, %b
  br i1 %c, label %yes, label %no
yes:
  ret i16 1
no:
  ret i16 0
}

define i16 @reverse32(i32 %a, i32 %b) {
  %c = icmp ult i32 %b, %a
  br i1 %c, label %yes, label %no
yes:
  ret i16 1
no:
  ret i16 0
}

define i32 @sum32(i32 %a, i32 %b) {
  %sum = add i32 %a, %b
  ret i32 %sum
}

define i16 @load_live(i16 %x) {
  %v = load volatile i16, ptr inttoptr (i32 4160 to ptr), align 2
  %r = add i16 %x, %v
  ret i16 %r
}

define i16 @identity(i16 %x) {
  ret i16 %x
}

define ptr @identity_address() {
  ret ptr @identity
}

define i16 @invoke(ptr %f, i16 %x) {
  %r = call i16 %f(i16 %x)
  ret i16 %r
}

define ptr @base_address() {
  ret ptr @buffer
}

define ptr @odd_address() {
  ret ptr getelementptr ([16 x i8], ptr @buffer, i32 0, i32 3)
}

define ptr @next_word() {
  ret ptr getelementptr ([16 x i8], ptr @buffer, i32 0, i32 6)
}

define i32 @widen(i16 %x) {
  %r = zext i16 %x to i32
  ret i32 %r
}
