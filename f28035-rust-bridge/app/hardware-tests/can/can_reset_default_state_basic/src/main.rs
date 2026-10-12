#![no_std]

use f28035_safe_hal::{system_init, pac};

/// Rust translation of can_reset_default_state_basic.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        if pac::f28035_gpio_mux(30) != 0 {
            pac::f28035_test_fail(0x5101);
            return;
        }
        if pac::f28035_gpio_mux(31) != 0 {
            pac::f28035_test_fail(0x5102);
            return;
        }
        pac::f28035_test_pass();
    }
