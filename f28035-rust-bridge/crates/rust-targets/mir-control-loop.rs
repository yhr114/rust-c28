#![no_std]

unsafe extern "C" {
    fn f28035_system_init();
    fn f28035_gpio_make_output(pin: u16) -> u16;
    fn f28035_gpio_write(pin: u16, high: u16);
    fn f28035_adc_result(result_index: u16) -> u16;
}

/// Minimal product-shaped Rust firmware used to grow the MIR backend.
///
/// The C bridge still owns the audited register access while Rust owns the
/// initialization sequence, the permanent control loop, and its decision.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() -> ! {
    unsafe {
        f28035_system_init();
        let _ = f28035_gpio_make_output(31);
    }

    loop {
        let sample = unsafe { f28035_adc_result(0) };
        unsafe {
            f28035_gpio_write(31, u16::from(sample >= 2048));
        }
    }
}
