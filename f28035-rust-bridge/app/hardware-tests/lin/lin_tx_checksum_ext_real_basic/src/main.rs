#![no_std]

/// Rust translation of lin_tx_checksum_ext_real_basic.
/// The full LIN-A register sequence + EALLOW-guarded masked readback checks
/// are sunk into the audited C-ABI wrapper $fn() (self-contained, reports
/// via the shared test runtime). This main only performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.lin_a.tx_checksum_extended();
}
