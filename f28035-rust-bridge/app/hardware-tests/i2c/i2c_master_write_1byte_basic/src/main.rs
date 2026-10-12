#![no_std]

/// Rust translation of i2c_master_write_1byte_basic.
/// Master write 1 byte (0x5A) to slave 0x36. Requires an external I2C slave.
/// The I2C-A master write sequence + status poll loop is still implemented by
/// the C-ABI bridge, but this business entry now uses the typed I2C-A HAL
/// handle and carries the 7-bit slave address in the type.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _slave = peripherals.i2c_a.master_write_1byte::<0x36>();
}
