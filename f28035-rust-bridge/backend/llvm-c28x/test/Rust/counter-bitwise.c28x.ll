; ModuleID = 'counter-bitwise.c28x.ll'
source_filename = "counter-bitwise.rs"
target datalayout = "e-m:e-p:32:32-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16"
target triple = "c28x-ti-none"

define i32 @rust_counter(i32 %n) {
entry:
  br label %loop

loop:
  %sum = phi i32 [ 0, %entry ], [ %sum3, %body ]
  %i = phi i32 [ 0, %entry ], [ %i1, %body ]
  %cmp = icmp slt i32 %i, %n
  br i1 %cmp, label %body, label %done

body:
  %add = add i32 %sum, %i
  %xor = xor i32 %add, 65535
  %i1 = add i32 %i, 1
  %sum3 = xor i32 %xor, 0
  br label %loop

done:
  ret i32 %sum
}