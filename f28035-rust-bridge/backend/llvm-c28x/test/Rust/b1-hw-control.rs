#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), no_main)]

#[cfg(not(feature = "cross-crate"))]
#[path = "b1-hw-mode.rs"]
mod mode;
#[cfg(not(feature = "cross-crate"))]
pub use mode::rust_mode;
#[cfg(feature = "cross-crate")]
pub use c28x_cargo_mode::rust_mode;

#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_sum_slice(ptr: *const u16, len: u16) -> u16 {
    // The test driver supplies an aligned, live four-word array.  Construct
    // the fat pointer locally so this test does not depend on an unrelated
    // aggregate-return helper ABI.
    let values: &[u16] = unsafe { core::mem::transmute((ptr, len as usize)) };
    let mut sum = 0u16;
    let mut index = 0u16;
    while index < values.len() as u16 {
        sum = sum.wrapping_add(unsafe { values.as_ptr().add(index as usize).read() });
        index = index.wrapping_add(1);
    }
    sum
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_control(ptr: *const u16, len: u16, tag: u16) -> u16 {
    // The raw pointer is supplied by a known-good static TI C test array.
    // This function is only used by the RAM/JTAG test driver.
    let sum = rust_sum_slice(ptr, len);
    rust_mode(tag, sum)
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
    fn enum_slice_and_calls() {
        let values = [2u16, 4, 6, 8];
        assert_eq!(rust_sum_slice(values.as_ptr(), 4), 20);
        assert_eq!(rust_control(values.as_ptr(), 4, 0), 23);
        assert_eq!(rust_control(values.as_ptr(), 4, 1), 40);
        assert_eq!(rust_control(values.as_ptr(), 4, 2), 19);
    }
}
