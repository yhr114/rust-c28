#![feature(abi_c28x_interrupt)]
#![no_std]
#![no_main]

mod builtins;

use c28x_pac::Peripherals;

extern "C" { fn enable_int(); }

#[no_mangle]
pub extern "C" fn main() -> ! {
    let p = unsafe { Peripherals::steal() };
    let _ea = p.eallow();
    unsafe {
        p.gpio.gpbmux1.modify(|v| v & !(3 << 4), &_ea);
        p.gpio.gpbdir.modify(|v| v | (1 << 2), &_ea);
        p.gpio.gpbclear.write(1u32 << 2);
    }
    loop {
        unsafe { enable_int(); }
    }
}

#[no_mangle]
pub extern "c28x-interrupt" fn TINT0_handler() {
    let p = unsafe { Peripherals::steal() };
    unsafe { p.gpio.gpbtoggle.write(1u32 << 2); }
    // TCR at word 0x0C04 -> byte addr 0x1808
    // Clear TIF (bit15 w1c), keep TIE (bit14=1), TSS=0 (running): write 0xC000
    unsafe { core::ptr::write_volatile(0x1808 as *mut u16, 0xC000); }
    // Clear PIEACK group1 (PIEACK at word 0x0CE1 -> byte addr 0x19C2)
    unsafe { core::ptr::write_volatile(0x19C2 as *mut u16, 0x0001); }
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! { loop {} }
