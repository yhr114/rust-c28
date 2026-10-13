#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> ! {
    unsafe {
        // 直接写寄存器：EALLOW
        let p = 0x7029 as *mut u16;
        *p = 0x5A5A;
        
        // GPBDIR: GPIO34 设为输出
        let p2 = 0x6F9A as *mut u16;
        *p2 = *p2 | (1 << 2);
        
        loop {
            // GPBTOGGLE: 翻转 GPIO34
            let p3 = 0x6FCE as *mut u16;
            *p3 = *p3 | (1 << 2);
        }
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
