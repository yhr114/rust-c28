#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _stage0 = pac::f28035_epwm1_configure_waveform(99, 0, 0x0012, 0);
        if pac::f28035_gpio_mux(0) != 1 { pac::f28035_test_fail(0xe701); return; }
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_compare() != 0 { pac::f28035_test_fail(0xe702); return; }
        let _stage1 = pac::f28035_epwm1_configure_waveform(99, 1, 0x0012, 0);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_compare() != 1 { pac::f28035_test_fail(0xe702); return; }
        let _stage2 = pac::f28035_epwm1_configure_waveform(99, 98, 0x0012, 0);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_compare() != 98 { pac::f28035_test_fail(0xe702); return; }
        let _stage3 = pac::f28035_epwm1_configure_waveform(99, 99, 0x0012, 0);
        pac::f28035_delay_us(260);
        if pac::f28035_epwm1_compare() != 99 { pac::f28035_test_fail(0xe702); return; }
        if pac::f28035_epwm1_counter_mode() != 0 { pac::f28035_test_fail(0xe703); return; }
        if pac::f28035_epwm1_period() != 99 { pac::f28035_test_fail(0xe703); return; }
        if pac::f28035_epwm1_aqctla() != 0x0012 { pac::f28035_test_fail(0xe703); return; }
        pac::f28035_test_pass();
    }
