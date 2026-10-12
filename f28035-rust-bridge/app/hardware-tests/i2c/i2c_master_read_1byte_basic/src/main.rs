#![no_std]

/// Rust translation of i2c_master_read_1byte_basic.
/// Master read 1 byte from slave 0x36, verify 0xDE. Requires an external
/// I2C slave device on the bus. The I2C-A master sequence + status poll
/// loop is sunk into `f28035_i2c_master_read_1byte_basic()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _slave = peripherals.i2c_a.master_read_1byte::<0x36>();
}
