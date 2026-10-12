target triple = "c28x-ti-none"
define i32 @shl4(i32 %a) {
  %r = shl i32 %a, 4
  ret i32 %r
}
define i32 @srl2(i32 %a) {
  %r = lshr i32 %a, 2
  ret i32 %r
}