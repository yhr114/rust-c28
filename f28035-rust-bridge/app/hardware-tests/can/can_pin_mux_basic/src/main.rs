#![no_std]

use f28035_safe_hal::{system_init, pac};

/// Rust translation of can_pin_mux_basic.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _canrx = pac::f28035_gpio_set_mux(30, 1);
        let _cantx = pac::f28035_gpio_set_mux(31, 1);
        pac::f28035_delay_us(100);
        if pac::f28035_gpio_mux(30) != 1 {
            pac::f28035_test_fail(0x5201);
            return;
        }
        if pac::f28035_gpio_mux(31) != 1 {
            pac::f28035_test_fail(0x5202);
            return;
        }
        pac::f28035_test_pass();
    }
