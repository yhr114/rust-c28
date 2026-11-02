; Addend-conversion probe: the address of element 5 of an i16 array is byte
; offset 10 from @thing = word offset 5.  With the FK_C28x_ABS22 addend fix the
; object field must hold 5 (word units); before the fix it held 10 (bytes) and
; the TI linker produced section_word_addr + 10, i.e. a pointer 5 words past the
; target.
@thing = private constant [8 x i16] [i16 11, i16 22, i16 33, i16 44, i16 55, i16 66, i16 77, i16 88]

define ptr @thing_elem5() {
  ret ptr getelementptr inbounds ([8 x i16], ptr @thing, i64 0, i64 5)
}

define ptr @thing_base() {
  ret ptr @thing
}
