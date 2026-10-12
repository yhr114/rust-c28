target triple = "c28x-ti-none"
define i32 @const_n() {
entry:
  br label %loop
loop:
  %sum = phi i32 [ 0, %entry ], [ %sumn, %body ]
  %i = phi i32 [ 0, %entry ], [ %inext, %body ]
  %cmp = icmp slt i32 %i, 10
  br i1 %cmp, label %body, label %done
body:
  %sumn = add i32 %sum, %i
  %inext = add i32 %i, 1
  br label %loop
done:
  ret i32 %sum
}