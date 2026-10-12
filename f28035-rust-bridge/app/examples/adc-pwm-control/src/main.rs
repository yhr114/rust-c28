use f28035_safe_hal::{Peripherals, system_init};

/// Main application entry point.
///
/// Put the F28035 control loop, state machines, protection logic, and calls to
/// safe peripheral wrappers in this function.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() -> ! {
    system_init();

    let peripherals = Peripherals::take().unwrap();
    let mut gpio = peripherals.gpio;
    let mut status_pin = gpio.output::<31>().unwrap();
    let _interrupt_pin = gpio.output::<30>().unwrap();
    let adc = peripherals.adc;
    let mut pwm = peripherals.pwm1.configure::<4095>().unwrap();
    let _timer = peripherals.timer0.start_periodic::<10>().unwrap();

    loop {
        let sample = adc.sample::<0>();
        pwm.set_compare(sample);
        status_pin.set(sample >= 2048);
    }
}

/// Timer0 interrupt behavior remains ordinary safe Rust. A small TI C ISR
/// wrapper owns the interrupt ABI prologue/epilogue and calls this function.
#[unsafe(no_mangle)]
pub extern "C" fn rust_timer0_interrupt() {
    // Safety: GPIO30 is configured before Timer0 is started, and the PIE group
    // acknowledgement is required once per completed Timer0 interrupt.
    unsafe {
        f28035_safe_hal::pac::ffi::f28035_gpio_toggle(30);
        f28035_safe_hal::pac::ffi::f28035_timer0_ack();
    }
}
