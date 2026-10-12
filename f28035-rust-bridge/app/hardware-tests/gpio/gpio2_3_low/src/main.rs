#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL version of `gpio2_3_low`.
///
/// This is the Safe HAL registry entry for `gpio2_3_low`.  It configures GPIO2
/// and GPIO3 as outputs and drives both low through typed `OutputPin` handles;
/// the body contains no `unsafe` block and no direct FFI declaration.  The C
/// harness (`firmware/gpio2_3_low_test.c`) snapshots both pins' MUX/DIR/DATA
/// after this function returns; the JTAG judge requires MUX=0, DIR=1, DATA=0
/// for both pins.
///
/// The linked target symbol is `crates/rust-api::application::rust_gpio2_3_low`,
/// lowered from optimized MIR into C28x assembly by `backend/c28x-mir`.
///
/// Verified with:
///
/// ```powershell
/// .\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio2_3_low
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin2 = peripherals
        .gpio
        .output::<2>()
        .expect("GPIO2 output rejected");
    let mut pin3 = peripherals
        .gpio
        .output::<3>()
        .expect("GPIO3 output rejected");

    pin2.set_low();
    pin3.set_low();
}
