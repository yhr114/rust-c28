#![no_std]

/// Rust translation of ecap_capture_dual_edge.
/// Dual-edge capture: verify CEVT1/CEVT2 flags + CAP1/CAP2 non-zero after a
/// rising/falling pair on GPIO19. Depends on external stimulus; sunk into
/// `f28035_ecap_capture_dual_edge()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.capture_dual_edge();
}
