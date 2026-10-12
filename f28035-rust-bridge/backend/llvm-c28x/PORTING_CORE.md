# Porting `core` to C28x

`core` is Rust's standard library for bare-metal targets.  It is `#![no_std]`
and must compile for the target.  This guide shows what to patch.

## 1. What `core` needs from the target

`core` uses:
- **Primitives**: i8/i16/i32/i64, f32/f64 (f32/f64 need software float)
- **Atomics**: C28x has no hardware atomics. Set `max_atomic_width = Some(0)`
  and `atomic_cas = false`; ordinary loads/stores remain valid, but atomic
  read-modify-write operations must either be rejected or lowered through an
  interrupt-masked critical section later.
- **`memcpy`/`memset`/`memcmp`**: provided by `compiler_builtins`
- **Panic**: `#[panic_handler]` in user code (we have `panic-c28x`)
- **`intrinsics`**: `unreachable`, `volatile_load`, `volatile_store`

## 2. Files to patch in `core`

### `library/core/src/ptr/mod.rs`
- `read_volatile` / `write_volatile` — map to C28x `volatile` intrinsics
- `copy_nonoverlapping` — maps to `memcpy`

### `library/core/src/sync/atomic.rs`
- Do not pretend RMW atomics are no-ops.
- For the first `core` bring-up, keep atomics disabled in the target spec and
  let unsupported atomic operations fail loudly.
- Later, add a target intrinsic path that masks interrupts around 16-bit RMW
  sequences if the HAL needs atomic flags.

### `library/core/src/arch/c28x/` (NEW)
Create this directory with:
```rust
//! C28x-specific intrinsics.

#[allow(dead_code)]
#[inline(always)]
pub unsafe fn eallow() {
    core::arch::asm!("eallow");
}

#[allow(dead_code)]
#[inline(always)]
pub unsafe fn edis() {
    core::arch::asm!("edis");
}
```

## 3. `compiler_builtins`

`compiler_builtins` provides `memcpy`, `memset`, `__udivmoddi4`, etc.

For C28x:
- `memcpy` / `memmove` / `memset` / `memcmp`: implement logical-byte
  semantics, including odd addresses and lane preservation.
- `__udivmoddi4`: software division (C28x has no hardware divide)

See `rustc-patches/compiler_builtins_c28x.md`.  Do not install
`rustc-patches/memcpy_c28x.asm` as-is; it is only an old physical-word copy
prototype and does not satisfy the frozen Rust ABI.

## 4. Build command

```bash
# With patched rustc/cargo:
cargo build --target c28x-none-elf \
    -Zbuild-std=core,compiler_builtins \
    -Zbuild-std-features=panic_immediate_abort
```

## 5. What works after this

- All of `core`'s data structures (Vec, Option, Result, HashMap)
- All arithmetic (i16/i32)
- All control flow (if/while/for/match)
- Panic works (via panic-c28x)
- `volatile_read` / `volatile_write` for MMIO

## 6. What still doesn't work

- **64-bit atomics** (no hardware support)
- **Floating point** (needs soft-float in compiler_builtins)
- **Threads** (C28x is single-core)
- **`extern "C"` variadic** (C28x ABI doesn't support varargs)
