#![no_std]

/// Rust translation of eqep_polarity_test.
/// EPOL/QLP/CLR polarity matrix over eQEP1. The full register sequence +
/// assert loops are sunk into the audited C-ABI wrapper; this main only
/// performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.eqep1.polarity_test();
}
