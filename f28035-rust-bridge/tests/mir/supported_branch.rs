#![no_std]

// if/else: return a+b if a > b, else return a-b
#[unsafe(no_mangle)]
pub extern "C" fn branch(a: u16, b: u16) -> u16 {
    if a > b {
        a + b
    } else {
        a - b
    }
}
