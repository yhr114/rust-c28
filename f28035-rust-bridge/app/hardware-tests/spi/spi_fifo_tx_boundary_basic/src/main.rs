#![no_std]

/// Rust translation of spi_fifo_tx_boundary_basic.
/// TX FIFO level boundary case: SPIRST+SPIFFENA+TXFFIL write/readback
/// verification at 3 different TXFFIL levels, a 4-iteration TX smoke
/// (write SPITXBUF, verify SPIRST/SPIFFENA bits not clobbered), plus
/// the threshold IRQ assertion check. All loops are sunk into the C-ABI wrapper.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.spi_b.fifo_tx_boundary();
}
