#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL version of `gpio_mux_basic`.
///
/// This is the Safe HAL registry entry for `gpio_mux_basic`.  It routes GPIO0
/// through the full MUX round trip of the original C case: 0 (GPIO) -> 1
/// (EPWM1A) -> 0 (GPIO), using the typed `Gpio::set_mux` method, which
/// programs GPAMUX1 and guards the bridge result.  The body contains no
/// `unsafe` block and no direct FFI declaration.
///
/// On-target verification splits the round trip into two linked mirror
/// functions (`rust_gpio0_mux_to_epwm1a` then `rust_gpio0_mux_restore_gpio`)
/// so the C harness can snapshot GPAMUX1.GPIO0 in the middle (must be 1) and
/// after the restore (must be 0) — a single call could only ever show the
/// final 0 and could not prove the intermediate 1 appeared.
///
/// Verified with:
///
/// ```powershell
/// .\tools\verify-mir-gpio0-mux.ps1
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    peripherals
        .gpio
        .set_mux::<0, 0>()
        .expect("GPIO0 MUX to GPIO rejected");
    peripherals
        .gpio
        .set_mux::<0, 1>()
        .expect("GPIO0 MUX to EPWM1A rejected");
    peripherals
        .gpio
        .set_mux::<0, 0>()
        .expect("GPIO0 MUX restore to GPIO rejected");
}
