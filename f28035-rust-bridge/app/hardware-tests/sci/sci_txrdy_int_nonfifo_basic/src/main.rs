#![no_std]

/// Rust translation of sci_txrdy_int_nonfifo_basic.
/// TXRDY IRQ non-FIFO: verify TXINTENA config, send 2 bytes, read back each.
/// The full SCI-A register sequences + poll loops are sunk into the audited
/// C-ABI wrapper `f28035_sci_txrdy_int_nonfifo_basic()`. This main only
/// performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.sci_a.tx_ready_interrupt_nonfifo();
}
