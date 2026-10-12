#![no_std]

/// Rust translation of i2c_master_read_back_to_back_basic.
/// Two back-to-back master reads of 4 bytes each from slave 0x36, verifying
/// DE AD BE EF each time. Requires an external I2C slave. The two read
/// sequences + status poll loops are sunk into
/// `f28035_i2c_master_read_back_to_back_basic()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _slave = peripherals.i2c_a.master_read_back_to_back::<0x36>();
}
