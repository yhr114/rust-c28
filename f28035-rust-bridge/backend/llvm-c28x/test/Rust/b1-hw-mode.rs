#[repr(u16)]
enum Mode {
    Add = 0,
    Double = 1,
    Subtract = 2,
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_mode(tag: u16, value: u16) -> u16 {
    let mode = match tag {
        0 => Mode::Add,
        1 => Mode::Double,
        _ => Mode::Subtract,
    };
    match mode {
        Mode::Add => value.wrapping_add(3),
        Mode::Double => value.wrapping_mul(2),
        Mode::Subtract => value.wrapping_sub(1),
    }
}
