#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let _configured = pac::f28035_adc_configure_soc0(13, 6);
        let _result = pac::f28035_adc_sample(13);
        if pac::f28035_adc_timeouts() != 0 {
            pac::f28035_test_fail(0x5201);
            return;
        }
        if pac::f28035_adc_int1_flag() != 0 {
            pac::f28035_test_fail(0x5202);
            return;
        }
        if pac::f28035_adc_soc0_overflow() != 0 {
            pac::f28035_test_fail(0x5203);
            return;
        }
        pac::f28035_test_pass();
    }
