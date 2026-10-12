//! # c28x-rt
//!
//! Minimal runtime / startup for TI C2000 (C28x) microcontrollers.
//!
//! Modeled after [`msp430-rt`](https://github.com/rust-embedded/msp430-rt).
//!
//! This crate provides:
//! - The `Reset` handler (stack setup, `PreInit`, PIE table copy, `.bss`
//!   zero, `.data` copy, call `main`)
//! - The CPU interrupt vector table (`.vector_table`) and PIE table
//! - A default interrupt handler
//! - The `#[entry]` macro to declare the application entry point
//! - The `#[pre_init]` macro to run code before RAM is initialized
//! - The `#[interrupt]` macro to declare interrupt handlers (transitional;
//!   see [Interrupts](#interrupts))
//!
//! ## `memory.x`
//!
//! The user (or the PAC crate) supplies a `memory.x` linker script with
//! at least these regions:
//!
//! ```text
//! MEMORY
//! {
//!     RAML2   : ORIGIN = 0x008C00, LENGTH = 0x000400   /* .bss / .data */
//!     FLASHA  : ORIGIN = 0x3F6000, LENGTH = 0x001F80   /* .text / .rodata */
//!     RESET   : ORIGIN = 0x3FFFC0, LENGTH = 0x000002   /* reset vector */
//!     VECTORS : ORIGIN = 0x3FFFC2, LENGTH = 0x00003E   /* CPU vectors */
//! }
//! ```
//!
//! The stack top is computed as `ORIGIN(RAMM0) + LENGTH(RAMM0)`; the heap
//! starts at `_edata` (right after both `.bss` and `.data`).
//!
//! ## Example
//!
//! ```ignore
//! #![no_std]
//! #![no_main]
//!
//! use c28x_rt::{entry, pre_init};
//!
//! #[pre_init]
//! fn early_init() {
//!     /* e.g. disable watchdog — runs before .bss/.data */
//! }
//!
//! #[entry]
//! fn main() -> ! {
//!     loop {
//!         // application code
//!     }
//! }
//!
//! #[panic_handler]
//! fn panic(_: &core::panic::PanicInfo) -> ! {
//!     loop {}
//! }
//! ```
//!
//! ## Symbols you will see in the output binary
//!
//! - `Reset` — assembly startup routine (defined in `asm.s`).
//! - `__RESET_VECTOR` — pointer to `Reset`, placed at the reset address.
//! - `__INTERRUPTS` — device interrupt table; weak-filled here, overridden
//!   by the PAC crate when the `device` feature is on.
//! - `PreInit` — weak alias to `PreInit_`; override with `#[pre_init]`.
//! - `DefaultHandler` — weak alias to `DefaultHandler_`; the default loop
//!   that catches unhandled interrupts.
//! - `_sbss`, `_ebss`, `_sdata`, `_edata`, `_sidata`, `_sheap`,
//!   `__stack_end` — boundaries exported by `link.x`.
//!
//! ## Interrupts
//!
//! The C28x has 32 CPU interrupt vectors, expanded through the PIE
//! controller into 12 groups × 16 entries.  When the `device` feature is
//! enabled (default), the PAC crate supplies `__INTERRUPTS` as a static
//! array of function pointers placed in `.vector_table.interrupts`, and
//! a `device.x` linker script with `PROVIDE(...)` weak aliases.
//!
//! ### Transitional status
//!
//! C28x has **no dedicated interrupt ABI** in rustc (unlike MSP430's
//! `extern "msp430-interrupt"`).  Until that lands:
//!
//! - `#[interrupt]` expands to a plain `extern "C"` function.
//! - C28x does **not** push registers on interrupt entry the way
//!   Cortex-M does.  ISRs that clobber ACC/XAR/XT/T must save/restore
//!   them in an assembly trampoline.
//! - Handlers must return via `LRETR` (what `extern "C"` leaf functions
//!   already emit).
//!
//! When `extern "c28x-interrupt"` is added to rustc, `#[interrupt]` will
//! switch to it transparently.

#![no_std]
#![deny(missing_docs)]

/// Number of CPU interrupt vectors on C28x (reset + 32 IRQs).
pub const NUM_VECTORS: usize = 32;

/// Default interrupt handler: infinite loop.
#[no_mangle]
unsafe extern "C" fn DefaultHandler_() -> ! {
    loop {
        /* Prevent the optimizer from removing this loop. */
        #[allow(clippy::empty_loop)]
        {}
    }
}

/// Weak alias for DefaultHandler (overridable by user).
#[no_mangle]
pub unsafe extern "C" fn DefaultHandler() -> ! {
    unsafe { DefaultHandler_() }
}

/// Pre-initialization hook (called before .bss/.data init).
#[no_mangle]
unsafe extern "C" fn PreInit_() {}

/// Entry point attribute: marks the function that `Reset` calls.
///
/// This is a placeholder; a proper proc-macro would expand to
/// `#[no_mangle] extern "C" fn main() -> !`.
///
/// The user writes:
/// ```ignore
/// #[entry]
/// fn main() -> ! { loop {} }
/// ```
///
/// Which expands to:
/// ```ignore
/// #[no_mangle]
/// extern "C" fn main() -> ! { loop {} }
/// ```
pub use c28x_rt_macros::{entry, interrupt, pre_init};

/// Reset vector: points to the `Reset` handler in asm.s.
///
/// Placed at 0x3FFFC0 (RESET region).
#[cfg(target_arch = "c28x")]
#[link_section = ".reset"]
#[no_mangle]
pub static __RESET_VECTOR: unsafe extern "C" fn() -> ! = Reset;

#[cfg(target_arch = "c28x")]
extern "C" {
    fn Reset() -> !;
}

extern "C" {
    static _sbss: u16;
    static _ebss: u16;
    static _sdata: u16;
    static _edata: u16;
    static _sidata: u16;
    static __stack_end: u16;
}

/// Returns the start of the heap (right after .bss + .data).
#[inline]
pub fn heap_start() -> *mut u32 {
    extern "C" {
        static mut _sheap: u32;
    }
    &raw mut _sheap
}

/* Generic vector table (device feature disabled): all vectors -> DefaultHandler. */
#[cfg(not(feature = "device"))]
#[link_section = ".vector_table.interrupts"]
#[no_mangle]
pub static __INTERRUPTS: [unsafe extern "C" fn(); NUM_VECTORS] = [
    DefaultHandler; NUM_VECTORS
];

/// PIE (Peripheral Interrupt Expansion) vector table in Flash.
///
/// The CPU vectors (in Boot ROM) point to entries in this table.
/// The startup code copies this to PIE RAM at 0x0D00.
///
/// Each entry is a 22-bit handler address.  Group 1 starts at index 0,
/// Group 2 at index 16, etc.  The first 16 entries are reserved for
/// CPU-specific interrupts (RESET, NMI, etc.).
#[repr(C)]
#[repr(align(2))]
#[allow(missing_docs)]
pub struct PieTable {
    pub reserved: [unsafe extern "C" fn() -> !; 16],
    pub group1: [unsafe extern "C" fn() -> !; 16], // ADC, TIMER0, ...
    pub group2: [unsafe extern "C" fn() -> !; 16],
    pub group3: [unsafe extern "C" fn() -> !; 16],
    pub group4: [unsafe extern "C" fn() -> !; 16],
    pub group5: [unsafe extern "C" fn() -> !; 16],
    pub group6: [unsafe extern "C" fn() -> !; 16],
    pub group7: [unsafe extern "C" fn() -> !; 16],
    pub group8: [unsafe extern "C" fn() -> !; 16],
    pub group9: [unsafe extern "C" fn() -> !; 16],
    pub group10: [unsafe extern "C" fn() -> !; 16],
    pub group11: [unsafe extern "C" fn() -> !; 16],
    pub group12: [unsafe extern "C" fn() -> !; 16],
}

/// Default PIE table: all entries point to DefaultHandler.
#[link_section = ".pie_table"]
#[no_mangle]
pub static _pie_table: PieTable = PieTable {
    reserved: [DefaultHandler_; 16],
    group1: [DefaultHandler_; 16],
    group2: [DefaultHandler_; 16],
    group3: [DefaultHandler_; 16],
    group4: [DefaultHandler_; 16],
    group5: [DefaultHandler_; 16],
    group6: [DefaultHandler_; 16],
    group7: [DefaultHandler_; 16],
    group8: [DefaultHandler_; 16],
    group9: [DefaultHandler_; 16],
    group10: [DefaultHandler_; 16],
    group11: [DefaultHandler_; 16],
    group12: [DefaultHandler_; 16],
};
