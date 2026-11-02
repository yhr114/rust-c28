#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn rust_div_u32(a: u32, b: u32) -> u32 { a / b }
#[no_mangle]
pub extern "C" fn rust_rem_u32(a: u32, b: u32) -> u32 { a % b }
#[no_mangle]
pub extern "C" fn rust_div_i32(a: i32, b: i32) -> i32 { a / b }
#[no_mangle]
pub extern "C" fn rust_rem_i32(a: i32, b: i32) -> i32 { a % b }

// Raw bit operands keep the C/Rust oracle independent of the C compiler's
// constant folding of floating-point expressions.
#[no_mangle]
pub extern "C" fn rust_add_f32(a: u32, b: u32) -> u32 {
    (f32::from_bits(a) + f32::from_bits(b)).to_bits()
}
#[no_mangle]
pub extern "C" fn rust_sub_f32(a: u32, b: u32) -> u32 {
    (f32::from_bits(a) - f32::from_bits(b)).to_bits()
}
#[no_mangle]
pub extern "C" fn rust_mul_f32(a: u32, b: u32) -> u32 {
    (f32::from_bits(a) * f32::from_bits(b)).to_bits()
}
#[no_mangle]
pub extern "C" fn rust_div_f32(a: u32, b: u32) -> u32 {
    (f32::from_bits(a) / f32::from_bits(b)).to_bits()
}

static LOCATION: u16 = 9;
extern "C" {
    fn check_four(p: *const u16, count: u32, size: u32, location: *const u16) -> u32;
}
#[no_mangle]
pub extern "C" fn rust_call_four(p: *const u16, count: u32) -> u32 {
    unsafe { check_four(p, count, 2, &LOCATION) }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! { loop {} }
