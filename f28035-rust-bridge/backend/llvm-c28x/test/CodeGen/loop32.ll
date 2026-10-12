target triple = "c28x-ti-none"
define i32 @loop32(i32 %n) {
entry:
  br label %loop
loop:
  %i = phi i32 [ 0, %entry ], [ %next, %body ]
  %sum = phi i32 [ 0, %entry ], [ %sum.val, %body ]
  %cmp = icmp slt i32 %i, %n
  br i1 %cmp, label %body, label %done
body:
  %sum.val = add i32 %sum, %i
  %next = add i32 %i, 1
  br label %loop
done:
  ret i32 %sum
}