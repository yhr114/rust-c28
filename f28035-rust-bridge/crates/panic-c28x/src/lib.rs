//! # panic-c28x
//!
//! Panic handler for TI C2000 (C28x) microcontrollers.
//!
//! On panic, this handler:
//! 1. Disables interrupts (DINT)
//! 2. Loops forever (so the debugger can halt and inspect state)
//!
//! # Usage
//!
//! ```no_run
//! #![no_std]
//! #![no_main]
//!
//! use panic_c28x as _;  // no need to call anything; #[panic_handler] is here
//!
//! #[entry]
//! fn main() -> ! {
//!     loop {}
//! }
//! ```

#![no_std]
#![deny(missing_docs)]

use core::panic::PanicInfo;

/// Panic handler: disable interrupts and loop forever.
///
/// The user can attach a debugger (XDS100) and halt at this loop
/// to inspect the call stack and registers.
#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    // Disable interrupts (DINT).
    // SAFETY: this is a single-core MCU; disabling interrupts on panic
    // is always safe.
    unsafe {
        core::arch::asm!("setc intm");
    }

    loop {
        // Prevent the optimizer from removing this loop.
        core::hint::spin_loop();
    }
}
