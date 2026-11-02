#![no_std]
#![no_main]

extern "C" {
    fn c28x_memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8;
    fn c28x_memmove(dst: *mut u8, src: *const u8, n: usize) -> *mut u8;
    fn c28x_memset(dst: *mut u8, value: u8, n: usize) -> *mut u8;
    fn c28x_memcmp(a: *const u8, b: *const u8, n: usize) -> i32;
    fn c28x_bcmp(a: *const u8, b: *const u8, n: usize) -> i32;
}

#[no_mangle]
#[inline(never)]
pub unsafe extern "C" fn rust_memory_copy(d: *mut u8, s: *const u8, n: usize) -> u32 {
    c28x_memcpy(d, s, n) as u32
}
#[no_mangle]
#[inline(never)]
pub unsafe extern "C" fn rust_memory_copy_intrinsic(d: *mut u8, s: *const u8, n: usize) -> u32 {
    core::ptr::copy_nonoverlapping(s, d, n);
    d as u32
}
#[no_mangle]
#[inline(never)]
pub unsafe extern "C" fn rust_memory_move(d: *mut u8, s: *const u8, n: usize) -> u32 {
    c28x_memmove(d, s, n) as u32
}
#[no_mangle]
#[inline(never)]
pub unsafe extern "C" fn rust_memory_move_intrinsic(d: *mut u8, s: *const u8, n: usize) -> u32 {
    core::ptr::copy(s, d, n);
    d as u32
}
#[no_mangle]
#[inline(never)]
pub unsafe extern "C" fn rust_memory_fill(d: *mut u8, n: usize, value: u16) -> u32 {
    c28x_memset(d, value as u8, n) as u32
}
#[no_mangle]
#[inline(never)]
pub unsafe extern "C" fn rust_memory_fill_intrinsic(d: *mut u8, n: usize, value: u16) -> u32 {
    core::ptr::write_bytes(d, value as u8, n);
    d as u32
}
#[no_mangle]
#[inline(never)]
pub unsafe extern "C" fn rust_memory_compare(a: *const u8, b: *const u8, n: usize) -> i32 {
    c28x_memcmp(a, b, n)
}
#[no_mangle]
#[inline(never)]
pub unsafe extern "C" fn rust_memory_bcmp(a: *const u8, b: *const u8, n: usize) -> i32 {
    c28x_bcmp(a, b, n)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! { loop {} }
