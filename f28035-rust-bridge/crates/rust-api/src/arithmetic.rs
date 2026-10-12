/// First Rust-to-C28x ABI validation function.
///
/// This deliberately uses only `u16` and wrapping addition.  On C28x the
/// addressable C byte is 16 bits, so the generator verifies that TI C's
/// `unsigned short` has exactly the same 0..=65535 value range.
#[unsafe(no_mangle)]
pub extern "C" fn rust_add(a: u16, b: u16) -> u16 {
    a.wrapping_add(b)
}

#[cfg(test)]
mod tests {
    use super::rust_add;

    #[test]
    fn adds_without_overflow() {
        assert_eq!(rust_add(20, 22), 42);
    }

    #[test]
    fn wraps_at_u16_boundary() {
        assert_eq!(rust_add(u16::MAX, 2), 1);
    }
}
