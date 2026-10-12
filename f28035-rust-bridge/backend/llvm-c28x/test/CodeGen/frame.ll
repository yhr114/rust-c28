target triple = "c28x-ti-none"

; 局部变量：alloca 到栈帧，store/load
define i16 @local_var(i16 %a) {
entry:
  %p = alloca i16, align 2
  store i16 %a, ptr %p, align 2
  %v = load i16, ptr %p, align 2
  %r = add i16 %v, 1
  ret i16 %r
}

; 循环 + 归纳变量
define i16 @count_loop(i16 %n) {
entry:
  br label %loop
loop:
  %i = phi i16 [ 0, %entry ], [ %next, %body ]
  %acc = phi i16 [ 0, %entry ], [ %sum, %body ]
  %cmp = icmp slt i16 %i, %n
  br i1 %cmp, label %body, label %done
body:
  %sum = add i16 %acc, %i
  %next = add i16 %i, 1
  br label %loop
done:
  ret i16 %acc
}
