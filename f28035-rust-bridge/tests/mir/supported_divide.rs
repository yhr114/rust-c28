#![no_std]

// u16 division is now supported via C28x RPT/SUBC hardware divide.
#[unsafe(no_mangle)]
pub extern "C" fn divide(a: u16, b: u16) -> u16 {
    a / b
}
