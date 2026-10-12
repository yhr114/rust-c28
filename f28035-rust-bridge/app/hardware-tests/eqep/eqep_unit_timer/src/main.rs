#![no_std]

/// Rust translation of eqep_unit_timer.
/// UTMR/UPRD unit timer free-run and compare behavior over eQEP1. The full
/// register sequence + poll loops are sunk into the audited C-ABI wrapper;
/// this main only performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.eqep1.unit_timer();
}
