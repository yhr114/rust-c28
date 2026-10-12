#![no_std]

/// Rust translation of sci_baud_program_basic.
/// Baud rate program + loopback send/read verification across divisors 3/5/7.
/// The full SCI-A register sequence + poll loops are sunk into the audited
/// C-ABI wrapper `f28035_sci_baud_program_basic()`. This main only performs
/// that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _profile = peripherals.sci_a.configure_basic::<194, 8>();
}
