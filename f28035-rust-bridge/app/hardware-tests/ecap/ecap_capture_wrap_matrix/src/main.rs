#![no_std]

/// Rust translation of ecap_capture_wrap_matrix.
/// Wrap matrix: sweep STP/WRP modes across a GPIO19 edge sequence, verify
/// capture behavior for each mode. Depends on external stimulus; sunk into
/// `f28035_ecap_capture_wrap_matrix()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.capture_wrap_matrix();
}
