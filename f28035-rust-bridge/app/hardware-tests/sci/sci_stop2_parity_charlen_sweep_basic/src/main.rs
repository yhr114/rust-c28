#![no_std]

/// Rust translation of sci_stop2_parity_charlen_sweep_basic.
/// Stop2/parity/charlen matrix loopback sweep. The full SCI-A register
/// sequences + nested matrix loops are sunk into the audited C-ABI wrapper
/// `f28035_sci_stop2_parity_charlen_sweep_basic()`. This main only performs
/// that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.sci_a.stop_parity_charlen_sweep();
}
