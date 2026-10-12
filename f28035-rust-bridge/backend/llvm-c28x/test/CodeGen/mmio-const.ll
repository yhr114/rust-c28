; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj < %s | llvm-objdump -s -j .text - | FileCheck %s
;
; Bare MMIO byte addresses: `inttoptr(i32 N)` fed straight into a volatile
; load/store.  Per ABI L1-1, pointers are logical byte addresses, so N=4160
; means byte address 4160 (word address 2080).  The 16-bit load/store converts
; the byte address to a word address before issuing MOV *XARn.
;
; Regression guard for:
;   LLVM ERROR: Cannot select: t1: i32 = Constant<4160>
; i32's register class is ACC32, but LOAD16_PSEUDO/STORE16_PSEUDO take their
; address in GR32 (the XARn pointer class), so nothing could produce the
; address.  The `(i32 imm22:$src) -> MOVL_XAR_imm` pattern closes that gap.
;
; load_mmio():
;   movl xar0, #4160    ; byte address (8d00 1040)
;   movl acc, xar0      ; a93a
;   clrc c              ; 0829
;   ror acc             ; 52ff  (byte>>1 -> word addr 2080)
;   movl xar7, acc      ; a9c5
;   mov al, *xar7       ; 92c0
;   lretr               ; 0006
;
; Encoding oracle: every new opcode (MOVL_ACC_XAR, CLRC_C, ROR_ACC,
; MOVL_XAR_ACC) was cross-checked with TI asm2000 -v28 / dis2000.
define i16 @load_mmio() {
entry:
  %v = load volatile i16, ptr inttoptr (i32 4160 to ptr), align 2
  ret i16 %v
}

; CHECK: 008d4010a93a082952ffa9c5c7920600

; store_mmio(v):
;   movl xar0, #4160    ; 8d00 1040
;   movl acc, xar0      ; a93a
;   clrc c              ; 0829
;   ror acc             ; 52ff
;   movl xar7, acc      ; a9c5
;   mov *xar7, al       ; 96c0
;   lretr               ; 0006
define void @store_mmio(i16 %v) {
entry:
  store volatile i16 %v, ptr inttoptr (i32 4160 to ptr), align 2
  ret void
}

; CHECK: 008d4010a93a082952ffa9c5c7960600
