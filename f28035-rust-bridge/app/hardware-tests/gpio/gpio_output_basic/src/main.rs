#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL version of `gpio_output_basic`.
///
/// This app case is verified with:
///
/// ```powershell
/// .\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_output_basic
/// ```
///
/// The legacy `build-case.ps1` Rust-to-C translator is intentionally bypassed
/// for this case because the safety evidence requires the rustc -> c28x-mir
/// route.  The linked target symbol is currently
/// `crates/rust-api::application::rust_gpio34_output_basic`, which mirrors
/// this body and is lowered from optimized MIR into C28x assembly.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin34 = peripherals
        .gpio
        .output::<34>()
        .expect("GPIO34 output rejected");

    pin34.set_low();
    pin34.set_high();
    pin34.set_low();
}
