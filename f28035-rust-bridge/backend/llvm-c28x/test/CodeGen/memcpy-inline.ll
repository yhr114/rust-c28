; RUN: llc -mtriple=c28x-ti-none -mcpu=c28x -O2 -filetype=asm < %s | FileCheck %s
;
; A constant-size `llvm.memcpy`/`llvm.memset` must be expanded into plain loads
; and stores, never into a call to the TI RTS `memcpy`.
;
; The generic chooser rejects every candidate type on this target (it walks
; MVT::LAST_INTEGER_VALUETYPE down to the largest legal integer type and the
; alignment tests never pass), so every memcpy used to become `lcr memcpy`.
; The RTS routine dereferences C word addresses while the Rust ABI passes
; logical byte addresses, so each in-memory aggregate copy of 4 bytes or more
; read and wrote the wrong memory.  Hardware symptoms:
;
;   core-ex group B2 : zip(iter, iter.skip(1)) summed 12 instead of 30
;                      (ZipImpl::new's 12-byte Skip copy came from an unrelated
;                      address) — the whole group read 72 instead of 90;
;   minimal repro    : tools/iter-probe/parts13.rs — a pure #[repr(C)] copy of
;                      a 12-byte struct returned b.p = 0 instead of 0x101.
;
; The fix overrides C28xTargetLowering::findOptimalMemOpLowering to fall back
; to i32 words, then one i16 word, then one i8 byte (the byte tail uses the
; existing byte-offset path), and raises MaxStoresPerMemcpy to 16.
;
; copy12(d, s): three 32-bit word pairs, no libcall.
define void @copy12(ptr align 4 %d, ptr align 4 %s) {
  call void @llvm.memcpy.p0.p0.i32(ptr align 4 %d, ptr align 4 %s, i32 12, i1 false)
  ret void
}
; CHECK-LABEL: copy12:
; CHECK-NOT: lcr memcpy
; The backend expands the 12-byte copy into three 32-bit word moves.  Each word
; is copied as load-low (mov al, *xar7) / load-high (mov ah, *xar7) / store-low
; (mov *xar7, al) / store-high (mov *xar7, ah).  The scheduler interleaves the
; loads and stores per word (load1, store1, load2, store2, load3, store3), so the
; checks below follow that order rather than grouping every load before every
; store.  All 12 bytes are copied (3 words x 2 halves = 6 mov *xar7 stores).
; CHECK: mov al, *xar7
; CHECK: mov ah, *xar7
; CHECK: mov *xar7, al
; CHECK: mov *xar7, ah
; CHECK: mov al, *xar7
; CHECK: mov ah, *xar7
; CHECK: mov *xar7, al
; CHECK: mov *xar7, ah
; CHECK: mov al, *xar7
; CHECK: mov ah, *xar7
; CHECK: mov *xar7, al
; CHECK: mov *xar7, ah
; CHECK: lretr

; copy3(d, s): one 16-bit word plus one byte tail through the AR0 byte lane.
define void @copy3(ptr align 4 %d, ptr align 4 %s) {
  call void @llvm.memcpy.p0.p0.i32(ptr align 4 %d, ptr align 4 %s, i32 3, i1 false)
  ret void
}
; CHECK-LABEL: copy3:
; CHECK-NOT: lcr memcpy
; CHECK: movb al, *+xar7[ar0]
; CHECK: lretr

; zero12(d): a zero-fill is stores only, still no libcall.
define void @zero12(ptr align 4 %d) {
  call void @llvm.memset.p0.i32(ptr align 4 %d, i8 0, i32 12, i1 false)
  ret void
}
; CHECK-LABEL: zero12:
; CHECK-NOT: lcr memset
; CHECK: lretr

; varcopy(d, s, n): a copy whose length is only known at run time cannot be
; expanded inline, so it becomes a libcall.  The C28x backend routes MEMCPY to
; our own `c28x_memcpy`, which (like the rest of the runtime crate) receives
; Rust's 32-bit *logical byte* pointers.  No byte->word conversion is performed,
; so the pointer arguments are passed through unchanged.  (An earlier build
; converted them to TI C word addresses, which only matched TI's rts2800
; memcpy and corrupted the copy — tools/iter-probe/parts14.rs left the
; destination untouched.)  The runtime crate's c28x_memcpy dereferences the
; byte addresses directly.
define void @varcopy(ptr align 2 %d, ptr align 2 %s, i32 %n) {
  %bytes = mul i32 %n, 2
  call void @llvm.memcpy.p0.p0.i32(ptr align 2 %d, ptr align 2 %s, i32 %bytes, i1 false)
  ret void
}
; CHECK-LABEL: varcopy:
; CHECK: lcr c28x_memcpy
; CHECK: lretr
