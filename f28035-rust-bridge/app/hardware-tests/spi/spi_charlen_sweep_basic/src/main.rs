#![no_std]

/// Rust translation of spi_charlen_sweep_basic.
/// Sweeps character length 0/7/15 through the SPI, verifying the CHARLEN
/// readback and the INT_FLAG assertion after a transfer in each width. The
/// per-width runs (with their poll loops) are sunk into the C-ABI wrapper.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.spi_b.charlen_sweep();
}
