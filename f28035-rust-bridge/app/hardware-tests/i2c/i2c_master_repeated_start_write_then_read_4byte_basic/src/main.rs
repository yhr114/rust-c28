#![no_std]

/// Rust translation of i2c_master_repeated_start_write_then_read_4byte_basic.
/// Master write-no-stop (4 bytes) then repeated-start read, verify round-trip.
/// Requires an external I2C slave. The write-no-stop + repeated-start read
/// sequences are sunk into `f28035_i2c_master_repeated_start_write_then_read_4byte_basic()`.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _slave = peripherals
        .i2c_a
        .repeated_start_write_then_read_4byte::<0x36>();
}
