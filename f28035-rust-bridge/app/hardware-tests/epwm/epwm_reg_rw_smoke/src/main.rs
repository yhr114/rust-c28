#![no_std]

/// Rust translation of fpga_delivery_28035/case_src/epwm/epwm_reg_rw_smoke.
///
/// The source C case performs a reset-value snapshot plus a masked 16-bit
/// read-write scan of EPWM1 (including HR/shadow and packed-32-bit lane
/// writes). The Rust translator accepts exactly one function, cannot express
/// loops / register scans, and cannot pass a local value across the ABI, so the
/// whole scan is sunk into the audited C-ABI wrapper
/// `f28035_epwm1_reg_rw_smoke()`. That wrapper reports the outcome through the
/// shared test runtime (`f28035_test_pass` / `f28035_test_fail`), so this main
/// only performs the call and stays in the translator's supported subset.
///
/// NOTE: `rust_timer0_interrupt` is intentionally NOT defined here. This case
/// does not use Timer0 interrupts; the C bridge's `default_interrupts.c`
/// provides that symbol, so the Rust file must contain exactly one function.
use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    pac::f28035_epwm1_reg_rw_smoke();
}
