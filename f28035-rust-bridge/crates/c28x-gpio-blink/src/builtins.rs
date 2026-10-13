//! C28x compiler builtins: 32-bit division/modulus.
//! Replaces TI rts library __divsi3/__udivsi3/__modsi3/__umodsi3.
//! Implemented with shift-subtract (no hardware divider on C28x).
//! MUST be compiled into the same .o as main to avoid cross-.o LCR relocation bug.

/// Unsigned 32-bit division: a / b.
#[no_mangle]
pub extern "C" fn __udivsi3(a: u32, b: u32) -> u32 {
    if b == 0 {
        return 0;
    }
    let mut quotient: u32 = 0;
    let mut remainder: u32 = 0;
    let mut i: i32 = 31;
    while i >= 0 {
        remainder = (remainder << 1) | ((a >> i) & 1);
        if remainder >= b {
            remainder -= b;
            quotient |= 1 << i;
        }
        i -= 1;
    }
    quotient
}

/// Signed 32-bit division: a / b.
#[no_mangle]
pub extern "C" fn __divsi3(a: i32, b: i32) -> i32 {
    let negative = (a ^ b) < 0;
    let ua = if a < 0 { (a as u32).wrapping_neg() } else { a as u32 };
    let ub = if b < 0 { (b as u32).wrapping_neg() } else { b as u32 };
    let q = __udivsi3(ua, ub);
    if negative { (q as i32).wrapping_neg() } else { q as i32 }
}

/// Unsigned 32-bit modulus: a % b.
#[no_mangle]
pub extern "C" fn __umodsi3(a: u32, b: u32) -> u32 {
    if b == 0 {
        return a;
    }
    let mut remainder: u32 = 0;
    let mut i: i32 = 31;
    while i >= 0 {
        remainder = (remainder << 1) | ((a >> i) & 1);
        if remainder >= b {
            remainder -= b;
        }
        i -= 1;
    }
    remainder
}

/// Signed 32-bit modulus: a % b.
#[no_mangle]
pub extern "C" fn __modsi3(a: i32, b: i32) -> i32 {
    let ua = if a < 0 { (a as u32).wrapping_neg() } else { a as u32 };
    let ub = if b < 0 { (b as u32).wrapping_neg() } else { b as u32 };
    let r = __umodsi3(ua, ub);
    if a < 0 { (r as i32).wrapping_neg() } else { r as i32 }
}
