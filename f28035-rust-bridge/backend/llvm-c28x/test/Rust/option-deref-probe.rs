//! Minimal hardware probe for the `Option::is_some` / pointer-dereference
//! failure seen in `core_ex_option` (returns 138, expected 140).
//!
//! The failing pattern in `core_ex_option` is `Some(1u16).is_some()` where
//! LLVM promotes the temporary to a `.rodata` constant and passes its
//! 22-bit logical-byte address to `is_some`.  Three variants isolate where
//! that path breaks:
//!   probe_is_some_temp  - the exact failing pattern (promoted .rodata const)
//!   probe_deref_rodata  - volatile byte load from a .rodata static
//!   probe_deref_stack   - volatile byte load from a stack array
//! Expected on hardware: 1, 1, 1, 1111
#![no_std]

#[no_mangle]
#[inline(never)]
pub extern "C" fn probe_is_some_temp() -> u16 {
    let o: Option<u16> = Some(1);
    (o.is_some()) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn probe_deref_rodata() -> u16 {
    static T: [u8; 4] = [1, 0, 1, 0];
    unsafe { core::ptr::read_volatile(T.as_ptr()) as u16 }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn probe_deref_stack() -> u16 {
    let t: [u8; 4] = [1, 0, 1, 0];
    unsafe { core::ptr::read_volatile(t.as_ptr()) as u16 }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn probe_all() -> u16 {
    probe_is_some_temp()
        .wrapping_mul(1000)
        .wrapping_add(probe_deref_rodata().wrapping_mul(10))
        .wrapping_add(probe_deref_stack())
}
