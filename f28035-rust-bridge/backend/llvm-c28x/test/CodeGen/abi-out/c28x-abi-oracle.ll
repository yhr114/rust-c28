target triple = "c28x-ti-none"

; Mirror of c28x-abi-oracle.c to verify the LLVM-side convention matches cl2000.

%Wide = type { i32, i32 }

; sret: real struct return -> hidden buffer pointer in XAR6.
define { i32, i32 } @make_wide(i32 %a, i32 %b) {
  %s = insertvalue { i32, i32 } undef, i32 %a, 0
  %r = insertvalue { i32, i32 } %s, i32 %b, 1
  ret { i32, i32 } %r
}
define i32 @use_wide(i32 %a, i32 %b) {
  %r = call { i32, i32 } @make_wide(i32 %a, i32 %b)
  %lo = extractvalue { i32, i32 } %r, 0
  %hi = extractvalue { i32, i32 } %r, 1
  %t = add i32 %lo, %hi
  ret i32 %t
}

; Stack overflow: only ACC for first i32, rest on the stack.
define i32 @many(i32 %a, i32 %b, i32 %c, i32 %d, i32 %e) {
  %t1 = add i32 %a, %b
  %t2 = add i32 %t1, %c
  %t3 = add i32 %t2, %d
  %t4 = add i32 %t3, %e
  ret i32 %t4
}
define i32 @call_many() {
  %r = call i32 @many(i32 1, i32 2, i32 3, i32 4, i32 5)
  ret i32 %r
}

; i64 return -> P:ACC.
define i64 @wide_mul(i32 %a, i32 %b) {
  %a64 = sext i32 %a to i64
  %b64 = sext i32 %b to i64
  %m = mul i64 %a64, %b64
  ret i64 %m
}
define i32 @use_widemul(i32 %a, i32 %b) {
  %r = call i64 @wide_mul(i32 %a, i32 %b)
  %t = trunc i64 %r to i32
  ret i32 %t
}
