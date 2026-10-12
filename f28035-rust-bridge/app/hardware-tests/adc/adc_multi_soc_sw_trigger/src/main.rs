#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _base = pac::f28035_adc_configure_soc0(0, 6);
        let _soc0 = pac::f28035_adc_configure_soc(0, 0, 6, 0);
        let _soc1 = pac::f28035_adc_configure_soc(1, 1, 6, 0);
        let _soc2 = pac::f28035_adc_configure_soc(2, 8, 6, 0);
        let _int1 = pac::f28035_adc_configure_interrupt(1, 0);
        let _int2 = pac::f28035_adc_configure_interrupt(2, 1);
        let _int3 = pac::f28035_adc_configure_interrupt(3, 2);

        pac::f28035_adc_force_mask(0x0007);
        if pac::f28035_adc_wait_interrupt(1) != 1 { pac::f28035_test_fail(0x5301); return; }
        pac::f28035_adc_clear_interrupt(1);
        if pac::f28035_adc_wait_interrupt(2) != 1 { pac::f28035_test_fail(0x5302); return; }
        pac::f28035_adc_clear_interrupt(2);
        if pac::f28035_adc_wait_interrupt(3) != 1 { pac::f28035_test_fail(0x5303); return; }
        pac::f28035_adc_clear_interrupt(3);

        let _result0 = pac::f28035_adc_result(0);
        let _result1 = pac::f28035_adc_result(1);
        let _result2 = pac::f28035_adc_result(2);
        if pac::f28035_adc_busy_mask() != 0 { pac::f28035_test_fail(0x5304); return; }
        pac::f28035_test_pass();
    }
