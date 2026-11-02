; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O0 -verify-machineinstrs -filetype=asm < %s | FileCheck %s

; Exercise the C28x call ABI used by the Rust memory builtins.  The two
; pointer pairs deliberately use opposite byte lanes (even/odd logical byte
; addresses); the backend must pass all i32 pointers/lengths without truncating
; the lane bit.  The runtime crate implements these as c28x_memcpy / c28x_memmove
; / c28x_memset / c28x_memcmp (byte-address), which is what the MEMCPY/MEMMOVE/
; MEMSET/MEMCMP libcalls lower to.
declare ptr @c28x_memcpy(ptr, ptr, i32)
declare ptr @c28x_memmove(ptr, ptr, i32)
declare ptr @c28x_memset(ptr, i8, i32)
declare i32 @c28x_memcmp(ptr, ptr, i32)

define i32 @exercise_mem_builtins() {
entry:
  %a = call ptr @c28x_memcpy(ptr inttoptr (i32 4096 to ptr),
                        ptr inttoptr (i32 4097 to ptr), i32 3)
  %b = call ptr @c28x_memmove(ptr inttoptr (i32 4097 to ptr),
                         ptr inttoptr (i32 4096 to ptr), i32 3)
  %c = call ptr @c28x_memset(ptr inttoptr (i32 4097 to ptr), i8 -91, i32 3)
  %d = call i32 @c28x_memcmp(ptr inttoptr (i32 4096 to ptr),
                         ptr inttoptr (i32 4097 to ptr), i32 3)
  ret i32 %d
}

; CHECK-LABEL: exercise_mem_builtins:
; CHECK: lcr c28x_memcpy
; CHECK: lcr c28x_memmove
; CHECK: lcr c28x_memset
; CHECK: lcr c28x_memcmp
