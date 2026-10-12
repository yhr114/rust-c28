use crate::pac::ffi;

/// Entry point called by the C harness (platform/firmware/user_main_test.c).
/// Must match the C declaration: `Uint16 rust_main(void);`
/// The MIR backend is invoked with `-OnlyExport rust_main`.
///
/// The C28x MIR backend's `classify_user_main_cfg` parser only accepts:
///   * u16/bool locals (no HAL structs like Peripherals/OutputPin)
///   * straight-line calls to pac::ffi::f28035_* functions
///   * simple u16 arithmetic (add/sub/mul/and/or/xor/compare)
/// So this body calls the C bridge FFI directly rather than going through the
/// Safe HAL wrapper methods, which would leave non-u16 locals in MIR.
#[unsafe(no_mangle)]
pub extern "C" fn rust_user_main() -> u16 {
    unsafe { ffi::f28035_system_init() };

    unsafe { ffi::f28035_gpio_set_output(30) };
    unsafe { ffi::f28035_gpio_set_output(34) };
    unsafe { ffi::f28035_gpio_set_low(30) };
    unsafe { ffi::f28035_gpio_set_low(34) };

    let mut count: u16 = 0;
    while count < 5 {
        if count & 1 == 0 {
            unsafe { ffi::f28035_gpio_toggle_pin(30) };
        } else {
            unsafe { ffi::f28035_gpio_set_high(34) };
        }
        count = count.wrapping_add(1);
    }

    // Read back GPIO30 driven level and compute a deterministic check value.
    let observed = unsafe { ffi::f28035_gpio_read_input(30) };
    let computed = ((observed.wrapping_mul(0x8001).wrapping_add(1)) ^ 0x7fff)
        .wrapping_sub(observed)
        | observed;
    unsafe { ffi::f28035_gpio_set_low(34) };
    if computed > 0x8000 {
        unsafe { ffi::f28035_gpio_set_high(34) };
    }
    computed
}
