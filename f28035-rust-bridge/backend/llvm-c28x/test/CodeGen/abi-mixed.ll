target triple = "c28x-ti-none"

; Test mixed i16/i32 argument allocation per TI EABI:
;   If any i32 arg exists: first i32 -> ACC, i16 args -> AR4, AR5, stack
;   If no i32 arg: i16 args -> AL, AH, AR4, AR5, stack

; (i16 a, i32 b) -> a=AR4, b=ACC
define i16 @f_i16_i32(i16 %a, i32 %b) {
  %b.trunc = trunc i32 %b to i16
  %r = add i16 %a, %b.trunc
  ret i16 %r
}

; (i32 a, i16 b) -> a=ACC, b=AR4
define i32 @f_i32_i16(i32 %a, i16 %b) {
  %b.ext = zext i16 %b to i32
  %r = add i32 %a, %b.ext
  ret i32 %r
}

; (i16 a, i16 b, i32 c) -> a=AR4, b=AR5, c=ACC
define i16 @f_i16_i16_i32(i16 %a, i16 %b, i32 %c) {
  %c.trunc = trunc i32 %c to i16
  %t = add i16 %a, %b
  %r = add i16 %t, %c.trunc
  ret i16 %r
}

; (i32 a, i16 b, i16 c) -> a=ACC, b=AR4, c=AR5
define i32 @f_i32_i16_i16(i32 %a, i16 %b, i16 %c) {
  %b.ext = zext i16 %b to i32
  %c.ext = zext i16 %c to i32
  %t = add i32 %a, %b.ext
  %r = add i32 %t, %c.ext
  ret i32 %r
}

; (i16 a, i32 b, i16 c) -> a=AR4, b=ACC, c=AR5
define i16 @f_i16_i32_i16(i16 %a, i32 %b, i16 %c) {
  %b.trunc = trunc i32 %b to i16
  %t = add i16 %a, %b.trunc
  %r = add i16 %t, %c
  ret i16 %r
}
