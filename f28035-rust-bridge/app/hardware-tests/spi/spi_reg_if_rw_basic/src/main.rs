#![no_std]

/// Rust translation of spi_reg_if_rw_basic.
/// Register interface read/write smoke test for SPICCR/SPICTL/SPIBRR/SPIFFCT/SPIPRI.
/// The full masked-RW scan is sunk into the audited C-ABI wrapper; this main
/// only performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.spi_b.reg_readback();
}
