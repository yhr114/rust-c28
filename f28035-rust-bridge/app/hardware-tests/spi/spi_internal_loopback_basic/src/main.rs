#![no_std]

/// Rust translation of spi_internal_loopback_basic.
/// 8-bit internal loopback (SPILBK, non-FIFO path, CPHA configurable). The
/// source C case sends 0x003C and verifies the looped-back byte returns in
/// SPIRXBUF[15:8] after INT_FLAG asserts. The register sequence is still
/// implemented by the C-ABI bridge, but the business entry now goes through
/// the typed SPI-B HAL handle.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _loopback = peripherals.spi_b.internal_loopback::<8>();
}
