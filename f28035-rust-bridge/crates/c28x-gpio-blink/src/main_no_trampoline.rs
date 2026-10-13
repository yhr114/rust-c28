#![no_std]
#![no_main]
// 启用 c28x-interrupt ABI（需要打了补丁的 rustc）
#![feature(abi_c28x_interrupt)]

use c28x_pac::Peripherals;

#[no_mangle]
pub extern "C" fn main() -> ! {
    let p = match Peripherals::take() {
        Some(p) => p,
        None => loop {},
    };

    // GPIO34 = GPIOB bit2: configure as GPIO output, start low
    let _ea = p.eallow();
    unsafe {
        p.gpio.gpbmux1.modify(|v| v & !(3 << 4), &_ea);  // MUX bits 5:4 = 00 (GPIO)
        p.gpio.gpbdir.modify(|v| v | (1 << 2), &_ea);    // DIR bit2 = 1 (output)
    }
    unsafe { p.gpio.gpbdat.modify(|v| v & !(1 << 2)); }   // start low (not EALLOW-protected)

    // Interrupts (PIE + Timer0 + CPU IER + INTM) are configured in startup asm.
    // Just idle — Timer0 ISR toggles GPIO34.
    loop {}
}

/// Timer0 interrupt handler (overrides weak TINT0_handler in assembly).
/// 使用 c28x-interrupt 调用约定：函数直接以 IRET 返回，无需 trampoline。
/// C28x 硬件在中断入口自动保存全部寄存器（ACC/P/XT/XAR0-7/ST0/ST1/DP/SP/PC），
/// IRET 时自动恢复——因此函数体不需要额外的 prologue/epilogue。
#[no_mangle]
pub extern "c28x-interrupt" fn TINT0_handler() {
    unsafe {
        let p = Peripherals::steal();
        p.gpio.gpbtoggle.write(1 << 2);   // toggle GPIO34
        p.cputimer0.clear_flag();          // clear TIF
        p.piectrl.ack_group(1);            // ack PIE group 1
    }
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
