target triple = "c28x-ti-none"
define i32 @simple_loop(i32 %n) {
entry:
  br label %loop
loop:
  %i = phi i32 [ 0, %entry ], [ %next, %body ]
  %cmp = icmp slt i32 %i, %n
  br i1 %cmp, label %body, label %done
body:
  %next = add i32 %i, 1
  br label %loop
done:
  ret i32 %i
}