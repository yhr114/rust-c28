#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

const ADC_STATUS_THRESHOLD: u16 = 2048;
const PWM1_PERIOD_TICKS: u16 = 4095;

#[inline(always)]
const fn status_high(sample: u16) -> bool {
    sample >= ADC_STATUS_THRESHOLD
}

#[inline(always)]
const fn pwm_compare_from_sample(sample: u16) -> u16 {
    if sample > PWM1_PERIOD_TICKS {
        PWM1_PERIOD_TICKS
    } else {
        sample
    }
}

/// Safe HAL integration loop for ADC + ePWM1 + Timer0 + GPIO.
///
/// This case is verified through the MIR bridge:
///
/// ```powershell
/// .\tools\verify-safe-hal-case-ram.ps1 -Case integration/safe_hal_control_loop
/// ```
///
/// The linked target symbol is currently
/// `crates/rust-api::application::rust_main`, which mirrors this body and is
/// lowered from optimized MIR into C28x assembly by `backend/c28x-mir`.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() -> ! {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    let mut gpio = peripherals.gpio;
    let mut status_pin = gpio.output::<31>().expect("GPIO31 output rejected");
    let _interrupt_pin = gpio.output::<30>().expect("GPIO30 output rejected");
    let adc = peripherals.adc;
    let mut pwm = peripherals.pwm1.configure::<PWM1_PERIOD_TICKS>();
    let _timer = peripherals.timer0.start_periodic::<10>();

    loop {
        let sample = adc.sample::<0>();
        pwm.set_compare(pwm_compare_from_sample(sample));
        status_pin.set(status_high(sample));
    }
}
