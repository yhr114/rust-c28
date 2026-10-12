target triple = "c28x-ti-none"
define i32 @loop_mixed(i32 %n) {
entry:
  br label %loop
loop:
  %i = phi i32 [ 0, %entry ], [ %next, %body ]
  %sum = phi i16 [ 0, %entry ], [ %sum.val, %body ]
  %cmp = icmp slt i32 %i, %n
  br i1 %cmp, label %body, label %done
body:
  %sum.val = add i16 %sum, 1
  %next = add i32 %i, 1
  br label %loop
done:
  %z = zext i16 %sum to i32
  ret i32 %z
}