#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _configured = pac::f28035_epwm1_configure_events(99, 40);
        if pac::f28035_gpio_mux(0) != 1 { pac::f28035_test_fail(0xe122); return; }
        pac::f28035_delay_us(200);
        if pac::f28035_epwm1_period() != 99 { pac::f28035_test_fail(0xe121); return; }
        if pac::f28035_epwm1_compare() != 40 { pac::f28035_test_fail(0xe121); return; }
        if pac::f28035_epwm1_aqctla() != 0x0012 { pac::f28035_test_fail(0xe121); return; }
        if pac::f28035_epwm1_event_int_enabled() != 1 { pac::f28035_test_fail(0xe121); return; }
        if pac::f28035_epwm1_event_soca_enabled() != 1 { pac::f28035_test_fail(0xe121); return; }
        if pac::f28035_epwm1_event_int_period() != 1 { pac::f28035_test_fail(0xe121); return; }
        if pac::f28035_epwm1_event_soca_period() != 1 { pac::f28035_test_fail(0xe121); return; }
        if pac::f28035_epwm1_counter_mode() != 0 { pac::f28035_test_fail(0xe121); return; }
        pac::f28035_test_pass();
    }
