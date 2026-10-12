//! F28035 GPIO34 toggle — built with real cargo + patched rustc.
//!
//! Built for `c28x-none-elf`, no_std / no_main. The entry point `main` is
//! called by the RAM startup stub (cargo_blink_start.asm) after SP setup
//! and watchdog disable. It configures GPIO34 (GPIOB bit 2) as a GPIO
//! output and toggles it in a loop.
//!
//! F28035 register word addresses (verified on-board via crates/bare-gpio34):
//!   GPBMUX1  0x6F96   GPIO32..37 mux; bits 5:4 select GPIO34 (00=GPIO)
//!   GPBDIR   0x6F9A   direction; bit2 = GPIO34 (1 = output)
//!   GPBTOGGLE 0x6FCE  toggle; bit2 = GPIO34
//!
//! The LLVM C28x backend uses 8-bit char pointers (byte addresses), so the
//! pointer value must be the word address ×2.  The backend's indirect-load
//! lowering does ROR ACC (÷2) to convert back to a word address.
//!
//! Volatile access goes through core::intrinsics::volatile_load/store to
//! bypass core's precondition_check UB wrapper (which instantiates
//! maybe_is_aligned and triggers a TI linker internal error on the
//! C28x relocation expansion).

#![no_std]
#![no_main]
#![feature(core_intrinsics)]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[inline(always)]
unsafe fn rd(addr: u16) -> u16 {
    unsafe { core::intrinsics::volatile_load(addr as *const u16) }
}

#[inline(always)]
unsafe fn wr(addr: u16, val: u16) {
    unsafe { core::intrinsics::volatile_store(addr as *mut u16, val) }
}

// Byte addresses (word address ×2) — backend does ÷2 on indirect access.
const GPBMUX1: u16 = 0x6F96 * 2;
const GPBDIR: u16 = 0x6F9A * 2;
const GPBTOGGLE: u16 = 0x6FCE * 2;

#[no_mangle]
pub extern "C" fn main() -> ! {
    unsafe {
        // GPIO34 = GPIOB bit2: mux bits 5:4 -> 00 (GPIO function)
        wr(GPBMUX1, rd(GPBMUX1) & !(3 << 4));
        // GPIOB bit2 -> output
        wr(GPBDIR, rd(GPBDIR) | (1 << 2));
        loop {
            wr(GPBTOGGLE, 1 << 2);
            // crude delay so the pin toggles at a visible rate
            let mut d: u32 = 0;
            while d < 30_000 {
                d += 1;
            }
        }
    }
}
