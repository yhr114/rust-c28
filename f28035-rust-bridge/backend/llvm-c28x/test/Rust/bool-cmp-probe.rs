#![no_std]
//! Minimal repro for the boolean-comparison codegen bug.
//! Each entry returns (a OP b) as u16 so the DSS can read the raw bool.

#[no_mangle]
#[inline(never)]
pub extern "C" fn cmp_eq_u16(a: u16, b: u16) -> u16 {
    (a == b) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn cmp_lt_u16(a: u16, b: u16) -> u16 {
    (a < b) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn cmp_eq_u8(a: u8, b: u8) -> u16 {
    (a == b) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn cmp_eq_one(a: u16) -> u16 {
    (a == 1) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn is_some_u16(o: Option<u16>) -> u16 {
    o.is_some() as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn is_none_u16(o: Option<u16>) -> u16 {
    o.is_none() as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn not_bool(b: bool) -> u16 {
    (!b) as u16
}
