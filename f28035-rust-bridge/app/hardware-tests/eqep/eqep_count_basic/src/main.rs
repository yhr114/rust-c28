#![no_std]

/// Rust translation of eqep_count_basic.
/// Basic quadrature count: wait for QPOSCNT to change. Depends on UVM
/// quadrature encoder stimulus; without external signal the count stays 0 and
/// the wrapper asserts the no-change path. The full eQEP1 register sequence +
/// poll loops are sunk into the audited C-ABI wrapper; this main only
/// performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.eqep1.count_basic();
}
