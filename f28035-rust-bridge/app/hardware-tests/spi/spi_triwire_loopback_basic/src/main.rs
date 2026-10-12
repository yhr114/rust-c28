#![no_std]

/// Rust translation of spi_triwire_loopback_basic.
/// SPIPRI TRIWIRE mode (3-wire): enable triwire via SPIPRI.TRIWIRE=1, verify
/// the bit reads back, then run an 8-bit internal loopback at 0x005A and
/// verify the looped-back byte in SPIRXBUF[15:8]. All poll loops are sunk
/// into the C-ABI wrapper.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _loopback = peripherals.spi_b.triwire_loopback::<8>();
}
