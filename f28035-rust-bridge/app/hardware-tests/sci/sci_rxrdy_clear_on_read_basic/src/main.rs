#![no_std]

/// Rust translation of sci_rxrdy_clear_on_read_basic.
/// Verify RXRDY clears after reading SCIRXBUF (internal loopback, no FIFO).
/// The full SCI-A register sequence + poll loop is sunk into the audited
/// C-ABI wrapper `f28035_sci_rxrdy_clear_on_read_basic()`. This main only
/// performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.sci_a.rx_ready_clears_on_read();
}
