#![no_std]

/// Rust translation of sci_fifo_reset_then_loopback_basic.
/// FIFO TX/RX reset edge verification + single-byte internal loopback. The
/// full SCI-A FIFO reset sequence + poll loop is sunk into the audited C-ABI
/// wrapper `f28035_sci_fifo_reset_then_loopback_basic()`. This main only
/// performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.sci_a.fifo_reset_then_loopback();
}
