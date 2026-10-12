#![no_std]

// if/else with non-Add/Sub operations in both branches.
#[unsafe(no_mangle)]
pub extern "C" fn branch_mul_div(a: u16, b: u16) -> u16 {
    if a > b {
        a * b
    } else {
        a / b
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_and_or(a: u16, b: u16) -> u16 {
    if a == b {
        a & b
    } else {
        a | b
    }
}
