#![no_std]
#![no_main]
#![feature(core_intrinsics)]

// Probe: how does the C28x LLVM backend lower a volatile load/store through a
// pointer?  The frozen ABI says Rust pointers are 32-bit logical byte
// addresses and the backend halves them for word accesses, so an MMIO helper
// must double the physical word address before forming the pointer.

#[no_mangle]
#[inline(never)]
pub unsafe fn probe_load_word(addr: u16) -> u16 {
    // Word address used directly as the pointer value.
    unsafe { core::intrinsics::volatile_load(usize::from(addr) as *const u16) }
}

#[no_mangle]
#[inline(never)]
pub unsafe fn probe_load_doubled(addr: u16) -> u16 {
    // Word address doubled into the logical byte pointer.
    unsafe { core::intrinsics::volatile_load((usize::from(addr) << 1) as *const u16) }
}

#[no_mangle]
#[inline(never)]
pub unsafe fn probe_store_doubled(addr: u16, value: u16) {
    unsafe { core::intrinsics::volatile_store((usize::from(addr) << 1) as *mut u16, value) }
}

#[no_mangle]
#[inline(never)]
pub unsafe fn probe_load_doubled_ptr(read_volatile_style: bool, addr: u16) -> u16 {
    let _ = read_volatile_style;
    unsafe { core::intrinsics::volatile_load((usize::from(addr) << 1) as *const u16) }
}
