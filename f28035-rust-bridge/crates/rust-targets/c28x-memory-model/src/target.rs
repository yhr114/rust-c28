//! Target bindings for the audited C28x packed-byte runtime.

unsafe extern "C" {
    fn c28x_read_logical_byte(words: *const u16, offset: u16) -> u16;
    fn c28x_write_logical_byte(words: *mut u16, offset: u16, value: u16);
}

/// Reads one logical 8-bit byte from a physical C28x word buffer.
///
/// # Safety
///
/// `words` must be valid for the physical word selected by `offset >> 1`.
pub unsafe fn read(words: *const u16, offset: u16) -> u8 {
    // SAFETY: the caller supplies the validity required by the target runtime.
    unsafe { c28x_read_logical_byte(words, offset) as u8 }
}

/// Writes one logical byte without changing its adjacent packed byte.
///
/// # Safety
///
/// `words` must be writable for the physical word selected by `offset >> 1`.
/// It must point to ordinary RAM, never to an MMIO register.
pub unsafe fn write(words: *mut u16, offset: u16, value: u8) {
    // SAFETY: the caller supplies the validity and non-MMIO requirements.
    unsafe { c28x_write_logical_byte(words, offset, value as u16) }
}
