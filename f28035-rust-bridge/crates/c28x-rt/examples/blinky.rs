//! Minimal blinky for F28035 using c28x-rt.
//!
//! Build (once a C28x Rust target exists):
//!   cargo build --target c28x-none-elf --example blinky
//!
//! This example documents the intended usage pattern; it will not compile
//! until a LLVM C28x backend is available.

#![no_std]
#![no_main]

use c28x_rt::{entry, interrupt, pre_init};

/// Runs before .bss/.data are initialized — disable the watchdog here.
#[pre_init]
fn early_init() {
    /* TODO: WDOG->disable() once the PAC exposes it. */
}

#[entry]
fn main() -> ! {
    /* TODO: GPIO setup, timer config, LED toggle.
     * For now this documents the API shape. */
    loop {
        core::hint::spin_loop();
    }
}

/// Example ISR — replace with your actual handler.  The symbol name
/// (`TINT0`) must match what the PAC crate puts in the PIE table.
#[interrupt]
fn TINT0() {
    /* TODO: PIE acknowledge + clear TINT0 flag + user logic. */
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
