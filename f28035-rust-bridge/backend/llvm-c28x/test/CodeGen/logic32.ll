target triple = "c28x-ti-none"
define i32 @and32(i32 %a, i32 %b) {
  %r = and i32 %a, %b
  ret i32 %r
}
define i32 @or32(i32 %a, i32 %b) {
  %r = or i32 %a, %b
  ret i32 %r
}
define i32 @xor32(i32 %a, i32 %b) {
  %r = xor i32 %a, %b
  ret i32 %r
}