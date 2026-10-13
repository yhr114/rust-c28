//! Peripheral Access Crate for TI F28035 (C28x).
//!
//! Designed for the path2 LLVM C28x backend.  Key constraints:
//!
//! 1. **Byte addresses**: the LLVM backend treats pointers as byte addresses
//!    and does `ROR ACC` (÷2) on every indirect load/store.  `Reg`/`Reg32`
//!    therefore store the *word* address and multiply by 2 internally.
//! 2. **intrinsics**: `core::intrinsics::volatile_load/store` are used instead
//!    of `ptr::read_volatile`, because the latter instantiates
//!    `maybe_is_aligned` which triggers a TI linker relocation-expansion
//!    internal error on C28x.
//! 3. **EALLOW**: GPIO mux/dir and SysCtrl registers are EALLOW-protected.
//!    The startup stub keeps EALLOW set after watchdog disable.
//! 4. **#[inline(always)]**: all methods are force-inlined to avoid cross-.o
//!    `LCR` relocations, which the TI linker does not resolve correctly
//!    (call target stays 0x000000).

#![no_std]
#![feature(core_intrinsics)]

use core::cell::UnsafeCell;

// ---------------------------------------------------------------------------
// Register wrappers
// ---------------------------------------------------------------------------

/// A 16-bit memory-mapped register.
#[derive(Clone, Copy)]
pub struct Reg {
    word_addr: u16,
}

impl Reg {
    #[inline(always)]
    pub const fn at(word_addr: u16) -> Self {
        Self { word_addr }
    }

    #[inline(always)]
    pub unsafe fn read(&self) -> u16 {
        let p = (self.word_addr as u32 * 2) as *const u16;
        unsafe { core::intrinsics::volatile_load(p) }
    }

    #[inline(always)]
    pub unsafe fn write(&self, value: u16) {
        let p = (self.word_addr as u32 * 2) as *mut u16;
        unsafe { core::intrinsics::volatile_store(p, value) }
    }

    #[inline(always)]
    pub unsafe fn modify<F>(&self, f: F)
    where
        F: FnOnce(u16) -> u16,
    {
        let v = unsafe { self.read() };
        unsafe { self.write(f(v)) };
    }

    #[inline(always)]
    pub unsafe fn set_bits(&self, bits: u16) {
        self.modify(|v| v | bits)
    }

    #[inline(always)]
    pub unsafe fn clear_bits(&self, bits: u16) {
        self.modify(|v| v & !bits)
    }

    /// Read a single bit. `bit` is 0..15.
    #[inline(always)]
    pub unsafe fn read_bit(&self, bit: u16) -> bool {
        (unsafe { self.read() } >> bit) & 1 != 0
    }

    /// Write a single bit. `bit` is 0..15.
    #[inline(always)]
    pub unsafe fn write_bit(&self, bit: u16, value: bool) {
        if value {
            self.set_bits(1 << bit);
        } else {
            self.clear_bits(1 << bit);
        }
    }

    /// Toggle a single bit. `bit` is 0..15.
    #[inline(always)]
    pub unsafe fn toggle_bit(&self, bit: u16) {
        self.modify(|v| v ^ (1 << bit));
    }

    /// Read a bit-field. `shift` is the LSB position, `mask` is the field mask.
    /// Returns the field value right-aligned.
    #[inline(always)]
    pub unsafe fn read_field(&self, shift: u16, mask: u16) -> u16 {
        (unsafe { self.read() } >> shift) & mask
    }

    /// Write a bit-field. `shift` is the LSB position, `mask` is the field mask.
    /// `value` is masked automatically.
    #[inline(always)]
    pub unsafe fn write_field(&self, shift: u16, mask: u16, value: u16) {
        self.modify(|v| (v & !(mask << shift)) | ((value & mask) << shift));
    }
}

/// A 32-bit memory-mapped register (two consecutive 16-bit words: low then high).
#[derive(Clone, Copy)]
pub struct Reg32 {
    word_addr: u16,
}

impl Reg32 {
    #[inline(always)]
    pub const fn at(word_addr: u16) -> Self {
        Self { word_addr }
    }

    #[inline(always)]
    pub unsafe fn read(&self) -> u32 {
        let p = (self.word_addr as u32 * 2) as *const u32;
        unsafe { core::intrinsics::volatile_load(p) }
    }

    #[inline(always)]
    pub unsafe fn write(&self, value: u32) {
        let p = (self.word_addr as u32 * 2) as *mut u32;
        unsafe { core::intrinsics::volatile_store(p, value) }
    }

    #[inline(always)]
    pub unsafe fn modify<F>(&self, f: F)
    where
        F: FnOnce(u32) -> u32,
    {
        let v = unsafe { self.read() };
        unsafe { self.write(f(v)) };
    }

    /// Read a single bit. `bit` is 0..31.
    #[inline(always)]
    pub unsafe fn read_bit(&self, bit: u32) -> bool {
        (unsafe { self.read() } >> bit) & 1 != 0
    }

    /// Write a single bit. `bit` is 0..31.
    #[inline(always)]
    pub unsafe fn write_bit(&self, bit: u32, value: bool) {
        self.modify(|v| if value { v | (1 << bit) } else { v & !(1 << bit) });
    }

    /// Read a bit-field. `shift` is LSB position, `mask` is field mask.
    #[inline(always)]
    pub unsafe fn read_field(&self, shift: u32, mask: u32) -> u32 {
        (unsafe { self.read() } >> shift) & mask
    }

    /// Write a bit-field with automatic masking.
    #[inline(always)]
    pub unsafe fn write_field(&self, shift: u32, mask: u32, value: u32) {
        self.modify(|v| (v & !(mask << shift)) | ((value & mask) << shift));
    }
}

// ---------------------------------------------------------------------------
// EALLOW-protected register access (compile-time guard)
// ---------------------------------------------------------------------------

/// RAII guard for EALLOW-protected register access.
///
/// Created via [`Peripherals::eallow`].  Executes the `EALLOW` instruction
/// (0x7622) on creation and `EDIS` (0x761A) on drop.  Cannot be copied,
/// cloned, or constructed by user code — the only way to obtain one is
/// through [`Peripherals::eallow`], which ties the token to the live
/// `Peripherals` instance.
///
/// `ProtectedReg` write methods require a `&EallowToken`, so the compiler
/// statically guarantees that EALLOW is active before any protected register
/// is written.
pub struct EallowToken {
    _private: (),
}

impl EallowToken {
    /// Execute EALLOW instruction (0x7622).  Only callable via
    /// [`Peripherals::eallow`].
    #[inline(always)]
    unsafe fn new() -> Self {
        unsafe { eallow_inst() }
        Self { _private: () }
    }
}

impl Drop for EallowToken {
    #[inline(always)]
    fn drop(&mut self) {
        unsafe { edis_inst() }
    }
}

/// A 16-bit memory-mapped register whose *write* side is EALLOW-protected.
///
/// Read methods need no token (reads are never gated by EALLOW).  Write
/// methods (`write`, `modify`, `set_bits`, `clear_bits`, `write_bit`,
/// `toggle_bit`, `write_field`) all require a `&EallowToken`, enforcing at
/// compile time that the EALLOW instruction was executed first.
#[derive(Clone, Copy)]
pub struct ProtectedReg {
    inner: Reg,
}

impl ProtectedReg {
    #[inline(always)]
    pub const fn at(word_addr: u16) -> Self {
        Self { inner: Reg::at(word_addr) }
    }

    // ---- reads (no token needed) ----

    #[inline(always)]
    pub unsafe fn read(&self) -> u16 {
        unsafe { self.inner.read() }
    }

    #[inline(always)]
    pub unsafe fn read_bit(&self, bit: u16) -> bool {
        unsafe { self.inner.read_bit(bit) }
    }

    #[inline(always)]
    pub unsafe fn read_field(&self, shift: u16, mask: u16) -> u16 {
        unsafe { self.inner.read_field(shift, mask) }
    }

    // ---- writes (require &EallowToken) ----

    #[inline(always)]
    pub unsafe fn write(&self, value: u16, _ea: &EallowToken) {
        unsafe { self.inner.write(value) }
    }

    #[inline(always)]
    pub unsafe fn modify<F>(&self, f: F, _ea: &EallowToken)
    where
        F: FnOnce(u16) -> u16,
    {
        unsafe { self.inner.modify(f) }
    }

    #[inline(always)]
    pub unsafe fn set_bits(&self, bits: u16, _ea: &EallowToken) {
        unsafe { self.inner.set_bits(bits) }
    }

    #[inline(always)]
    pub unsafe fn clear_bits(&self, bits: u16, _ea: &EallowToken) {
        unsafe { self.inner.clear_bits(bits) }
    }

    #[inline(always)]
    pub unsafe fn write_bit(&self, bit: u16, value: bool, _ea: &EallowToken) {
        unsafe { self.inner.write_bit(bit, value) }
    }

    #[inline(always)]
    pub unsafe fn toggle_bit(&self, bit: u16, _ea: &EallowToken) {
        unsafe { self.inner.toggle_bit(bit) }
    }

    #[inline(always)]
    pub unsafe fn write_field(&self, shift: u16, mask: u16, value: u16, _ea: &EallowToken) {
        unsafe { self.inner.write_field(shift, mask, value) }
    }
}

// ---------------------------------------------------------------------------
// System Control (base 0x7010)
// ---------------------------------------------------------------------------

pub struct SysCtrl {
    pub xclk: ProtectedReg,     // 0x7010 XCLKOUT Control (EALLOW)
    pub pllsts: Reg,            // 0x7011 PLL Status
    pub clkctl: ProtectedReg,   // 0x7012 Clock Control (EALLOW)
    pub plllockprd: Reg,        // 0x7013 PLL Lock Period
    pub intosc1trim: Reg,       // 0x7014 Internal Oscillator 1 Trim
    pub rsvd1: Reg,             // 0x7015
    pub intosc2trim: Reg,       // 0x7016 Internal Oscillator 2 Trim
    pub rsvd2: [Reg; 2],        // 0x7017-0x7018
    pub pclkcr2: ProtectedReg,  // 0x7019 Peripheral Clock Control 2 (EALLOW)
    pub rsvd3: Reg,             // 0x701A
    pub lospcp: ProtectedReg,    // 0x701B Low-Speed Peripheral Clock Prescaler (EALLOW)
    pub pclkcr0: ProtectedReg,   // 0x701C Peripheral Clock Control 0 (EALLOW)
    pub pclkcr1: ProtectedReg,   // 0x701D Peripheral Clock Control 1 (EALLOW)
    pub lpmcr0: ProtectedReg,   // 0x701E Low-Power Mode Control 0 (EALLOW)
    pub rsvd4: Reg,             // 0x701F
    pub pclkcr3: ProtectedReg,   // 0x7020 Peripheral Clock Control 3 (EALLOW)
    pub pllcr: ProtectedReg,     // 0x7021 PLL Control (EALLOW)
    pub scsr: ProtectedReg,     // 0x7022 System Control & Status (EALLOW)
    pub wdcntr: Reg,            // 0x7023 Watchdog Counter
    pub rsvd5: Reg,             // 0x7024
    pub wdkey: Reg,             // 0x7025 Watchdog Reset Key (not EALLOW)
    pub rsvd6: [Reg; 3],        // 0x7026-0x7028
    pub wdcr: ProtectedReg,      // 0x7029 Watchdog Control (EALLOW)
}

impl SysCtrl {
    #[inline(always)]
    const fn new() -> Self {
        const B: u16 = 0x7010;
        Self {
            xclk: ProtectedReg::at(B + 0),
            pllsts: Reg::at(B + 1),
            clkctl: ProtectedReg::at(B + 2),
            plllockprd: Reg::at(B + 3),
            intosc1trim: Reg::at(B + 4),
            rsvd1: Reg::at(B + 5),
            intosc2trim: Reg::at(B + 6),
            rsvd2: [Reg::at(B + 7), Reg::at(B + 8)],
            pclkcr2: ProtectedReg::at(B + 9),
            rsvd3: Reg::at(B + 10),
            lospcp: ProtectedReg::at(B + 11),
            pclkcr0: ProtectedReg::at(B + 12),
            pclkcr1: ProtectedReg::at(B + 13),
            lpmcr0: ProtectedReg::at(B + 14),
            rsvd4: Reg::at(B + 15),
            pclkcr3: ProtectedReg::at(B + 16),
            pllcr: ProtectedReg::at(B + 17),
            scsr: ProtectedReg::at(B + 18),
            wdcntr: Reg::at(B + 19),
            rsvd5: Reg::at(B + 20),
            wdkey: Reg::at(B + 21),
            rsvd6: [Reg::at(B + 22), Reg::at(B + 23), Reg::at(B + 24)],
            wdcr: ProtectedReg::at(B + 25),
        }
    }

    /// Service the watchdog (write 0x55 then 0xAA to WDKEY).
    #[inline(always)]
    pub unsafe fn kick_dog(&self) {
        unsafe {
            self.wdkey.write(0x0055);
            self.wdkey.write(0x00AA);
        }
    }

    /// Disable the watchdog (WDCR = 0x0068: WDCHK=101, WDDIS=1).
    /// Requires an active [`EallowToken`] because WDCR is EALLOW-protected.
    #[inline(always)]
    pub unsafe fn disable_watchdog(&self, ea: &EallowToken) {
        unsafe { self.wdcr.write(0x0068, ea) }
    }
}

// ---------------------------------------------------------------------------
// CPU Timer (base 0x0C00 for Timer0; 0x0C08 Timer1; 0x0C10 Timer2)
// ---------------------------------------------------------------------------

pub struct CpuTimer {
    pub tim: Reg32,     // 0+1 Timer Counter (32-bit)
    pub prd: Reg32,     // 2+3 Period (32-bit)
    pub tcr: Reg,       // 4   Timer Control
    pub rsvd1: Reg,     // 5
    pub tpr: Reg,       // 6   Timer Prescale Low
    pub tprh: Reg,      // 7   Timer Prescale High
}

impl CpuTimer {
    #[inline(always)]
    const fn new(base: u16) -> Self {
        Self {
            tim: Reg32::at(base + 0),
            prd: Reg32::at(base + 2),
            tcr: Reg::at(base + 4),
            rsvd1: Reg::at(base + 5),
            tpr: Reg::at(base + 6),
            tprh: Reg::at(base + 7),
        }
    }

    /// Start timer (TSS=0, TRB=1 to reload).
    #[inline(always)]
    pub unsafe fn start(&self) {
        unsafe {
            self.tcr.modify(|v| (v & !(1 << 4)) | (1 << 5)); // TSS=0, TRB=1
        }
    }

    /// Stop timer (TSS=1).
    #[inline(always)]
    pub unsafe fn stop(&self) {
        unsafe { self.tcr.set_bits(1 << 4) }
    }

    /// Configure for periodic interrupt: stop, set period/prescale, enable TIE.
    /// prescale is the full 16-bit TDDRH:TDDR value (0 = /1, 1 = /2, ...).
    #[inline(always)]
    pub unsafe fn configure_periodic(&self, period: u32, prescale: u16) {
        unsafe {
            self.stop();
            self.prd.write(period);
            self.tpr.write(prescale & 0xFF);
            self.tprh.write((prescale >> 8) & 0xFF);
            // TIE=1 (bit14), TSS=1 (stop, bit4), TRB=1 (reload, bit5)
            self.tcr.write((1 << 14) | (1 << 4) | (1 << 5));
        }
    }

    /// Clear timer interrupt flag (TCR bit4 TIF is w1c on F28035).
    #[inline(always)]
    pub unsafe fn clear_flag(&self) {
        unsafe { self.tcr.set_bits(1 << 4) }
    }
}

// ---------------------------------------------------------------------------
// PIE Control (base 0x0CE0)
// ---------------------------------------------------------------------------

pub struct PieCtrl {
    pub piectrl: Reg,    // 0x0CE0 PIE Control
    pub pieack: Reg,     // 0x0CE1 PIE Acknowledge
    pub pieier1: Reg,    // 0x0CE2 PIE INT1 Enable
    pub pieifr1: Reg,    // 0x0CE3 PIE INT1 Flag
    pub pieier2: Reg,    // 0x0CE4
    pub pieifr2: Reg,    // 0x0CE5
    pub pieier3: Reg,    // 0x0CE6
    pub pieifr3: Reg,    // 0x0CE7
    pub pieier4: Reg,    // 0x0CE8
    pub pieifr4: Reg,    // 0x0CE9
    pub pieier5: Reg,    // 0x0CEA
    pub pieifr5: Reg,    // 0x0CEB
    pub pieier6: Reg,    // 0x0CEC
    pub pieifr6: Reg,    // 0x0CED
    pub pieier7: Reg,    // 0x0CEE
    pub pieifr7: Reg,    // 0x0CEF
    pub pieier8: Reg,    // 0x0CF0
    pub pieifr8: Reg,    // 0x0CF1
    pub pieier9: Reg,    // 0x0CF2
    pub pieifr9: Reg,    // 0x0CF3
    pub pieier10: Reg,   // 0x0CF4
    pub pieifr10: Reg,   // 0x0CF5
    pub pieier11: Reg,   // 0x0CF6
    pub pieifr11: Reg,   // 0x0CF7
    pub pieier12: Reg,   // 0x0CF8
    pub pieifr12: Reg,   // 0x0CF9
}

impl PieCtrl {
    #[inline(always)]
    const fn new() -> Self {
        const B: u16 = 0x0CE0;
        Self {
            piectrl: Reg::at(B + 0),
            pieack: Reg::at(B + 1),
            pieier1: Reg::at(B + 2),
            pieifr1: Reg::at(B + 3),
            pieier2: Reg::at(B + 4),
            pieifr2: Reg::at(B + 5),
            pieier3: Reg::at(B + 6),
            pieifr3: Reg::at(B + 7),
            pieier4: Reg::at(B + 8),
            pieifr4: Reg::at(B + 9),
            pieier5: Reg::at(B + 10),
            pieifr5: Reg::at(B + 11),
            pieier6: Reg::at(B + 12),
            pieifr6: Reg::at(B + 13),
            pieier7: Reg::at(B + 14),
            pieifr7: Reg::at(B + 15),
            pieier8: Reg::at(B + 16),
            pieifr8: Reg::at(B + 17),
            pieier9: Reg::at(B + 18),
            pieifr9: Reg::at(B + 19),
            pieier10: Reg::at(B + 20),
            pieifr10: Reg::at(B + 21),
            pieier11: Reg::at(B + 22),
            pieifr11: Reg::at(B + 23),
            pieier12: Reg::at(B + 24),
            pieifr12: Reg::at(B + 25),
        }
    }

    /// Enable PIE (PIECTRL.ENPIE=1).
    #[inline(always)]
    pub unsafe fn enable(&self) {
        unsafe { self.piectrl.set_bits(1) }
    }

    /// Acknowledge PIE group (write group bit to PIEACK).
    #[inline(always)]
    pub unsafe fn ack_group(&self, group: u16) {
        unsafe { self.pieack.write(1 << (group - 1)) }
    }

    /// Full PIE initialization: enable PIE, clear all IER/IFR, ack all groups.
    #[inline(always)]
    pub unsafe fn init(&self) {
        unsafe {
            self.enable();
            self.pieier1.write(0); self.pieier2.write(0);
            self.pieier3.write(0); self.pieier4.write(0);
            self.pieier5.write(0); self.pieier6.write(0);
            self.pieier7.write(0); self.pieier8.write(0);
            self.pieier9.write(0); self.pieier10.write(0);
            self.pieier11.write(0); self.pieier12.write(0);
            self.pieifr1.write(0); self.pieifr2.write(0);
            self.pieifr3.write(0); self.pieifr4.write(0);
            self.pieifr5.write(0); self.pieifr6.write(0);
            self.pieifr7.write(0); self.pieifr8.write(0);
            self.pieifr9.write(0); self.pieifr10.write(0);
            self.pieifr11.write(0); self.pieifr12.write(0);
            self.pieack.write(0xFFFF);
        }
    }

    /// Enable a specific PIE interrupt: group (1-12), bit (0-7).
    #[inline(always)]
    pub unsafe fn enable_irq(&self, group: u16, bit: u16) {
        unsafe {
            let mask = 1u16 << bit;
            match group {
                1 => self.pieier1.set_bits(mask),
                2 => self.pieier2.set_bits(mask),
                3 => self.pieier3.set_bits(mask),
                4 => self.pieier4.set_bits(mask),
                5 => self.pieier5.set_bits(mask),
                6 => self.pieier6.set_bits(mask),
                7 => self.pieier7.set_bits(mask),
                8 => self.pieier8.set_bits(mask),
                9 => self.pieier9.set_bits(mask),
                10 => self.pieier10.set_bits(mask),
                11 => self.pieier11.set_bits(mask),
                12 => self.pieier12.set_bits(mask),
                _ => {}
            }
        }
    }
}

// ---------------------------------------------------------------------------
// SPI (SPI-A base 0x7040, SPI-B base 0x7740)
// ---------------------------------------------------------------------------

pub struct Spi {
    pub spiccr: Reg,     // 0  Configuration
    pub spictl: Reg,     // 1  Operation Control
    pub spists: Reg,     // 2  Status
    pub rsvd1: Reg,      // 3
    pub spibrr: Reg,     // 4  Baud Rate
    pub rsvd2: Reg,      // 5
    pub spirxemu: Reg,   // 6  Emulation Buffer
    pub spirxbuf: Reg,   // 7  Receive Buffer
    pub spitxbuf: Reg,   // 8  Transmit Buffer
    pub spidat: Reg,     // 9  Serial Data
    pub spifftx: Reg,    // 10 FIFO Transmit
    pub spiffrx: Reg,    // 11 FIFO Receive
    pub spiffct: Reg,    // 12 FIFO Control
    pub rsvd3: [Reg; 2], // 13-14
    pub spipri: Reg,     // 15 Priority Control
}

impl Spi {
    #[inline(always)]
    const fn new(base: u16) -> Self {
        Self {
            spiccr: Reg::at(base + 0),
            spictl: Reg::at(base + 1),
            spists: Reg::at(base + 2),
            rsvd1: Reg::at(base + 3),
            spibrr: Reg::at(base + 4),
            rsvd2: Reg::at(base + 5),
            spirxemu: Reg::at(base + 6),
            spirxbuf: Reg::at(base + 7),
            spitxbuf: Reg::at(base + 8),
            spidat: Reg::at(base + 9),
            spifftx: Reg::at(base + 10),
            spiffrx: Reg::at(base + 11),
            spiffct: Reg::at(base + 12),
            rsvd3: [Reg::at(base + 13), Reg::at(base + 14)],
            spipri: Reg::at(base + 15),
        }
    }

    /// Write a byte to TX buffer (blocks until TX ready).
    #[inline(always)]
    pub unsafe fn write_byte(&self, byte: u16) {
        unsafe {
            while self.spists.read() & (1 << 5) != 0 {} // wait TX not full
            self.spitxbuf.write(byte);
        }
    }

    /// Read a byte from RX buffer.
    #[inline(always)]
    pub unsafe fn read_byte(&self) -> u16 {
        unsafe {
            while self.spists.read() & (1 << 6) == 0 {} // wait RX not empty
            self.spirxbuf.read()
        }
    }
}

// ---------------------------------------------------------------------------
// SCI / UART (base 0x7050)
// ---------------------------------------------------------------------------

pub struct Sci {
    pub sciccr: Reg,     // 0  Communications Control
    pub scictl1: Reg,    // 1  Control 1
    pub scihbaud: Reg,   // 2  Baud Rate High
    pub scilbaud: Reg,   // 3  Baud Rate Low
    pub scictl2: Reg,    // 4  Control 2
    pub scirxst: Reg,    // 5  Receive Status
    pub scirxemu: Reg,   // 6  Receive Emulation
    pub scirxbuf: Reg,   // 7  Receive Buffer
    pub rsvd1: Reg,      // 8
    pub scitxbuf: Reg,   // 9  Transmit Buffer
    pub scifftx: Reg,    // 10 FIFO Transmit
    pub sciffrx: Reg,    // 11 FIFO Receive
    pub sciffct: Reg,    // 12 FIFO Control
    pub rsvd2: Reg,      // 13
    pub rsvd3: Reg,      // 14
    pub scipri: Reg,     // 15 Priority
}

impl Sci {
    #[inline(always)]
    const fn new() -> Self {
        const B: u16 = 0x7050;
        Self {
            sciccr: Reg::at(B + 0),
            scictl1: Reg::at(B + 1),
            scihbaud: Reg::at(B + 2),
            scilbaud: Reg::at(B + 3),
            scictl2: Reg::at(B + 4),
            scirxst: Reg::at(B + 5),
            scirxemu: Reg::at(B + 6),
            scirxbuf: Reg::at(B + 7),
            rsvd1: Reg::at(B + 8),
            scitxbuf: Reg::at(B + 9),
            scifftx: Reg::at(B + 10),
            sciffrx: Reg::at(B + 11),
            sciffct: Reg::at(B + 12),
            rsvd2: Reg::at(B + 13),
            rsvd3: Reg::at(B + 14),
            scipri: Reg::at(B + 15),
        }
    }

    /// Write a byte (poll TX ready).
    #[inline(always)]
    pub unsafe fn write_byte(&self, byte: u16) {
        unsafe {
            while self.scictl2.read() & (1 << 7) == 0 {} // TXRDY
            self.scitxbuf.write(byte);
        }
    }

    /// Read a byte (poll RX ready).
    #[inline(always)]
    pub unsafe fn read_byte(&self) -> u16 {
        unsafe {
            while self.scirxst.read() & 1 == 0 {} // RXRDY
            self.scirxbuf.read()
        }
    }

    /// Initialize SCI: 8N1, given baud rate.
    /// `lsplclk` is low-speed peripheral clock in Hz (typically 30MHz or 60MHz).
    #[inline(always)]
    pub unsafe fn init(&self, baud: u32, lsplclk: u32) {
        unsafe {
            // Reset SCI
            self.scictl1.clear_bits(1 << 5); // SW RESET
            // 8-bit, 1 stop, no parity, idle-line mode
            self.sciccr.write(0x07); // STOP=0, PARITY=0, SCICHAR=111 (8 bits)
            // Baud rate: BRR = LSPCLK / (baud * 8) - 1
            let brr = (lsplclk / (baud * 8) - 1) as u16;
            self.scilbaud.write(brr & 0xFF);
            self.scihbaud.write((brr >> 8) & 0xFF);
            // Enable TX/RX, release reset
            self.scictl1.write((1 << 5) | (1 << 4) | (1 << 3)); // SW RESET=1, TXENA=1, RXENA=1
            self.scictl2.write((1 << 7) | (1 << 6)); // TX/RX FIFO reset
            self.scictl2.write(0); // FIFO normal mode
        }
    }

    /// Write a null-terminated string.
    #[inline(always)]
    pub unsafe fn write_str(&self, s: &str) {
        for &b in s.as_bytes() {
            unsafe { self.write_byte(b as u16) };
        }
    }
}

// ---------------------------------------------------------------------------
// I2C (base 0x7900)
// ---------------------------------------------------------------------------

pub struct I2c {
    pub i2coar: Reg,       // 0  Own Address
    pub i2cier: Reg,       // 1  Interrupt Enable
    pub i2cstr: Reg,       // 2  Interrupt Status
    pub i2cclkl: Reg,      // 3  Clock Divider Low
    pub i2cclkh: Reg,      // 4  Clock Divider High
    pub i2ccnt: Reg,       // 5  Data Count
    pub i2cdrr: Reg,       // 6  Data Receive
    pub i2csar: Reg,       // 7  Slave Address
    pub i2cdxr: Reg,       // 8  Data Transmit
    pub i2cmdr: Reg,       // 9  Mode
    pub i2cisrc: Reg,      // 10 Interrupt Source
    pub i2cemdr: Reg,      // 11 Extended Mode
    pub i2cpsc: Reg,       // 12 Prescaler
    pub rsvd1: [Reg; 19],  // 13-31
    pub i2cfftx: Reg,      // 32 FIFO Transmit
    pub i2cffrx: Reg,      // 33 FIFO Receive
}

impl I2c {
    #[inline(always)]
    const fn new() -> Self {
        const B: u16 = 0x7900;
        Self {
            i2coar: Reg::at(B + 0),
            i2cier: Reg::at(B + 1),
            i2cstr: Reg::at(B + 2),
            i2cclkl: Reg::at(B + 3),
            i2cclkh: Reg::at(B + 4),
            i2ccnt: Reg::at(B + 5),
            i2cdrr: Reg::at(B + 6),
            i2csar: Reg::at(B + 7),
            i2cdxr: Reg::at(B + 8),
            i2cmdr: Reg::at(B + 9),
            i2cisrc: Reg::at(B + 10),
            i2cemdr: Reg::at(B + 11),
            i2cpsc: Reg::at(B + 12),
            rsvd1: [
                Reg::at(B + 13), Reg::at(B + 14), Reg::at(B + 15), Reg::at(B + 16),
                Reg::at(B + 17), Reg::at(B + 18), Reg::at(B + 19), Reg::at(B + 20),
                Reg::at(B + 21), Reg::at(B + 22), Reg::at(B + 23), Reg::at(B + 24),
                Reg::at(B + 25), Reg::at(B + 26), Reg::at(B + 27), Reg::at(B + 28),
                Reg::at(B + 29), Reg::at(B + 30), Reg::at(B + 31),
            ],
            i2cfftx: Reg::at(B + 32),
            i2cffrx: Reg::at(B + 33),
        }
    }
}

// ---------------------------------------------------------------------------
// ADC (control base 0x7100, result base 0x0B00)
// ---------------------------------------------------------------------------

pub struct Adc {
    pub adcctl1: Reg,          // 0x7100
    pub adcctl2: Reg,          // 0x7101
    pub rsvd1: [Reg; 2],       // 0x7102-0x7103
    pub adcintflg: Reg,        // 0x7104
    pub adcintflgclr: Reg,     // 0x7105
    pub adcintovf: Reg,        // 0x7106
    pub adcintovfclr: Reg,     // 0x7107
    pub intsel1n2: Reg,        // 0x7108
    pub intsel3n4: Reg,        // 0x7109
    pub intsel5n6: Reg,        // 0x710A
    pub intsel7n8: Reg,        // 0x710B
    pub intsel9n10: Reg,       // 0x710C
    pub rsvd2: [Reg; 3],       // 0x710D-0x710F
    pub socprictl: Reg,        // 0x7110
    pub rsvd3: Reg,            // 0x7111
    pub adcsamplemode: Reg,    // 0x7112
    pub rsvd4: Reg,            // 0x7113
    pub adcintsocsel1: Reg,    // 0x7114
    pub adcintsocsel2: Reg,    // 0x7115
    pub rsvd5: [Reg; 2],       // 0x7116-0x7117
    pub adcsocflg1: Reg,       // 0x7118
    pub rsvd6: Reg,            // 0x7119
    pub adcsocfrc1: Reg,       // 0x711A
    pub rsvd7: Reg,            // 0x711B
    pub adcsocovf1: Reg,       // 0x711C
    pub rsvd8: Reg,            // 0x711D
    pub adcsocovfclr1: Reg,    // 0x711E
    pub rsvd9: Reg,            // 0x711F
    pub adcsoc0ctl: Reg,       // 0x7120
    pub adcsoc1ctl: Reg,       // 0x7121
    pub adcsoc2ctl: Reg,       // 0x7122
    pub adcsoc3ctl: Reg,       // 0x7123
    pub adcsoc4ctl: Reg,       // 0x7124
    pub adcsoc5ctl: Reg,       // 0x7125
    pub adcsoc6ctl: Reg,       // 0x7126
    pub adcsoc7ctl: Reg,       // 0x7127
    pub adcsoc8ctl: Reg,       // 0x7128
    pub adcsoc9ctl: Reg,       // 0x7129
    pub adcsoc10ctl: Reg,      // 0x712A
    pub adcsoc11ctl: Reg,      // 0x712B
    pub adcsoc12ctl: Reg,      // 0x712C
    pub adcsoc13ctl: Reg,      // 0x712D
    pub adcsoc14ctl: Reg,      // 0x712E
    pub adcsoc15ctl: Reg,      // 0x712F
    pub rsvd10: [Reg; 16],     // 0x7130-0x713F
    pub adcreftrim: Reg,       // 0x7140
    pub adcofftrim: Reg,       // 0x7141
    pub rsvd11: [Reg; 10],     // 0x7142-0x714B
    pub comphystctl: Reg,      // 0x714C
}

pub struct AdcResult {
    pub result0: Reg,   // 0x0B00
    pub result1: Reg,
    pub result2: Reg,
    pub result3: Reg,
    pub result4: Reg,
    pub result5: Reg,
    pub result6: Reg,
    pub result7: Reg,
    pub result8: Reg,
    pub result9: Reg,
    pub result10: Reg,
    pub result11: Reg,
    pub result12: Reg,
    pub result13: Reg,
    pub result14: Reg,
    pub result15: Reg,
}

impl Adc {
    #[inline(always)]
    const fn new() -> Self {
        const B: u16 = 0x7100;
        Self {
            adcctl1: Reg::at(B + 0),
            adcctl2: Reg::at(B + 1),
            rsvd1: [Reg::at(B + 2), Reg::at(B + 3)],
            adcintflg: Reg::at(B + 4),
            adcintflgclr: Reg::at(B + 5),
            adcintovf: Reg::at(B + 6),
            adcintovfclr: Reg::at(B + 7),
            intsel1n2: Reg::at(B + 8),
            intsel3n4: Reg::at(B + 9),
            intsel5n6: Reg::at(B + 10),
            intsel7n8: Reg::at(B + 11),
            intsel9n10: Reg::at(B + 12),
            rsvd2: [Reg::at(B + 13), Reg::at(B + 14), Reg::at(B + 15)],
            socprictl: Reg::at(B + 16),
            rsvd3: Reg::at(B + 17),
            adcsamplemode: Reg::at(B + 18),
            rsvd4: Reg::at(B + 19),
            adcintsocsel1: Reg::at(B + 20),
            adcintsocsel2: Reg::at(B + 21),
            rsvd5: [Reg::at(B + 22), Reg::at(B + 23)],
            adcsocflg1: Reg::at(B + 24),
            rsvd6: Reg::at(B + 25),
            adcsocfrc1: Reg::at(B + 26),
            rsvd7: Reg::at(B + 27),
            adcsocovf1: Reg::at(B + 28),
            rsvd8: Reg::at(B + 29),
            adcsocovfclr1: Reg::at(B + 30),
            rsvd9: Reg::at(B + 31),
            adcsoc0ctl: Reg::at(B + 32),
            adcsoc1ctl: Reg::at(B + 33),
            adcsoc2ctl: Reg::at(B + 34),
            adcsoc3ctl: Reg::at(B + 35),
            adcsoc4ctl: Reg::at(B + 36),
            adcsoc5ctl: Reg::at(B + 37),
            adcsoc6ctl: Reg::at(B + 38),
            adcsoc7ctl: Reg::at(B + 39),
            adcsoc8ctl: Reg::at(B + 40),
            adcsoc9ctl: Reg::at(B + 41),
            adcsoc10ctl: Reg::at(B + 42),
            adcsoc11ctl: Reg::at(B + 43),
            adcsoc12ctl: Reg::at(B + 44),
            adcsoc13ctl: Reg::at(B + 45),
            adcsoc14ctl: Reg::at(B + 46),
            adcsoc15ctl: Reg::at(B + 47),
            rsvd10: [
                Reg::at(B + 48), Reg::at(B + 49), Reg::at(B + 50), Reg::at(B + 51),
                Reg::at(B + 52), Reg::at(B + 53), Reg::at(B + 54), Reg::at(B + 55),
                Reg::at(B + 56), Reg::at(B + 57), Reg::at(B + 58), Reg::at(B + 59),
                Reg::at(B + 60), Reg::at(B + 61), Reg::at(B + 62), Reg::at(B + 63),
            ],
            adcreftrim: Reg::at(B + 64),
            adcofftrim: Reg::at(B + 65),
            rsvd11: [
                Reg::at(B + 66), Reg::at(B + 67), Reg::at(B + 68), Reg::at(B + 69),
                Reg::at(B + 70), Reg::at(B + 71), Reg::at(B + 72), Reg::at(B + 73),
                Reg::at(B + 74), Reg::at(B + 75),
            ],
            comphystctl: Reg::at(B + 76),
        }
    }

    /// Force SOC0 conversion.
    #[inline(always)]
    pub unsafe fn force_soc0(&self) {
        unsafe { self.adcsocfrc1.write(1) }
    }

    /// Initialize ADC: power up, set sampling mode, configure SOC0 for software trigger.
    #[inline(always)]
    pub unsafe fn init(&self) {
        unsafe {
            // Power up ADC bandgap and reference
            self.adcctl1.modify(|v| (v & !(3 << 6)) | (1 << 6)); // ADCBGPWD=1
            self.adcctl1.modify(|v| (v & !(3 << 4)) | (1 << 4)); // ADCPWMD=1
            // Wait for power up (approx 1ms at 60MHz)
            let mut i = 0u16;
            while i < 1000 { i += 1; }
            // Set SOC0 trigger = software (no trigger), channel = ADCINA0
            self.adcsoc0ctl.write(0); // CHSEL=0 (ADCINA0), TRIGSEL=0 (software)
            // Sample window = 16 cycles
            self.adcsoc0ctl.modify(|v| (v & !(0xFF << 8)) | (16 << 8));
        }
    }

    /// Read a single ADC channel (0-15) via SOC0, blocking until conversion complete.
    /// Returns 12-bit result (0-4095).
    #[inline(always)]
    pub unsafe fn read_channel(&self, channel: u16) -> u16 {
        unsafe {
            // Configure SOC0 channel
            self.adcsoc0ctl.modify(|v| (v & !(0xF << 0)) | (channel & 0xF));
            // Clear ADCINT1 flag
            self.adcintflg.write(1);
            // Force SOC0
            self.adcsocfrc1.write(1);
            // Wait for ADCINT1 (conversion complete)
            while self.adcintflg.read() & 1 == 0 {}
            // Read result from ADCRESULT0 (result registers are at 0x0B00)
            let result_p = (0x0B00u32 * 2) as *const u16;
            core::intrinsics::volatile_load(result_p)
        }
    }
}

impl AdcResult {
    #[inline(always)]
    const fn new() -> Self {
        const B: u16 = 0x0B00;
        Self {
            result0: Reg::at(B + 0),
            result1: Reg::at(B + 1),
            result2: Reg::at(B + 2),
            result3: Reg::at(B + 3),
            result4: Reg::at(B + 4),
            result5: Reg::at(B + 5),
            result6: Reg::at(B + 6),
            result7: Reg::at(B + 7),
            result8: Reg::at(B + 8),
            result9: Reg::at(B + 9),
            result10: Reg::at(B + 10),
            result11: Reg::at(B + 11),
            result12: Reg::at(B + 12),
            result13: Reg::at(B + 13),
            result14: Reg::at(B + 14),
            result15: Reg::at(B + 15),
        }
    }
}

// ---------------------------------------------------------------------------
// ePWM (base 0x6800, stride 0x40 words; 7 instances on F28035)
// ---------------------------------------------------------------------------

pub struct EPwm {
    pub tbctl: Reg,       // 0  Time Base Control
    pub tbsts: Reg,       // 1  Time Base Status
    pub tbphs: Reg32,     // 2-3 Time Base Phase (32-bit)
    pub tbctr: Reg,       // 4  Time Base Counter
    pub tbprd: Reg,       // 5  Time Base Period
    pub tbprdhr: Reg,     // 6  Time Base Period High-Res
    pub cmpctl: Reg,      // 7  Compare Control
    pub cmpa: Reg32,      // 8-9 Compare A (32-bit)
    pub cmpb: Reg,        // 10 Compare B
    pub aqctla: Reg,      // 11 Action Qualifier Output A
    pub aqctlb: Reg,      // 12 Action Qualifier Output B
    pub aqsfrc: Reg,      // 13 Action Qualifier SW Force
    pub aqcsfrc: Reg,     // 14 Action Qualifier Continuous SW Force
    pub dbctl: Reg,       // 15 Dead-Band Control
    pub dbred: Reg,       // 16 Dead-Band Rising Edge Delay
    pub dbfed: Reg,       // 17 Dead-Band Falling Edge Delay
    pub tzsel: Reg,       // 18 Trip Zone Select
    pub tzdcsel: Reg,     // 19 Trip Zone Digital Comparator Select
    pub tzctl: Reg,       // 20 Trip Zone Control
    pub tzeint: Reg,      // 21 Trip Zone Interrupt Enable
    pub tzflg: Reg,       // 22 Trip Zone Flag
    pub tzclr: Reg,       // 23 Trip Zone Clear
    pub tzfrc: Reg,       // 24 Trip Zone Force
    pub etsel: Reg,       // 25 Event Trigger Select
    pub etps: Reg,        // 26 Event Trigger Prescaler
    pub etflg: Reg,       // 27 Event Trigger Flag
    pub etclr: Reg,       // 28 Event Trigger Clear
    pub etfrc: Reg,       // 29 Event Trigger Force
    pub pcctl: Reg,       // 30 PWM Chopper Control
    pub rsvd1: Reg,       // 31
    pub hrcnfg: Reg,      // 32 HRPWM Config
    pub hrpwr: Reg,       // 33 HRPWM Power
    pub rsvd2: [Reg; 4],  // 34-37
    pub hrmstep: Reg,     // 38 HRPWM MEP Step
    pub rsvd3: Reg,       // 39
    pub hrpctl: Reg,      // 40 High-Res Period Control
    pub rsvd4: Reg,       // 41
    pub tbprdm: Reg32,    // 42-43 TBPRD Mirror (32-bit)
    pub cmpam: Reg32,     // 44-45 CMPA Mirror (32-bit)
    pub rsvd5: [Reg; 2],  // 46-47
    pub dctripsel: Reg,   // 48 Digital Compare Trip Select
    pub dcactl: Reg,      // 49 Digital Compare A Control
    pub dcbctl: Reg,      // 50 Digital Compare B Control
    pub dcfctl: Reg,      // 51 Digital Compare Filter Control
    pub dccapctl: Reg,    // 52 Digital Compare Capture Control
    pub dcfoffset: Reg,   // 53 Digital Compare Filter Offset
}

impl EPwm {
    #[inline(always)]
    const fn new(base: u16) -> Self {
        Self {
            tbctl: Reg::at(base + 0),
            tbsts: Reg::at(base + 1),
            tbphs: Reg32::at(base + 2),
            tbctr: Reg::at(base + 4),
            tbprd: Reg::at(base + 5),
            tbprdhr: Reg::at(base + 6),
            cmpctl: Reg::at(base + 7),
            cmpa: Reg32::at(base + 8),
            cmpb: Reg::at(base + 10),
            aqctla: Reg::at(base + 11),
            aqctlb: Reg::at(base + 12),
            aqsfrc: Reg::at(base + 13),
            aqcsfrc: Reg::at(base + 14),
            dbctl: Reg::at(base + 15),
            dbred: Reg::at(base + 16),
            dbfed: Reg::at(base + 17),
            tzsel: Reg::at(base + 18),
            tzdcsel: Reg::at(base + 19),
            tzctl: Reg::at(base + 20),
            tzeint: Reg::at(base + 21),
            tzflg: Reg::at(base + 22),
            tzclr: Reg::at(base + 23),
            tzfrc: Reg::at(base + 24),
            etsel: Reg::at(base + 25),
            etps: Reg::at(base + 26),
            etflg: Reg::at(base + 27),
            etclr: Reg::at(base + 28),
            etfrc: Reg::at(base + 29),
            pcctl: Reg::at(base + 30),
            rsvd1: Reg::at(base + 31),
            hrcnfg: Reg::at(base + 32),
            hrpwr: Reg::at(base + 33),
            rsvd2: [
                Reg::at(base + 34), Reg::at(base + 35),
                Reg::at(base + 36), Reg::at(base + 37),
            ],
            hrmstep: Reg::at(base + 38),
            rsvd3: Reg::at(base + 39),
            hrpctl: Reg::at(base + 40),
            rsvd4: Reg::at(base + 41),
            tbprdm: Reg32::at(base + 42),
            cmpam: Reg32::at(base + 44),
            rsvd5: [Reg::at(base + 46), Reg::at(base + 47)],
            dctripsel: Reg::at(base + 48),
            dcactl: Reg::at(base + 49),
            dcbctl: Reg::at(base + 50),
            dcfctl: Reg::at(base + 51),
            dccapctl: Reg::at(base + 52),
            dcfoffset: Reg::at(base + 53),
        }
    }

    /// Initialize ePWM: up-count mode, given period and duty on output A.
    /// `tbclk_hz` is time-base clock in Hz (typically SYSCLKOUT = 60MHz).
    /// `freq_hz` is desired PWM frequency.
    /// `duty_percent` is 0-100.
    #[inline(always)]
    pub unsafe fn init(&self, tbclk_hz: u32, freq_hz: u32, duty_percent: u16) {
        unsafe {
            // Period = TBPRD = TB_CLK / (2 * freq) for up-down, or TB_CLK / freq for up-count
            // Use up-count mode: period = tbclk / freq
            let period = (tbclk_hz / freq_hz) as u16;
            self.tbprd.write(period);
            // Time base: up-count, sync disabled
            self.tbctl.write(0); // CTRMODE=00 (up-count)
            // Compare A: duty = period * duty_percent / 100
            let cmp = (period as u32 * duty_percent as u32 / 100) as u16;
            self.cmpa.write(cmp as u32);
            // Action qualifier: set on CMPA up, clear on period
            self.aqctla.write((2 << 4) | (1 << 0)); // CAU=set(2), PRD=clear(1)
            // Enable output
            self.aqcsfrc.write(0);
        }
    }

    /// Set duty cycle on output A (0-100 percent).
    #[inline(always)]
    pub unsafe fn set_duty(&self, duty_percent: u16) {
        unsafe {
            let period = self.tbprd.read() as u32;
            let cmp = (period * duty_percent as u32 / 100) as u16;
            self.cmpa.write(cmp as u32);
        }
    }
}

// ---------------------------------------------------------------------------
// eCAP (base 0x6A00)
// ---------------------------------------------------------------------------

pub struct ECap {
    pub tsctr: Reg32,    // 0-1 Time Stamp Counter (32-bit)
    pub ctrphs: Reg32,   // 2-3 Counter Phase (32-bit)
    pub cap1: Reg32,     // 4-5 Capture 1 (32-bit)
    pub cap2: Reg32,     // 6-7 Capture 2 (32-bit)
    pub cap3: Reg32,     // 8-9 Capture 3 (32-bit)
    pub cap4: Reg32,     // 10-11 Capture 4 (32-bit)
    pub rsvd1: [Reg; 8], // 12-19
    pub ecctl1: Reg,     // 20 Capture Control 1
    pub ecctl2: Reg,     // 21 Capture Control 2
    pub eceint: Reg,     // 22 Interrupt Enable
    pub ecflg: Reg,      // 23 Interrupt Flag
    pub ecclr: Reg,      // 24 Interrupt Clear
    pub ecfrc: Reg,      // 25 Interrupt Force
}

impl ECap {
    #[inline(always)]
    const fn new(base: u16) -> Self {
        Self {
            tsctr: Reg32::at(base + 0),
            ctrphs: Reg32::at(base + 2),
            cap1: Reg32::at(base + 4),
            cap2: Reg32::at(base + 6),
            cap3: Reg32::at(base + 8),
            cap4: Reg32::at(base + 10),
            rsvd1: [
                Reg::at(base + 12), Reg::at(base + 13), Reg::at(base + 14), Reg::at(base + 15),
                Reg::at(base + 16), Reg::at(base + 17), Reg::at(base + 18), Reg::at(base + 19),
            ],
            ecctl1: Reg::at(base + 20),
            ecctl2: Reg::at(base + 21),
            eceint: Reg::at(base + 22),
            ecflg: Reg::at(base + 23),
            ecclr: Reg::at(base + 24),
            ecfrc: Reg::at(base + 25),
        }
    }
}

// ---------------------------------------------------------------------------
// eQEP (base 0x6B00)
// ---------------------------------------------------------------------------

pub struct EQep {
    pub qposcnt: Reg32,    // 0-1 Position Counter (32-bit)
    pub qposinit: Reg32,   // 2-3 Position Init (32-bit)
    pub qposmax: Reg32,    // 4-5 Position Max (32-bit)
    pub qposcmp: Reg32,    // 6-7 Position Compare (32-bit)
    pub qposilat: Reg32,   // 8-9 Index Position Latch (32-bit)
    pub qposslat: Reg32,   // 10-11 Strobe Position Latch (32-bit)
    pub qposlat: Reg32,    // 12-13 Position Latch (32-bit)
    pub qutmr: Reg32,      // 14-15 Unit Timer (32-bit)
    pub quprd: Reg32,      // 16-17 Unit Period (32-bit)
    pub qwdtmr: Reg,       // 18 Watchdog Timer
    pub qwdprd: Reg,       // 19 Watchdog Period
    pub qdecctl: Reg,      // 20 Quadrature Decoder Control
    pub qepctl: Reg,       // 21 QEP Control
    pub qcapctl: Reg,      // 22 Capture Control
    pub qposctl: Reg,      // 23 Position Compare Control
    pub qeint: Reg,        // 24 Interrupt Enable
    pub qflg: Reg,         // 25 Interrupt Flag
    pub qclr: Reg,         // 26 Interrupt Clear
    pub qfrc: Reg,         // 27 Interrupt Force
    pub qepsts: Reg,       // 28 Status
    pub qctmr: Reg,        // 29 Capture Timer
    pub qcprd: Reg,        // 30 Capture Period
    pub qctmrlat: Reg,     // 31 Capture Timer Latch
    pub qcprdlat: Reg,     // 32 Capture Period Latch
}

impl EQep {
    #[inline(always)]
    const fn new() -> Self {
        const B: u16 = 0x6B00;
        Self {
            qposcnt: Reg32::at(B + 0),
            qposinit: Reg32::at(B + 2),
            qposmax: Reg32::at(B + 4),
            qposcmp: Reg32::at(B + 6),
            qposilat: Reg32::at(B + 8),
            qposslat: Reg32::at(B + 10),
            qposlat: Reg32::at(B + 12),
            qutmr: Reg32::at(B + 14),
            quprd: Reg32::at(B + 16),
            qwdtmr: Reg::at(B + 18),
            qwdprd: Reg::at(B + 19),
            qdecctl: Reg::at(B + 20),
            qepctl: Reg::at(B + 21),
            qcapctl: Reg::at(B + 22),
            qposctl: Reg::at(B + 23),
            qeint: Reg::at(B + 24),
            qflg: Reg::at(B + 25),
            qclr: Reg::at(B + 26),
            qfrc: Reg::at(B + 27),
            qepsts: Reg::at(B + 28),
            qctmr: Reg::at(B + 29),
            qcprd: Reg::at(B + 30),
            qctmrlat: Reg::at(B + 31),
            qcprdlat: Reg::at(B + 32),
        }
    }
}

// ---------------------------------------------------------------------------
// GPIO (control base 0x6F80, data base 0x6FC0)
// ---------------------------------------------------------------------------

pub struct Gpio {
    // --- Port A Control (0x6F80) — all EALLOW-protected ---
    pub gpacontrol: ProtectedReg,   // 0x6F80
    pub gpaqsel1: ProtectedReg,     // 0x6F82
    pub gpaqsel2: ProtectedReg,     // 0x6F84
    pub gpamux1: ProtectedReg,      // 0x6F86
    pub gpamux2: ProtectedReg,      // 0x6F88
    pub gpadir: ProtectedReg,       // 0x6F8A
    pub gpapud: ProtectedReg,       // 0x6F8C
    // --- Port B Control — all EALLOW-protected ---
    pub gpbcontrol: ProtectedReg,   // 0x6F90
    pub gpbqsel1: ProtectedReg,     // 0x6F92
    pub gpbqsel2: ProtectedReg,     // 0x6F94
    pub gpbmux1: ProtectedReg,      // 0x6F96
    pub gpbmux2: ProtectedReg,      // 0x6F98
    pub gpbdir: ProtectedReg,       // 0x6F9A
    pub gpbpud: ProtectedReg,       // 0x6F9C
    // --- Port A Data (0x6FC0) — NOT EALLOW-protected ---
    pub gpadat: Reg32,       // 0x6FC0
    pub gpaset: Reg32,       // 0x6FC2
    pub gpaclear: Reg32,     // 0x6FC4
    pub gpatoggle: Reg32,    // 0x6FC6
    // --- Port B Data — NOT EALLOW-protected ---
    pub gpbdat: Reg32,       // 0x6FC8
    pub gpbset: Reg32,       // 0x6FCA
    pub gpbclear: Reg32,     // 0x6FCC
    pub gpbtoggle: Reg32,    // 0x6FCE
}

impl Gpio {
    #[inline(always)]
    const fn new() -> Self {
        Self {
            gpacontrol: ProtectedReg::at(0x6F80),
            gpaqsel1: ProtectedReg::at(0x6F82),
            gpaqsel2: ProtectedReg::at(0x6F84),
            gpamux1: ProtectedReg::at(0x6F86),
            gpamux2: ProtectedReg::at(0x6F88),
            gpadir: ProtectedReg::at(0x6F8A),
            gpapud: ProtectedReg::at(0x6F8C),
            gpbcontrol: ProtectedReg::at(0x6F90),
            gpbqsel1: ProtectedReg::at(0x6F92),
            gpbqsel2: ProtectedReg::at(0x6F94),
            gpbmux1: ProtectedReg::at(0x6F96),
            gpbmux2: ProtectedReg::at(0x6F98),
            gpbdir: ProtectedReg::at(0x6F9A),
            gpbpud: ProtectedReg::at(0x6F9C),
            gpadat: Reg32::at(0x6FC0),
            gpaset: Reg32::at(0x6FC2),
            gpaclear: Reg32::at(0x6FC4),
            gpatoggle: Reg32::at(0x6FC6),
            gpbdat: Reg32::at(0x6FC8),
            gpbset: Reg32::at(0x6FCA),
            gpbclear: Reg32::at(0x6FCC),
            gpbtoggle: Reg32::at(0x6FCE),
        }
    }
}

// ---------------------------------------------------------------------------
// Peripherals singleton
// ---------------------------------------------------------------------------

struct TakeGuard {
    taken: UnsafeCell<bool>,
}

unsafe impl Sync for TakeGuard {}

static PERIPHERALS_TAKEN: TakeGuard = TakeGuard {
    taken: UnsafeCell::new(false),
};

/// All F28035 peripherals.
pub struct Peripherals {
    pub sysctrl: SysCtrl,
    pub cputimer0: CpuTimer,
    pub cputimer1: CpuTimer,
    pub cputimer2: CpuTimer,
    pub piectrl: PieCtrl,
    pub spia: Spi,
    pub spib: Spi,
    pub scia: Sci,
    pub i2ca: I2c,
    pub adc: Adc,
    pub adc_result: AdcResult,
    pub epwm1: EPwm,
    pub epwm2: EPwm,
    pub epwm3: EPwm,
    pub epwm4: EPwm,
    pub epwm5: EPwm,
    pub epwm6: EPwm,
    pub epwm7: EPwm,
    pub ecap1: ECap,
    pub eqep1: EQep,
    pub gpio: Gpio,
}

impl Peripherals {
    /// Enter EALLOW-protected region. Returns a token that grants write access
    /// to EALLOW-protected registers (GPIO mux/dir/pud, SysCtrl clock config,
    /// WDCR, etc.). EDIS is executed automatically when the token is dropped.
    #[inline(always)]
    pub fn eallow(&self) -> EallowToken {
        unsafe { EallowToken::new() }
    }

    #[inline(always)]
    pub fn take() -> Option<Self> {
        let taken = unsafe { &mut *PERIPHERALS_TAKEN.taken.get() };
        if *taken {
            None
        } else {
            *taken = true;
            Some(Self::new())
        }
    }

    #[inline(always)]
    pub const unsafe fn steal() -> Self {
        Self::new()
    }

    #[inline(always)]
    const fn new() -> Self {
        Self {
            sysctrl: SysCtrl::new(),
            cputimer0: CpuTimer::new(0x0C00),
            cputimer1: CpuTimer::new(0x0C08),
            cputimer2: CpuTimer::new(0x0C10),
            piectrl: PieCtrl::new(),
            spia: Spi::new(0x7040),
            spib: Spi::new(0x7740),
            scia: Sci::new(),
            i2ca: I2c::new(),
            adc: Adc::new(),
            adc_result: AdcResult::new(),
            epwm1: EPwm::new(0x6800),
            epwm2: EPwm::new(0x6840),
            epwm3: EPwm::new(0x6880),
            epwm4: EPwm::new(0x68C0),
            epwm5: EPwm::new(0x6900),
            epwm6: EPwm::new(0x6940),
            epwm7: EPwm::new(0x6980),
            ecap1: ECap::new(0x6A00),
            eqep1: EQep::new(),
            gpio: Gpio::new(),
        }
    }
}

// ---------------------------------------------------------------------------
// CPU interrupt management (IER / INTM — not memory-mapped, use asm helpers)
// ---------------------------------------------------------------------------

extern "C" {
    fn eint();
    fn dint();
    fn ier_or(mask: u16);
    fn ier_and(mask: u16);
    /// Emit the EALLOW instruction (opcode 0x7622). Defined in assembly.
    fn eallow_inst();
    /// Emit the EDIS instruction (opcode 0x761A). Defined in assembly.
    fn edis_inst();
}

/// Enable global interrupts (CLRC INTM).
#[inline(always)]
pub unsafe fn enable_global() {
    unsafe { eint() }
}

/// Disable global interrupts (SETC INTM).
#[inline(always)]
pub unsafe fn disable_global() {
    unsafe { dint() }
}

/// Enable a CPU interrupt line (1-12) by setting its IER bit.
#[inline(always)]
pub unsafe fn enable_cpu_int(int_num: u16) {
    unsafe { ier_or(1 << (int_num - 1)) }
}

/// Disable a CPU interrupt line (1-12) by clearing its IER bit.
#[inline(always)]
pub unsafe fn disable_cpu_int(int_num: u16) {
    unsafe { ier_and(!(1 << (int_num - 1))) }
}
