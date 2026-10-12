#![no_std]

/// Rust translation of ecap_reg_rw_smoke.
/// Internal eCAP1 register read/write smoke (TSCTR/CTRPHS/CAP1..4/ECCTL1/ECEINT
/// reset snapshot + masked RW). No external stimulus required; the full
/// register scan is sunk into the C-ABI wrapper `f28035_ecap_reg_rw_smoke()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.reg_readback();
}
