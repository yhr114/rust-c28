#![no_std]

/// Rust translation of spi_multiple_frame_loopback_basic.
/// Sends two 8-bit frames back-to-back through the SPI (0x0012, 0x0034),
/// verifying each looped-back byte in SPIRXBUF after INT_FLAG asserts.
/// Both frame runs (with their poll loops) are sunk into the C-ABI wrapper.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.spi_b.multiple_frame_loopback();
}
