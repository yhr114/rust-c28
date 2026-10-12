#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL version of `gpio_direction_switch_basic`.
///
/// This is the Safe HAL registry entry for `gpio_direction_switch_basic`.  It
/// drives GPIO34 as an output high, reconfigures the same pin as an input via
/// `OutputPin::into_input` (the consuming direction-switch handle transfer,
/// which releases the exclusive claim), then reconfigures it back as an output
/// and drives it low.  The body contains no `unsafe` block and no direct FFI
/// declaration.
///
/// The C harness (`firmware/gpio34_direction_switch_test.c`) snapshots MUX,
/// DIR, DATA and the input-stage residue (GPBQSEL1 = Sync, GPBPUD = pull-up
/// enabled) after this function returns; the JTAG judge requires the final
/// state to be an output low and the input residue to prove the pin really
/// switched through the input configuration.
///
/// The linked target symbol is `crates/rust-api::application::rust_gpio34_direction_switch`,
/// lowered from optimized MIR into C28x assembly by `backend/c28x-mir`.
///
/// Verified with:
///
/// ```powershell
/// .\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_direction_switch_basic
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

    let input34 = pin34
        .into_input(&mut peripherals.gpio)
        .expect("GPIO34 input rejected");

    let mut pin34 = input34
        .into_output(&mut peripherals.gpio)
        .expect("GPIO34 output rejected");
    pin34.set_low();
}
