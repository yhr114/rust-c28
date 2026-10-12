#![no_std]

/// Rust translation of fpga_delivery_28035/case_src/gpio/gpio_xint_falling_basic.
///
/// The source C case drives GPIO30, wires XINT1 to GPIO0 on the falling edge,
/// waits for the ISR to fire (GPIO30 must be jumpered to GPIO0 on the board),
/// then verifies at least one edge was seen. The ISR + PIE vector hookup +
/// wait loop are sunk into the audited C-ABI wrapper
/// `f28035_gpio_xint_falling_smoke()` (self-contained, reports via the shared
/// test runtime), so this main only performs that one FFI call.
///
/// EXTERNAL-DEPENDENT: requires a GPIO30 -> GPIO0 jumper. On a bare board with
/// no jumper the edge never arrives and this case FAILs (fail code 0x0901);
/// that is an expected hardware prerequisite, not a migration defect.
///
/// NOTE: `rust_timer0_interrupt` is intentionally NOT defined here; the C
/// bridge's `default_interrupts.c` provides that symbol, and the translator
/// requires exactly one Rust function in this file.
use f28035_safe_hal::{system_init, pac};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    pac::f28035_gpio_xint_falling_smoke();
}
