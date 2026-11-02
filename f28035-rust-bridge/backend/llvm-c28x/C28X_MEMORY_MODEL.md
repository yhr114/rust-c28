# C28x Rust memory model

> 更新于 2026-09-15：指针模型已按 `ABI_FREEZE.md` 冻结为 **32 位逻辑字节地址**。
> 本文档与冻结规范冲突之处，以 `ABI_FREEZE.md` 为准。

The initial target is deliberately limited to the small data model used by
F2802x/F2803x devices.

## Rust-visible model (FROZEN)

- `usize`, `isize`, and data pointers are **32-bit logical byte addresses**
  (4 logical bytes, aligned to 4 bytes). Hardware C28x words are 16 bits:
  `logical_byte_address = word_address * 2 + lane`.
- Rust keeps its language-defined 8-bit `u8`/`i8` semantics. Values are
  promoted to 16-bit registers for arithmetic and packed into one lane of a
  word on stores (packed-byte model, verified on silicon — see
  `C28X_RUST_ABI.md`).
- `u16` is the native MMIO word. PAC register blocks must use `u16` fields and
  volatile accesses.
- The hardware stack pointer (SP) is a **16-bit word address**. The backend
  converts frame/index byte pointers with `>>1`, preserves the byte lane for
  `i8` accesses, and emits legal chunked SP adjustments for large frames.
  `MOVB` performs the hardware byte-lane read/write, so the other byte in the
  containing 16-bit word is preserved. The implementation is covered by
  `mem-access.ll` and `stack-byte-stress.ll`.
- Direct `u8` global accesses use a separate TI word-address expansion:
  `MOVL XAR7,#symbol` plus indexed `MOVB` with offset 0/1. The symbol is
  already a physical word address, so this path must not `ROL ACC`.
  Escaped/ordinary Rust pointers remain logical byte addresses and convert
  `word = pointer >> 1`, `lane = pointer & 1` at the byte operation. Frame
  pointers retain their own SP-word-to-logical-byte conversion. This direct
  global fast path currently covers constant offsets 0 and 1 only.
- Program addresses are not interchangeable with Rust data pointers. Calls,
  branches, vector entries, and linker symbols use C28x program relocations;
  the fn-pointer byte mapping is an open contract item (L1-3).
- No atomic type is exposed initially (`max_atomic_width = 0`). Interrupt
  masking is not a substitute for the Rust atomic memory model.

## TI ABI boundary

TI C28x C defines an addressable byte as 16 bits. LLVM and Rust define a byte
as 8 bits. Consequently, Rust structs containing `u8`, byte slices, strings,
or packed fields are not ABI-compatible with TI C structs.

FFI types in the first milestone are restricted to `u16`, `i16`, explicitly
split 32-bit values, and opaque handles. Shared layouts need dedicated bridge
types and compile-time size/offset assertions on both sides.

## Rust memory runtime and TI RTS

B-1 routes memory intrinsics to `c28x_memcpy`, `c28x_memmove`,
`c28x_memset`, `c28x_memcmp`, and `c28x_bcmp` in the published Rust builtins.
Their pointers remain 32-bit logical byte addresses, including the lane bit;
the call boundary must not shift them right. Dereferences perform the normal
word/lane conversion. The ordinary TI names retain TI word-address semantics.

The private fill signature is `c28x_memset(*mut u8, u8, usize) -> *mut u8`.
SelectionDAG passes the intrinsic fill operand as `i8`; declaring it as `i32`
changes register/stack placement on C28x and corrupts the length/value. This
signature is deliberately distinct from TI C's ordinary `memset` prototype.
Lengths are Rust logical bytes (`usize`, 32 bits). Copy/move/fill return the
original logical destination pointer; comparisons return `i32`.

The implementation uses `wrapping_add` for its internal pointer arithmetic so
the bottom of the runtime does not depend on core precondition/formatting
helpers. Unsafe callers still must supply valid buffers, and memcpy regions
must not overlap. This does not change general Rust UB-check policy.

LLVM's global libcall declarations are non-default entries, selected only by
`C28xSubtarget`. `tools/patch-llvm-c28x-memory-libcalls.ps1` reproduces them;
`sync-and-build-c28x.ps1` runs that step before rebuilding. Other targets retain
their usual memory libcall defaults.

`tools/verify-cargo-memory.ps1` in the B-1 tree validates normal Cargo rlib
consumption and F28035 RAM results: 48 copy, 192 overlapping/self moves, 72
fills, 144 comparisons, and 6 TI word-address coexistence cases. Coverage uses
lengths 0/1/3/7/33/67, both byte lanes, sentinels, and returned pointers.

## Deferred large model

The frozen 32-bit logical byte address space covers 2Gi logical bytes
(1Gi words), far beyond F2803x devices. A further model (e.g. explicit
address spaces or 64-bit addresses) is deferred until a device actually
needs it; do not change the default pointer width without a new freeze
decision, because that changes `usize`, layout, the calling convention,
and every PAC pointer.
