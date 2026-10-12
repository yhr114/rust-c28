target triple = "c28x-ti-none"

@word = global i16 7, align 2

define i16 @sub(i16 %a, i16 %b) {
entry:
  %r = sub i16 %a, %b
  ret i16 %r
}

define i16 @choose(i16 %a, i16 %b) {
entry:
  %cond = icmp eq i16 %a, %b
  br i1 %cond, label %yes, label %no
yes:
  ret i16 1
no:
  ret i16 0
}

define i16 @load_word() {
entry:
  %v = load volatile i16, ptr @word, align 2
  ret i16 %v
}

define void @store_word(i16 %v) {
entry:
  store volatile i16 %v, ptr @word, align 2
  ret void
}

declare i16 @callee(i16)

define i16 @caller(i16 %v) {
entry:
  %r = call i16 @callee(i16 %v)
  ret i16 %r
}

define i16 @stack_roundtrip(i16 %v) {
entry:
  %slot = alloca i16, align 2
  store volatile i16 %v, ptr %slot, align 2
  %r = load volatile i16, ptr %slot, align 2
  ret i16 %r
}
