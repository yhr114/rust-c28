target triple = "c28x-ti-none"
declare i16 @callee(i16 %a)
define i16 @caller(i16 %x, i16 %y) {
  %sum = add i16 %x, %y
  %r1 = call i16 @callee(i16 %sum)
  %r2 = call i16 @callee(i16 %r1)
  ret i16 %r2
}
