target triple = "c28x-ti-none"

; i32 signed less-than compare + conditional branch
define i16 @icmp32_slt(i32 %a, i32 %b) {
entry:
  %cmp = icmp slt i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}