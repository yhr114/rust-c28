//! Compiler-rt builtins for C28x EABI.
//!
//! C28x has no hardware 32-bit multiply-high or divide, so these functions
//! are required when LLVM lowers SDIV/UDIV/SREM/UREM i32 to libcalls.
//!
//! ABI (TI C28x EABI):
//!   - i32 arg0 -> ACC
//!   - i32 arg1 -> stack (at [SP-4] / [SP-3] after callee prologue)
//!   - i32 return -> ACC
//!
//! Division/modulo functions are normally provided by TI's rts2800_ml_eabi.lib.
//! When linking without the TI runtime, provide weak fallback implementations.

#![no_std]
#![no_builtins]
#![feature(compiler_builtins)]
#![compiler_builtins]

// ---------------------------------------------------------------------------
// Extern declarations — normally resolved by TI rts2800_ml_eabi.lib
// ---------------------------------------------------------------------------

extern "C" {
    /// Signed 32-bit division: returns quotient (ACC = dividend / divisor).
    pub fn __divsi3(a: i32, b: i32) -> i32;
    /// Unsigned 32-bit division: returns quotient (ACC = dividend / divisor).
    pub fn __udivsi3(a: u32, b: u32) -> u32;
    /// Signed 32-bit modulo: returns remainder (ACC = dividend % divisor).
    pub fn __modsi3(a: i32, b: i32) -> i32;
    /// Unsigned 32-bit modulo: returns remainder (ACC = dividend % divisor).
    pub fn __umodsi3(a: u32, b: u32) -> u32;
}

/// Return the unsigned quotient and optionally write the remainder through a
/// C28x Rust logical-byte pointer, as required by LLVM's div/rem libcall.
/// The divisor must be nonzero, and a non-null remainder must be writable and
/// aligned for a `u32`.
#[no_mangle]
pub unsafe extern "C" fn __udivmodsi4(a: u32, b: u32, remainder: *mut u32) -> u32 {
    let quotient = unsafe { __udivsi3(a, b) };
    if !remainder.is_null() {
        unsafe { *remainder = __umodsi3(a, b) };
    }
    quotient
}

// ---------------------------------------------------------------------------
// memcpy / memmove / memset / memcmp / bcmp — Rust (byte-address) implementations
//
// The C28x backend routes the MEMCPY/MEMMOVE/MEMSET/MEMCMP/BCMP libcalls to the
// uniquely-named symbols below (c28x_*) so they cannot collide with TI's
// rts2800_ml_eabi.lib definitions of memcpy/memmove/memset/memcmp, which use
// C WORD addresses.  Our versions take Rust's 32-bit *logical byte* pointers.
// See C28X_MEMORY_MODEL.md and the backend's C28xSubtarget.cpp.
// These are the bottom of the memory-runtime stack. Use wrapping pointer
// arithmetic so a valid transfer does not itself depend on core's pointer
// precondition/panic/formatting machinery. The unsafe callers must still
// provide valid buffers (and memcpy must not overlap).
// ---------------------------------------------------------------------------

/// Copy `n` bytes from `src` to `dst`. Regions must not overlap.
#[no_mangle]
pub unsafe extern "C" fn c28x_memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    let mut i = 0usize;
    while i < n {
        *dst.wrapping_add(i) = *src.wrapping_add(i);
        i += 1;
    }
    dst
}

/// Copy `n` bytes from `src` to `dst`. Regions may overlap.
#[no_mangle]
pub unsafe extern "C" fn c28x_memmove(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    if (dst as *const u8) < src {
        // Forward copy
        let mut i = 0usize;
        while i < n {
            *dst.wrapping_add(i) = *src.wrapping_add(i);
            i += 1;
        }
    } else if (dst as *const u8) > src {
        // Backward copy
        let mut i = n;
        while i > 0 {
            i -= 1;
            *dst.wrapping_add(i) = *src.wrapping_add(i);
        }
    }
    dst
}

/// Fill `n` bytes of `dst` with value `c`.
/// SelectionDAG passes the llvm.memset fill operand as i8, not C's i32 int.
/// This uniquely named helper therefore uses a byte-valued fill ABI.
#[no_mangle]
pub unsafe extern "C" fn c28x_memset(dst: *mut u8, c: u8, n: usize) -> *mut u8 {
    let mut i = 0usize;
    while i < n {
        *dst.wrapping_add(i) = c;
        i += 1;
    }
    dst
}

/// Compare `n` bytes of `a` and `b`. Returns negative/zero/positive.
#[no_mangle]
pub unsafe extern "C" fn c28x_memcmp(a: *const u8, b: *const u8, n: usize) -> i32 {
    let mut i = 0usize;
    while i < n {
        let av = *a.wrapping_add(i) as i32;
        let bv = *b.wrapping_add(i) as i32;
        if av != bv {
            return av - bv;
        }
        i += 1;
    }
    0
}

/// Compare `n` bytes of `a` and `b`. Returns 0 if equal, non-zero otherwise.
#[no_mangle]
pub unsafe extern "C" fn c28x_bcmp(a: *const u8, b: *const u8, n: usize) -> i32 {
    let mut i = 0usize;
    while i < n {
        if *a.wrapping_add(i) != *b.wrapping_add(i) {
            return 1;
        }
        i += 1;
    }
    0
}
