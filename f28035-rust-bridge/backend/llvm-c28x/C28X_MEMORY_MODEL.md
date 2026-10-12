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
- The hardware stack pointer (SP) is a **16-bit word address**; frame and
  dereference lowering must convert between byte pointers and word addresses
  (`>>1` on dereference, lane select for i8) — contract L1-1 in
  `ABI_FREEZE.md`. Until L1-1 lands, pointer-carrying frame/index code paths
  are scaffolded on GR16 (see `C28xRegisterInfo.cpp`).
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

## Deferred large model

The frozen 32-bit logical byte address space covers 2Gi logical bytes
(1Gi words), far beyond F2803x devices. A further model (e.g. explicit
address spaces or 64-bit addresses) is deferred until a device actually
needs it; do not change the default pointer width without a new freeze
decision, because that changes `usize`, layout, the calling convention,
and every PAC pointer.
