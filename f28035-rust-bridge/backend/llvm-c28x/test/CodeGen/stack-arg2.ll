; Minimal: call with 5 constant i16 args (4 regs + 1 stack)
declare void @callee(i16, i16, i16, i16, i16)

define void @caller() {
  call void @callee(i16 1, i16 2, i16 3, i16 4, i16 5)
  ret void
}
