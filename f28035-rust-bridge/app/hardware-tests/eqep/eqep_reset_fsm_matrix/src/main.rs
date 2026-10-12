#![no_std]

/// Rust translation of eqep_reset_fsm_matrix.
/// eQEP1 reset behavior and FSM state matrix (EPGMODE, direction, QDWCTM).
/// The full register sequence + assert loops are sunk into the audited C-ABI
/// wrapper; this main only performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.eqep1.reset_fsm_matrix();
}
