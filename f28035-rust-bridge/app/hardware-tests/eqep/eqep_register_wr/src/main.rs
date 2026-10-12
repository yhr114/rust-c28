#![no_std]

/// Rust translation of eqep_register_wr.
/// Masked read/write smoke scan over eQEP1 registers. The full register
/// sequence + assert loops are sunk into the audited C-ABI wrapper; this
/// main only performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.eqep1.register_write_readback();
}
