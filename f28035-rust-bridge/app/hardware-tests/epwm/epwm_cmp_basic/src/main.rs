#![no_std]

use f28035_safe_hal::{PWM1_PERIOD_TICKS, Peripherals, system_init};

/// Safe HAL bridge case for ePWM1 period/compare programming.
///
/// The verified target symbol is
/// `crates/rust-api::application::rust_epwm_cmp_basic`, which mirrors this
/// body and is lowered from optimized MIR into C28x assembly.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pwm = peripherals.pwm1.configure::<PWM1_PERIOD_TICKS>();
    pwm.set_compare(2048);
}
