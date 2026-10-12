#![no_std]

/// Rust translation of i2c_master_addr_nack_stop_basic.
/// Master NACK/stop condition check: write 1 byte to slave 0x36, expect NACK
/// or stop on a bare board (no external slave). The full I2C-A master
/// register sequence + status poll loop is sunk into the C-ABI wrapper
/// `f28035_i2c_master_addr_nack_stop_basic()` (self-contained, reports via
/// the shared test runtime). This main only performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _slave = peripherals.i2c_a.addr_nack_stop::<0x36>();
}
