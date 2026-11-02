target triple = "c28x-ti-none"

; At -O0 the select's PHI copies used to spill between SUBL and B EQ,
; overwriting ST0. This is the NonNull::eq path used by slice::Iter::next.
define i16 @select_eq32(ptr %a, ptr %b) {
  %x = load i32, ptr %a, align 4
  %y = load i32, ptr %b, align 4
  %same = icmp eq i32 %x, %y
  %result = select i1 %same, i16 1, i16 0
  ret i16 %result
}

define i16 @select_lt16(i16 %a, i16 %b) {
  %less = icmp slt i16 %a, %b
  %result = select i1 %less, i16 7, i16 9
  ret i16 %result
}

define i16 @branch_hi32(i32 %a, i32 %b, ptr %out) {
  %higher = icmp ugt i32 %a, %b
  br i1 %higher, label %yes, label %no
yes:
  store volatile i16 3, ptr %out
  ret i16 3
no:
  store volatile i16 5, ptr %out
  ret i16 5
}
