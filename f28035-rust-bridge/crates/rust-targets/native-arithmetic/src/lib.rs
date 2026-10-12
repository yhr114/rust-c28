#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_add(a: u16, b: u16) -> u16 {
    a.wrapping_add(b)
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_sub(a: u16, b: u16) -> u16 {
    a.wrapping_sub(b)
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_mul(a: u16, b: u16) -> u16 {
    a.wrapping_mul(b)
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_xor(a: u16, b: u16) -> u16 {
    a ^ b
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_not(value: u16) -> u16 {
    !value
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_max(a: u16, b: u16) -> u16 {
    if a >= b { a } else { b }
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_min(a: u16, b: u16) -> u16 {
    if a <= b { a } else { b }
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_add_three(value: u16) -> u16 {
    let adjusted = value.wrapping_add(3u16);
    adjusted
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_native_add_large(value: u16) -> u16 {
    let adjusted = value.wrapping_add(4660u16);
    adjusted
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_unpack_low_byte(word: u16) -> u16 {
    word & 0x00ffu16
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_unpack_high_byte(word: u16) -> u16 {
    word >> 8u16
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_write_low_byte(word: u16, value: u16) -> u16 {
    (word & 0xff00u16) | (value & 0x00ffu16)
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_write_high_byte(word: u16, value: u16) -> u16 {
    (word & 0x00ffu16) | ((value & 0x00ffu16) << 8u16)
}

#[cfg(test)]
mod tests {
    use super::{
        rust_native_add, rust_native_add_large, rust_native_add_three, rust_native_max,
        rust_native_min, rust_native_mul, rust_native_not, rust_native_sub, rust_native_xor,
        rust_unpack_high_byte, rust_unpack_low_byte, rust_write_high_byte, rust_write_low_byte,
    };

    #[test]
    fn wrapping_boundaries_match_rust() {
        assert_eq!(rust_native_add(u16::MAX, 2), 1);
        assert_eq!(rust_native_sub(2, 5), u16::MAX - 2);
        assert_eq!(rust_native_sub(0, 1), u16::MAX);
        assert_eq!(rust_native_mul(u16::MAX, 2), 65534);
        assert_eq!(rust_native_mul(0x8001, 3), 0x8003);
        assert_eq!(rust_native_xor(0x55aa, 0x0ff0), 0x5a5a);
        assert_eq!(rust_native_not(0x55aa), 0xaa55);
        assert_eq!(rust_native_max(2, 5), 5);
        assert_eq!(rust_native_max(u16::MAX, 5), u16::MAX);
        assert_eq!(rust_native_max(7, 7), 7);
        assert_eq!(rust_native_add_three(u16::MAX), 2);
        assert_eq!(rust_native_add_large(u16::MAX), 4659);
        assert_eq!(rust_native_min(0, u16::MAX), 0);
        assert_eq!(rust_native_min(u16::MAX, 2), 2);
        assert_eq!(rust_unpack_low_byte(0x2211), 0x11);
        assert_eq!(rust_unpack_high_byte(0x2211), 0x22);
        assert_eq!(rust_write_low_byte(0x2211, 0x01aa), 0x22aa);
        assert_eq!(rust_write_high_byte(0x2211, 0x01bb), 0xbb11);
    }
}
