//! Peripheral Access Crate for TI F28035 (C28x).
//!
//! Designed for the path2 LLVM C28x backend.  Key differences from the
//! path1 (MIR) `WordAddress` pattern:
//!
//! 1. **Byte addresses**: the LLVM backend treats pointers as byte addresses
//!    and does `ROR ACC` (÷2) on every indirect load/store.  `Reg` therefore
//!    stores the *word* address and multiplies by 2 internally.
//! 2. **intrinsics**: `core::intrinsics::volatile_load/store` are used instead
//!    of `ptr::read_volatile`, because the latter instantiates
//!    `maybe_is_aligned` which triggers a TI linker relocation-expansion
//!    internal error on C28x.
//! 3. **EALLOW**: GPIO mux/dir registers are EALLOW-protected.  The startup
//!    stub keeps EALLOW set after watchdog disable, so all writes succeed.
//!    A future revision will add an `Eallow` token type.

#![no_std]
#![feature(core_intrinsics)]

use core::sync::atomic::{AtomicU8, Ordering};

// ---------------------------------------------------------------------------
// Register wrapper
// ---------------------------------------------------------------------------

/// A 16-bit memory-mapped register.
///
/// Stores the **word** address (as found in the F28035 datasheet).  The
/// accessors convert to a byte address (×2) before issuing the volatile
/// load/store, matching the LLVM C28x backend's pointer model.
#[derive(Clone, Copy)]
pub struct Reg {
    word_addr: u16,
}

impl Reg {
    /// Create a register from its datasheet word address.
    pub const fn at(word_addr: u16) -> Self {
        Self { word_addr }
    }

    /// Volatile 16-bit read.
    #[inline(always)]
    pub unsafe fn read(&self) -> u16 {
        let byte_ptr = (self.word_addr as u32 * 2) as *const u16;
        // SAFETY: word_addr comes from the F28035 register map; ×2 yields a
        // valid byte address within the peripheral frame.
        unsafe { core::intrinsics::volatile_load(byte_ptr) }
    }

    /// Volatile 16-bit write.
    #[inline(always)]
    pub unsafe fn write(&self, value: u16) {
        let byte_ptr = (self.word_addr as u32 * 2) as *mut u16;
        // SAFETY: same as read.
        unsafe { core::intrinsics::volatile_store(byte_ptr, value) }
    }

    /// Read-modify-write with a closure.
    #[inline(always)]
    pub unsafe fn modify<F>(&self, f: F)
    where
        F: FnOnce(u16) -> u16,
    {
        let v = unsafe { self.read() };
        unsafe { self.write(f(v)) };
    }
}

// ---------------------------------------------------------------------------
// GPIO peripheral (Port A + Port B)
// ---------------------------------------------------------------------------

/// F28035 GPIO registers (datasheet word addresses).
pub struct Gpio {
    // --- Port A ---
    pub gpacontrol: Reg,   // 0x6F80  GPIO A control
    pub gpaqsel1: Reg,     // 0x6F82  GPIO A qualifier select 1
    pub gpaqsel2: Reg,     // 0x6F84  GPIO A qualifier select 2
    pub gpamux1: Reg,      // 0x6F86  GPIO A mux 1
    pub gpamux2: Reg,      // 0x6F88  GPIO A mux 2
    pub gpadir: Reg,       // 0x6F8A  GPIO A direction
    pub gpapud: Reg,       // 0x6F8C  GPIO A pull-up disable
    pub gpadat: Reg,       // 0x6FC0  GPIO A data
    pub gpaset: Reg,       // 0x6FC2  GPIO A set
    pub gpaclear: Reg,     // 0x6FC4  GPIO A clear
    pub gpatoggle: Reg,    // 0x6FC6  GPIO A toggle
    // --- Port B ---
    pub gpbcontrol: Reg,   // 0x6F90  GPIO B control
    pub gpbqsel1: Reg,     // 0x6F92  GPIO B qualifier select 1
    pub gpbqsel2: Reg,     // 0x6F94  GPIO B qualifier select 2
    pub gpbmux1: Reg,      // 0x6F96  GPIO B mux 1
    pub gpbmux2: Reg,      // 0x6F98  GPIO B mux 2
    pub gpbdir: Reg,       // 0x6F9A  GPIO B direction
    pub gpbpud: Reg,       // 0x6F9C  GPIO B pull-up disable
    pub gpbdat: Reg,       // 0x6FC8  GPIO B data
    pub gpbset: Reg,       // 0x6FCA  GPIO B set
    pub gpbclear: Reg,     // 0x6FCC  GPIO B clear
    pub gpbtoggle: Reg,    // 0x6FCE  GPIO B toggle
}

impl Gpio {
    const fn new() -> Self {
        Self {
            gpacontrol: Reg::at(0x6F80),
            gpaqsel1: Reg::at(0x6F82),
            gpaqsel2: Reg::at(0x6F84),
            gpamux1: Reg::at(0x6F86),
            gpamux2: Reg::at(0x6F88),
            gpadir: Reg::at(0x6F8A),
            gpapud: Reg::at(0x6F8C),
            gpadat: Reg::at(0x6FC0),
            gpaset: Reg::at(0x6FC2),
            gpaclear: Reg::at(0x6FC4),
            gpatoggle: Reg::at(0x6FC6),
            gpbcontrol: Reg::at(0x6F90),
            gpbqsel1: Reg::at(0x6F92),
            gpbqsel2: Reg::at(0x6F94),
            gpbmux1: Reg::at(0x6F96),
            gpbmux2: Reg::at(0x6F98),
            gpbdir: Reg::at(0x6F9A),
            gpbpud: Reg::at(0x6F9C),
            gpbdat: Reg::at(0x6FC8),
            gpbset: Reg::at(0x6FCA),
            gpbclear: Reg::at(0x6FCC),
            gpbtoggle: Reg::at(0x6FCE),
        }
    }
}

// ---------------------------------------------------------------------------
// Peripherals singleton
// ---------------------------------------------------------------------------

static PERIPHERALS_TAKEN: AtomicU8 = AtomicU8::new(0);

/// All F28035 peripherals.  Obtain via [`Peripherals::take()`].
pub struct Peripherals {
    pub gpio: Gpio,
}

impl Peripherals {
    /// Take the peripherals singleton.  Returns `Some` only on the first
    /// call; subsequent calls return `None`.  This prevents two parts of the
    /// firmware from concurrently owning the same hardware.
    pub fn take() -> Option<Self> {
        // compare_exchange: 0 → 1 means we got it.
        match PERIPHERALS_TAKEN.compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire) {
            Ok(_) => Some(Self {
                gpio: Gpio::new(),
            }),
            Err(_) => None,
        }
    }

    /// Steal the peripherals without checking the take flag.
    ///
    /// # Safety
    /// Only use if you can guarantee no other code owns the peripherals.
    pub unsafe fn steal() -> Self {
        Self {
            gpio: Gpio::new(),
        }
    }
}
