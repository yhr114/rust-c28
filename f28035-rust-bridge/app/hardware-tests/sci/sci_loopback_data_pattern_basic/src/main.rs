#![no_std]

/// Rust translation of sci_loopback_data_pattern_basic.
/// 4-pattern loopback data verification (0x00/0x55/0xAA/0xFF). The full
/// SCI-A register sequence + poll loops are sunk into the audited C-ABI
/// wrapper `f28035_sci_loopback_data_pattern_basic()`. This main only
/// performs that one FFI call.
use f28035_safe_hal::{system_init, Peripherals};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let _profile = peripherals.sci_a.loopback_data_pattern::<194, 8>();
}
