#![no_std]

/// Rust translation of i2c_master_reg_readback_sweep.
/// Internal I2C-A register read/write smoke sweep (OAR/CLKL/H/CNT/FFCT),
/// no external I2C slave required. The masked readback scan is sunk into
/// `f28035_i2c_reg_readback_sweep_basic()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    peripherals.i2c_a.reg_readback_sweep();
}
