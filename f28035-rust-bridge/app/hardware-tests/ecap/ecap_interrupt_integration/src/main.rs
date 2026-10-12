#![no_std]

/// Rust translation of ecap_interrupt_integration.
/// Interrupt integration: verify ECEINT/ECFRC/ECCLR/ECFLG routing across
/// all 7 interrupt sources (CEVT1-4, CTROVF, CTR_PRD, CTR_CMP) without
/// needing external stimulus. Sunk into `f28035_ecap_interrupt_integration()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.ecap1.interrupt_integration();
}
