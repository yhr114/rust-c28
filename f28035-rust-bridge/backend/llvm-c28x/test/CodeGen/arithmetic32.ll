target triple = "c28x-ti-none"

; Test i32 arithmetic operations
define i32 @mul(i32 %a, i32 %b) {
  %r = mul i32 %a, %b
  ret i32 %r
}

define i32 @sdiv(i32 %a, i32 %b) {
  %r = sdiv i32 %a, %b
  ret i32 %r
}

define i32 @udiv(i32 %a, i32 %b) {
  %r = udiv i32 %a, %b
  ret i32 %r
}

define i32 @srem(i32 %a, i32 %b) {
  %r = srem i32 %a, %b
  ret i32 %r
}

define i32 @urem(i32 %a, i32 %b) {
  %r = urem i32 %a, %b
  ret i32 %r
}

define i32 @shl(i32 %a, i32 %b) {
  %r = shl i32 %a, %b
  ret i32 %r
}

define i32 @srl(i32 %a, i32 %b) {
  %r = lshr i32 %a, %b
  ret i32 %r
}

define i32 @sra(i32 %a, i32 %b) {
  %r = ashr i32 %a, %b
  ret i32 %r
}

define i32 @shl_c(i32 %a) {
  %r = shl i32 %a, 5
  ret i32 %r
}

define i32 @srl_c(i32 %a) {
  %r = lshr i32 %a, 3
  ret i32 %r
}

define i32 @sra_c(i32 %a) {
  %r = ashr i32 %a, 4
  ret i32 %r
}
