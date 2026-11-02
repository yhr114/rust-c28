target triple = "c28x-ti-none"

; At O0 the incoming value can occupy ACC. The -1 constant must be free to
; use another wide register, rather than forcing both operands into ACCOnly.
define i16 @is_minus_one(i32 %value) {
  %negative_one = icmp eq i32 %value, -1
  %result = select i1 %negative_one, i16 1, i16 0
  ret i16 %result
}

define i16 @division_overflows(i32 %a, i32 %b) {
  %minus_one = icmp eq i32 %b, -1
  br i1 %minus_one, label %check_min, label %done
check_min:
  %is_min = icmp eq i32 %a, -2147483648
  br label %done
done:
  %overflow = phi i1 [ false, %0 ], [ %is_min, %check_min ]
  %result = zext i1 %overflow to i16
  ret i16 %result
}
