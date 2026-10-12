#![no_std]

use f28035_safe_hal::{system_init, pac};

/// Rust translation of epwm_updown_aq_smoke.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _configured = pac::f28035_epwm1_configure_waveform(99, 20, 0x0092, 2);
        if pac::f28035_gpio_mux(0) != 1 {
            pac::f28035_test_fail(0xe112);
            return;
        }

        pac::f28035_delay_us(200);
        if pac::f28035_epwm1_period() != 99 {
            pac::f28035_test_fail(0xe111);
            return;
        }
        if pac::f28035_epwm1_compare() != 20 {
            pac::f28035_test_fail(0xe111);
            return;
        }
        if pac::f28035_epwm1_aqctla() != 0x0092 {
            pac::f28035_test_fail(0xe111);
            return;
        }
        if pac::f28035_epwm1_counter_mode() != 2 {
            pac::f28035_test_fail(0xe111);
            return;
        }
        pac::f28035_test_pass();
    }
