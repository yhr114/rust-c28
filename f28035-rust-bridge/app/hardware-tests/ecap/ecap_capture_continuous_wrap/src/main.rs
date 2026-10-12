#![no_std]

/// Rust translation of ecap_capture_continuous_wrap.
/// Continuous wrap capture: verify CEVT1-4 flags + non-zero CAP1..4 after
/// a continuous-wrapping edge sequence on GPIO19. Depends on external
/// stimulus; sunk into `f28035_ecap_capture_continuous_wrap()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.capture_continuous_wrap();
}
