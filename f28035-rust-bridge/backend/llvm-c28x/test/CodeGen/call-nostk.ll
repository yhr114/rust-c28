declare void @callee(i16, i16)
define void @caller() {
  call void @callee(i16 1, i16 2)
  ret void
}
