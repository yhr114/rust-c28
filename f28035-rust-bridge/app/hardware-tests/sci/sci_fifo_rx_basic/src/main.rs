#![no_std]

/// Rust translation of sci_fifo_rx_basic.
/// FIFO RX boundary: write 4 bytes, verify FIFO level >= 4, read back each
/// byte. The full SCI-A FIFO init + poll loops are sunk into the audited
/// C-ABI wrapper `f28035_sci_fifo_rx_basic()`. This main only performs that
/// one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.sci_a.fifo_rx();
}
