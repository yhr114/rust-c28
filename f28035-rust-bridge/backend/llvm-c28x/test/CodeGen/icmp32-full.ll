target triple = "c28x-ti-none"

; All 12 i32 comparisons: signed eq/ne/lt/le/gt/ge and unsigned eq/ne/ult/ule/ugt/uge.
; Each function takes two i32 args, compares, and returns 1 or 0.

define i16 @eq(i32 %a, i32 %b) {
entry:
  %cmp = icmp eq i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @ne(i32 %a, i32 %b) {
entry:
  %cmp = icmp ne i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @slt(i32 %a, i32 %b) {
entry:
  %cmp = icmp slt i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @sle(i32 %a, i32 %b) {
entry:
  %cmp = icmp sle i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @sgt(i32 %a, i32 %b) {
entry:
  %cmp = icmp sgt i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @sge(i32 %a, i32 %b) {
entry:
  %cmp = icmp sge i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @ult(i32 %a, i32 %b) {
entry:
  %cmp = icmp ult i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @ule(i32 %a, i32 %b) {
entry:
  %cmp = icmp ule i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @ugt(i32 %a, i32 %b) {
entry:
  %cmp = icmp ugt i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}

define i16 @uge(i32 %a, i32 %b) {
entry:
  %cmp = icmp uge i32 %a, %b
  br i1 %cmp, label %true, label %false
true:
  ret i16 1
false:
  ret i16 0
}
