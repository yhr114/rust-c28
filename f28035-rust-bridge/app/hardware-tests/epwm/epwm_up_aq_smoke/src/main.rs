#![no_std]

use f28035_safe_hal::{system_init, pac};

/// Rust translation of epwm_up_aq_smoke.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _configured = pac::f28035_epwm1_configure(99);
        pac::f28035_epwm1_set_compare(40);

        if pac::f28035_gpio_mux(0) != 1 {
            pac::f28035_test_fail(0xe102);
            return;
        }

        pac::f28035_delay_us(200);
        if pac::f28035_epwm1_period() != 99 {
            pac::f28035_test_fail(0xe101);
            return;
        }
        if pac::f28035_epwm1_compare() != 40 {
            pac::f28035_test_fail(0xe101);
            return;
        }
        if pac::f28035_epwm1_aqctla() != 0x0012 {
            pac::f28035_test_fail(0xe101);
            return;
        }
        if pac::f28035_epwm1_counter_mode() != 0 {
            pac::f28035_test_fail(0xe101);
            return;
        }
        pac::f28035_test_pass();
    }
