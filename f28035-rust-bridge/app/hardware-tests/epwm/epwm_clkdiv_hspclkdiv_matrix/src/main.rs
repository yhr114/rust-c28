#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _configured = pac::f28035_epwm1_configure_waveform(49, 20, 0x0012, 0);
        if pac::f28035_gpio_mux(0) != 1 { pac::f28035_test_fail(0xe501); return; }

        let _d0 = pac::f28035_epwm1_set_clock_dividers(0, 0);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 0 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 0 { pac::f28035_test_fail(0xe502); return; }
        let _d1 = pac::f28035_epwm1_set_clock_dividers(1, 0);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 1 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 0 { pac::f28035_test_fail(0xe502); return; }
        let _d2 = pac::f28035_epwm1_set_clock_dividers(2, 0);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 2 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 0 { pac::f28035_test_fail(0xe502); return; }
        let _d3 = pac::f28035_epwm1_set_clock_dividers(3, 0);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 3 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 0 { pac::f28035_test_fail(0xe502); return; }
        let _d4 = pac::f28035_epwm1_set_clock_dividers(0, 1);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 0 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 1 { pac::f28035_test_fail(0xe502); return; }
        let _d5 = pac::f28035_epwm1_set_clock_dividers(1, 1);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 1 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 1 { pac::f28035_test_fail(0xe502); return; }
        let _d6 = pac::f28035_epwm1_set_clock_dividers(2, 1);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 2 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 1 { pac::f28035_test_fail(0xe502); return; }
        let _d7 = pac::f28035_epwm1_set_clock_dividers(3, 1);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 3 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 1 { pac::f28035_test_fail(0xe502); return; }
        let _d8 = pac::f28035_epwm1_set_clock_dividers(4, 2);
        pac::f28035_delay_us(180);
        if pac::f28035_epwm1_hspclkdiv() != 4 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_clkdiv() != 2 { pac::f28035_test_fail(0xe502); return; }

        if pac::f28035_epwm1_period() != 49 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_compare() != 20 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_aqctla() != 0x0012 { pac::f28035_test_fail(0xe502); return; }
        if pac::f28035_epwm1_counter_mode() != 0 { pac::f28035_test_fail(0xe503); return; }
        pac::f28035_delay_us(500);
        pac::f28035_test_pass();
    }
