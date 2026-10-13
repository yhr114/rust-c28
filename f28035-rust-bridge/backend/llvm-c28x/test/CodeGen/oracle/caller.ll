target triple = "c28x-ti-none"
declare i16 @callee(i16 %a)
define i16 @caller(i16 %x) {
  %r = call i16 @callee(i16 %x)
  %r2 = add i16 %r, 2
  ret i16 %r2
}
