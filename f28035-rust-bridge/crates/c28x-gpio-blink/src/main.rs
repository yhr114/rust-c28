#![no_std]
#![no_main]

mod builtins;

use c28x_pac::Peripherals;

#[no_mangle]
pub extern "C" fn main() -> ! {
    let p = match Peripherals::take() {
        Some(p) => p,
        None => loop {},
    };

    // GPIO34 = GPIOB bit2: configure as GPIO output, start low
    let _ea = p.eallow();  // EALLOW protects mux/dir/pud writes
    unsafe {
        p.gpio.gpbmux1.modify(|v| v & !(3 << 4), &_ea);  // MUX bits 5:4 = 00 (GPIO)
        p.gpio.gpbdir.modify(|v| v | (1 << 2), &_ea);    // DIR bit2 = 1 (output)
    }
    // gpbdat write is NOT EALLOW-protected — no token needed
    unsafe { p.gpio.gpbdat.modify(|v| v & !(1 << 2)); }   // start low
    // _ea dropped here → EDIS

    // Interrupts (PIE + Timer0 + CPU IER + INTM) are configured in startup asm.
    // Just idle — Timer0 ISR toggles GPIO34.
    loop {}
}

/// Timer0 interrupt handler (overrides weak TINT0_handler in assembly).
#[no_mangle]
pub extern "C" fn TINT0_handler() {
    unsafe {
        let p = Peripherals::steal();
        p.gpio.gpbtoggle.write(1 << 2);   // toggle GPIO34
        p.cputimer0.clear_flag();          // clear TIF
        p.piectrl.ack_group(1);            // ack PIE group 1
    }
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    unsafe {
        let p = Peripherals::steal();
        // Initialize SCI-A at 9600 baud (LSPCLK = 30MHz)
        p.scia.init(9600, 30_000_000);
        // Output "PANIC\r\n"
        p.scia.write_str("PANIC\r\n");
    }
    loop {}
}
