#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _configured = pac::f28035_epwm1_configure_software_trip(99, 40);
        if pac::f28035_gpio_mux(0) != 1 { pac::f28035_test_fail(0xe701); return; }
        if pac::f28035_gpio_mux(1) != 1 { pac::f28035_test_fail(0xe701); return; }
        pac::f28035_delay_us(80);
        if pac::f28035_epwm1_period() != 99 { pac::f28035_test_fail(0xe702); return; }
        if pac::f28035_epwm1_compare() != 40 { pac::f28035_test_fail(0xe702); return; }
        if pac::f28035_epwm1_aqctla() != 0x0012 { pac::f28035_test_fail(0xe702); return; }
        if pac::f28035_epwm1_tzctl() != 0x000a { pac::f28035_test_fail(0xe702); return; }
        if pac::f28035_epwm1_tzeint() != 0x0004 { pac::f28035_test_fail(0xe702); return; }
        if pac::f28035_epwm1_counter_mode() != 0 { pac::f28035_test_fail(0xe702); return; }

        pac::f28035_epwm1_force_ost();
        if pac::f28035_epwm1_wait_ost(1) != 1 { pac::f28035_test_fail(0xe703); return; }
        pac::f28035_delay_us(60);
        pac::f28035_epwm1_clear_ost();
        if pac::f28035_epwm1_wait_ost(0) != 1 { pac::f28035_test_fail(0xe704); return; }
        pac::f28035_delay_us(120);
        pac::f28035_test_pass();
    }
