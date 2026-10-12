#![no_std]

// u16 remainder is now supported via C28x RPT/SUBC hardware divide
// (quotient in ACC low half, remainder in ACC high half).
#[unsafe(no_mangle)]
pub extern "C" fn remainder(a: u16, b: u16) -> u16 {
    a % b
}
