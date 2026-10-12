#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL version of `gpio_mux_dynamic_switch_basic`.
///
/// Mirrors the original C case: GPIO0 MUX routed 0 (GPIO) -> 1 (EPWM1A) ->
/// 0 (GPIO), with the bridge-result guard folded into each `set_mux` call.
/// The original C read back `GPAMUX1.GPIO0` after every step and failed with
/// 0x0b01/0x0b02/0x0b03 if the field did not match; the typed `set_mux`
/// returns `Err` on any rejected function encoding, which the `.expect(...)`
/// turns into a panic (the test runtime maps that to FAIL) — equivalent
/// guard, no `unsafe` block, no direct FFI declaration.
///
/// On-target verification reuses the two-phase harness from
/// `gpio_mux_basic`: a single call only shows the final 0, so the C harness
/// snapshots GPAMUX1.GPIO0 between `rust_gpio0_mux_to_epwm1a` (must read 1)
/// and `rust_gpio0_mux_restore_gpio` (must read 0).
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
