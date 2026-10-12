#![no_std]

/// Rust translation of spi_loopback_mode_matrix_basic.
/// Runs four loopback mode combinations (charlen, master/talk, cpha, cpol)
/// and verifies the looped-back byte after INT_FLAG asserts in each mode.
/// All four runs (with their poll loops) are sunk into the C-ABI wrapper.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.spi_b.loopback_mode_matrix();
}
