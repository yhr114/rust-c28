; Allocated pointer constants use logical byte addresses. TI's symbols and
; ABS32 relocations use word addresses: two ABS32 records at each field must
; yield 2*S + byte_addend. Verify the final fields with the TI linker, not just
; the presence of relocation records (tools/verify-llvm-c28x-link.ps1).
target triple = "c28x-ti-none"
declare i32 @callee()
@reloc_data = external global [4 x i16]
@reloc_local = constant i16 4660, section ".rodata.reloc_local", align 2
@reloc_pointers = constant [6 x ptr] [
  ptr @callee,
  ptr @reloc_data,
  ptr getelementptr (i8, ptr @reloc_data, i32 1),
  ptr getelementptr (i8, ptr @reloc_data, i32 3),
  ptr getelementptr (i8, ptr @reloc_data, i32 -1),
  ptr @reloc_local
], section ".rodata.reloc_pointers", align 4
