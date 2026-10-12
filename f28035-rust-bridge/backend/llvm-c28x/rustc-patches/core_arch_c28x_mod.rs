//===-- mod.rs - C28x-specific core intrinsics -------------------------===//
//
// Place this file at:
//   library/core/src/arch/c28x/mod.rs
//
// Then add to library/core/src/arch/mod.rs:
//   #[cfg(any(target_arch = "c28x", doc))]
//   pub mod c28x;
//
//===----------------------------------------------------------------------===//

//! C28x-specific intrinsics.
//!
//! These wrap the C28x instruction set that has no portable equivalent.

use crate::arch::asm;

/// Enable protected register writes (unlock EALLOW-protected registers).
///
/// After calling this, writes to SysCtrlRegs, GpioCtrlRegs, PieCtrlRegs
/// are allowed.  Call [`edis`] to re-lock.
///
/// # Safety
///
/// This modifies the ST1.EALLOW bit.  Must be paired with `edis`.
#[inline]
pub unsafe fn eallow() {
    asm!("eallow");
}

/// Disable protected register writes (re-lock EALLOW-protected registers).
///
/// # Safety
///
/// This modifies the ST1.EALLOW bit.  Must be paired with `eallow`.
#[inline]
pub unsafe fn edis() {
    asm!("edis");
}

/// Set the data page pointer (DP).
///
/// C28x uses a 16-bit data page register to address memory in 64-word
/// blocks.  This sets DP directly.
///
/// # Safety
///
/// This modifies the DP register.  Incorrect values cause wrong memory
/// accesses.
#[inline]
pub unsafe fn set_dp(page: u16) {
    asm!("mov dp, #{}", in(reg) page);
}

/// Delay for N cycles (busy-wait).
///
/// C28x has no cycle-accurate delay primitive in hardware; this uses a
/// software loop.
#[inline]
pub fn delay_cycles(n: u16) {
    for _ in 0..n {
        unsafe { asm!("nop") };
    }
}

/// Read the timer count register (TIMP).
///
/// # Safety
///
/// Reads a CPU register; no side effects.
#[inline]
pub fn read_tim() -> u16 {
    let v: u16;
    unsafe { asm!("mov {}, tim", out(reg) v) };
    v
}
