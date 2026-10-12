#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL version of `gpio30_low`.
///
/// This is the Safe HAL registry entry for `gpio30_low`.  It configures GPIO30
/// as an output and drives it low through a typed `OutputPin` handle; the body
/// contains no `unsafe` block and no direct FFI declaration.  The C harness
/// (`firmware/gpio30_low_test.c`) snapshots MUX/DIR/DATA after this function
/// returns; the JTAG judge requires MUX=0, DIR=1, DATA=0.
///
/// The linked target symbol is `crates/rust-api::application::rust_gpio30_low`,
/// lowered from optimized MIR into C28x assembly by `backend/c28x-mir`.
///
/// Verified with:
///
/// ```powershell
/// .\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio30_low
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin30 = peripherals
        .gpio
        .output::<30>()
        .expect("GPIO30 output rejected");

    pin30.set_low();
}
