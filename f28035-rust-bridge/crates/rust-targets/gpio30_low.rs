#![no_std]

unsafe extern "C" {
    fn f28035_gpio_make_output(pin: u16) -> u16;
    fn f28035_gpio_write(pin: u16, high: u16);
}

/// Configure GPIO30 (GPA30) as a GPIO output and drive it low.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio30_low() {
    unsafe {
        f28035_gpio_make_output(30);
        f28035_gpio_write(30, 0);
    }
}
