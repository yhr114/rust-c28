#![no_std]

/// Rust translation of spi_fifo_level_boundary_basic.
/// TX FIFO level boundary case: verify TXFFST reads 0 after FIFO reset,
/// then fill to depth 4 and verify the drain. All poll loops are sunk
/// into the C-ABI wrapper.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.spi_b.fifo_level_boundary();
}
