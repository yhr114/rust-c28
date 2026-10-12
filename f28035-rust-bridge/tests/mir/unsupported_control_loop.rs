#![no_std]

unsafe extern "C" {
    fn f28035_system_init();
    fn f28035_gpio_make_output(pin: u16) -> u16;
    fn f28035_gpio_write(pin: u16, high: u16);
    fn f28035_adc_result(result_index: u16) -> u16;
}

// GPIO45 does not exist on F28035. The code generator must reject this
// product-shaped function rather than emitting an invalid peripheral access.
#[unsafe(no_mangle)]
pub extern "C" fn unsupported_control_loop() -> ! {
    unsafe {
        f28035_system_init();
        let _ = f28035_gpio_make_output(45);
    }
    loop {
        let sample = unsafe { f28035_adc_result(0) };
        unsafe { f28035_gpio_write(45, u16::from(sample >= 2048)) };
    }
}
