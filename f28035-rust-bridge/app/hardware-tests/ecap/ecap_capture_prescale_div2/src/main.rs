#![no_std]

/// Rust translation of ecap_capture_prescale_div2.
/// Prescale=2 capture: verify that PRESCALE division discards the first
/// edge and captures on the second rise on GPIO19. Depends on external
/// stimulus; sunk into `f28035_ecap_capture_prescale_div2()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.capture_prescale_div2();
}
