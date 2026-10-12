#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL version of `gpio_toggle_basic`.
///
/// This is the Safe HAL registry entry for `gpio_toggle_basic`.  It mirrors
/// the original C case: GPIO34 starts low, then toggles `GPIO_TOGGLE_BASIC_COUNT`
/// (8, an even count) times, so the final level is low again.  The body uses
/// typed `OutputPin` handles (`set_low` + eight `toggle` calls); no `unsafe`
/// block, no direct FFI declaration.
///
/// The read-back proof is performed by the C harness
/// (`firmware/gpio34_toggle_test.c`) after this function returns: it reads
/// `GPBDAT` (must be 0 after 8 even toggles), then issues two TOGGLE commands
/// of its own and records 1 then 0, proving the toggle path flips the pin.
///
/// The linked target symbol is `crates/rust-api::application::rust_gpio34_toggle_basic`,
/// lowered from optimized MIR into C28x assembly by `backend/c28x-mir`.
///
/// Verified with:
///
/// ```powershell
/// .\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_toggle_basic
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin34 = peripherals
        .gpio
        .output::<34>()
        .expect("GPIO34 output rejected");

    pin34.set_low();
    pin34.toggle(); // 1
    pin34.toggle(); // 2
    pin34.toggle(); // 3
    pin34.toggle(); // 4
    pin34.toggle(); // 5
    pin34.toggle(); // 6
    pin34.toggle(); // 7
    pin34.toggle(); // 8 (even -> back to low)
}
