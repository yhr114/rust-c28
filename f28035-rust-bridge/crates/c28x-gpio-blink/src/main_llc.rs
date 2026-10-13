#![no_std]
#![no_main]

// F28035 GPIO 寄存器字地址（byte addr = word * 2）
// GPBMUX1: 0x6F96, GPBDIR: 0x6F9A, GPBCLEAR: 0x6FC4, GPBTOGGLE: 0x6FCE
// EALLOW/EDIS 寄存器: 0x7029

extern "C" { fn enable_int(); }

#[inline(always)]
unsafe fn write_reg(word_addr: u16, value: u16) {
    let byte_addr = (word_addr as u32) * 2;
    core::ptr::write_volatile(byte_addr as *mut u16, value);
}

#[inline(always)]
unsafe fn read_reg(word_addr: u16) -> u16 {
    let byte_addr = (word_addr as u32) * 2;
    core::ptr::read_volatile(byte_addr as *const u16)
}

#[no_mangle]
pub extern "C" fn main() -> ! {
    unsafe {
        // EALLOW: 写 0x5A5A 到 0x7029
        write_reg(0x7029, 0x5A5A);

        // GPBMUX1: GPIO34 设为 GPIO 功能（清 bit8-9）
        let mux = read_reg(0x6F96);
        write_reg(0x6F96, mux & !(3 << 4));

        // GPBDIR: GPIO34 设为输出（bit2 = 1）
        let dir = read_reg(0x6F9A);
        write_reg(0x6F9A, dir | (1 << 2));

        // GPBCLEAR: 先拉低 GPIO34
        write_reg(0x6FC4, 1 << 2);

        // EDIS: 写 0xA5A5
        write_reg(0x7029, 0xA5A5);
    }
    loop {
        unsafe { enable_int(); }
    }
}

#[no_mangle]
pub extern "C" fn TINT0_handler() {
    unsafe {
        // GPBTOGGLE: 翻转 GPIO34
        write_reg(0x6FCE, 1 << 2);
        // TCR at word 0x0C04 -> byte addr 0x1808
        // Clear TIF (bit15 w1c), keep TIE (bit14=1): write 0xC000
        write_reg(0x0C04, 0xC000);
        // Clear PIEACK group1 (PIEACK at word 0x0CE1 -> byte addr 0x19C2)
        write_reg(0x0CE1, 0x0001);
    }
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! { loop {} }
