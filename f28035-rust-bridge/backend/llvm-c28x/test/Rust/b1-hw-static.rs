#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), no_main)]

// Hardware sample for the static-address relocation path of the B-1
// direct-object route (2026-10-22).
//
// Before the fix, every statically initialised pointer came out as four zero
// bytes with NO relocation (`external-static.rs` reproduced it), so a static
// function-pointer table or a `&'static` reference was silently null at run
// time.  This sample pins the three shapes that must survive:
//
//   1. static array of function pointers      TABLE[0..2]
//   2. static reference to that array         TABLE_REF -> &TABLE
//   3. static pointer with a nonzero addend   DATA_PTR = &DATA[1]
//
// Each entry is also read through from the TI C driver, so the same symbols
// double as a Rust<->C interop check (TI C declares them with C pointer
// types, and the frozen ABI makes every pointer a logical BYTE address).
//
// Expected on hardware:
//   use_table(5)   = fn_a(5) + fn_b(5) = 6 + 10 = 16
//   use_ref(4)     = TABLE_REF[0](4) + TABLE_REF[1](4) = 5 + 8 = 13
//   use_data_ptr() = *DATA_PTR = DATA[1] = 11
//   driver TABLE[0](3) + TABLE[1](4) = 4 + 8 = 12

#[no_mangle]
#[inline(never)]
pub extern "C" fn fn_a(x: u16) -> u16 {
    x.wrapping_add(1)
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn fn_b(x: u16) -> u16 {
    x.wrapping_mul(2)
}

#[no_mangle]
pub static TABLE: [extern "C" fn(u16) -> u16; 2] = [fn_a, fn_b];

#[no_mangle]
#[used]
pub static TABLE_REF: &[extern "C" fn(u16) -> u16; 2] = &TABLE;

#[no_mangle]
pub static DATA: [u16; 3] = [7, 11, 13];

/// Raw pointer statics need Sync; the wrapper keeps the raw-pointer shape so
/// the relocation (not a reference re-materialisation) is what gets tested.
pub struct RawPtr(pub *const u16);
unsafe impl Sync for RawPtr {}

/// Nonzero addend: points at DATA[1], not at the start of DATA.
#[no_mangle]
pub static DATA_PTR: RawPtr = RawPtr(&DATA[1]);

/// Reference form of the same addended address (also an ABS32 relocation).
#[no_mangle]
#[used]
pub static DATA_REF: &u16 = &DATA[1];

#[no_mangle]
#[inline(never)]
pub extern "C" fn use_table(x: u16) -> u16 {
    (TABLE[0])(x).wrapping_add((TABLE[1])(x))
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn use_ref(x: u16) -> u16 {
    (TABLE_REF[0])(x).wrapping_add((TABLE_REF[1])(x))
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn use_data_ptr() -> u16 {
    unsafe { *DATA_PTR.0 }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn use_data_ref() -> u16 {
    *DATA_REF
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn static_addresses_behave_on_host() {
        assert_eq!(use_table(5), 16);
        assert_eq!(use_ref(4), 13);
        assert_eq!(use_data_ptr(), 11);
        assert_eq!(use_data_ref(), 11);
        assert_eq!((TABLE[0])(3), 4);
        assert_eq!((TABLE[1])(4), 8);
    }
}
