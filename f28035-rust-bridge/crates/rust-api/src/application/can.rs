//! Auto-generated peripheral module. Do not hand-edit; see split-apply.py.
use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn rust_can_pin_mux_setup() {
    system_init();
    let _p = Peripherals::take().expect("taken");
}

#[cfg(test)]
mod tests {
    use super::{ADC_STATUS_THRESHOLD, PWM1_PERIOD_TICKS, pwm_compare_from_sample, status_high};

    #[test]
    fn status_policy_switches_at_threshold() {
        assert!(!status_high(ADC_STATUS_THRESHOLD - 1));
        assert!(status_high(ADC_STATUS_THRESHOLD));
        assert!(status_high(u16::MAX));
    }

    #[test]
    fn pwm_policy_clamps_to_configured_period() {
        assert_eq!(pwm_compare_from_sample(0), 0);
        assert_eq!(pwm_compare_from_sample(2048), 2048);
        assert_eq!(
            pwm_compare_from_sample(PWM1_PERIOD_TICKS),
            PWM1_PERIOD_TICKS
        );
        assert_eq!(pwm_compare_from_sample(u16::MAX), PWM1_PERIOD_TICKS);
    }
}


#[unsafe(no_mangle)]
pub extern "C" fn rust_can_reset_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_can_status_flag_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_can_selftest_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_can_mbox32_sweep_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_can_rx_extid_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_can_extid_filter_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_can_global_mask_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_can_int_dual_setup() {
    system_init();
}


