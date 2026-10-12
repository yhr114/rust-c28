#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _base = pac::f28035_adc_configure_soc0(0, 6);
        let _soc0 = pac::f28035_adc_configure_soc(0, 0, 6, 1);
        let _timer = pac::f28035_timer0_start_adc_trigger(5000);

        if pac::f28035_adc_wait_soc_activity(0) != 1 { pac::f28035_test_fail(0x5510); return; }
        pac::f28035_timer0_stop_adc_trigger();
        if pac::f28035_adc_wait_interrupt(1) != 1 { pac::f28035_test_fail(0x5501); return; }
        let _result = pac::f28035_adc_result(0);
        pac::f28035_adc_clear_interrupt(1);
        if pac::f28035_adc_int1_flag() != 0 { pac::f28035_test_fail(0x5502); return; }
        if pac::f28035_adc_soc0_overflow() != 0 { pac::f28035_test_fail(0x5503); return; }
        pac::f28035_test_pass();
    }
