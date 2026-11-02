//! Layered hardware probe for the B-1 direct-object route.
//!
//! Each entry isolates one layer, and every input comes from the C driver so
//! nothing is constant-folded away:
//!   * argument passing            lp_echo
//!   * comparison result (value)   lp_cmp_eq
//!   * compare + branch            lp_if_zero, lp_mode
//!   * loop + word pointer load    lp_sum
//!   * stack byte array            lp_byte_stack
//!   * byte / word pointer load    lp_byte_ptr, lp_word_ptr
//!
//! Expected values are listed in tools/hw_rust_layer_probe_driver.c and
//! mirrored in tools/dss-read-rust-layer-probe.js.
#![no_std]

#[no_mangle]
#[inline(never)]
pub extern "C" fn lp_echo(a: u16) -> u16 {
    a
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn lp_cmp_eq(a: u16, b: u16) -> u16 {
    if a == b { 1 } else { 0 }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn lp_if_zero(a: u16) -> u16 {
    if a == 0 { 23 } else { 40 }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn lp_mode(tag: u16, v: u16) -> u16 {
    if tag == 0 {
        v.wrapping_add(3)
    } else if tag == 1 {
        v.wrapping_mul(2)
    } else {
        v.wrapping_sub(1)
    }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn lp_sum(ptr: *const u16, len: u16) -> u16 {
    let mut sum = 0u16;
    let mut i = 0u16;
    while i < len {
        sum = sum.wrapping_add(unsafe { core::ptr::read_volatile(ptr.add(i as usize)) });
        i = i.wrapping_add(1);
    }
    sum
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn lp_byte_stack(x: u16) -> u16 {
    let mut t = [0u8; 2];
    t[0] = x as u8;
    t[1] = 0x5A;
    let lo = unsafe { core::ptr::read_volatile(&t[0] as *const u8) } as u16;
    let hi = unsafe { core::ptr::read_volatile(&t[1] as *const u8) } as u16;
    lo | (hi << 8)
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn lp_byte_ptr(p: *const u8) -> u16 {
    unsafe { core::ptr::read_volatile(p) as u16 }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn lp_word_ptr(p: *const u16) -> u16 {
    unsafe { core::ptr::read_volatile(p) }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
