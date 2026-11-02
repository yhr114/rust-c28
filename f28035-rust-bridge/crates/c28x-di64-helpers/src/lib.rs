//! 64-bit integer helpers for C28x EABI.
//!
//! LLVM lowers 64-bit multiply/divide appearing in `core` (widened
//! `checked_mul`, `align_offset`, the formatting closure) to compiler-rt
//! libcalls `__muldi3` / `__udivdi3`, which neither the C28x LLVM backend nor
//! TI's rts2800_ml_eabi.lib provides.
//!
//! This crate deliberately contains *only* those helpers: it is linked as a
//! standalone object next to rts2800_ml_eabi.lib, so any other symbol
//! (memcpy, memset, ...) would duplicate the TI runtime.
//!
//! All arithmetic below uses 32-bit `wrapping_mul` (C28x MPYU partial
//! products) plus shifts and compares, so the implementations cannot recurse
//! into themselves.

#![no_std]

/// Full 64-bit product of two 32-bit values, via 16-bit limbs.
#[inline]
fn mul32(a: u32, b: u32) -> u64 {
    let al = a & 0xFFFF;
    let ah = a >> 16;
    let bl = b & 0xFFFF;
    let bh = b >> 16;
    let ll = al.wrapping_mul(bl) as u64;
    let lh = al.wrapping_mul(bh) as u64;
    let hl = ah.wrapping_mul(bl) as u64;
    let hh = ah.wrapping_mul(bh) as u64;
    let mid = lh.wrapping_add(hl);
    ll.wrapping_add(mid << 16).wrapping_add(hh << 32)
}

/// Truncated 64-bit product of two 64-bit values (low 64 bits).
#[inline]
fn mul_u64(a: u64, b: u64) -> u64 {
    let al = a as u32;
    let ah = (a >> 32) as u32;
    let bl = b as u32;
    let bh = (b >> 32) as u32;
    let ll = mul32(al, bl);
    // The high halves of the cross terms land at bit 64 and above: truncated.
    let lh = mul32(al, bh) << 32;
    let hl = mul32(ah, bl) << 32;
    ll.wrapping_add(lh).wrapping_add(hl)
}

/// `__muldi3`: signed 64-bit multiply (compiler-rt ABI).
#[no_mangle]
pub extern "C" fn __muldi3(a: i64, b: i64) -> i64 {
    let ua = a as u64;
    let ub = b as u64;
    let neg = (a < 0) ^ (b < 0);
    let ma = if a < 0 { ua.wrapping_neg() } else { ua };
    let mb = if b < 0 { ub.wrapping_neg() } else { ub };
    let prod = mul_u64(ma, mb);
    if neg {
        prod.wrapping_neg() as i64
    } else {
        prod as i64
    }
}

/// `__udivdi3`: unsigned 64-bit quotient (compiler-rt ABI), shift-subtract.
#[no_mangle]
pub extern "C" fn __udivdi3(mut n: u64, d: u64) -> u64 {
    let mut q: u64 = 0;
    let mut r: u64 = 0;
    let mut i: i32 = 64;
    while i > 0 {
        i -= 1;
        r = (r << 1) | (n >> 63);
        n <<= 1;
        if r >= d {
            r -= d;
            q |= 1u64 << (i as u32);
        }
    }
    q
}

/// `__umoddi3`: unsigned 64-bit remainder (compiler-rt ABI), shift-subtract.
#[no_mangle]
pub extern "C" fn __umoddi3(mut n: u64, d: u64) -> u64 {
    let mut r: u64 = 0;
    let mut i: i32 = 64;
    while i > 0 {
        i -= 1;
        r = (r << 1) | (n >> 63);
        n <<= 1;
        if r >= d {
            r -= d;
        }
    }
    r
}

/// `__moddi3`: signed 64-bit remainder (compiler-rt ABI).
#[no_mangle]
pub extern "C" fn __moddi3(a: i64, b: i64) -> i64 {
    let ua = a as u64;
    let ub = b as u64;
    let ma = if a < 0 { ua.wrapping_neg() } else { ua };
    let mb = if b < 0 { ub.wrapping_neg() } else { ub };
    let r = __umoddi3(ma, mb);
    if a < 0 {
        r.wrapping_neg() as i64
    } else {
        r as i64
    }
}
