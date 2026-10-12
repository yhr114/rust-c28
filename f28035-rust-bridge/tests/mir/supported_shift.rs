#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn shl(a: u16, b: u16) -> u16 {
    a << b
}

#[unsafe(no_mangle)]
pub extern "C" fn shr(a: u16, b: u16) -> u16 {
    a >> b
}
