; Minimal reproduction: i8 store to a stack frame index.
; Mirrors the core/src/cmp.rs:672 failure recorded in docs/PATH_B.md.
define void @i8_frame_store(i8 %v, ptr %out) {
entry:
  %slot = alloca i8
  store i8 %v, ptr %slot
  %loaded = load i8, ptr %slot
  store i8 %loaded, ptr %out
  ret void
}

; Two i8 slots in one frame: adjacent byte lanes must not corrupt each other.
define void @i8_two_slots(i8 %a, i8 %b, ptr %out) {
entry:
  %s1 = alloca i8
  %s2 = alloca i8
  store i8 %a, ptr %s1
  store i8 %b, ptr %s2
  %la = load i8, ptr %s1
  %lb = load i8, ptr %s2
  store i8 %la, ptr %out
  store i8 %lb, ptr %out
  ret void
}
