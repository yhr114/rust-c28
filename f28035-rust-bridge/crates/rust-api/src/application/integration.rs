//! Auto-generated peripheral module. Do not hand-edit; see split-apply.py.
use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() -> ! {
    system_init();

    let peripherals = Peripherals::take().unwrap();
    let mut gpio = peripherals.gpio;
    let mut status_pin = gpio.output::<31>();
    let _interrupt_pin = gpio.output::<30>();
    let adc = peripherals.adc;
    let mut pwm = peripherals.pwm1.configure::<PWM1_PERIOD_TICKS>();
    let _timer = peripherals.timer0.start_periodic::<10>();

    loop {
        let sample = adc.sample::<0>();
        pwm.set_compare(pwm_compare_from_sample(sample));
        status_pin.set(status_high(sample));
    }
}

/// Timer0 interrupt behavior remains ordinary safe Rust. A small TI C ISR
/// wrapper owns the interrupt ABI prologue/epilogue and calls this function.
#[unsafe(no_mangle)]
pub extern "C" fn rust_et_jtag_setup() {
    system_init();
}


