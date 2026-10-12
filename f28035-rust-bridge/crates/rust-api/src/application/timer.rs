//! Auto-generated peripheral module. Do not hand-edit; see split-apply.py.
use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn rust_timer0_periodic_basic() {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    let _timer = peripherals.timer0.start_periodic::<10>();
}

/// Timer0 interrupt handler called from the TI C ISR wrapper.
#[unsafe(no_mangle)]
pub extern "C" fn rust_timer0_interrupt() {
    unsafe {
        crate::ffi::f28035_gpio_toggle(30);
        crate::ffi::f28035_timer0_ack();
    }
}
