#![no_std]

/// Rust translation of spi_fifo_rx_boundary_basic.
/// FIFO RX boundary case: RXFFIL set to 3, then three back-to-back 8-bit
/// transfers verified via loopback (INT_FLAG assert + readback in SPIRXBUF).
/// All three transfers (with their poll loops) are sunk into the C-ABI wrapper.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.spi_b.fifo_rx_boundary();
}
