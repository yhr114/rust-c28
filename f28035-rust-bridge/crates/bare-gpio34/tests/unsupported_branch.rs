#![no_std]

#[derive(Clone, Copy)]
struct WordAddress(u16);

impl WordAddress {
    unsafe fn read(self) -> u16 {
        unsafe { (usize::from(self.0) as *const u16).read_volatile() }
    }

    unsafe fn write(self, value: u16) {
        unsafe { (usize::from(self.0) as *mut u16).write_volatile(value) }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_bare_gpio34_low() {
    let address = WordAddress(0x6f96);
    unsafe {
        let value = address.read();
        if value & 1 != 0 {
            address.write(value | 4);
        } else {
            address.write(value & !4);
        }
    }
}
