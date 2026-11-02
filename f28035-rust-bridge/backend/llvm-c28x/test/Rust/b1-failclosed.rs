#![no_std]
#![feature(core_intrinsics)]

#[unsafe(no_mangle)]
pub extern "C" fn trap_guard() -> ! {
    core::intrinsics::abort()
}

// At O0, basic-block-sections splits the conditional's destinations into
// separate sections. C28x must refuse this unsupported PC-relative relocation.
#[unsafe(no_mangle)]
pub extern "C" fn branch_guard(a: u16, b: u16) -> u16 {
    if a == b { a.wrapping_add(1) } else { b.wrapping_add(2) }
}
