; Stress coverage for C28x frame lowering and packed byte accesses.
; These are structural tests: the exact instruction bytes are intentionally
; not frozen because register allocation may choose different spill homes.

target triple = "c28x-ti-none"

; A frame larger than the 7-bit ADDB/SUBB immediate.  The final element is
; deliberately volatile so the alloca and its large offset survive lowering.
define i16 @large_local_frame(i16 %v) nounwind {
entry:
  %a = alloca [256 x i16], align 2
  %p = getelementptr [256 x i16], ptr %a, i32 0, i32 255
  store volatile i16 %v, ptr %p, align 2
  %r = load volatile i16, ptr %p, align 2
  ret i16 %r
}

; Many independent i32 values force the allocator to exercise spill/reload
; paths for ACC/XT/GPR32 values rather than only ordinary local allocas.
define i32 @many_live_i32(i32 %a, i32 %b, i32 %c, i32 %d,
                           i32 %e, i32 %f, i32 %g, i32 %h) nounwind {
entry:
  %x0 = add i32 %a, %b
  %x1 = add i32 %c, %d
  %x2 = add i32 %e, %f
  %x3 = add i32 %g, %h
  %x4 = xor i32 %x0, %x1
  %x5 = xor i32 %x2, %x3
  %x6 = add i32 %x4, %x5
  %x7 = mul i32 %x6, 17
  %x8 = xor i32 %x7, %x0
  %x9 = add i32 %x8, %x2
  ret i32 %x9
}

; Packed bytes in a structure.  The byte fields are intentionally at offsets
; 1 and 3 so both lanes and byte-address GEPs are exercised.
%Packed = type { i8, i8, i16, i8 }
@packed = global %Packed zeroinitializer, align 1

define void @packed_byte_store(i8 %a, i8 %b) nounwind {
entry:
  %p1 = getelementptr %Packed, ptr @packed, i32 0, i32 1
  %p3 = getelementptr %Packed, ptr @packed, i32 0, i32 3
  store volatile i8 %a, ptr %p1, align 1
  store volatile i8 %b, ptr %p3, align 1
  ret void
}

define i16 @packed_byte_sum() nounwind {
entry:
  %p1 = getelementptr %Packed, ptr @packed, i32 0, i32 1
  %p3 = getelementptr %Packed, ptr @packed, i32 0, i32 3
  %a = load volatile i8, ptr %p1, align 1
  %b = load volatile i8, ptr %p3, align 1
  %a16 = zext i8 %a to i16
  %b16 = zext i8 %b to i16
  %s = add i16 %a16, %b16
  ret i16 %s
}
