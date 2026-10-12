// Reference user program for the one-file path.
//
// NOTE: this file is not itself compiled by tools/run-user-main.ps1; the
// script MIR-dumps crates/rust-api/src/lib.rs, which includes user_main.rs.
// This file is kept here as a copy of the user-facing entry point so the
// GPIO call style stays in sync with the current HAL API in
// crates/rust-api/src/lib.rs. When editing the HAL, mirror changes here.

use f28035_safe_hal::{Peripherals, system_init};

#[unsafe(no_mangle)]
pub extern "C" fn rust_user_main() -> u16 {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut gpio30 = peripherals.gpio().output::<30>().expect("gpio30");
    let mut gpio34 = peripherals.gpio().output::<34>().expect("gpio34");

    gpio30.set_low();
    gpio34.set_low();

    let mut count = 0_u16;
    while count < 5 {
        if count & 1 == 0 {
            gpio30.toggle();
        } else {
            gpio34.set_high();
        }
        count = count.wrapping_add(1);
    }

    let observed = gpio30.is_high() as u16;
    let computed = ((observed.wrapping_mul(0x8001).wrapping_add(1)) ^ 0x7fff)
        .wrapping_sub(observed)
        | observed;
    gpio34.set_low();
    if computed > 0x8000 {
        gpio34.set_high();
    }
    computed
}
