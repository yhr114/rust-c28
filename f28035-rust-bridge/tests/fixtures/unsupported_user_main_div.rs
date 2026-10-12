#![no_std]

mod pac {
    pub mod ffi {
        unsafe extern "C" {
            pub fn f28035_gpio_read(pin: u16) -> u16;
            pub fn f28035_gpio_write(pin: u16, high: u16);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_user_main() {
    let value = unsafe { pac::ffi::f28035_gpio_read(30) };
    let divided = value / 3;
    unsafe { pac::ffi::f28035_gpio_write(34, divided) };
}
