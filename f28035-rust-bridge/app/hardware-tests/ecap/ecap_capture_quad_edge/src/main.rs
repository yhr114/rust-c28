#![no_std]

/// Rust translation of ecap_capture_quad_edge.
/// Quad-edge capture: verify CEVT1-4 flags + CAP1..4 non-zero + ordered
/// sequence after a 4-edge GPIO19 pulse. Depends on external stimulus;
/// sunk into `f28035_ecap_capture_quad_edge()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.capture_quad_edge();
}
