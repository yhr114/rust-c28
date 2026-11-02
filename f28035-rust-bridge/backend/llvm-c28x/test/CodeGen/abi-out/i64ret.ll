target triple = "c28x-ti-none"
define i64 @ret_i64(i32 %a) {
  %x = sext i32 %a to i64
  ret i64 %x
}
define i32 @use_i64(i32 %a) {
  %r = call i64 @ret_i64(i32 %a)
  %t = trunc i64 %r to i32
  ret i32 %t
}
