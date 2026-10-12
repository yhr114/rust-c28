#![no_std]

/// Rust translation of ecap_apwm_matrix.
/// APWM compare matrix: drive eCAP1 in CAP_APWM mode on GPIO5, verify
/// PRD flag assertion + CAP1 load. Depends on the APWM output pad; the
/// full register sequence is sunk into `f28035_ecap_apwm_matrix()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.apwm_matrix();
}
