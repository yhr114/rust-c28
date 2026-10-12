#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn mir_chain_add(a: u16, b: u16) -> u16 {
    a.wrapping_add(b)
}

#[unsafe(no_mangle)]
pub extern "C" fn mir_chain_mul(a: u16, b: u16) -> u16 {
    a.wrapping_mul(b)
}

#[unsafe(no_mangle)]
pub extern "C" fn mir_chain_sub(a: u16, b: u16) -> u16 {
    a.wrapping_sub(b)
}

#[unsafe(no_mangle)]
pub extern "C" fn mir_chain_xor(a: u16, b: u16) -> u16 {
    a ^ b
}

#[unsafe(no_mangle)]
pub extern "C" fn mir_add_then_mul(a: u16, b: u16) -> u16 {
    let sum = mir_chain_add(a, b);
    mir_chain_mul(sum, 3u16)
}

#[unsafe(no_mangle)]
pub extern "C" fn mir_xor_then_sub(a: u16, b: u16) -> u16 {
    let mixed = mir_chain_xor(a, b);
    mir_chain_sub(mixed, 0x1234u16)
}

#[unsafe(no_mangle)]
pub extern "C" fn mir_linear_mix(a: u16, b: u16) -> u16 {
    let sum = mir_chain_add(a, b);
    let mixed = mir_chain_xor(sum, 0x1234u16);
    mir_chain_sub(mixed, 7u16)
}

#[unsafe(no_mangle)]
pub extern "C" fn mir_reuse_first_result(a: u16, b: u16) -> u16 {
    let sum = mir_chain_add(a, b);
    let mixed = mir_chain_xor(sum, 0x1234u16);
    mir_chain_sub(mixed, sum)
}

#[unsafe(no_mangle)]
pub extern "C" fn mir_non_lifo_locals(a: u16, b: u16) -> u16 {
    let sum = mir_chain_add(a, b);
    let mixed = mir_chain_xor(sum, 0x1234u16);
    let scaled = mir_chain_mul(mixed, 3u16);
    let reduced = mir_chain_sub(scaled, sum);
    mir_chain_add(reduced, mixed)
}
