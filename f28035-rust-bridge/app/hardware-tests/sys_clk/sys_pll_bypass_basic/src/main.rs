use f28035_safe_hal::{Peripherals, system_init};

/// Hardware-test entry point. Replace the loop body with this case's checks.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() -> ! {
    system_init();
    let _peripherals = Peripherals::take().unwrap();

    loop {
        core::hint::spin_loop();
    }
}

/// Required by the current C bridge even when this case does not use Timer0.
#[unsafe(no_mangle)]
pub extern "C" fn rust_timer0_interrupt() {
    f28035_safe_hal::pac::ack_timer0_interrupt();
}

