target triple = "c28x-ti-none"
define i16 @callee(i16 %a) {
  %r = add i16 %a, 1
  ret i16 %r
}
