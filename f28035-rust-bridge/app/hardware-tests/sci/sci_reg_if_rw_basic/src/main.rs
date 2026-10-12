#![no_std]

/// Rust translation of sci_reg_if_rw_basic.
/// Internal SCI register read/write smoke (CC/CTL1/CTL2/HBAUD/LBAUD/FFTX/FFRX/FFCT/PRI).
/// The full SCI-A register sequence + masked readback checks are sunk into the
/// audited C-ABI wrapper `f28035_sci_reg_if_rw_basic()` (self-contained,
/// reports via the shared test runtime). This main only performs that FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.sci_a.reg_readback();
}
