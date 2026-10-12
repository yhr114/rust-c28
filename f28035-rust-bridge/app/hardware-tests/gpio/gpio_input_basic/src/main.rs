#![no_std]

use f28035_safe_hal::{system_init, pac};

/// Rust translation of gpio_input_basic. GPIO30 must be connected to GPIO0.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _output = pac::f28035_gpio_make_output(30);
        pac::f28035_gpio_write(30, 0);
        let _input = pac::f28035_gpio_make_input(0, 0, 0);
        pac::f28035_delay_us(100);

        pac::f28035_gpio_write(30, 1);
        pac::f28035_delay_us(50);
        if pac::f28035_gpio_wait_for_level(0, 1) != 0 {
            pac::f28035_test_fail(0x0401);
            return;
        }

        pac::f28035_gpio_write(30, 0);
        pac::f28035_delay_us(50);
        if pac::f28035_gpio_wait_for_level(0, 0) != 0 {
            pac::f28035_test_fail(0x0402);
            return;
        }
        pac::f28035_test_pass();
    }
