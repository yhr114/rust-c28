#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL version of `gpio_output_readback_basic`.
///
/// This is the Safe HAL registry entry for `gpio_output_readback_basic`.  It
/// mirrors the original C case's write/read sequence (high -> read high,
/// low -> read low, high -> read high) through typed `OutputPin` handles; the
/// body contains no `unsafe` block and no direct FFI declaration.  The C
/// harness (`firmware/gpio34_readback_test.c`) still snapshots final hardware
/// state after this function returns, but the read-back assertion now lives in
/// Rust and is lowered by the MIR backend.
///
/// The linked target symbol is `crates/rust-api::application::rust_gpio34_output_readback`,
/// lowered from optimized MIR into C28x assembly by `backend/c28x-mir`.
///
/// Verified with:
///
/// ```powershell
/// .\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_output_readback_basic
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin34 = peripherals
        .gpio
        .output::<34>()
        .expect("GPIO34 output rejected");

    pin34.set_high();
    if !pin34.is_high() {
        loop {}
    }
    pin34.set_low();
    if !pin34.is_low() {
        loop {}
    }
    pin34.set_high();
    if !pin34.is_high() {
        loop {}
    }
}
