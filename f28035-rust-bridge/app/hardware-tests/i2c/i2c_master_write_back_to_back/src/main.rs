#![no_std]

/// Rust translation of i2c_master_write_back_to_back.
/// Two back-to-back master writes: 4 bytes then 6 bytes to slave 0x36.
/// Requires an external I2C slave. The two write sequences + status poll
/// loops are sunk into `f28035_i2c_master_write_back_to_back()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _slave = peripherals.i2c_a.master_write_back_to_back::<0x36>();
}
