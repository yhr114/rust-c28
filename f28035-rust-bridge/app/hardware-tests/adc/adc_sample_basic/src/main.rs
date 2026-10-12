#![no_std]

use f28035_safe_hal::{Peripherals, system_init};

/// Safe HAL bridge case for one ADC SOC0 sample on channel 0.
///
/// The verified target symbol is
/// `crates/rust-api::application::rust_adc_sample_basic`, which mirrors this
/// body and is lowered from optimized MIR into C28x assembly.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() -> u16 {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    peripherals.adc.sample::<0>()
}
