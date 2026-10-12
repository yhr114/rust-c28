#![no_std]

use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
        system_init();
        let configured = pac::f28035_adc_configure_soc0(13, 6);
        if configured != 1 { pac::f28035_test_fail(0x5101); return; }
        if pac::f28035_adc_clock_enabled() != 1 { pac::f28035_test_fail(0x5102); return; }
        if pac::f28035_adc_clkdiv2_enabled() != 1 { pac::f28035_test_fail(0x5103); return; }
        if pac::f28035_adc_ctl1_configured() != 1 { pac::f28035_test_fail(0x5104); return; }
        if pac::f28035_adc_int1_configured() != 1 { pac::f28035_test_fail(0x5105); return; }
        if pac::f28035_adc_soc0_channel() != 13 { pac::f28035_test_fail(0x5106); return; }
        if pac::f28035_adc_soc0_acqps() != 6 { pac::f28035_test_fail(0x5106); return; }
        if pac::f28035_adc_soc0_trigger() != 0 { pac::f28035_test_fail(0x5106); return; }
        pac::f28035_test_pass();
    }
