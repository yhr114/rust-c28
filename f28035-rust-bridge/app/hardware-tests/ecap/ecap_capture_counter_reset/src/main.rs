#![no_std]

/// Rust translation of ecap_capture_counter_reset.
/// Counter reset capture: verify ECCLR clears CEVT flags + counter reset
/// behavior. Depends on external GPIO19 stimulus; sunk into
/// `f28035_ecap_capture_counter_reset()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.capture_counter_reset();
}
