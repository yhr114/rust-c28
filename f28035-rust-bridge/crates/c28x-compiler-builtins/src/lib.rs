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

// ---------------------------------------------------------------------------
// memcpy / memmove / memset / memcmp — Rust implementations
// ---------------------------------------------------------------------------

/// Copy `n` bytes from `src` to `dst`. Regions must not overlap.
#[no_mangle]
pub unsafe extern "C" fn memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    let mut i = 0usize;
    while i < n {
        *dst.add(i) = *src.add(i);
        i += 1;
    }
    dst
}

/// Copy `n` bytes from `src` to `dst`. Regions may overlap.
#[no_mangle]
pub unsafe extern "C" fn memmove(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    if (dst as *const u8) < src {
        // Forward copy
        let mut i = 0usize;
        while i < n {
            *dst.add(i) = *src.add(i);
            i += 1;
        }
    } else if (dst as *const u8) > src {
        // Backward copy
        let mut i = n;
        while i > 0 {
            i -= 1;
            *dst.add(i) = *src.add(i);
        }
    }
    dst
}

/// Fill `n` bytes of `dst` with value `c`.
#[no_mangle]
pub unsafe extern "C" fn memset(dst: *mut u8, c: i32, n: usize) -> *mut u8 {
    let mut i = 0usize;
    while i < n {
        *dst.add(i) = c as u8;
        i += 1;
    }
    dst
}

/// Compare `n` bytes of `a` and `b`. Returns negative/zero/positive.
#[no_mangle]
pub unsafe extern "C" fn memcmp(a: *const u8, b: *const u8, n: usize) -> i32 {
    let mut i = 0usize;
    while i < n {
        let av = *a.add(i) as i32;
        let bv = *b.add(i) as i32;
        if av != bv {
            return av - bv;
        }
        i += 1;
    }
    0
}
