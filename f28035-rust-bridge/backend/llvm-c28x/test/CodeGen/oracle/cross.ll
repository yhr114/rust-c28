target triple = "c28x-ti-none"

declare i16 @callee(i16 %a)

define i16 @caller(i16 %x) {
  %r = call i16 @callee(i16 %x)
  ret i16 %r
}
