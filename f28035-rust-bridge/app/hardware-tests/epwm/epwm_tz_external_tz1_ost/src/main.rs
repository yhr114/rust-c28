#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _tz_input = pac::f28035_gpio_make_input(15, 0, 3);
        let _tz_mux = pac::f28035_gpio_set_mux(15, 1);
        let _configured = pac::f28035_epwm1_configure_external_trip(99, 40);

        if pac::f28035_gpio_mux(0) != 1 { pac::f28035_test_fail(0xee01); return; }
        if pac::f28035_gpio_mux(1) != 1 { pac::f28035_test_fail(0xee01); return; }
        if pac::f28035_gpio_mux(15) != 1 { pac::f28035_test_fail(0xee01); return; }
        if pac::f28035_gpio_direction(15) != 0 { pac::f28035_test_fail(0xee01); return; }
        if pac::f28035_gpio_qualification(15) != 3 { pac::f28035_test_fail(0xee01); return; }
        pac::f28035_delay_us(100);

        if pac::f28035_epwm1_period() != 99 { pac::f28035_test_fail(0xee02); return; }
        if pac::f28035_epwm1_compare() != 40 { pac::f28035_test_fail(0xee02); return; }
        if pac::f28035_epwm1_aqctla() != 0x0012 { pac::f28035_test_fail(0xee02); return; }
        if pac::f28035_epwm1_tzsel() != 0x0100 { pac::f28035_test_fail(0xee02); return; }
        if pac::f28035_epwm1_tzctl() != 0x000a { pac::f28035_test_fail(0xee02); return; }
        if pac::f28035_epwm1_tzeint() != 0x0004 { pac::f28035_test_fail(0xee02); return; }
        if pac::f28035_epwm1_counter_mode() != 0 { pac::f28035_test_fail(0xee02); return; }

        if pac::f28035_epwm1_wait_ost(1) != 1 { pac::f28035_test_fail(0xee03); return; }
        pac::f28035_delay_us(80);
        pac::f28035_epwm1_clear_ost();
        if pac::f28035_epwm1_wait_ost(0) != 1 { pac::f28035_test_fail(0xee04); return; }
        pac::f28035_delay_us(140);
        pac::f28035_test_pass();
    }
