#![no_std]

/// Rust translation of ecap_capture_single_edge.
/// Single-edge capture: verify CEVT1 flag + INT flag + non-zero CAP1 after
/// one rising edge on GPIO19, then ECCLR clears the flags. Depends on
/// external stimulus; sunk into `f28035_ecap_capture_single_edge()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.capture_single_edge();
}
