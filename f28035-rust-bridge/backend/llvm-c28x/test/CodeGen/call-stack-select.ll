target triple = "c28x-ti-none"

declare i32 @stack_inner(i16, i16, i16, i16, i16, i32)

; Select expansion splits a live outgoing call area into several blocks.
; MachineVerifier must see inherited call-frame sizes, and incoming stack
; arguments must include that live area in their physical SP offsets.
define i32 @call_stack_select(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e, i32 %f, i16 %sel) {
  %test = and i16 %sel, 1
  %odd = icmp ne i16 %test, 0
  %x = select i1 %odd, i16 %a, i16 %b
  %y = select i1 %odd, i16 %e, i16 %c
  %zx = zext i16 %x to i32
  %zy = zext i16 %y to i32
  %sum = add i32 %zx, %zy
  %branch_sum = add i32 %sum, %f
  %inner = call i32 @stack_inner(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e, i32 %f)
  %result = add i32 %branch_sum, %inner
  ret i32 %result
}
