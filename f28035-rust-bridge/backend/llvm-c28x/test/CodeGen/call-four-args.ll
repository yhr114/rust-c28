target triple = "c28x-ti-none"
@call_location = private constant [4 x i16] [i16 1, i16 2, i16 3, i16 4], align 4
declare void @check_four(ptr, i32, i32, ptr)

; Iter::new/precondition_check shape: keep the incoming count in ACC while
; materializing two pointer arguments and the outgoing 32-bit stack argument.
define void @call_four(ptr %data, i32 %count) {
  call void @check_four(ptr %data, i32 %count, i32 2, ptr @call_location)
  ret void
}

define void @call_four_reload(ptr %data, i32 %count) {
  %p = alloca ptr, align 4
  %n = alloca i32, align 4
  store volatile ptr %data, ptr %p
  store volatile i32 %count, ptr %n
  %length = load volatile i32, ptr %n
  %pointer = load volatile ptr, ptr %p
  call void @check_four(ptr %pointer, i32 %length, i32 2, ptr @call_location)
  ret void
}

declare { ptr, i32 } @from_ref(ptr, i32)
declare ptr @cast(ptr, i32)
declare i1 @check_language_ub()

; Reduced from the failing core::slice::Iter::new LLVM IR. Earlier calls
; force count/pointer spills; O0 reloads both directly during check_four's
; argument setup. This exercises the FI LOAD32 expansion, not just a normal
; pointer load as in call_four_reload.
define { ptr, ptr } @iter_four_args(ptr %slice, i32 %count) {
entry:
  %view = call { ptr, i32 } @from_ref(ptr %slice, i32 %count)
  %vp = extractvalue { ptr, i32 } %view, 0
  %vn = extractvalue { ptr, i32 } %view, 1
  %p = call ptr @cast(ptr %vp, i32 %vn)
  %check = call i1 @check_language_ub()
  br i1 %check, label %checked, label %done
checked:
  call void @check_four(ptr %p, i32 %count, i32 2, ptr @call_location)
  br label %done
done:
  %end = getelementptr i16, ptr %p, i32 %count
  %first = insertvalue { ptr, ptr } poison, ptr %p, 0
  %pair = insertvalue { ptr, ptr } %first, ptr %end, 1
  ret { ptr, ptr } %pair
}
