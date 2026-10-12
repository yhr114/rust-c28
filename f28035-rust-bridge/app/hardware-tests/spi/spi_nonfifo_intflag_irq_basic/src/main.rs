#![no_std]

/// Rust translation of spi_nonfifo_intflag_irq_basic.
/// Non-FIFO INT_FLAG IRQ case: with INTENA enabled, two 8-bit frames per
/// CPHA setting (0 and 1) assert INT_FLAG then clear it after the RX buffer
/// read. All status poll loops are sunk into the C-ABI wrapper.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.spi_b.nonfifo_interrupt_flag();
}
