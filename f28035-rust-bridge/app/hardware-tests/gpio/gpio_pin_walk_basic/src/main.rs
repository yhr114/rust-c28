#![no_std]

/// Rust translation of fpga_delivery_28035/case_src/gpio/gpio_pin_walk_basic.
///
/// The source C case walks per-pin drive on the GPIO A bank (GPIO0..31) and B
/// bank (GPIO32..44), sweeps mux/qualification patterns, then resets and
/// verifies the mux/direction registers read back zero. The loop and register
/// scans are sunk into the audited C-ABI wrapper `f28035_gpio_pin_walk_smoke()`
/// (self-contained, reports via the shared test runtime), so this main only
/// performs that one FFI call. This case is a pure internal self-check with no
/// external pin jumper, so it is expected to PASS on the bare board.
///
/// NOTE: `rust_timer0_interrupt` is intentionally NOT defined here; the C
/// bridge's `default_interrupts.c` provides that symbol, and the translator
/// requires exactly one Rust function in this file.
use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    pac::f28035_gpio_pin_walk_smoke();
}
