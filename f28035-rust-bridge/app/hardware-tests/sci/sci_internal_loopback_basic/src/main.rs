#![no_std]

/// Rust translation of sci_internal_loopback_basic.
/// Internal loopback across 4 SCICCR profiles (parity/stop/charlen variants).
/// The full SCI-A register sequences + poll loops still live in the audited
/// C-ABI bridge, while this business entry now uses the typed SCI-A HAL
/// handle instead of calling the bridge symbol directly.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _profile = peripherals.sci_a.internal_loopback::<194, 8>();
}
