#![no_std]

// C28x peripheral addresses are physical 16-bit word addresses.
struct WordAddress(u16);

impl WordAddress {
    unsafe fn read(self) -> u16 {
        unsafe { (usize::from(self.0) as *const u16).read_volatile() }
    }

    unsafe fn write(self, value: u16) {
        unsafe { (usize::from(self.0) as *mut u16).write_volatile(value) }
    }
}

const GPA_MUX1: WordAddress = WordAddress(0x6f86);
const GPA_DIR: WordAddress = WordAddress(0x6f8a);
const GPA_CLEAR: WordAddress = WordAddress(0x6fc4);
const GPB_MUX1: WordAddress = WordAddress(0x6f96);
const GPB_DIR: WordAddress = WordAddress(0x6f9a);
const GPB_SET: WordAddress = WordAddress(0x6fca);
const GPB_CLEAR: WordAddress = WordAddress(0x6fcc);
const GPIO2_BIT: u16 = 1 << 2;
const GPIO34_BIT: u16 = 1 << 2;

/// Two-pin target experiment: configure GPIO2/34 and leave both low.
#[unsafe(no_mangle)]
pub extern "C" fn rust_bare_gpio34_low() {
    unsafe {
        GPA_MUX1.write(GPA_MUX1.read() & !(3 << 4));
        GPA_DIR.write(GPA_DIR.read() | GPIO2_BIT);
        GPA_CLEAR.write(GPIO2_BIT);

        GPB_MUX1.write(GPB_MUX1.read() & !(3 << 4));
        GPB_DIR.write(GPB_DIR.read() | GPIO34_BIT);
        GPB_SET.write(GPIO34_BIT);
        GPB_CLEAR.write(GPIO34_BIT);
        GPB_MUX1.write(GPB_MUX1.read() & !(3 << 4));
        GPB_DIR.write(GPB_DIR.read() | GPIO34_BIT);
        GPB_CLEAR.write(GPIO34_BIT);
    }
}
