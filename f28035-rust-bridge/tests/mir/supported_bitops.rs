#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn bitand(a: u16, b: u16) -> u16 {
    a & b
}

#[unsafe(no_mangle)]
pub extern "C" fn bitor(a: u16, b: u16) -> u16 {
    a | b
}
