target triple = "c28x-ti-none"

; TI EABI multi-argument tests:
;   i16 args: AL, AH, AR4, AR5 (packed 16-bit slots)
;   i32 args: ACC (second i32 goes on stack)

; two i16: a->AL, b->AH
define i16 @f2(i16 %a, i16 %b) {
  %r = add i16 %a, %b
  ret i16 %r
}

; three i16: a->AL, b->AH, c->AR4
define i16 @f3(i16 %a, i16 %b, i16 %c) {
  %t1 = add i16 %a, %b
  %r = add i16 %t1, %c
  ret i16 %r
}

; four i16: a->AL, b->AH, c->AR4, d->AR5
define i16 @f4(i16 %a, i16 %b, i16 %c, i16 %d) {
  %t1 = add i16 %a, %b
  %t2 = add i16 %c, %d
  %r = add i16 %t1, %t2
  ret i16 %r
}

; one i32: a->ACC
define i32 @f1_32(i32 %a) {
  %r = add i32 %a, %a
  ret i32 %r
}

; two i32: a->ACC, b->stack
define i32 @f2_32(i32 %a, i32 %b) {
  %r = add i32 %a, %b
  ret i32 %r
}
