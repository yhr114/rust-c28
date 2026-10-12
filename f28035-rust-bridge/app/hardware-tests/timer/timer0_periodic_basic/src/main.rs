#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL bridge case for Timer0 10 ms periodic interrupt startup.
///
/// The verified target symbol is
/// `crates/rust-api::application::rust_timer0_periodic_basic`, which mirrors
/// this body and is lowered from optimized MIR into C28x assembly.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    let _timer = peripherals.timer0.start_periodic::<10>();
}
