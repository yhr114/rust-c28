#![no_std]

/// Rust translation of sci_sciccr_charlen_sweep_basic.
/// SCICCR character length sweep 0..7 with loopback readback verification.
/// The full SCI-A register sequence + sweep loop is sunk into the audited
/// C-ABI wrapper `f28035_sci_sciccr_charlen_sweep_basic()`. This main only
/// performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.sci_a.charlen_sweep();
}
