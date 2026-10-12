; Comprehensive survey of operations core library needs
; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 < %s

target datalayout = "e-m:e-p:32:32-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16"
target triple = "c28x-ti-none"

; === i8 operations ===
define i8 @test_i8_add(i8 %a, i8 %b) {
  %r = add i8 %a, %b
  ret i8 %r
}

define i8 @test_i8_sub(i8 %a, i8 %b) {
  %r = sub i8 %a, %b
  ret i8 %r
}

define i1 @test_i8_icmp_eq(i8 %a, i8 %b) {
  %r = icmp eq i8 %a, %b
  ret i1 %r
}

define i1 @test_i8_icmp_lt(i8 %a, i8 %b) {
  %r = icmp slt i8 %a, %b
  ret i1 %r
}

define i8 @test_i8_and(i8 %a, i8 %b) {
  %r = and i8 %a, %b
  ret i8 %r
}

define i8 @test_i8_or(i8 %a, i8 %b) {
  %r = or i8 %a, %b
  ret i8 %r
}

define i8 @test_i8_xor(i8 %a, i8 %b) {
  %r = xor i8 %a, %b
  ret i8 %r
}

define i8 @test_i8_shl(i8 %a, i8 %b) {
  %r = shl i8 %a, %b
  ret i8 %r
}

define i8 @test_i8_lshr(i8 %a, i8 %b) {
  %r = lshr i8 %a, %b
  ret i8 %r
}

define i8 @test_i8_ashr(i8 %a, i8 %b) {
  %r = ashr i8 %a, %b
  ret i8 %r
}

; === i16 operations ===
define i16 @test_i16_mul(i16 %a, i16 %b) {
  %r = mul i16 %a, %b
  ret i16 %r
}

define i1 @test_i16_icmp(i16 %a, i16 %b) {
  %r = icmp ugt i16 %a, %b
  ret i1 %r
}

define i16 @test_i16_and(i16 %a, i16 %b) {
  %r = and i16 %a, %b
  ret i16 %r
}

define i16 @test_i16_or(i16 %a, i16 %b) {
  %r = or i16 %a, %b
  ret i16 %r
}

define i16 @test_i16_xor(i16 %a, i16 %b) {
  %r = xor i16 %a, %b
  ret i16 %r
}

define i16 @test_i16_shl(i16 %a, i16 %b) {
  %r = shl i16 %a, %b
  ret i16 %r
}

; === i32 operations ===
define i32 @test_i32_mul(i32 %a, i32 %b) {
  %r = mul i32 %a, %b
  ret i32 %r
}

define i1 @test_i32_icmp(i32 %a, i32 %b) {
  %r = icmp eq i32 %a, %b
  ret i1 %r
}

define i32 @test_i32_and(i32 %a, i32 %b) {
  %r = and i32 %a, %b
  ret i32 %r
}

define i32 @test_i32_or(i32 %a, i32 %b) {
  %r = or i32 %a, %b
  ret i32 %r
}

define i32 @test_i32_xor(i32 %a, i32 %b) {
  %r = xor i32 %a, %b
  ret i32 %r
}

define i32 @test_i32_shl(i32 %a, i32 %b) {
  %r = shl i32 %a, %b
  ret i32 %r
}

define i32 @test_i32_lshr(i32 %a, i32 %b) {
  %r = lshr i32 %a, %b
  ret i32 %r
}

; === select / zext / trunc ===
define i16 @test_select(i1 %c, i16 %a, i16 %b) {
  %r = select i1 %c, i16 %a, i16 %b
  ret i16 %r
}

define i32 @test_zext(i16 %a) {
  %r = zext i16 %a to i32
  ret i32 %r
}

define i16 @test_trunc(i32 %a) {
  %r = trunc i32 %a to i16
  ret i16 %r
}

define i8 @test_trunc_i8(i32 %a) {
  %r = trunc i32 %a to i8
  ret i8 %r
}

; === stack-passed args (i8, i32) ===
define i8 @test_stack_i8(i16 %a, i16 %b, i16 %c, i16 %d, i8 %e) {
  %t = trunc i16 %a to i8
  %r = add i8 %t, %e
  ret i8 %r
}

define i32 @test_stack_i32(i32 %a, i32 %b, i32 %c, i32 %d, i32 %e) {
  %r = add i32 %a, %e
  ret i32 %r
}

; === alloca i8 ===
define i8 @test_alloca_i8(i8 %v) {
  %p = alloca i8
  store i8 %v, ptr %p
  %r = load i8, ptr %p
  ret i8 %r
}

; === alloca i32 ===
define i32 @test_alloca_i32(i32 %v) {
  %p = alloca i32
  store i32 %v, ptr %p
  %r = load i32, ptr %p
  ret i32 %r
}

; === conditional branch ===
define i16 @test_branch(i16 %a, i16 %b) {
entry:
  %c = icmp eq i16 %a, %b
  br i1 %c, label %then, label %else
then:
  ret i16 1
else:
  ret i16 2
}

; === phi ===
define i16 @test_phi(i1 %c, i16 %a, i16 %b) {
entry:
  br i1 %c, label %then, label %else
then:
  br label %merge
else:
  br label %merge
merge:
  %r = phi i16 [ %a, %then ], [ %b, %else ]
  ret i16 %r
}
