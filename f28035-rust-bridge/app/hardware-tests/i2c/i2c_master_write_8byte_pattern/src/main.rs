#![no_std]

/// Rust translation of i2c_master_write_8byte_pattern.
/// Master write 8-byte pattern (00 11 22 33 44 55 66 77) to slave 0x36.
/// Requires an external I2C slave. The I2C-A master write sequence + status
/// poll loop is sunk into `f28035_i2c_master_write_8byte_pattern()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _slave = peripherals.i2c_a.master_write_8byte_pattern::<0x36>();
}
