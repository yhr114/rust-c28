//! F28035 peripheral access definitions.
//!
//! This is the first PAC layer, deliberately separate from the safe HAL in
//! `lib.rs`.  Addresses are TI *physical word* addresses: they must never be
//! converted to ordinary Rust byte pointers.  The [`MmioBus`] trait abstracts
//! word read/write.  Host tests execute every register sequence through
//! [`HostMmio`], a 64k-word register model, and the resulting side effects
//! are cross-checked against the existing C bridge.  Direct C28x MMIO lowering
//! of these primitives is the pending backend milestone -- until then the HAL
//! keeps calling the C bridge, and nothing here runs on the target.
#[cfg(test)]
extern crate std;

/// A C28x physical 16-bit word address used exclusively for MMIO.
///
/// This prevents accidentally treating a TI linker/MMIO address as a normal
/// Rust byte pointer, whose representation is different on this target.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(transparent)]
pub struct TiWordAddress(u16);

impl TiWordAddress {
    pub const fn new(value: u16) -> Self {
        Self(value)
    }

    pub const fn get(self) -> u16 {
        self.0
    }

    pub const fn offset_words(self, offset: u16) -> Self {
        Self(self.0 + offset)
    }

    /// Reads this physical word through the supplied bus.
    ///
    /// # Safety
    ///
    /// The caller must guarantee that `self` names a valid, readable register
    /// and that the bus outlives the call.  On real hardware this lowers to a
    /// direct C28x word load once the backend accepts it; until then it only
    /// executes in host tests.
    pub unsafe fn read<B: MmioBus>(self, bus: &mut B) -> u16 {
        // SAFETY: forwarded contract from the caller.
        unsafe { bus.read_word(self) }
    }

    /// Writes this physical word through the supplied bus.
    ///
    /// # Safety
    ///
    /// The caller must guarantee that `self` names a valid, writable register
    /// (never a read-only result register or an aliasing command register
    /// unless that aliasing is intended).
    pub unsafe fn write<B: MmioBus>(self, bus: &mut B, value: u16) {
        // SAFETY: forwarded contract from the caller.
        unsafe { bus.write_word(self, value) };
    }

    /// Read-modify-write one word: `(current & !mask) | (bits & mask)`.
    ///
    /// Use this only for configuration registers whose fields must be updated
    /// without touching neighbouring fields.  GPIO SET/CLEAR/TOGGLE command
    /// registers are *write-only commands* and must never be read back.
    ///
    /// # Safety
    ///
    /// Same as [`TiWordAddress::write`], plus the register must support
    /// read-modify-write semantics (not a write-only command register).
    pub unsafe fn modify<B: MmioBus>(self, bus: &mut B, mask: u16, bits: u16) {
        // SAFETY: forwarded contract from the caller.
        let current = unsafe { bus.read_word(self) };
        let updated = (current & !mask) | (bits & mask);
        // SAFETY: forwarded contract from the caller.
        unsafe { bus.write_word(self, updated) };
    }
}

/// Abstract C28x MMIO word access.
///
/// The host test harness uses [`HostMmio`].  On real hardware a bus backed by
/// direct C28x word loads/stores will be implemented by the MIR backend once
/// `TiWordAddress` volatile access is audited; the unsafe API shape here is
/// frozen in the meantime so register-level code can be written and verified
/// on the host first.
pub unsafe trait MmioBus {
    /// Reads one 16-bit physical word.
    ///
    /// # Safety
    ///
    /// `address` must name a readable register in the bus's address space.
    unsafe fn read_word(&mut self, address: TiWordAddress) -> u16;

    /// Writes one 16-bit physical word.
    ///
    /// # Safety
    ///
    /// `address` must name a writable register in the bus's address space.
    unsafe fn write_word(&mut self, address: TiWordAddress, value: u16);
}

/// Host simulation of the F28035 64k-word peripheral address space.
///
/// Storage is one `u16` per physical word, indexed directly by the word
/// address.  It models *storage only*: writing a GPIO SET command record does
/// not spontaneously flip the corresponding DAT bit here; that hardware
/// behaviour is verified on the real target.
#[cfg(test)]
pub struct HostMmio {
    words: std::vec::Vec<u16>,
}

#[cfg(test)]
impl HostMmio {
    /// Creates an empty, all-zero register file covering `0x0000..=0xFFFF`.
    pub fn new() -> Self {
        Self {
            words: std::vec![0; 0x10000],
        }
    }

    /// Direct peek used by tests to inspect storage bypassing the bus trait.
    pub fn peek(&self, address: TiWordAddress) -> u16 {
        self.words[address.get() as usize]
    }
}

#[cfg(test)]
impl Default for HostMmio {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
// SAFETY: the model covers every physical word address in a plain Vec.
unsafe impl MmioBus for HostMmio {
    unsafe fn read_word(&mut self, address: TiWordAddress) -> u16 {
        self.words[address.get() as usize]
    }

    unsafe fn write_word(&mut self, address: TiWordAddress, value: u16) {
        self.words[address.get() as usize] = value;
    }
}

/// The target-side MMIO bus: every word address is a physical C28x register.
///
/// On the real device the audited MIR backend lowers [`MmioBus::read_word`]
/// / [`MmioBus::write_word`] calls to direct C28x word load/store when it
/// classifies the containing function; until then these bodies exist only
/// so the typed API has a non-host bus to type-check against.  They are
/// never actually executed by the generated firmware (the backend inlines
/// each recognized call as a fixed MMIO sequence).
#[cfg(not(test))]
pub struct C28xMmio;

#[cfg(not(test))]
// SAFETY: every `TiWordAddress` in this PAC is a valid physical C28x word
// register; the backend selects them by constant and never dereferences a
// computed address.
unsafe impl MmioBus for C28xMmio {
    unsafe fn read_word(&mut self, address: TiWordAddress) -> u16 {
        // SAFETY: forwarded by the PAC callers; lowered by the backend.
        unsafe { (usize::from(address.get()) as *const u16).read_volatile() }
    }

    unsafe fn write_word(&mut self, address: TiWordAddress, value: u16) {
        // SAFETY: forwarded by the PAC callers; lowered by the backend.
        unsafe { (usize::from(address.get()) as *mut u16).write_volatile(value) }
    }
}

/// A 32-bit F28035 register represented as two adjacent C28x words.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Register32 {
    address: TiWordAddress,
}

impl Register32 {
    pub const fn at(address: TiWordAddress) -> Self {
        Self { address }
    }

    pub const fn address(self) -> TiWordAddress {
        self.address
    }

    /// Reads the 32-bit register as two little-endian physical words: the
    /// low word at `address`, the high word at `address + 1`.
    ///
    /// # Safety
    ///
    /// Same rules as [`TiWordAddress::read`]; the high word pair must also be
    /// a valid readable register.
    pub unsafe fn read_u32<B: MmioBus>(self, bus: &mut B) -> u32 {
        // SAFETY: forwarded contract from the caller.
        let low = unsafe { self.address.read(bus) } as u32;
        // SAFETY: forwarded contract from the caller.
        let high = unsafe { self.address.offset_words(1).read(bus) } as u32;
        low | (high << 16)
    }

    /// Writes the 32-bit register as two little-endian physical words.
    ///
    /// # Safety
    ///
    /// Same rules as [`TiWordAddress::write`] for both words of the pair.
    pub unsafe fn write_u32<B: MmioBus>(self, bus: &mut B, value: u32) {
        // SAFETY: forwarded contract from the caller.
        unsafe {
            self.address.write(bus, value as u16);
            self.address
                .offset_words(1)
                .write(bus, (value >> 16) as u16);
        }
    }

    /// Read-modify-write the 32-bit register: `(current & !mask) | (bits & mask)`.
    ///
    /// # Safety
    ///
    /// Same rules as [`TiWordAddress::modify`] for both words of the pair.
    pub unsafe fn modify_u32<B: MmioBus>(self, bus: &mut B, mask: u32, bits: u32) {
        // SAFETY: forwarded contract from the caller.
        let current = unsafe { self.read_u32(bus) };
        let updated = (current & !mask) | (bits & mask);
        // SAFETY: forwarded contract from the caller.
        unsafe { self.write_u32(bus, updated) };
    }
}

pub mod gpio {
    use super::{MmioBus, Register32, TiWordAddress};

    const GPIO_CTRL_BASE: TiWordAddress = TiWordAddress::new(0x6f80);
    const GPIO_DATA_BASE: TiWordAddress = TiWordAddress::new(0x6fc0);
    const GPIO_INT_BASE: TiWordAddress = TiWordAddress::new(0x6fe0);

    /// GPIO control registers used by the initial PAC subset.
    pub const GPA_CTRL: Register32 = Register32::at(GPIO_CTRL_BASE);
    pub const GPA_QSEL1: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(2));
    pub const GPA_QSEL2: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(4));
    pub const GPA_MUX1: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(6));
    pub const GPA_MUX2: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(8));
    pub const GPA_DIR: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(10));
    pub const GPA_PUD: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(12));
    pub const GPB_CTRL: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(18));
    pub const GPB_QSEL1: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(20));
    pub const GPB_MUX1: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(22));
    pub const GPB_DIR: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(26));
    pub const GPB_PUD: Register32 = Register32::at(GPIO_CTRL_BASE.offset_words(28));

    /// Atomic GPIO data command registers.  Writing a one affects only the
    /// selected pin; no read-modify-write of the data register is required.
    pub const GPA_DAT: Register32 = Register32::at(GPIO_DATA_BASE);
    pub const GPA_SET: Register32 = Register32::at(GPIO_DATA_BASE.offset_words(2));
    pub const GPA_CLEAR: Register32 = Register32::at(GPIO_DATA_BASE.offset_words(4));
    pub const GPA_TOGGLE: Register32 = Register32::at(GPIO_DATA_BASE.offset_words(6));
    pub const GPB_DAT: Register32 = Register32::at(GPIO_DATA_BASE.offset_words(8));
    pub const GPB_SET: Register32 = Register32::at(GPIO_DATA_BASE.offset_words(10));
    pub const GPB_CLEAR: Register32 = Register32::at(GPIO_DATA_BASE.offset_words(12));
    pub const GPB_TOGGLE: Register32 = Register32::at(GPIO_DATA_BASE.offset_words(14));

    pub const XINT1_SEL: TiWordAddress = GPIO_INT_BASE;
    pub const XINT2_SEL: TiWordAddress = GPIO_INT_BASE.offset_words(1);
    pub const XINT3_SEL: TiWordAddress = GPIO_INT_BASE.offset_words(2);

    /// The register operations needed to convert one valid F28035 pin into a
    /// GPIO output.  The HAL keeps this value private; future C28x MMIO
    /// lowering will consume these exact physical addresses and masks.
    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub struct OutputConfig {
        pub mux: Register32,
        pub direction: Register32,
        pub pin_mask: u32,
        pub mux_mask: u32,
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub struct OutputCommand {
        pub set: Register32,
        pub clear: Register32,
        pub toggle: Register32,
        pub pin_mask: u32,
    }

    impl OutputConfig {
        /// Programs the pin as a GPIO output through the bus: clears the
        /// 2-bit MUX field and sets the direction bit.  Mirrors the register
        /// side effects of `f28035_gpio_make_output`.
        ///
        /// EALLOW/EDIS bracketing is a backend responsibility on the target;
        /// on the host it is a no-op.
        ///
        /// # Safety
        ///
        /// Same rules as [`Register32::modify_u32`]; MUX and DIR are
        /// read-modify-write configuration registers.
        pub unsafe fn apply<B: MmioBus>(self, bus: &mut B) {
            // SAFETY: forwarded contract from the caller.
            unsafe {
                self.mux.modify_u32(bus, self.mux_mask, 0);
                self.direction.modify_u32(bus, self.pin_mask, self.pin_mask);
            }
        }
    }

    impl OutputCommand {
        /// Drives the pin high by writing the SET command word.
        ///
        /// # Safety
        ///
        /// The SET register is a write-only command; writing the pin mask is
        /// its entire semantics.
        pub unsafe fn set<B: MmioBus>(self, bus: &mut B) {
            // SAFETY: forwarded contract from the caller.
            unsafe { self.set.write_u32(bus, self.pin_mask) };
        }

        /// Drives the pin low by writing the CLEAR command word.
        ///
        /// # Safety
        /// Same as [`Self::set`].
        pub unsafe fn clear<B: MmioBus>(self, bus: &mut B) {
            // SAFETY: forwarded contract from the caller.
            unsafe { self.clear.write_u32(bus, self.pin_mask) };
        }

        /// Toggles the pin by writing the TOGGLE command word.
        ///
        /// # Safety
        /// Same as [`Self::set`].
        pub unsafe fn toggle<B: MmioBus>(self, bus: &mut B) {
            // SAFETY: forwarded contract from the caller.
            unsafe { self.toggle.write_u32(bus, self.pin_mask) };
        }
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub enum Qualification {
        Sync,
        Sample3,
        Sample6,
        Async,
    }

    impl Qualification {
        pub const fn bits(self) -> u32 {
            match self {
                Self::Sync => 0,
                Self::Sample3 => 1,
                Self::Sample6 => 2,
                Self::Async => 3,
            }
        }
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub struct InputConfig {
        pub mux: Register32,
        pub direction: Register32,
        pub pullup_disable: Register32,
        pub qualification: Register32,
        pub data: Register32,
        pub pin_mask: u32,
        pub mux_mask: u32,
        pub qualification_mask: u32,
        pub qualification_bits: u32,
        pub pullup_disable_bits: u32,
    }

    impl InputConfig {
        /// Reads the pin level from the data register.
        ///
        /// # Safety
        /// Same as [`Register32::read_u32`] for the data register.
        pub unsafe fn read<B: MmioBus>(self, bus: &mut B) -> bool {
            // SAFETY: forwarded contract from the caller.
            unsafe { (self.data.read_u32(bus) & self.pin_mask) != 0 }
        }

        /// Programs the pin as a GPIO input through the bus: clears the MUX
        /// field, clears the direction bit, writes the pull-up disable bit,
        /// and programs the qualification field.  Mirrors the register side
        /// effects of `f28035_gpio_make_input`.
        ///
        /// # Safety
        ///
        /// Same rules as [`Register32::modify_u32`]; all four registers are
        /// read-modify-write configuration registers.
        pub unsafe fn apply<B: MmioBus>(self, bus: &mut B) {
            // SAFETY: forwarded contract from the caller.
            unsafe {
                self.mux.modify_u32(bus, self.mux_mask, 0);
                self.direction.modify_u32(bus, self.pin_mask, 0);
                self.pullup_disable
                    .modify_u32(bus, self.pin_mask, self.pullup_disable_bits);
                self.qualification.modify_u32(
                    bus,
                    self.qualification_mask,
                    self.qualification_bits,
                );
            }
        }
    }

    pub const fn output_config(pin: u16) -> Option<OutputConfig> {
        if pin < 16 {
            let bit = 1u32 << pin;
            Some(OutputConfig {
                mux: GPA_MUX1,
                direction: GPA_DIR,
                pin_mask: bit,
                mux_mask: 3u32 << (pin * 2),
            })
        } else if pin < 32 {
            let bit = 1u32 << pin;
            Some(OutputConfig {
                mux: GPA_MUX2,
                direction: GPA_DIR,
                pin_mask: bit,
                mux_mask: 3u32 << ((pin - 16) * 2),
            })
        } else if pin <= 44 {
            let local_pin = pin - 32;
            let bit = 1u32 << local_pin;
            Some(OutputConfig {
                mux: GPB_MUX1,
                direction: GPB_DIR,
                pin_mask: bit,
                mux_mask: 3u32 << (local_pin * 2),
            })
        } else {
            None
        }
    }

    pub const fn output_command(pin: u16) -> Option<OutputCommand> {
        let config = match output_config(pin) {
            Some(config) => config,
            None => return None,
        };
        if pin < 32 {
            Some(OutputCommand {
                set: GPA_SET,
                clear: GPA_CLEAR,
                toggle: GPA_TOGGLE,
                pin_mask: config.pin_mask,
            })
        } else {
            Some(OutputCommand {
                set: GPB_SET,
                clear: GPB_CLEAR,
                toggle: GPB_TOGGLE,
                pin_mask: config.pin_mask,
            })
        }
    }

    pub const fn input_config(
        pin: u16,
        pullup_enabled: bool,
        qualification: Qualification,
    ) -> Option<InputConfig> {
        // When the pull-up is enabled the PUD bit stays 0; when disabled it
        // is set.  Mirrors the C bridge's `pullup_enabled` branch.
        if pin < 16 {
            let bit = 1u32 << pin;
            let field_shift = pin * 2;
            Some(InputConfig {
                mux: GPA_MUX1,
                direction: GPA_DIR,
                pullup_disable: GPA_PUD,
                qualification: GPA_QSEL1,
                data: GPA_DAT,
                pin_mask: bit,
                mux_mask: 3u32 << field_shift,
                qualification_mask: 3u32 << field_shift,
                qualification_bits: qualification.bits() << field_shift,
                pullup_disable_bits: if pullup_enabled { 0 } else { bit },
            })
        } else if pin < 32 {
            let bit = 1u32 << pin;
            let field_shift = (pin - 16) * 2;
            Some(InputConfig {
                mux: GPA_MUX2,
                direction: GPA_DIR,
                pullup_disable: GPA_PUD,
                qualification: GPA_QSEL2,
                data: GPA_DAT,
                pin_mask: bit,
                mux_mask: 3u32 << field_shift,
                qualification_mask: 3u32 << field_shift,
                qualification_bits: qualification.bits() << field_shift,
                pullup_disable_bits: if pullup_enabled { 0 } else { bit },
            })
        } else if pin <= 44 {
            let local_pin = pin - 32;
            let bit = 1u32 << local_pin;
            let field_shift = local_pin * 2;
            Some(InputConfig {
                mux: GPB_MUX1,
                direction: GPB_DIR,
                pullup_disable: GPB_PUD,
                qualification: GPB_QSEL1,
                data: GPB_DAT,
                pin_mask: bit,
                mux_mask: 3u32 << field_shift,
                qualification_mask: 3u32 << field_shift,
                qualification_bits: qualification.bits() << field_shift,
                pullup_disable_bits: if pullup_enabled { 0 } else { bit },
            })
        } else {
            None
        }
    }
}

/// eCAP1 module registers (TI F2803x ECAP reference).
pub mod ecap {
    use super::{MmioBus, Register32, TiWordAddress};

    const ECAP1_BASE: TiWordAddress = TiWordAddress::new(0x6a00);

    /// Time-stamp counter (32-bit, offset 0).
    pub const TSCTR: Register32 = Register32::at(ECAP1_BASE.offset_words(0));
    /// Counter phase (32-bit, offset 2).
    pub const CTRPHS: Register32 = Register32::at(ECAP1_BASE.offset_words(2));
    /// Capture 1 (32-bit, offset 4).
    pub const CAP1: Register32 = Register32::at(ECAP1_BASE.offset_words(4));
    /// Capture 2 (32-bit, offset 6).
    pub const CAP2: Register32 = Register32::at(ECAP1_BASE.offset_words(6));
    /// Capture 3 (32-bit, offset 8).
    pub const CAP3: Register32 = Register32::at(ECAP1_BASE.offset_words(8));
    /// Capture 4 (32-bit, offset 10).
    pub const CAP4: Register32 = Register32::at(ECAP1_BASE.offset_words(10));
    /// ECAP control 1 (offset 14).
    pub const ECCTL1: TiWordAddress = ECAP1_BASE.offset_words(14);
    /// ECAP control 2 (offset 15).
    pub const ECCTL2: TiWordAddress = ECAP1_BASE.offset_words(15);
    /// ECAP interrupt enable (offset 16).
    pub const ECEINT: TiWordAddress = ECAP1_BASE.offset_words(16);
    /// ECAP interrupt force (offset 17).
    pub const ECFRC: TiWordAddress = ECAP1_BASE.offset_words(17);
    /// ECAP interrupt flag (offset 18).
    pub const ECFLG: TiWordAddress = ECAP1_BASE.offset_words(18);
    /// ECAP interrupt clear (offset 19).
    pub const ECCLR: TiWordAddress = ECAP1_BASE.offset_words(19);
}
/// eQEP1 module registers (TI F2803x EQEP reference).
pub mod eqep {
    use super::{MmioBus, Register32, TiWordAddress};

    const EQEP1_BASE: TiWordAddress = TiWordAddress::new(0x6b00);

    /// Position counter (32-bit, offset 0).
    pub const QPOSCNT: Register32 = Register32::at(EQEP1_BASE.offset_words(0));
    /// Position init (32-bit, offset 2).
    pub const QPOSINIT: Register32 = Register32::at(EQEP1_BASE.offset_words(2));
    /// Position max (32-bit, offset 4).
    pub const QPOSMAX: Register32 = Register32::at(EQEP1_BASE.offset_words(4));
    /// Position compare (32-bit, offset 6).
    pub const QPOSCMP: Register32 = Register32::at(EQEP1_BASE.offset_words(6));
    /// Unit timer (32-bit, offset 14).
    pub const QUTMR: Register32 = Register32::at(EQEP1_BASE.offset_words(14));
    /// Unit period (32-bit, offset 16).
    pub const QUPRD: Register32 = Register32::at(EQEP1_BASE.offset_words(16));
    /// Watchdog period (offset 19).
    pub const QWDPRD: TiWordAddress = EQEP1_BASE.offset_words(19);
    /// Decoder control (offset 20).
    pub const QDECCTL: TiWordAddress = EQEP1_BASE.offset_words(20);
    /// QEP control (offset 21).
    pub const QEPCTL: TiWordAddress = EQEP1_BASE.offset_words(21);
    /// Capture control (offset 22).
    pub const QCAPCTL: TiWordAddress = EQEP1_BASE.offset_words(22);
    /// Position compare control (offset 23).
    pub const QPOSCTL: TiWordAddress = EQEP1_BASE.offset_words(23);
    /// Interrupt enable (offset 24).
    pub const QEINT: TiWordAddress = EQEP1_BASE.offset_words(24);
    /// Interrupt flag (offset 25).
    pub const QFLG: TiWordAddress = EQEP1_BASE.offset_words(25);
    /// Interrupt clear (offset 26).
    pub const QCLR: TiWordAddress = EQEP1_BASE.offset_words(26);
    /// Interrupt force (offset 27).
    pub const QFRC: TiWordAddress = EQEP1_BASE.offset_words(27);
}
/// SPI-B module registers (TI F2803x SPI reference).
pub mod spi {
    use super::{MmioBus, TiWordAddress};

    const SPIB_BASE: TiWordAddress = TiWordAddress::new(0x7740);

    /// SPI configuration control (offset 0).
    pub const SPICCR: TiWordAddress = SPIB_BASE;
    /// SPI operation control (offset 1).
    pub const SPICTL: TiWordAddress = SPIB_BASE.offset_words(1);
    /// SPI status (offset 2).
    pub const SPISTS: TiWordAddress = SPIB_BASE.offset_words(2);
    /// SPI baud rate (offset 3).
    pub const SPIBRR: TiWordAddress = SPIB_BASE.offset_words(3);
    /// SPI emulation buffer (offset 4).
    pub const SPIEMU: TiWordAddress = SPIB_BASE.offset_words(4);
    /// SPI receive buffer (offset 5).
    pub const SPIRXBUF: TiWordAddress = SPIB_BASE.offset_words(5);
    /// SPI transmit buffer (offset 6).
    pub const SPITXBUF: TiWordAddress = SPIB_BASE.offset_words(6);
    /// SPI serial data (offset 7).
    pub const SPIDAT: TiWordAddress = SPIB_BASE.offset_words(7);
    /// SPI FIFO transmit (offset 9).
    pub const SPIFFTX: TiWordAddress = SPIB_BASE.offset_words(9);
    /// SPI FIFO receive (offset 10).
    pub const SPIFFRX: TiWordAddress = SPIB_BASE.offset_words(10);
    /// SPI FIFO control (offset 8).
    pub const SPIFFCT: TiWordAddress = SPIB_BASE.offset_words(8);
    /// SPI priority (offset 11).
    pub const SPIPRI: TiWordAddress = SPIB_BASE.offset_words(11);

    /// The SPI-B status bit that indicates a non-FIFO transmit interrupt is
    /// pending (INT bit of SPISTS).  Mirrors `f28035_spi_wait_int_flag`, which
    /// polls this single bit.
    pub const SPISTS_INT_FLAG: u16 = 0x0040;
    /// SPISTS TXFIFO overflow flag, used to distinguish a 0x0300-class timeout
    /// from a plain 0x0100-class timeout in the internal-loopback sequence.
    pub const SPISTS_TXOVR: u16 = 0x0020;

    /// `SPILBK` plus the 8-bit character length used by the internal loopback
    /// C case (charlen 0x7 == 8 bits).  This is the SPICCR word written before
    /// the soft reset.
    pub const SPICCR_LB_8BIT: u16 = 0x0017;
    /// The SPICCR word that also asserts `SWRSTN` to re-arm the block in
    /// loopback mode.
    pub const SPICCR_LB_8BIT_RESTART: u16 = 0x0097;
    /// SPICTL value that enables the SPI block with interrupts on (the value
    /// used by the C internal-loopback case).
    pub const SPICTL_LB_RUN: u16 = 0x000E;
    /// Baud divider used by the internal-loopback case (SYSCLK/4).
    pub const SPIBRR_LB: u16 = 0x0003;
    /// SPIFFTX enable word: TXENA plus the level used by the non-FIFO case.
    pub const SPIFFTX_LB: u16 = 0xA000;
    /// SPIFFRX enable word: RXENA.
    pub const SPIFFRX_LB: u16 = 0x2000;
    /// The 8-bit payload written to SPITXBUF; in internal loopback it is what
    /// SPIRXBUF returns.
    pub const SPI_LB_TX_DATA: u16 = 0x003C;

    /// Failure-code families, kept byte-for-byte with the C bridge so the JTAG
    /// observed `fail_code` is unchanged whether the ported Rust sequence or
    /// the C fallback runs.
    pub const FAIL_LB_TIMEOUT_BASE: u16 = 0x0100;
    pub const FAIL_LB_TXOVR_TIMEOUT_BASE: u16 = 0x0300;
    pub const FAIL_LB_RX_ZERO_BASE: u16 = 0x0400;
    pub const FAIL_LB_RX_MISMATCH_BASE: u16 = 0x0200;

    /// Extracts the 8-bit SPI-B character from a received word.
    ///
    /// C28x SPI-B packs the last-received byte in the low eight bits and, for
    /// the 8-bit internal-loopback case, the transmitted byte surfaces in the
    /// high half read back through SPIRXBUF.  The C bridge uses
    /// `(rx_data >> 8) & 0x00FF`; this is the same operation made a pure,
    /// host-testable function.
    #[inline]
    pub const fn unpack_rx_byte(rx_word: u16) -> u16 {
        (rx_word >> 8) & 0x00FF
    }

    /// The outcome of a ported internal-loopback exchange.
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum LoopbackResult {
        /// The exchange completed and the byte read back matched the payload.
        Ok,
        /// The exchange stopped and the reason is one of the `FAIL_LB_*`
        /// families plus a low-byte detail, matching the C `fail_code`.
        Fail(u16),
    }

    /// Runs the SPI-B internal-loopback register sequence through `bus`.
    ///
    /// This is the Rust port of `f28035_spi_internal_loopback_basic`: program
    /// the loopback SPICCR/SPICTL/SPIBRR, enable the FIFOs, soft-reset, write
    /// `SPI_LB_TX_DATA`, poll `SPISTS` until the transmit-interrupt bit is set
    /// (bounded by `poll_limit`), then read `SPIRXBUF`, unpack the byte, and
    /// verify it equals the payload.  It is shared by the target image (via
    /// `C28xMmio`, where the unsafe boundary is contained in the `SpiB`
    /// wrapper) and the host tests (via `HostMmio`), so the exact register
    /// side effects and every failure branch can be asserted on the host.
    ///
    /// # Safety
    ///
    /// `bus` must model the SPI-B register block so that `SPICCR`, `SPICTL`,
    /// `SPIBRR`, `SPIFFTX`, `SPIFFRX`, `SPISTS`, `SPITXBUF` and `SPIRXBUF`
    /// are valid physical word addresses.  The EALLOW/EDIS bracketing the C
    /// case performs stays in the startup wrapper on the target; this
    /// sequence only issues the register writes.
    pub unsafe fn run_internal_loopback<B: MmioBus>(
        bus: &mut B,
        poll_limit: u32,
    ) -> LoopbackResult {
        // --- configuration, mirroring f28035_spi_clk_enable + the C case ---
        SPICCR.write(bus, SPICCR_LB_8BIT);
        SPICTL.write(bus, SPICTL_LB_RUN);
        SPIBRR.write(bus, SPIBRR_LB);
        SPIFFTX.write(bus, SPIFFTX_LB);
        SPIFFRX.write(bus, SPIFFRX_LB);
        // Soft reset in loopback mode (SWRSTN | SPILBK | 0x7).
        SPICCR.write(bus, SPICCR_LB_8BIT_RESTART);
        // --- single 8-bit frame ---
        SPITXBUF.write(bus, SPI_LB_TX_DATA);

        // Bounded poll of the transmit-interrupt bit, 1:1 with
        // `f28035_spi_wait_int_flag`.
        let mut remaining = poll_limit;
        let mut st = 0u16;
        while remaining != 0 {
            st = SPISTS.read(bus);
            if st & SPISTS_INT_FLAG != 0 {
                break;
            }
            remaining -= 1;
        }

        if st & SPISTS_INT_FLAG == 0 {
            // Timed out: classify by the TX-overflow flag, exactly as the C
            // branch between 0x0300 and 0x0100.
            if st & SPISTS_TXOVR != 0 {
                return LoopbackResult::Fail(FAIL_LB_TXOVR_TIMEOUT_BASE + (st & 0x00FF));
            }
            return LoopbackResult::Fail(FAIL_LB_TIMEOUT_BASE + (st & 0x00FF));
        }

        let rx_data = SPIRXBUF.read(bus);
        if rx_data == 0 {
            return LoopbackResult::Fail(FAIL_LB_RX_ZERO_BASE + (st & 0x00FF));
        }
        let rx_byte = unpack_rx_byte(rx_data);
        if rx_byte != SPI_LB_TX_DATA {
            return LoopbackResult::Fail(FAIL_LB_RX_MISMATCH_BASE + rx_byte);
        }
        LoopbackResult::Ok
    }

    /// Host-verified driver for the SPI-B register read/write sweep, mirroring
    /// the audited `f28035_spi_reg_if_rw_basic` sequence 1:1.  Each register is
    /// written and then read back with its mask, and the C sequence stops at
    /// the first mismatch reporting that fixed fail code (`0` = all passed,
    /// matching `f28035_test_pass`).  Assertable on the host through
    /// [`super::HostMmio`] or a fault bus, without the C `f28035_test_fail`
    /// no-op.
    ///
    /// # Safety
    ///
    /// `bus` must model the SPI-B block so `SPICCR`, `SPICTL`, `SPIBRR`,
    /// `SPIFFCT` and `SPIPRI` are valid physical word addresses.
    pub unsafe fn run_spi_reg_rw<B: MmioBus>(bus: &mut B) -> u16 {
        // (register, value written, readback mask, fail code on mismatch)
        let steps: [(TiWordAddress, u16, u16, u16); 5] = [
            (SPICCR, 0x00D7, 0x00D7, 0x0001),
            (SPICTL, 0x001F, 0x001F, 0x0002),
            (SPIBRR, 0x007F, 0x007F, 0x0003),
            (SPIFFCT, 0x0055, 0x00FF, 0x0004),
            (SPIPRI, 0x0073, 0x003F, 0x0005),
        ];
        for &(reg, value, mask, fail_code) in steps.iter() {
            unsafe { reg.write(bus, value) };
            let got = unsafe { reg.read(bus) };
            if got & mask != value & mask {
                return fail_code;
            }
        }
        0
    }
}

/// SCI-A module registers (TI F2803x SCI reference).
pub mod sci {
    use super::{MmioBus, TiWordAddress};

    const SCIA_BASE: TiWordAddress = TiWordAddress::new(0x7050);

    /// SCI configuration control (offset 0).
    pub const SCICCR: TiWordAddress = SCIA_BASE;
    /// SCI control 1 (offset 1).
    pub const SCICTL1: TiWordAddress = SCIA_BASE.offset_words(1);
    /// SCI baud high (offset 2).
    pub const SCIHBAUD: TiWordAddress = SCIA_BASE.offset_words(2);
    /// SCI baud low (offset 3).
    pub const SCILBAUD: TiWordAddress = SCIA_BASE.offset_words(3);
    /// SCI control 2 (offset 4).
    pub const SCICTL2: TiWordAddress = SCIA_BASE.offset_words(4);
    /// SCI receive status (offset 5).
    pub const SCIRXST: TiWordAddress = SCIA_BASE.offset_words(5);
    /// SCI receive emulation (offset 6).
    pub const SCIRXEMU: TiWordAddress = SCIA_BASE.offset_words(6);
    /// SCI receive buffer (offset 7).
    pub const SCIRXBUF: TiWordAddress = SCIA_BASE.offset_words(7);
    /// SCI transmit buffer (offset 8).
    pub const SCITXBUF: TiWordAddress = SCIA_BASE.offset_words(8);
    /// SCI FIFO transmit (offset 10).
    pub const SCIFFTX: TiWordAddress = SCIA_BASE.offset_words(10);
    /// SCI FIFO receive (offset 11).
    pub const SCIFFRX: TiWordAddress = SCIA_BASE.offset_words(11);
    /// SCI FIFO control (offset 12).
    pub const SCIFFCT: TiWordAddress = SCIA_BASE.offset_words(12);
    /// SCI priority (offset 13).
    pub const SCIPRI: TiWordAddress = SCIA_BASE.offset_words(13);

    /// Host-verified driver for the SCI-A register read/write sweep, mirroring
    /// `f28035_sci_reg_if_rw_basic` 1:1: program the clock + config words,
    /// then verify each register's masked readback, returning the C fail code
    /// (including the raw read value, e.g. `0x0001 + rd`) or `0` for pass.
    ///
    /// # Safety
    ///
    /// `bus` must model the SCI-A block and `PCLKCR0` as valid word addresses.
    pub unsafe fn run_sci_reg_rw<B: MmioBus>(bus: &mut B) -> u16 {
        // Enable the SCI-A clock (PCLKCR0 bit), matching the C prologue.
        let mut pclkcr0 = unsafe { super::sysctrl::PCLKCR0.read_u32(bus) };
        pclkcr0 |= super::sysctrl::PCLKCR0_SCIAENCLK as u32;
        unsafe { super::sysctrl::PCLKCR0.write_u32(bus, pclkcr0) };

        // Program the configuration words.
        unsafe {
            SCICCR.write(bus, 0x0037);
            SCICTL1.write(bus, 0x0043);
            SCICTL2.write(bus, 0x0003);
            SCIHBAUD.write(bus, 0x0012);
            SCILBAUD.write(bus, 0x0034);
            SCIFFTX.write(bus, 0xC003);
            SCIFFRX.write(bus, 0x0024);
            SCIFFCT.write(bus, 0x2055);
            SCIPRI.write(bus, 0x0010);
        }

        // Verify each masked readback; the C code reports `base + raw read`.
        let rd = unsafe { SCICCR.read(bus) };
        if rd & 0x0077 != 0x0037 { return 0x0001 + rd; }
        let rd = unsafe { SCICTL1.read(bus) };
        if rd & 0x0043 != 0x0043 { return 0x0002 + rd; }
        let rd = unsafe { SCIHBAUD.read(bus) };
        if rd & 0x00FF != 0x0012 { return 0x0003 + rd; }
        let rd = unsafe { SCILBAUD.read(bus) };
        if rd & 0x00FF != 0x0034 { return 0x0103 + rd; }
        let rd = unsafe { SCICTL2.read(bus) };
        if rd & 0x0003 != 0x0003 { return 0x0004 + rd; }
        let rd = unsafe { SCIFFTX.read(bus) };
        if rd & 0xC01F != 0xC003 { return 0x0005 + rd; }
        let rd = unsafe { SCIFFRX.read(bus) };
        if rd & 0x003F != 0x0024 { return 0x0006 + rd; }
        let rd = unsafe { SCIFFCT.read(bus) };
        if rd & 0x20FF != 0x2055 { return 0x0007 + rd; }
        let rd = unsafe { SCIPRI.read(bus) };
        if rd & 0x0010 != 0x0010 { return 0x0008 + rd; }
        0
    }
}
/// I2C-A module registers (TI F2803x I2C reference).
pub mod i2c {
    use super::{MmioBus, TiWordAddress};

    const I2CA_BASE: TiWordAddress = TiWordAddress::new(0x7900);

    /// Own address (offset 0).
    pub const I2COAR: TiWordAddress = I2CA_BASE;
    /// Interrupt enable (offset 1).
    pub const I2CIER: TiWordAddress = I2CA_BASE.offset_words(1);
    /// Status (offset 2).
    pub const I2CSTR: TiWordAddress = I2CA_BASE.offset_words(2);
    /// Clock low divider (offset 3).
    pub const I2CCLKL: TiWordAddress = I2CA_BASE.offset_words(3);
    /// Clock high divider (offset 4).
    pub const I2CCLKH: TiWordAddress = I2CA_BASE.offset_words(4);
    /// Data count (offset 5).
    pub const I2CCNT: TiWordAddress = I2CA_BASE.offset_words(5);
    /// Data receive (offset 6).
    pub const I2CDRR: TiWordAddress = I2CA_BASE.offset_words(6);
    /// Slave address (offset 7).
    pub const I2CSAR: TiWordAddress = I2CA_BASE.offset_words(7);
    /// Data transmit (offset 8).
    pub const I2CDXR: TiWordAddress = I2CA_BASE.offset_words(8);
    /// Mode (offset 9).
    pub const I2CMDR: TiWordAddress = I2CA_BASE.offset_words(9);
    /// Interrupt source (offset 10).
    pub const I2CISRC: TiWordAddress = I2CA_BASE.offset_words(10);
    /// Extended mode (offset 11).
    pub const I2CEMDR: TiWordAddress = I2CA_BASE.offset_words(11);
    /// Prescaler (offset 12).
    pub const I2CPSC: TiWordAddress = I2CA_BASE.offset_words(12);
    /// FIFO transmit (offset 13).
    pub const I2CFFTX: TiWordAddress = I2CA_BASE.offset_words(13);
    /// FIFO receive (offset 14).
    pub const I2CFFRX: TiWordAddress = I2CA_BASE.offset_words(14);

    /// Host-verified driver for the I2C-A register readback sweep, mirroring
    /// `f28035_i2c_reg_readback_sweep_basic` through every *deterministic*
    /// write/readback check and the FIFO reset-state reads, returning the C
    /// fail code (`0` = pass).
    ///
    /// The final hardware liveness gate in the C case — XOR-accumulating
    /// `DDRR/ISRC/EMDR/STR` into `sink` and failing `0x7F40` when it is all
    /// ones — is not reproducible on a plain storage bus (writing `I2CSTR =
    /// 0xFFFF` and reading it back inverts the heuristic), so this driver
    /// stops at the last deterministic check (`0x7F21`) and that gate stays
    /// board-verified.
    ///
    /// # Safety
    ///
    /// `bus` must model the I2C-A block and `PCLKCR0`; the FIFO status
    /// registers should be pre-seeded to their reset words (0x0105 / 0x0005)
    /// to model hardware reset state.
    pub unsafe fn run_i2c_reg_rw<B: MmioBus>(bus: &mut B) -> u16 {
        // Enable I2C-A clock (PCLKCR0), matching the C prologue.
        let mut pclkcr0 = unsafe { super::sysctrl::PCLKCR0.read_u32(bus) };
        pclkcr0 |= super::sysctrl::PCLKCR0_I2CAENCLK as u32;
        unsafe { super::sysctrl::PCLKCR0.write_u32(bus, pclkcr0) };
        // Standard init: exit reset, program PSCL / clocks / own address.
        unsafe {
            I2CMDR.write(bus, 0);
            I2CPSC.write(bus, 6);
            I2CCLKL.write(bus, 200);
            I2CCLKH.write(bus, 160);
            I2COAR.write(bus, 0x00C0);
            I2CSTR.write(bus, 0xFFFF);
            I2CMDR.write(bus, 0);
            I2CMDR.write(bus, 0x0020); // IRS = 1
        }
        // Deterministic readback sweep.
        unsafe { I2COAR.write(bus, 0x0035) };
        if unsafe { I2COAR.read(bus) } & 0x03FF != 0x0035 { return 0x7F01; }
        unsafe { I2CIER.write(bus, 0x0055) };
        if unsafe { I2CIER.read(bus) } & 0x007F != 0x0055 { return 0x7F02; }
        unsafe { I2CCLKL.write(bus, 0x00C8) };
        if unsafe { I2CCLKL.read(bus) } != 0x00C8 { return 0x7F03; }
        unsafe { I2CCLKH.write(bus, 0x00A0) };
        if unsafe { I2CCLKH.read(bus) } != 0x00A0 { return 0x7F04; }
        unsafe { I2CCNT.write(bus, 0x0004) };
        if unsafe { I2CCNT.read(bus) } != 0x0004 { return 0x7F05; }
        unsafe { I2CSAR.write(bus, 0x0036) };
        if unsafe { I2CSAR.read(bus) } & 0x03FF != 0x0036 { return 0x7F07; }
        unsafe { I2CDXR.write(bus, 0x00A5) };
        if unsafe { I2CDXR.read(bus) } & 0x00FF != 0x00A5 { return 0x7F08; }
        unsafe { I2CMDR.write(bus, 0x0020) };
        if unsafe { I2CMDR.read(bus) } & 0x0020 != 0x0020 { return 0x7F09; }
        unsafe { I2CPSC.write(bus, 0x0006) };
        if unsafe { I2CPSC.read(bus) } & 0x00FF != 0x0006 { return 0x7F0C; }
        // FIFO reset-state reads (need reset words pre-seeded on the host).
        if unsafe { I2CFFTX.read(bus) } != 0x0105 { return 0x7F0D; }
        if unsafe { I2CFFRX.read(bus) } != 0x0005 { return 0x7F0E; }
        // FIFO write + masked readback.
        unsafe { I2CFFTX.write(bus, 0x6000) };
        if unsafe { I2CFFTX.read(bus) } & 0x6000 != 0x6000 { return 0x7F20; }
        unsafe { I2CFFRX.write(bus, 0x2040) };
        if unsafe { I2CFFRX.read(bus) } & 0x2000 != 0x2000 { return 0x7F21; }
        // The final `sink` liveness gate is hardware-only and is NOT run here.
        0
    }
}
/// LIN-A module registers (TI F2803x LIN reference).
pub mod lin {
    use super::{MmioBus, Register32, TiWordAddress};

    const LINA_BASE: TiWordAddress = TiWordAddress::new(0x7a00);

    /// SCI global control 1 (offset 0).
    pub const SCIGCR1: TiWordAddress = LINA_BASE;
    /// SCI global control 2 (offset 1).
    pub const SCIGCR2: TiWordAddress = LINA_BASE.offset_words(1);
    /// SCI flag (offset 7).
    pub const SCIFLR: TiWordAddress = LINA_BASE.offset_words(7);
    /// SCI format (offset 10).
    pub const SCIFORMAT: TiWordAddress = LINA_BASE.offset_words(10);
    /// Baud rate (offset 11).
    pub const BRSR: Register32 = Register32::at(LINA_BASE.offset_words(11));
    /// Mapped baud rate (offset 19).
    pub const MBRSR: TiWordAddress = LINA_BASE.offset_words(19);
    /// LIN compare (offset 20).
    pub const LINCOMP: TiWordAddress = LINA_BASE.offset_words(20);
    /// LIN mask (offset 21).
    pub const LINMASK: TiWordAddress = LINA_BASE.offset_words(21);
    /// LIN ID (offset 22).
    pub const LINID: TiWordAddress = LINA_BASE.offset_words(22);
    /// LIN transmit data 0 (offset 23).
    pub const LINTD0: Register32 = Register32::at(LINA_BASE.offset_words(23));
    /// LIN transmit data 1 (offset 25).
    pub const LINTD1: Register32 = Register32::at(LINA_BASE.offset_words(25));
    /// LIN receive data 0 (offset 27).
    pub const LINRD0: Register32 = Register32::at(LINA_BASE.offset_words(27));
    /// LIN receive data 1 (offset 29).
    pub const LINRD1: Register32 = Register32::at(LINA_BASE.offset_words(29));

    /// Host-verified driver for the LIN-A register readback, mirroring
    /// `f28035_lin_reg_if_rw_basic` through its configuration + verify steps,
    /// returning the C fail code (`0` = pass).
    ///
    /// The GPIO9/GPIO11 mux programming in the C case is a `GPA_MUX1` field
    /// write; it is modelled here as the same masked 32-bit read-modify-write
    /// the C code performs, so the bus-side effect matches.
    ///
    /// # Safety
    ///
    /// `bus` must model the LIN-A block, `GPA_MUX1` and `PCLKCR0`; the
    /// `BRSR` 32-bit pair must be a writable two-word region.
    pub unsafe fn run_lin_reg_rw<B: MmioBus>(bus: &mut B) -> u16 {
        // GPIO9=LIN_TX, GPIO11=LIN_RX: clear the 2-bit MUX fields then set.
        let mut mux1 = unsafe { super::gpio::GPA_MUX1.read_u32(bus) };
        mux1 = (mux1 & !(0x3 << 18)) | (1 << 18);
        mux1 = (mux1 & !(0x3 << 22)) | (1 << 22);
        unsafe { super::gpio::GPA_MUX1.write_u32(bus, mux1) };
        // Enable LIN-A clock.
        let mut pclkcr0 = unsafe { super::sysctrl::PCLKCR0.read_u32(bus) };
        pclkcr0 |= super::sysctrl::PCLKCR0_LINAENCLK as u32;
        unsafe { super::sysctrl::PCLKCR0.write_u32(bus, pclkcr0) };
        // Basic slave init.
        unsafe {
            SCIGCR1.write(bus, 0);
            SCIGCR2.write(bus, 0);
            SCIGCR1.write(bus, 0x0080); // SWnRST = 1
            SCIGCR1.write(bus, 0);      // SWnRST = 0
            SCIGCR1.write(bus, 0x0002); // LINMODE = 1
            SCIGCR2.write(bus, 0x0001); // CC = 1
            BRSR.write_u32(bus, (11u32 << 16) | 96); // M = 11, PSL = 96
            MBRSR.write(bus, 92);
            SCIFORMAT.write(bus, 0);
            LINCOMP.write(bus, (5u16 << 6) | 3);
            LINMASK.write(bus, (0xFFu16 << 8) | 0xFF);
            LINID.write(bus, 0x10);
        }
        // Verify.
        let scigcr2 = unsafe { SCIGCR2.read(bus) };
        if scigcr2 & 1 != 1 {
            return 0x5202 + scigcr2;
        }
        let brsr = unsafe { BRSR.read_u32(bus) };
        if brsr & 0xFFFF != 96 || brsr >> 16 != 11 {
            return 0x5203 + brsr as u16;
        }
        if unsafe { MBRSR.read(bus) } & 0xFFFF != 92 {
            return 0x5204 + unsafe { MBRSR.read(bus) };
        }
        if unsafe { SCIFORMAT.read(bus) } & 7 != 0 {
            return 0x5205 + unsafe { SCIFORMAT.read(bus) };
        }
        let lincomp = unsafe { LINCOMP.read(bus) };
        if (lincomp >> 6) & 0xF != 5 || lincomp & 0xF != 3 {
            return 0x5206 + lincomp;
        }
        let linmask = unsafe { LINMASK.read(bus) };
        if linmask >> 8 != 0xFF || linmask & 0xFF != 0xFF {
            return 0x5207 + linmask;
        }
        if unsafe { LINID.read(bus) } != 0x10 {
            return 0x5208 + unsafe { LINID.read(bus) };
        }
        0
    }
}
pub mod xint {
    use super::{MmioBus, Register32, TiWordAddress};

    const XINTRUPT_BASE: TiWordAddress = TiWordAddress::new(0x7070);
    const PIE_CTRL_BASE: TiWordAddress = TiWordAddress::new(0x0ce0);
    const PIE_VECTOR_BASE: TiWordAddress = TiWordAddress::new(0x0d00);

    pub const XINT1CR: TiWordAddress = XINTRUPT_BASE;
    pub const XINT2CR: TiWordAddress = XINTRUPT_BASE.offset_words(1);
    pub const XINT3CR: TiWordAddress = XINTRUPT_BASE.offset_words(2);
    pub const XINT1CTR: TiWordAddress = XINTRUPT_BASE.offset_words(8);
    pub const XINT2CTR: TiWordAddress = XINTRUPT_BASE.offset_words(9);
    pub const XINT3CTR: TiWordAddress = XINTRUPT_BASE.offset_words(10);
    pub const PIEIER1: TiWordAddress = PIE_CTRL_BASE.offset_words(2);
    pub const XINT1_VECTOR: Register32 = Register32::at(PIE_VECTOR_BASE.offset_words(6));
    pub const XINT2_VECTOR: Register32 = Register32::at(PIE_VECTOR_BASE.offset_words(8));

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub enum Edge {
        Falling,
        Rising,
        Both,
    }

    impl Edge {
        pub const fn bits(self) -> u16 {
            match self {
                Self::Falling => 0,
                Self::Rising => 1,
                Self::Both => 3,
            }
        }
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub struct ExternalInterruptConfig {
        pub selector: TiWordAddress,
        pub control: TiWordAddress,
        pub vector: Register32,
        pub pieier1_mask: u16,
        pub gpio_select: u16,
        pub edge_bits: u16,
    }

    impl ExternalInterruptConfig {
        /// Writes the XINT selector/control through the bus in the exact
        /// order used by `f28035_gpio_configure_xint`: program the GPIOSEL,
        /// disable the interrupt, set polarity, enable the PIE line, then
        /// re-enable the interrupt.  EALLOW bracketing the selector write and
        /// the global `EINT` stay in the startup wrapper.
        ///
        /// # Safety
        /// All addresses are fixed XINT/PIE register offsets.
        pub unsafe fn apply<B: MmioBus>(self, bus: &mut B) {
            // SAFETY: fixed XINT/PIE register addresses.
            unsafe {
                // GPIOSEL is the low 5 bits of the selector register.
                self.selector.modify(bus, 0x001f, self.gpio_select);
                // Disable, set polarity (bits 3:2), re-enable (bit 0).
                self.control.modify(bus, 0x0001, 0);
                self.control.modify(bus, 0x000c, self.edge_bits << 2);
                PIEIER1.modify(bus, self.pieier1_mask, self.pieier1_mask);
                self.control.modify(bus, 0x0001, 0x0001);
            }
        }
    }

    pub const fn xint1(pin: u16, edge: Edge) -> Option<ExternalInterruptConfig> {
        if pin < 32 {
            Some(ExternalInterruptConfig {
                selector: super::gpio::XINT1_SEL,
                control: XINT1CR,
                vector: XINT1_VECTOR,
                pieier1_mask: 1u16 << 3,
                gpio_select: pin,
                edge_bits: edge.bits(),
            })
        } else {
            None
        }
    }

    pub const fn xint2(pin: u16, edge: Edge) -> Option<ExternalInterruptConfig> {
        if pin < 32 {
            Some(ExternalInterruptConfig {
                selector: super::gpio::XINT2_SEL,
                control: XINT2CR,
                vector: XINT2_VECTOR,
                pieier1_mask: 1u16 << 4,
                gpio_select: pin,
                edge_bits: edge.bits(),
            })
        } else {
            None
        }
    }
}

/// ePWM1 registers used by the initial PAC subset.
pub mod epwm1 {
    use super::{MmioBus, Register32, TiWordAddress};

    const EPWM1_BASE: TiWordAddress = TiWordAddress::new(0x6800);

    /// Time-base control register.
    pub const TBCTL: TiWordAddress = EPWM1_BASE;

    /// Time-base counter.
    pub const TBCTR: TiWordAddress = EPWM1_BASE.offset_words(4);

    /// The 16-bit time-base period register.
    pub const TBPRD: TiWordAddress = EPWM1_BASE.offset_words(5);

    /// The 16-bit CMPA half of the C28x CMPA:CMPAHR register pair.
    pub const CMPA: TiWordAddress = EPWM1_BASE.offset_words(9);

    /// Action-qualifier register for output A.
    pub const AQCTLA: TiWordAddress = EPWM1_BASE.offset_words(11);
    /// Dead-band control register.
    pub const DBCTL: TiWordAddress = EPWM1_BASE.offset_words(15);
    /// Dead-band rising-edge delay register.
    pub const DBRED: TiWordAddress = EPWM1_BASE.offset_words(16);
    /// Dead-band falling-edge delay register.
    pub const DBFED: TiWordAddress = EPWM1_BASE.offset_words(17);
    /// Trip-zone select register.
    pub const TZSEL: TiWordAddress = EPWM1_BASE.offset_words(18);
    /// Trip-zone control register.
    pub const TZCTL: TiWordAddress = EPWM1_BASE.offset_words(19);
    /// Trip-zone enable interrupt register.
    pub const TZEINT: TiWordAddress = EPWM1_BASE.offset_words(20);
    /// Event-trigger selection register.
    pub const ETSEL: TiWordAddress = EPWM1_BASE.offset_words(24);
    /// Event-trigger prescale register.
    pub const ETPS: TiWordAddress = EPWM1_BASE.offset_words(25);
    /// Trip-zone clear register.
    pub const TZCLR: TiWordAddress = EPWM1_BASE.offset_words(22);
    /// Trip-zone force register.
    pub const TZFRC: TiWordAddress = EPWM1_BASE.offset_words(23);
    /// Action-qualifier register for output B.
    pub const AQCTLB: TiWordAddress = EPWM1_BASE.offset_words(12);
    /// Trip-zone flag register.
    pub const TZFLG: TiWordAddress = EPWM1_BASE.offset_words(21);
    /// Event-trigger clear register.
    pub const ETCLR: TiWordAddress = EPWM1_BASE.offset_words(27);
    /// HRPWM configuration register (offset 30).
    pub const HRCNFG: TiWordAddress = EPWM1_BASE.offset_words(30);
    /// HRPWM power register (offset 31).
    pub const HRPWR: TiWordAddress = EPWM1_BASE.offset_words(31);
    /// HRPWM control register (offset 32).
    pub const HRPCTL: TiWordAddress = EPWM1_BASE.offset_words(32);
    /// HRPWM phase high-res register (offset 2).
    pub const TBPHSHR: TiWordAddress = EPWM1_BASE.offset_words(2);
    /// Time-base phase register (offset 3).
    pub const TBPHS: TiWordAddress = EPWM1_BASE.offset_words(3);
    /// HRPWM period high-res register (offset 6).
    pub const TBPRDHR: TiWordAddress = EPWM1_BASE.offset_words(6);
    /// HRPWM CMPA high-res register (offset 8, high half of CMPA pair).
    pub const CMPAHR: TiWordAddress = EPWM1_BASE.offset_words(8);

    /// Full 32-bit pair, retained for future HRPWM support.
    pub const CMPA_PAIR: Register32 = Register32::at(EPWM1_BASE.offset_words(8));

    /// Action-qualifier values for the AQCTLA/ZRO/CAU fields (DSP2803x_EPwm.h).
    pub const AQ_NO_ACTION: u16 = 0;
    pub const AQ_CLEAR: u16 = 1;
    pub const AQ_SET: u16 = 2;

    /// Up-counting ePWM1 configuration that mirrors `f28035_epwm1_configure`:
    /// ZERO event drives EPWM1A high, CMPA-up drives it low.
    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub struct UpCountConfig {
        pub period_ticks: u16,
    }

    impl UpCountConfig {
        /// Writes the ePWM1 registers through the bus in the exact order used
        /// by the C bridge.  GPIO0 mux and TBCLKSYNC are owned by the system
        /// setup path and are not part of this sequence.
        ///
        /// # Safety
        ///
        /// All addresses are fixed ePWM1 register offsets.
        pub unsafe fn apply<B: MmioBus>(self, bus: &mut B) {
            // SAFETY: fixed ePWM1 register addresses.
            unsafe {
                TBCTL.write(bus, 0);
                TBCTR.write(bus, 0);
                TBPRD.write(bus, self.period_ticks);
                CMPA.write(bus, 0);
                // ZRO=SET (bits 1:0), CAU=CLEAR (bits 5:4) -> 0x0012.
                let aq = AQ_SET | (AQ_CLEAR << 4);
                AQCTLA.write(bus, aq);
                // CTRMODE stays 0 (up-counting) because TBCTL was zeroed.
            }
        }
    }

    /// Sets CMPA, clamped to the active period exactly like the C bridge.
    ///
    /// # Safety
    /// Same as [`TiWordAddress::read`]/[`TiWordAddress::write`] for TBPRD and
    /// CMPA.
    pub unsafe fn set_compare<B: MmioBus>(bus: &mut B, compare_ticks: u16) {
        // SAFETY: fixed ePWM1 register addresses.
        let period = unsafe { TBPRD.read(bus) };
        let clamped = if compare_ticks > period {
            period
        } else {
            compare_ticks
        };
        // SAFETY: fixed ePWM1 register address.
        unsafe { CMPA.write(bus, clamped) };
    }

    /// Reads back the active CMPA value.
    ///
    /// # Safety
    /// Same as [`TiWordAddress::read`] for CMPA.
    pub unsafe fn read_compare<B: MmioBus>(bus: &mut B) -> u16 {
        // SAFETY: fixed ePWM1 register address.
        unsafe { CMPA.read(bus) }
    }

    /// ePWM1A PWM-enable bit (TBCTL bit 9, `PWMENABLE`).
    pub const TBCTL_PWMENABLE: u16 = 1 << 9;
    /// ePWM1A idle-high flag (TBCTL bit 6, `SHDWDBLOAD`).  Idle-state
    /// forcing is left to the caller's dead-band control; we only toggle the
    /// enable bit here.

    /// Enables the ePWM1 time base output (sets TBCTL PWMENABLE).
    ///
    /// # Safety
    /// Same as [`TiWordAddress::write`] for TBCTL.
    pub unsafe fn enable<B: MmioBus>(bus: &mut B) {
        // SAFETY: fixed ePWM1 register address.
        unsafe { TBCTL.modify(bus, TBCTL_PWMENABLE, TBCTL_PWMENABLE) };
    }

    /// Disables the ePWM1 time base output (clears TBCTL PWMENABLE).
    ///
    /// # Safety
    /// Same as [`TiWordAddress::write`] for TBCTL.
    pub unsafe fn disable<B: MmioBus>(bus: &mut B) {
        // SAFETY: fixed ePWM1 register address.
        unsafe { TBCTL.modify(bus, TBCTL_PWMENABLE, 0) };
    }
}

/// System-control registers used by the audited peripheral setup path.
pub mod sysctrl {
    use super::{Register32, TiWordAddress};

    const SYSCTRL_BASE: TiWordAddress = TiWordAddress::new(0x7010);

    /// Peripheral clock control register containing ADCENCLK and TBCLKSYNC.
    pub const PCLKCR0: Register32 = Register32::at(SYSCTRL_BASE.offset_words(12));

    /// ADC enable-clock bit in PCLKCR0.
    pub const PCLKCR0_ADCENCLK: u16 = 0x0008;
    /// ePWM time-base clock sync bit in PCLKCR0.
    pub const PCLKCR0_TBCLKSYNC: u16 = 0x0004;
    /// SPI-B clock-enable bit in PCLKCR0.
    pub const PCLKCR0_SPIBENCLK: u16 = 0x0100;
    /// SCI-A clock-enable bit in PCLKCR0.
    pub const PCLKCR0_SCIAENCLK: u16 = 0x0040;
    /// I2C-A clock-enable bit in PCLKCR0.
    pub const PCLKCR0_I2CAENCLK: u16 = 0x0400;
    /// LIN-A clock-enable bit in PCLKCR0.
    pub const PCLKCR0_LINAENCLK: u16 = 0x1000;
    /// Peripheral clock control register 1 (ePWM/eCAP/eQEP clock enables).
    pub const PCLKCR1: Register32 = Register32::at(SYSCTRL_BASE.offset_words(13));
    /// ePWM1 clock-enable bit in PCLKCR1.
    pub const PCLKCR1_EPWM1ENCLK: u32 = 0x0001;
    /// eCAP1 clock-enable bit in PCLKCR1.
    pub const PCLKCR1_ECAP1ENCLK: u32 = 0x0010;
    /// eQEP1 clock-enable bit in PCLKCR1.
    pub const PCLKCR1_EQEP1ENCLK: u32 = 0x0020;
    /// Peripheral clock control register 3 (CPU Timer0 clock enable).
    pub const PCLKCR3: TiWordAddress = SYSCTRL_BASE.offset_words(15);
    /// CPU Timer0 clock-enable bit in PCLKCR3.
    pub const PCLKCR3_CPUTIMER0ENCLK: u16 = 0x0100;
}

/// ADC registers used by SOC0 setup and software-triggered sampling.
pub mod adc {
    use super::{MmioBus, TiWordAddress};

    pub(crate) const ADC_BASE: TiWordAddress = TiWordAddress::new(0x7100);

    pub const ADCCTL1: TiWordAddress = ADC_BASE;
    pub const ADCCTL2: TiWordAddress = ADC_BASE.offset_words(1);
    pub const ADCINTFLG: TiWordAddress = ADC_BASE.offset_words(4);
    pub const ADCINTFLGCLR: TiWordAddress = ADC_BASE.offset_words(5);
    pub const INTSEL1N2: TiWordAddress = ADC_BASE.offset_words(8);
    pub const INTSEL3N4: TiWordAddress = ADC_BASE.offset_words(9);
    pub const ADCSOCFLG1: TiWordAddress = ADC_BASE.offset_words(24);
    pub const ADCSOCOVF1: TiWordAddress = ADC_BASE.offset_words(28);
    pub const ADCSOCFRC1: TiWordAddress = ADC_BASE.offset_words(26);
    pub const ADCSOC0CTL: TiWordAddress = ADC_BASE.offset_words(32);

    /// CHSEL field of ADCSOC0CTL (5 channel select bits, bits 0-4).
    pub const SOC0_CHSEL_MASK: u16 = 0x001f;
    /// ACQPS field shift in ADCSOC0CTL (bits 6-10).
    pub const SOC0_ACQPS_SHIFT: u16 = 6;
    /// TRIGSEL field of ADCSOC0CTL (5 trigger-source bits, bits 11-15).
    pub const SOC0_TRIGSEL_MASK: u16 = 0xf800;
    pub const SOC0_TRIGSEL_SHIFT: u16 = 11;
    /// ADCINT1 result pending flag in ADCINTFLG / ADCINTFLGCLR.
    pub const ADCINT1_FLAG: u16 = 0x0002;
    /// SOC0 bit in ADCSOCFRC1 / ADCSOCFLG1 / ADCSOCOVF1.
    pub const SOC0_FORCE: u16 = 0x0001;
    /// CLKDIV2EN bit in ADCCTL2 (bit 0).
    pub const ADCCTL2_CLKDIV2EN: u16 = 0x0001;

    /// Mirrors the trigger half of `f28035_adc_sample`: select the channel on
    /// SOC0, clear the EOC flag, then force SOC0.  The bounded EOC polling
    /// loop is runtime behavior and intentionally stays outside this sequence.
    ///
    /// # Safety
    ///
    /// `channel` must be <= 15; the caller validates this before crossing.
    /// All addresses are fixed ADC register offsets.
    pub unsafe fn trigger_soc0<B: MmioBus>(bus: &mut B, channel: u16) {
        // SAFETY: fixed ADC register addresses; channel is masked to 5 bits.
        unsafe {
            ADCSOC0CTL.modify(bus, SOC0_CHSEL_MASK, channel);
            ADCINTFLGCLR.write(bus, ADCINT1_FLAG);
            ADCSOCFRC1.write(bus, SOC0_FORCE);
        }
    }

    /// Clears the SOC0 EOC flag after a completed conversion.
    ///
    /// # Safety
    /// Same as [`TiWordAddress::write`] for ADCINTFLGCLR.
    pub unsafe fn clear_eoc<B: MmioBus>(bus: &mut B) {
        // SAFETY: fixed ADC register address.
        unsafe { ADCINTFLGCLR.write(bus, ADCINT1_FLAG) };
    }

    // -- ADC power-up constants (DSP2803x_Adc.h, mirrored from the audited
    //    backend sequence in emit_f28035_board_init) --------------------------

    /// ADCCTL1 power-up bits: bit14 (refbuf), bit7/6/5 (power up).
    const ADCCTL1_POWERUP_MASK: u16 = 0x40e0;
    /// ADCCTL1 reset bit (bit2, ADCENABLE).
    const ADCCTL1_RESET_BIT: u16 = 0x0004;
    /// INTSEL1N2 low 5 bits: ADCINT1 source channel select.
    const INTSEL1N2_SOURCE_MASK: u16 = 0x001f;
    /// INTSEL1N2 bit5: ADCINT1 routed to SOC0.
    const INTSEL1N2_ADCINT1_ON_SOC0: u16 = 0x0020;
    /// INTSEL1N2 bit6: ADCINT1 interrupt enable.
    const INTSEL1N2_ADCINT1_ENABLE: u16 = 0x0040;
    /// ADCSOC0CTL reserved/upper bits above ACQPS.
    const SOC0CTL_UPPER_MASK: u16 = 0xf800;
    /// ADCSOC0CTL acquisition-window prescale bits (bits 6..10).
    pub const SOC0_ACQPS_MASK: u16 = 0x07c0;
    /// Acquisition window of 6 SYSCLK cycles, matching the audited sequence.
    const SOC0_ACQPS_6: u16 = 6;

    /// Mirrors `emit_f28035_board_init`'s ADC block: enable ADC clock, power
    /// up the ADC, (settle delay on target only), release reset, route
    /// ADCINT1 to SOC0, and set a 6-cycle acquisition window.
    ///
    /// The ~60k-cycle `DSP28x_usDelay` settle loop is runtime timing and is
    /// intentionally not part of this register sequence.  EALLOW/EDIS
    /// bracketing is added by the backend on target; on the host it is a
    /// no-op.
    ///
    /// # Safety
    /// All addresses are fixed ADC / sysctrl register offsets.
    pub unsafe fn power_up_and_configure_soc0<B: MmioBus>(bus: &mut B) {
        // SAFETY: fixed ADC / sysctrl register addresses.
        unsafe {
            // 1. Enable the ADC clock in PCLKCR0.
            super::sysctrl::PCLKCR0.modify_u32(
                bus,
                super::sysctrl::PCLKCR0_ADCENCLK as u32,
                super::sysctrl::PCLKCR0_ADCENCLK as u32,
            );
            // 2. Power up the ADC reference and bandgap.
            ADCCTL1.modify(bus, ADCCTL1_POWERUP_MASK, ADCCTL1_POWERUP_MASK);
            ADCCTL1.modify(bus, ADCCTL1_RESET_BIT, 0);
            // 3. (target-only: LCR #DSP28x_usDelay with ACC=59997)
            // 4. Release the ADC from reset.
            ADCCTL1.modify(bus, ADCCTL1_RESET_BIT, ADCCTL1_RESET_BIT);
            // 5. Route ADCINT1 to SOC0 and enable the interrupt source.
            INTSEL1N2.modify(bus, INTSEL1N2_SOURCE_MASK, 0);
            INTSEL1N2.modify(bus, INTSEL1N2_ADCINT1_ON_SOC0, INTSEL1N2_ADCINT1_ON_SOC0);
            INTSEL1N2.modify(bus, INTSEL1N2_ADCINT1_ENABLE, 0);
            // 6. SOC0: clear upper reserved bits and set ACQPS=6.
            ADCSOC0CTL.modify(bus, SOC0CTL_UPPER_MASK, 0);
            ADCSOC0CTL.modify(bus, 0x003f, 0);
            ADCSOC0CTL.modify(bus, SOC0_ACQPS_MASK, SOC0_ACQPS_6 << 6);
        }
    }
}

/// CPU Timer0 and PIE registers used by the audited periodic interrupt path.
pub mod timer0 {
    use super::{MmioBus, Register32, TiWordAddress};

    const CPU_TIMER0_BASE: TiWordAddress = TiWordAddress::new(0x0c00);
    const PIE_CTRL_BASE: TiWordAddress = TiWordAddress::new(0x0ce0);
    const PIE_VECTOR_BASE: TiWordAddress = TiWordAddress::new(0x0d00);

    /// 32-bit period register pair.
    pub const PRD: Register32 = Register32::at(CPU_TIMER0_BASE.offset_words(2));

    /// Timer control register.  The direct backend sets TSS/TRB/TIE here.
    pub const TCR: TiWordAddress = CPU_TIMER0_BASE.offset_words(4);

    /// Prescaler registers, both zero for a 60 MHz CPU clock.
    pub const TPR: TiWordAddress = CPU_TIMER0_BASE.offset_words(6);
    pub const TPRH: TiWordAddress = CPU_TIMER0_BASE.offset_words(7);

    /// PIE group-1 enable and acknowledge registers.
    pub const PIEACK: TiWordAddress = PIE_CTRL_BASE.offset_words(1);
    pub const PIEIER1: TiWordAddress = PIE_CTRL_BASE.offset_words(2);

    /// TINT0 vector entry in the PIE vector table.
    pub const TINT0_VECTOR: Register32 = Register32::at(PIE_VECTOR_BASE.offset_words(76));

    /// TCR bit definitions (DSP2803x_CpuTimers.h).
    pub const TCR_TSS: u16 = 1 << 4;
    pub const TCR_TRB: u16 = 1 << 5;
    pub const TCR_TIE: u16 = 1 << 14;

    /// PIEIER1 INTx7 (TINT0) enable bit.
    pub const PIE_INT7_EN: u16 = 1 << 6;
    /// PIEACK group-1 acknowledge bit.
    pub const PIEACK_GROUP1: u16 = 1 << 0;

    /// Mirrors `f28035_timer0_start_ms`: stop the timer, load the period,
    /// zero the prescaler, reload with interrupts enabled, then start.
    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub struct PeriodicStart {
        pub period_cycles: u32,
    }

    impl PeriodicStart {
        /// Writes the timer registers through the bus in the exact order used
        /// by the C bridge.  The vector-table pointer swap and global IER/EINT
        /// handling stay in the startup wrapper.
        ///
        /// # Safety
        /// All addresses are fixed CPU Timer0 / PIE register offsets.
        pub unsafe fn apply<B: MmioBus>(self, bus: &mut B) {
            // SAFETY: fixed CPU Timer0 / PIE register addresses.
            unsafe {
                // 1. Stop.
                TCR.modify(bus, TCR_TSS, TCR_TSS);
                // 2. Load period and zero the prescaler.
                PRD.write_u32(bus, self.period_cycles);
                TPR.write(bus, 0);
                TPRH.write(bus, 0);
                // 3. Reload (TRB) and enable the interrupt (TIE).
                TCR.modify(bus, TCR_TSS | TCR_TRB | TCR_TIE, TCR_TRB | TCR_TIE);
                // 4. PIE group-1 enable for TINT0.
                PIEIER1.modify(bus, PIE_INT7_EN, PIE_INT7_EN);
                // 5. Start (clear TSS).
                TCR.modify(bus, TCR_TSS, 0);
            }
        }
    }

    /// Acknowledges the PIE group-1 interrupt line, exactly like the C
    /// bridge's `PieCtrlRegs.PIEACK.all = PIEACK_GROUP1`.
    ///
    /// # Safety
    /// Same as [`TiWordAddress::write`] for PIEACK.
    pub unsafe fn ack_pie_group1<B: MmioBus>(bus: &mut B) {
        // SAFETY: fixed PIE register address.
        unsafe { PIEACK.write(bus, PIEACK_GROUP1) };
    }

    /// Writes the TINT0 entry of the PIE vector table, mirroring the backend's
    /// `MOVL XAR4, #handler; MOVW DP, #PieVectTable+76; MOVL @..., XAR4`.
    ///
    /// Global interrupt masking (DINT) and the EALLOW bracket around the
    /// vector write are CPU/startup concerns; the host models only the two
    /// word stores.
    ///
    /// # Safety
    /// `handler_address` must be the C28x entry point of the Timer0 ISR.
    pub unsafe fn set_tint0_vector<B: MmioBus>(bus: &mut B, handler_address: u32) {
        // SAFETY: fixed PIE vector table entry.
        unsafe { TINT0_VECTOR.write_u32(bus, handler_address) };
    }
}

/// FFI surface consumed by the safe HAL.
///
/// On target these symbols are recognized **by name** in the audited MIR
/// backend (`classify_platform_control_loop` / `classify_interrupt_callback`)
/// and every call is replaced with an inlined C28x MMIO sequence 鈥?the C bridge
/// object is only linked for the handful of `.ref` symbols the backend cannot
/// itself synthesize.  Keeping the declarations here makes PAC the single
/// source of truth for the hardware ABI the HAL depends on, instead of a
/// second copy in `lib.rs`.
///
/// On the host the `cfg(test)` stubs below stand in for the hardware so the
/// safe-HAL type state machine can be exercised without a C28x target.
pub mod ffi {
    #[cfg(not(test))]
    use super::{C28xMmio, TiWordAddress, adc, ecap, epwm1, eqep, gpio, i2c, lin, sci, spi, sysctrl, timer0, xint};

    #[cfg(not(test))]
    unsafe extern "C" {
    }

    // Target path: these are ordinary Rust fn definitions (not extern "C"
    // imports).  The audited MIR backend recognizes each call **by item_name**
    // inlining a fixed MMIO sequence, so the bodies below are never executed
    // on target 鈥?they exist only so the HAL type-checks and so the symbols
    // have a single home in PAC.  On host the cfg(test) stubs stand in.
    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_system_init() {
        let mut bus = C28xMmio;
        // SAFETY: fixed ADC / sysctrl register addresses; mirrors the audited
        // board-init sequence (clock enable + ADC power-up + SOC0 config).
        unsafe { adc::power_up_and_configure_soc0(&mut bus) };
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_gpio_make_output(pin: u16) -> u16 {
        let mut bus = C28xMmio;
        match gpio::output_config(pin) {
            Some(config) => {
                // SAFETY: pin validated by the HAL before this call.
                unsafe { config.apply(&mut bus) };
                1
            }
            None => 0,
        }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_gpio_make_input(pin: u16, pullup_enabled: u16, qualification: u16) -> u16 {
        let mut bus = C28xMmio;
        let qual = match qualification {
            1 => gpio::Qualification::Sample3,
            2 => gpio::Qualification::Sample6,
            3 => gpio::Qualification::Async,
            _ => gpio::Qualification::Sync,
        };
        match gpio::input_config(pin, pullup_enabled != 0, qual) {
            Some(config) => {
                // SAFETY: pin validated by the HAL.
                unsafe { config.apply(&mut bus) };
                1
            }
            None => 0,
        }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_gpio_read(pin: u16) -> u16 {
        let mut bus = C28xMmio;
        match gpio::input_config(pin, true, gpio::Qualification::Sync) {
            Some(config) => {
                // SAFETY: pin validated by the HAL.
                unsafe { u16::from(config.read(&mut bus)) }
            }
            None => 0,
        }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_gpio_write(pin: u16, high: u16) {
        let mut bus = C28xMmio;
        if let Some(cmd) = gpio::output_command(pin) {
            // SAFETY: pin validated by the HAL; SET/CLEAR are write-only commands.
            unsafe {
                if high != 0 {
                    cmd.set(&mut bus);
                } else {
                    cmd.clear(&mut bus);
                }
            }
        }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_gpio_toggle(pin: u16) {
        let mut bus = C28xMmio;
        if let Some(cmd) = gpio::output_command(pin) {
            // SAFETY: pin validated by the HAL; TOGGLE is a write-only command.
            unsafe { cmd.toggle(&mut bus) }
        }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_gpio_configure_xint(line: u16, pin: u16, edge: u16) -> u16 {
        let mut bus = C28xMmio;
        let edge = match edge {
            1 => xint::Edge::Rising,
            3 => xint::Edge::Both,
            _ => xint::Edge::Falling,
        };
        let config = if line == 1 {
            xint::xint1(pin, edge)
        } else {
            xint::xint2(pin, edge)
        };
        match config {
            Some(c) => {
                // SAFETY: pin/line validated by the HAL.
                unsafe { c.apply(&mut bus) };
                1
            }
            None => 0,
        }
    }

    /// Programs the GPIO MUX field for pin to unction (0 = GPIO,
    /// 1..3 = peripheral function).  Mirrors the audited C bridge
    /// 28035_gpio_set_mux: pin<16 -> GPAMUX1, 16..31 -> GPAMUX2,
    /// 32..44 -> GPBMUX1, shift = (pin % 16) * 2, 2-bit field.
    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_gpio_set_mux(pin: u16, function: u16) -> u16 {
        if pin > 44 || function > 3 {
            return 0;
        }
        let mut bus = C28xMmio;
        let (mux, shift) = if pin < 16 {
            (gpio::GPA_MUX1, pin * 2)
        } else if pin < 32 {
            (gpio::GPA_MUX2, (pin - 16) * 2)
        } else {
            (gpio::GPB_MUX1, (pin - 32) * 2)
        };
        // SAFETY: pin/function validated by the HAL before this call.
        unsafe { mux.modify_u32(&mut bus, 3u32 << shift, (function as u32) << shift) };
        1
    }

    /// Reads back the GPIO MUX field for pin (0 = GPIO, 1..3 = peripheral).
    /// Mirrors the audited C bridge 28035_gpio_mux; returns 0xffff for an
    /// out-of-range pin.
    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_gpio_mux(pin: u16) -> u16 {
        if pin > 44 {
            return 0xffff;
        }
        let mut bus = C28xMmio;
        let (mux, shift) = if pin < 16 {
            (gpio::GPA_MUX1, pin * 2)
        } else if pin < 32 {
            (gpio::GPA_MUX2, (pin - 16) * 2)
        } else {
            (gpio::GPB_MUX1, (pin - 32) * 2)
        };
        // SAFETY: pin validated by the HAL before this call.
        unsafe { ((mux.read_u32(&mut bus) >> shift) & 3) as u16 }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_result(result_index: u16) -> u16 {
        let mut bus = C28xMmio;
        // ADCRESULTn lives at 0x7108 + n*2 (n in 0..=15).
        let addr = TiWordAddress::new(0x7108 + result_index * 2);
        // SAFETY: result_index validated by the HAL.
        unsafe { addr.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_sample(channel: u16) -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: channel masked to 5 bits by trigger_soc0.
        unsafe { adc::trigger_soc0(&mut bus, channel) };
        1
    }

    /// Reconfigures SOC0 channel and acquisition window.
    ///
    /// The ADC power-up, clock enable, and interrupt routing are already done
    /// by 28035_system_init -> dc::power_up_and_configure_soc0; this
    /// call only rewrites the CHSEL (bits 0..4) and ACQPS (bits 6..10) fields
    /// of ADCSOC0CTL.  Mirrors the audited C bridge
    /// 28035_adc_configure_soc0 register half.
    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_configure_soc0(channel: u16, acqps: u16) -> u16 {
        if channel > 15 || acqps > 63 {
            return 0;
        }
        let mut bus = C28xMmio;
        // SAFETY: channel/acqps validated above; ADCSOC0CTL is a fixed ADC
        // register already powered up by system_init.
        unsafe {
            adc::ADCSOC0CTL.modify(&mut bus, adc::SOC0_CHSEL_MASK, channel);
            adc::ADCSOC0CTL.modify(&mut bus, adc::SOC0_ACQPS_MASK, acqps << 6);
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_timeouts() -> u16 {
        // The bounded EOC poll is runtime loop behavior; the typed PAC only
        // owns the trigger sequence, so this counter is model state on host.
        0
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_take_peripherals() -> u16 {
        // Peripheral ownership lock is a host/HAL type-state concept; on the
        // real device the MMIO bus is directly addressable.
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_start_once_ms(period_ms: u16) -> u16 {
        let mut bus = C28xMmio;
        // 60 MHz CPU clock -> 60000 cycles per millisecond.
        let cycles = u32::from(period_ms).saturating_mul(60_000);
        // SAFETY: fixed CPU Timer0 / PIE register addresses.
        unsafe {
            timer0::PeriodicStart {
                period_cycles: cycles,
            }
            .apply(&mut bus)
        };
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_start_periodic_ms(period_ms: u16) -> u16 {
        let mut bus = C28xMmio;
        let cycles = u32::from(period_ms).saturating_mul(60_000);
        // SAFETY: fixed CPU Timer0 / PIE register addresses.
        unsafe {
            timer0::PeriodicStart {
                period_cycles: cycles,
            }
            .apply(&mut bus)
        };
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_ack() {
        let mut bus = C28xMmio;
        // SAFETY: fixed PIE register address.
        unsafe { timer0::ack_pie_group1(&mut bus) };
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_stop() {
        let mut bus = C28xMmio;
        // SAFETY: fixed TCR address; set TSS (bit4) to stop.
        unsafe { timer0::TCR.modify(&mut bus, timer0::TCR_TSS, timer0::TCR_TSS) };
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_restart() {
        let mut bus = C28xMmio;
        // SAFETY: fixed TCR address; pulse TRB (bit5) to reload, clear TSS.
        unsafe { timer0::TCR.modify(&mut bus, timer0::TCR_TSS | timer0::TCR_TRB, timer0::TCR_TRB) };
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_set_period_ms(period_ms: u16) -> u16 {
        let mut bus = C28xMmio;
        let cycles = u32::from(period_ms).saturating_mul(60_000);
        // SAFETY: fixed PRD register (32-bit pair).
        unsafe { timer0::PRD.write_u32(&mut bus, cycles) };
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_interrupts() -> u16 {
        // Global IER/EINT are CPU startup state, not a PAC register sequence.
        0
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_configure(period_ticks: u16) -> u16 {
        let mut bus = C28xMmio;
        if period_ticks != 0 {
            // SAFETY: fixed ePWM1 registers.
            unsafe { epwm1::UpCountConfig { period_ticks }.apply(&mut bus) };
            1
        } else {
            0
        }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_set_compare(compare_ticks: u16) {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 registers.
        unsafe { epwm1::set_compare(&mut bus, compare_ticks) };
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_compare() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 register address.
        unsafe { epwm1::read_compare(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_enable() {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 register address.
        unsafe { epwm1::enable(&mut bus) };
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_disable() {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 register address.
        unsafe { epwm1::disable(&mut bus) };
    }

    // === Sunk C-bridge test cases (auto-generated, 2026-09-23) ===
    // Self-contained C functions from f28035_bridge.c; the Rust HAL wraps
    // them in safe entry points at module level below.
    #[cfg(not(test))]
    unsafe extern "C" {
        pub fn f28035_test_pass();
        pub fn f28035_test_fail(code: u16);
        fn f28035_xint1_falling_isr();
        fn f28035_xint1_rising_isr();
        static mut f28035_xint1_falling_seen: u16;
        static mut f28035_xint1_rising_seen: u16;
        pub fn f28035_ecap_apwm_matrix();
        pub fn f28035_ecap_capture_continuous_wrap();
        pub fn f28035_ecap_capture_counter_reset();
        pub fn f28035_ecap_capture_dual_edge();
        pub fn f28035_ecap_capture_prescale_div2();
        pub fn f28035_ecap_capture_quad_edge();
        pub fn f28035_ecap_capture_single_edge();
        pub fn f28035_ecap_capture_wrap_matrix();
        pub fn f28035_ecap_interrupt_integration();
        pub fn f28035_eqep_compare_output_pulse();
        pub fn f28035_eqep_count_basic();
        pub fn f28035_eqep_interrupt_gate();
        pub fn f28035_eqep_mode_test();
        pub fn f28035_eqep_polarity_test();
        pub fn f28035_eqep_reset_fsm_matrix();
        pub fn f28035_eqep_unit_timeout_test();
        pub fn f28035_eqep_unit_timer();
        pub fn f28035_eqep_watchdog_timeout_test();
        pub fn f28035_i2c_master_addr_nack_stop_basic();
        pub fn f28035_i2c_master_read_1byte_basic();
        pub fn f28035_i2c_master_read_8byte_basic();
        pub fn f28035_i2c_master_read_back_to_back_basic();
        pub fn f28035_i2c_master_repeated_start_write_then_read_4byte_basic();
        pub fn f28035_i2c_master_write_1byte_basic();
        pub fn f28035_i2c_master_write_8byte_pattern();
        pub fn f28035_i2c_master_write_back_to_back();
        pub fn f28035_i2c_master_write_then_read_4byte_basic();
        pub fn f28035_lin_baud_program_basic();
        pub fn f28035_lin_header_break_sync_master_basic();
        pub fn f28035_lin_iodft_loopback_basic();
        pub fn f28035_lin_rx_checksum_length_real_basic();
        pub fn f28035_lin_rx_rxcnt_num_boundary_real_basic();
        pub fn f28035_lin_sci_multibuf_rdslot_sweep_basic();
        pub fn f28035_lin_top_mode_loopback_power_cross_basic();
        pub fn f28035_lin_tx_checksum_ext_real_basic();
        pub fn f28035_lin_wakeup_break_flag_route_basic();
        pub fn f28035_sci_baud_program_basic();
        pub fn f28035_sci_fifo_reset_then_loopback_basic();
        pub fn f28035_sci_fifo_rx_basic();
        pub fn f28035_sci_internal_loopback_basic();
        pub fn f28035_sci_loopback_data_pattern_basic();
        pub fn f28035_sci_rxrdy_clear_on_read_basic();
        pub fn f28035_sci_sciccr_charlen_sweep_basic();
        pub fn f28035_sci_stop2_parity_charlen_sweep_basic();
        pub fn f28035_sci_txrdy_int_nonfifo_basic();
        pub fn f28035_spi_charlen_sweep_basic();
        pub fn f28035_spi_fifo_level_boundary_basic();
        pub fn f28035_spi_fifo_rx_boundary_basic();
        pub fn f28035_spi_fifo_tx_boundary_basic();
        pub fn f28035_spi_internal_loopback_basic();
        pub fn f28035_spi_loopback_mode_matrix_basic();
        pub fn f28035_spi_multiple_frame_loopback_basic();
        pub fn f28035_spi_nonfifo_intflag_irq_basic();
        pub fn f28035_spi_triwire_loopback_basic();
    }

    // === Multi-call case FFI wrappers (auto-generated, 2026-09-23) ===
    #[cfg(not(test))]
    unsafe extern "C" {
    }

    // === Timer0 ADC trigger: direct Rust PAC (replaced C bridge, 2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_start_adc_trigger(period_ticks: u16) -> u16 {
        if period_ticks == 0 {
            return 0;
        }
        let mut bus = C28xMmio;
        // SAFETY: fixed sysctrl / timer0 register addresses; mirrors the C
        // bridge sequence: enable TBCLK, zero prescaler, load period, start.
        unsafe {
            sysctrl::PCLKCR3.write(&mut bus, sysctrl::PCLKCR3_CPUTIMER0ENCLK);
            timer0::TPR.write(&mut bus, 0);
            timer0::TPRH.write(&mut bus, 0);
            timer0::PRD.write_u32(&mut bus, period_ticks as u32);
            // TCR = 0xC020: TIE=1, FREE=1, TRB=1, TSS=0 (start with reload).
            timer0::TCR.write(&mut bus, 0xC020);
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_timer0_stop_adc_trigger() {
        let mut bus = C28xMmio;
        // SAFETY: fixed timer0 register; TCR = 0x8010: TIE=1, TSS=1 (stop).
        unsafe { timer0::TCR.write(&mut bus, 0x8010) };
    }

        // === lin_reg_if_rw_basic: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_lin_reg_if_rw_basic() {
        let mut bus = C28xMmio;
        // GPIO init: GPIO9=LIN_TX, GPIO11=LIN_RX
        let mut mux1 = gpio::GPA_MUX1.read_u32(&mut bus);
        mux1 = (mux1 & !(0x3 << 18)) | (1 << 18); // GPIO9
        mux1 = (mux1 & !(0x3 << 22)) | (1 << 22); // GPIO11
        gpio::GPA_MUX1.write_u32(&mut bus, mux1);
        // Enable LIN-A clock
        let mut pclkcr0 = sysctrl::PCLKCR0.read_u32(&mut bus);
        pclkcr0 |= sysctrl::PCLKCR0_LINAENCLK as u32;
        sysctrl::PCLKCR0.write_u32(&mut bus, pclkcr0);
        // Basic slave init
        lin::SCIGCR1.write(&mut bus, 0);
        lin::SCIGCR2.write(&mut bus, 0);
        lin::SCIGCR1.write(&mut bus, 0x0080); // SWnRST=1
        lin::SCIGCR1.write(&mut bus, 0);      // SWnRST=0
        lin::SCIGCR1.write(&mut bus, 0x0002); // LINMODE=1
        lin::SCIGCR2.write(&mut bus, 0x0001); // CC=1
        lin::BRSR.write_u32(&mut bus, (11u32 << 16) | 96); // M=11, PSL=96
        lin::MBRSR.write(&mut bus, 92);
        lin::SCIFORMAT.write(&mut bus, 0);
        lin::LINCOMP.write(&mut bus, (5u16 << 6) | 3); // SBREAK=5, SDEL=3
        lin::LINMASK.write(&mut bus, (0xFFu16 << 8) | 0xFF); // TXIDMASK=FF, RXIDMASK=FF
        lin::LINID.write(&mut bus, 0x10); // IDSLAVETASKBYTE=0x10
        // Verify
        if (lin::SCIGCR2.read(&mut bus) & 1) != 1 { f28035_test_fail(0x5202 + lin::SCIGCR2.read(&mut bus)); return; }
        let brsr = lin::BRSR.read_u32(&mut bus);
        if (brsr & 0xFFFF) != 96 || (brsr >> 16) != 11 { f28035_test_fail(0x5203 + brsr as u16); return; }
        if (lin::MBRSR.read(&mut bus) & 0xFFFF) != 92 { f28035_test_fail(0x5204 + lin::MBRSR.read(&mut bus)); return; }
        if (lin::SCIFORMAT.read(&mut bus) & 7) != 0 { f28035_test_fail(0x5205 + lin::SCIFORMAT.read(&mut bus)); return; }
        let lincomp = lin::LINCOMP.read(&mut bus);
        if (lincomp >> 6) & 0xF != 5 || (lincomp & 0xF) != 3 { f28035_test_fail(0x5206 + lincomp); return; }
        let linmask = lin::LINMASK.read(&mut bus);
        if (linmask >> 8) != 0xFF || (linmask & 0xFF) != 0xFF { f28035_test_fail(0x5207 + linmask); return; }
        if lin::LINID.read(&mut bus) != 0x10 { f28035_test_fail(0x5208 + lin::LINID.read(&mut bus)); return; }
        f28035_test_pass();
    }

        // === i2c_reg_readback_sweep_basic: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_i2c_reg_readback_sweep_basic() {
        let mut bus = C28xMmio;
        let mut sink = 0u16;
        // Standard init: enable clock + exit reset
        let mut pclkcr0 = sysctrl::PCLKCR0.read_u32(&mut bus);
        pclkcr0 |= sysctrl::PCLKCR0_I2CAENCLK as u32;
        sysctrl::PCLKCR0.write_u32(&mut bus, pclkcr0);
        i2c::I2CMDR.write(&mut bus, 0);
        i2c::I2CPSC.write(&mut bus, 6);
        i2c::I2CCLKL.write(&mut bus, 200);
        i2c::I2CCLKH.write(&mut bus, 160);
        i2c::I2COAR.write(&mut bus, 0x00C0);
        i2c::I2CSTR.write(&mut bus, 0xFFFF);
        i2c::I2CMDR.write(&mut bus, 0);
        i2c::I2CMDR.write(&mut bus, 0x0020); // IRS=1
        // Register readback sweep
        i2c::I2COAR.write(&mut bus, 0x0035);
        if (i2c::I2COAR.read(&mut bus) & 0x03FF) != 0x0035 { f28035_test_fail(0x7F01); return; }
        i2c::I2CIER.write(&mut bus, 0x0055);
        if (i2c::I2CIER.read(&mut bus) & 0x007F) != 0x0055 { f28035_test_fail(0x7F02); return; }
        i2c::I2CCLKL.write(&mut bus, 0x00C8);
        if i2c::I2CCLKL.read(&mut bus) != 0x00C8 { f28035_test_fail(0x7F03); return; }
        i2c::I2CCLKH.write(&mut bus, 0x00A0);
        if i2c::I2CCLKH.read(&mut bus) != 0x00A0 { f28035_test_fail(0x7F04); return; }
        i2c::I2CCNT.write(&mut bus, 0x0004);
        if i2c::I2CCNT.read(&mut bus) != 0x0004 { f28035_test_fail(0x7F05); return; }
        sink ^= i2c::I2CDRR.read(&mut bus) & 0x00FF;
        i2c::I2CSAR.write(&mut bus, 0x0036);
        if (i2c::I2CSAR.read(&mut bus) & 0x03FF) != 0x0036 { f28035_test_fail(0x7F07); return; }
        i2c::I2CDXR.write(&mut bus, 0x00A5);
        if (i2c::I2CDXR.read(&mut bus) & 0x00FF) != 0x00A5 { f28035_test_fail(0x7F08); return; }
        i2c::I2CMDR.write(&mut bus, 0x0020);
        if (i2c::I2CMDR.read(&mut bus) & 0x0020) != 0x0020 { f28035_test_fail(0x7F09); return; }
        sink ^= i2c::I2CISRC.read(&mut bus);
        sink ^= i2c::I2CEMDR.read(&mut bus);
        i2c::I2CPSC.write(&mut bus, 0x0006);
        if (i2c::I2CPSC.read(&mut bus) & 0x00FF) != 0x0006 { f28035_test_fail(0x7F0C); return; }
        if i2c::I2CFFTX.read(&mut bus) != 0x0105 { f28035_test_fail(0x7F0D); return; }
        if i2c::I2CFFRX.read(&mut bus) != 0x0005 { f28035_test_fail(0x7F0E); return; }
        i2c::I2CFFTX.write(&mut bus, 0x6000);
        if (i2c::I2CFFTX.read(&mut bus) & 0x6000) != 0x6000 { f28035_test_fail(0x7F20); return; }
        i2c::I2CFFRX.write(&mut bus, 0x2040);
        if (i2c::I2CFFRX.read(&mut bus) & 0x2000) != 0x2000 { f28035_test_fail(0x7F21); return; }
        i2c::I2CSTR.write(&mut bus, 0xFFFF);
        sink ^= i2c::I2CSTR.read(&mut bus);
        if sink == 0xFFFF { f28035_test_fail(0x7F40); return; }
        f28035_test_pass();
    }

        // === sci_reg_if_rw_basic: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_sci_reg_if_rw_basic() {
        let mut bus = C28xMmio;
        // Enable SCI-A clock
        let mut pclkcr0 = sysctrl::PCLKCR0.read_u32(&mut bus);
        pclkcr0 |= sysctrl::PCLKCR0_SCIAENCLK as u32;
        sysctrl::PCLKCR0.write_u32(&mut bus, pclkcr0);
        // Write config
        sci::SCICCR.write(&mut bus, 0x0037);
        sci::SCICTL1.write(&mut bus, 0x0043);
        sci::SCICTL2.write(&mut bus, 0x0003);
        sci::SCIHBAUD.write(&mut bus, 0x0012);
        sci::SCILBAUD.write(&mut bus, 0x0034);
        sci::SCIFFTX.write(&mut bus, 0xC003);
        sci::SCIFFRX.write(&mut bus, 0x0024);
        sci::SCIFFCT.write(&mut bus, 0x2055);
        sci::SCIPRI.write(&mut bus, 0x0010);
        // Verify
        let rd = sci::SCICCR.read(&mut bus);
        if (rd & 0x0077) != 0x0037 { f28035_test_fail(0x0001 + rd); return; }
        let rd = sci::SCICTL1.read(&mut bus);
        if (rd & 0x0043) != 0x0043 { f28035_test_fail(0x0002 + rd); return; }
        let rd = sci::SCIHBAUD.read(&mut bus);
        if (rd & 0x00FF) != 0x0012 { f28035_test_fail(0x0003 + rd); return; }
        let rd = sci::SCILBAUD.read(&mut bus);
        if (rd & 0x00FF) != 0x0034 { f28035_test_fail(0x0103 + rd); return; }
        let rd = sci::SCICTL2.read(&mut bus);
        if (rd & 0x0003) != 0x0003 { f28035_test_fail(0x0004 + rd); return; }
        let rd = sci::SCIFFTX.read(&mut bus);
        if (rd & 0xC01F) != 0xC003 { f28035_test_fail(0x0005 + rd); return; }
        let rd = sci::SCIFFRX.read(&mut bus);
        if (rd & 0x003F) != 0x0024 { f28035_test_fail(0x0006 + rd); return; }
        let rd = sci::SCIFFCT.read(&mut bus);
        if (rd & 0x20FF) != 0x2055 { f28035_test_fail(0x0007 + rd); return; }
        let rd = sci::SCIPRI.read(&mut bus);
        if (rd & 0x0010) != 0x0010 { f28035_test_fail(0x0008 + rd); return; }
        f28035_test_pass();
    }

        // === spi_reg_if_rw_basic: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_spi_reg_if_rw_basic() {
        let mut bus = C28xMmio;
        // Enable SPI-B clock
        let mut pclkcr0 = sysctrl::PCLKCR0.read_u32(&mut bus);
        pclkcr0 |= sysctrl::PCLKCR0_SPIBENCLK as u32;
        sysctrl::PCLKCR0.write_u32(&mut bus, pclkcr0);
        // SPICCR RW (mask 0x00D7)
        let wr = 0x00D7u16;
        spi::SPICCR.write(&mut bus, wr);
        if (spi::SPICCR.read(&mut bus) & 0x00D7) != (wr & 0x00D7) { f28035_test_fail(0x0001); return; }
        // SPICTL RW (mask 0x001F)
        let wr = 0x001Fu16;
        spi::SPICTL.write(&mut bus, wr);
        if (spi::SPICTL.read(&mut bus) & 0x001F) != (wr & 0x001F) { f28035_test_fail(0x0002); return; }
        // SPIBRR RW (mask 0x007F)
        let wr = 0x007Fu16;
        spi::SPIBRR.write(&mut bus, wr);
        if (spi::SPIBRR.read(&mut bus) & 0x007F) != (wr & 0x007F) { f28035_test_fail(0x0003); return; }
        // SPIFFCT RW (mask 0x00FF)
        let wr = 0x0055u16;
        spi::SPIFFCT.write(&mut bus, wr);
        if (spi::SPIFFCT.read(&mut bus) & 0x00FF) != (wr & 0x00FF) { f28035_test_fail(0x0004); return; }
        // SPIPRI RW (mask 0x003F)
        let wr = 0x0073u16;
        spi::SPIPRI.write(&mut bus, wr);
        if (spi::SPIPRI.read(&mut bus) & 0x003F) != (wr & 0x003F) { f28035_test_fail(0x0005); return; }
        f28035_test_pass();
    }

        // === eqep_register_wr: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_eqep_register_wr() {
        let mut bus = C28xMmio;
        let mut ok = 0u16;
        let mut errs = 0u16;
        // GPIO init: enable eQEP1 clock + GPIO20-23 mux
        let mut pclkcr1 = sysctrl::PCLKCR1.read_u32(&mut bus);
        pclkcr1 |= sysctrl::PCLKCR1_EQEP1ENCLK;
        sysctrl::PCLKCR1.write_u32(&mut bus, pclkcr1);
        let mut mux2 = gpio::GPA_MUX2.read_u32(&mut bus);
        mux2 = (mux2 & !(0x3 << 16)) | (1 << 16); // GPIO20 QEPA
        mux2 = (mux2 & !(0x3 << 18)) | (1 << 18); // GPIO21 QEPB
        mux2 = (mux2 & !(0x3 << 20)) | (1 << 20); // GPIO22 QEPI
        mux2 = (mux2 & !(0x3 << 22)) | (1 << 22); // GPIO23 QEPS
        gpio::GPA_MUX2.write_u32(&mut bus, mux2);
        // Base reset
        eqep::QEPCTL.write(&mut bus, 0);
        eqep::QDECCTL.write(&mut bus, 0);
        eqep::QCAPCTL.write(&mut bus, 0);
        eqep::QPOSCTL.write(&mut bus, 0);
        eqep::QEINT.write(&mut bus, 0);
        eqep::QCLR.write(&mut bus, 0x0FFF);
        // QDECCTL config
        eqep::QDECCTL.write(&mut bus, (3 << 14) | (1 << 12) | (1 << 11) | (1 << 10) | (1 << 9) | (1 << 8) | (1 << 7) | (1 << 6));
        let qdecctl = eqep::QDECCTL.read(&mut bus);
        if (qdecctl >> 14) & 3 == 3 { ok += 1; } else { errs += 1; }
        if (qdecctl >> 12) & 1 == 1 { ok += 1; } else { errs += 1; }
        if (qdecctl >> 11) & 1 == 1 { ok += 1; } else { errs += 1; }
        if (qdecctl >> 10) & 1 == 1 { ok += 1; } else { errs += 1; }
        // QEPCTL config
        eqep::QEPCTL.write(&mut bus, (2 << 14) | (1 << 13) | (1 << 9) | (1 << 5) | (1 << 4));
        let qepctl = eqep::QEPCTL.read(&mut bus);
        if (qepctl >> 9) & 1 == 1 { ok += 1; } else { errs += 1; }
        if (qepctl >> 4) & 1 == 1 { ok += 1; } else { errs += 1; }
        if (qepctl >> 3) & 1 == 0 { ok += 1; } else { errs += 1; }
        // QCAPCTL + QPOSCTL config
        eqep::QCAPCTL.write(&mut bus, (5 << 4) | 9);
        eqep::QPOSCTL.write(&mut bus, (1 << 12) | (1 << 11) | (1 << 10));
        let qcapctl = eqep::QCAPCTL.read(&mut bus);
        if (qcapctl >> 4) & 0xF == 5 { ok += 1; } else { errs += 1; }
        let qposctl = eqep::QPOSCTL.read(&mut bus);
        if (qposctl >> 12) & 1 == 1 { ok += 1; } else { errs += 1; }
        // 32-bit register writes
        eqep::QPOSINIT.write_u32(&mut bus, 0x12345678);
        eqep::QPOSMAX.write_u32(&mut bus, 0x89ABCDEF);
        eqep::QPOSCMP.write_u32(&mut bus, 0x00001234);
        eqep::QUPRD.write_u32(&mut bus, 0x00023456);
        eqep::QWDPRD.write(&mut bus, 0x3456);
        if eqep::QPOSINIT.read_u32(&mut bus) == 0x12345678 { ok += 1; } else { errs += 1; }
        if eqep::QPOSMAX.read_u32(&mut bus) == 0x89ABCDEF { ok += 1; } else { errs += 1; }
        if eqep::QUPRD.read_u32(&mut bus) == 0x00023456 { ok += 1; } else { errs += 1; }
        // QEINT config
        eqep::QEINT.write(&mut bus, 0x0FFE);
        if (eqep::QEINT.read(&mut bus) & 0x0FFE) == 0x0FFE { ok += 1; } else { errs += 1; }
        if errs == 0 && ok >= 14 {
            f28035_test_pass();
        } else {
            f28035_test_fail(0xEB01);
        }
    }

        // === ecap_reg_rw_smoke: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_ecap_reg_rw_smoke() {
        let mut bus = C28xMmio;
        // Enable eCAP1 clock
        let mut pclkcr1 = sysctrl::PCLKCR1.read_u32(&mut bus);
        pclkcr1 |= sysctrl::PCLKCR1_ECAP1ENCLK;
        sysctrl::PCLKCR1.write_u32(&mut bus, pclkcr1);
        // Read reset snapshot
        let tsctr = ecap::TSCTR.read_u32(&mut bus);
        let ctrphs = ecap::CTRPHS.read_u32(&mut bus);
        let cap1 = ecap::CAP1.read_u32(&mut bus);
        let cap2 = ecap::CAP2.read_u32(&mut bus);
        let cap3 = ecap::CAP3.read_u32(&mut bus);
        let cap4 = ecap::CAP4.read_u32(&mut bus);
        let ecctl1 = ecap::ECCTL1.read(&mut bus);
        let ecctl2 = ecap::ECCTL2.read(&mut bus);
        let eceint = ecap::ECEINT.read(&mut bus);
        let ecflg = ecap::ECFLG.read(&mut bus);
        // Verify reset values
        if tsctr != 0 { f28035_test_fail(0x3101); return; }
        if ctrphs != 0 { f28035_test_fail(0x3102); return; }
        if cap1 != 0 { f28035_test_fail(0x3103); return; }
        if cap2 != 0 { f28035_test_fail(0x3104); return; }
        if cap3 != 0 { f28035_test_fail(0x3105); return; }
        if cap4 != 0 { f28035_test_fail(0x3106); return; }
        if ecctl1 != 0 { f28035_test_fail(0x3107); return; }
        if ecctl2 != 0x0006 { f28035_test_fail(0x3108); return; }
        if eceint != 0 { f28035_test_fail(0x3109); return; }
        if ecflg != 0 { f28035_test_fail(0x310A); return; }
        // Quiet baseline
        ecap::ECEINT.write(&mut bus, 0);
        ecap::ECCLR.write(&mut bus, 0x00FF);
        ecap::ECCTL1.write(&mut bus, 0);
        ecap::ECCTL2.write(&mut bus, 0x0006);
        ecap::TSCTR.write_u32(&mut bus, 0);
        ecap::CTRPHS.write_u32(&mut bus, 0);
        ecap::CAP1.write_u32(&mut bus, 0);
        ecap::CAP2.write_u32(&mut bus, 0);
        ecap::CAP3.write_u32(&mut bus, 0);
        ecap::CAP4.write_u32(&mut bus, 0);
        // CTRPHS masked RW
        ecap::CTRPHS.write_u32(&mut bus, 0x55555555);
        if ecap::CTRPHS.read_u32(&mut bus) != 0x55555555 { f28035_test_fail(0x3111); return; }
        ecap::CTRPHS.write_u32(&mut bus, 0xAAAAAAAA);
        if ecap::CTRPHS.read_u32(&mut bus) != 0xAAAAAAAA { f28035_test_fail(0x3112); return; }
        ecap::CTRPHS.write_u32(&mut bus, 0);
        if ecap::CTRPHS.read_u32(&mut bus) != 0 { f28035_test_fail(0x3117); return; }
        // ECCTL1 masked RW
        ecap::ECCTL1.write(&mut bus, 0x5555);
        if ecap::ECCTL1.read(&mut bus) != 0x5555 { f28035_test_fail(0x3113); return; }
        ecap::ECCTL1.write(&mut bus, 0xAAAA);
        if ecap::ECCTL1.read(&mut bus) != 0xAAAA { f28035_test_fail(0x3114); return; }
        // ECEINT masked RW (mask 0x00FE)
        ecap::ECEINT.write(&mut bus, 0x5555);
        if ecap::ECEINT.read(&mut bus) != (0x5555 & 0x00FE) { f28035_test_fail(0x3115); return; }
        ecap::ECEINT.write(&mut bus, 0xAAAA);
        if ecap::ECEINT.read(&mut bus) != (0xAAAA & 0x00FE) { f28035_test_fail(0x3116); return; }
        // 32-bit data RW
        ecap::TSCTR.write_u32(&mut bus, 0x55555555);
        if ecap::TSCTR.read_u32(&mut bus) != 0x55555555 { f28035_test_fail(0x3118); return; }
        ecap::TSCTR.write_u32(&mut bus, 0xAAAAAAAA);
        if ecap::TSCTR.read_u32(&mut bus) != 0xAAAAAAAA { f28035_test_fail(0x3119); return; }
        ecap::CAP1.write_u32(&mut bus, 0x55555555);
        if ecap::CAP1.read_u32(&mut bus) != 0x55555555 { f28035_test_fail(0x311A); return; }
        ecap::CAP1.write_u32(&mut bus, 0xAAAAAAAA);
        if ecap::CAP1.read_u32(&mut bus) != 0xAAAAAAAA { f28035_test_fail(0x311B); return; }
        ecap::CAP2.write_u32(&mut bus, 0x55555555);
        if ecap::CAP2.read_u32(&mut bus) != 0x55555555 { f28035_test_fail(0x311C); return; }
        ecap::CAP2.write_u32(&mut bus, 0xAAAAAAAA);
        if ecap::CAP2.read_u32(&mut bus) != 0xAAAAAAAA { f28035_test_fail(0x311D); return; }
        ecap::CAP3.write_u32(&mut bus, 0x55555555);
        if ecap::CAP3.read_u32(&mut bus) != 0x55555555 { f28035_test_fail(0x311E); return; }
        ecap::CAP3.write_u32(&mut bus, 0xAAAAAAAA);
        if ecap::CAP3.read_u32(&mut bus) != 0xAAAAAAAA { f28035_test_fail(0x311F); return; }
        ecap::CAP4.write_u32(&mut bus, 0x55555555);
        if ecap::CAP4.read_u32(&mut bus) != 0x55555555 { f28035_test_fail(0x3120); return; }
        ecap::CAP4.write_u32(&mut bus, 0xAAAAAAAA);
        if ecap::CAP4.read_u32(&mut bus) != 0xAAAAAAAA { f28035_test_fail(0x3121); return; }
        // Action regs read back zero
        if ecap::ECCLR.read(&mut bus) != 0 { f28035_test_fail(0x3122); return; }
        if ecap::ECFRC.read(&mut bus) != 0 { f28035_test_fail(0x3123); return; }
        f28035_test_pass();
    }

        // === gpio_xint smoke tests: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_gpio_xint_falling_smoke() {
        let mut bus = C28xMmio;
        f28035_gpio_make_output(30);
        f28035_gpio_write(30, 1);
        f28035_gpio_make_input(0, 0, 0);
        // Set PIE vector table entry for XINT1 (INT1.4)
        xint::XINT1_VECTOR.write_u32(&mut bus, f28035_xint1_falling_isr as u32);
        // Configure XINT1 on GPIO0, falling edge
        f28035_gpio_configure_xint(1, 0, 0);
        f28035_xint1_falling_seen = 0;
        f28035_delay_us(50);
        f28035_gpio_write(30, 0); // falling edge if GPIO30 jumpered to GPIO0
        let mut i = 0u32;
        while i < 300000 {
            if f28035_xint1_falling_seen >= 1 { break; }
            i += 1;
        }
        // Disable XINT1
        xint::XINT1CR.modify(&mut bus, 0, 0x0001);
        xint::PIEIER1.modify(&mut bus, 0, 0x0008);
        if f28035_xint1_falling_seen < 1 {
            f28035_test_fail(0x0901);
            return;
        }
        f28035_test_pass();
    }

    #[cfg(not(test))]
    pub unsafe fn f28035_gpio_xint_rising_smoke() {
        let mut bus = C28xMmio;
        f28035_gpio_make_output(30);
        f28035_gpio_write(30, 0);
        f28035_gpio_make_input(0, 0, 0);
        // Set PIE vector table entry for XINT1 (INT1.4)
        xint::XINT1_VECTOR.write_u32(&mut bus, f28035_xint1_rising_isr as u32);
        // Configure XINT1 on GPIO0, rising edge
        f28035_gpio_configure_xint(1, 0, 1);
        f28035_xint1_rising_seen = 0;
        f28035_delay_us(50);
        f28035_gpio_write(30, 1); // rising edge if GPIO30 jumpered to GPIO0
        let mut i = 0u32;
        while i < 300000 {
            if f28035_xint1_rising_seen >= 1 { break; }
            i += 1;
        }
        // Disable XINT1
        xint::XINT1CR.modify(&mut bus, 0, 0x0001);
        xint::PIEIER1.modify(&mut bus, 0, 0x0008);
        if f28035_xint1_rising_seen < 1 {
            f28035_test_fail(0x0801);
            return;
        }
        f28035_test_pass();
    }

        // === epwm1_reg_rw_smoke: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_epwm1_reg_rw_smoke() {
        let mut bus = C28xMmio;
        // Enable ePWM1 clock
        let mut pclkcr1 = sysctrl::PCLKCR1.read_u32(&mut bus);
        pclkcr1 |= sysctrl::PCLKCR1_EPWM1ENCLK;
        sysctrl::PCLKCR1.write_u32(&mut bus, pclkcr1);
        // Read reset values
        let reset_tbctl = epwm1::TBCTL.read(&mut bus);
        let reset_tbctr = epwm1::TBCTR.read(&mut bus);
        let reset_tbprd = epwm1::TBPRD.read(&mut bus);
        let reset_cmpa = epwm1::CMPA.read(&mut bus);
        let reset_aqctla = epwm1::AQCTLA.read(&mut bus);
        let reset_aqctlb = epwm1::AQCTLB.read(&mut bus);
        let reset_dbctl = epwm1::DBCTL.read(&mut bus);
        let reset_dbred = epwm1::DBRED.read(&mut bus);
        let reset_dbfed = epwm1::DBFED.read(&mut bus);
        let reset_etsel = epwm1::ETSEL.read(&mut bus);
        let reset_etps = epwm1::ETPS.read(&mut bus);
        let reset_tbphshr = epwm1::TBPHSHR.read(&mut bus);
        let reset_tbprdhr = epwm1::TBPRDHR.read(&mut bus);
        let reset_cmpahr = epwm1::CMPAHR.read(&mut bus);
        let reset_hrcnfg = epwm1::HRCNFG.read(&mut bus);
        let reset_hrpwr = epwm1::HRPWR.read(&mut bus);
        let reset_hrpctl = epwm1::HRPCTL.read(&mut bus);
        // Verify reset values
        if reset_tbctl != 0x0083 { f28035_test_fail(0x3201); return; }
        if reset_tbctr != 0x0000 { f28035_test_fail(0x3202); return; }
        if reset_tbprd != 0x0000 { f28035_test_fail(0x3203); return; }
        if reset_cmpa != 0x0000 { f28035_test_fail(0x3204); return; }
        if reset_aqctla != 0x0000 { f28035_test_fail(0x3205); return; }
        if reset_aqctlb != 0x0000 { f28035_test_fail(0x3206); return; }
        if reset_dbctl != 0x0000 { f28035_test_fail(0x3207); return; }
        if reset_dbred != 0x0000 { f28035_test_fail(0x3208); return; }
        if reset_dbfed != 0x0000 { f28035_test_fail(0x3209); return; }
        if reset_etsel != 0x0000 { f28035_test_fail(0x320A); return; }
        if reset_etps != 0x0000 { f28035_test_fail(0x320B); return; }
        if reset_tbphshr != 0x0000 { f28035_test_fail(0x3230); return; }
        if reset_tbprdhr != 0x0000 { f28035_test_fail(0x3231); return; }
        if reset_cmpahr != 0x0000 { f28035_test_fail(0x3232); return; }
        if reset_hrcnfg != 0x0000 { f28035_test_fail(0x3233); return; }
        if reset_hrpwr != 0x0000 { f28035_test_fail(0x3234); return; }
        if reset_hrpctl != 0x0000 { f28035_test_fail(0x3235); return; }
        // Clear all registers
        epwm1::TBCTL.write(&mut bus, 0x0083);
        epwm1::TBCTR.write(&mut bus, 0);
        epwm1::TBPRD.write(&mut bus, 0);
        epwm1::CMPA.write(&mut bus, 0);
        epwm1::AQCTLA.write(&mut bus, 0);
        epwm1::AQCTLB.write(&mut bus, 0);
        epwm1::DBCTL.write(&mut bus, 0);
        epwm1::DBRED.write(&mut bus, 0);
        epwm1::DBFED.write(&mut bus, 0);
        epwm1::ETSEL.write(&mut bus, 0);
        epwm1::ETPS.write(&mut bus, 0);
        epwm1::TBPHSHR.write(&mut bus, 0);
        epwm1::TBPRDHR.write(&mut bus, 0);
        epwm1::CMPAHR.write(&mut bus, 0);
        epwm1::HRCNFG.write(&mut bus, 0);
        epwm1::HRPWR.write(&mut bus, 0);
        epwm1::HRPCTL.write(&mut bus, 0);
        // Masked 16-bit RW tests
        epwm1::TBPRD.write(&mut bus, 0x5555);
        if epwm1::TBPRD.read(&mut bus) != (0x5555 & 0xFFFF) { f28035_test_fail(0x3211); return; }
        epwm1::TBPRD.write(&mut bus, 0xAAAA);
        if epwm1::TBPRD.read(&mut bus) != (0xAAAA & 0xFFFF) { f28035_test_fail(0x3212); return; }
        epwm1::CMPA.write(&mut bus, 0x5555);
        if epwm1::CMPA.read(&mut bus) != (0x5555 & 0xFFFF) { f28035_test_fail(0x3213); return; }
        epwm1::CMPA.write(&mut bus, 0xAAAA);
        if epwm1::CMPA.read(&mut bus) != (0xAAAA & 0xFFFF) { f28035_test_fail(0x3214); return; }
        epwm1::AQCTLA.write(&mut bus, 0x5555);
        if epwm1::AQCTLA.read(&mut bus) != (0x5555 & 0x0FFF) { f28035_test_fail(0x3215); return; }
        epwm1::AQCTLA.write(&mut bus, 0xAAAA);
        if epwm1::AQCTLA.read(&mut bus) != (0xAAAA & 0x0FFF) { f28035_test_fail(0x3216); return; }
        epwm1::AQCTLB.write(&mut bus, 0x5555);
        if epwm1::AQCTLB.read(&mut bus) != (0x5555 & 0x0FFF) { f28035_test_fail(0x3217); return; }
        epwm1::AQCTLB.write(&mut bus, 0xAAAA);
        if epwm1::AQCTLB.read(&mut bus) != (0xAAAA & 0x0FFF) { f28035_test_fail(0x3218); return; }
        epwm1::DBCTL.write(&mut bus, 0x5555);
        if epwm1::DBCTL.read(&mut bus) != (0x5555 & 0x803F) { f28035_test_fail(0x3219); return; }
        epwm1::DBCTL.write(&mut bus, 0xAAAA);
        if epwm1::DBCTL.read(&mut bus) != (0xAAAA & 0x803F) { f28035_test_fail(0x321A); return; }
        epwm1::DBRED.write(&mut bus, 0x5555);
        if epwm1::DBRED.read(&mut bus) != (0x5555 & 0x03FF) { f28035_test_fail(0x321B); return; }
        epwm1::DBRED.write(&mut bus, 0xAAAA);
        if epwm1::DBRED.read(&mut bus) != (0xAAAA & 0x03FF) { f28035_test_fail(0x321C); return; }
        epwm1::DBFED.write(&mut bus, 0x5555);
        if epwm1::DBFED.read(&mut bus) != (0x5555 & 0x03FF) { f28035_test_fail(0x321D); return; }
        epwm1::DBFED.write(&mut bus, 0xAAAA);
        if epwm1::DBFED.read(&mut bus) != (0xAAAA & 0x03FF) { f28035_test_fail(0x321E); return; }
        epwm1::ETSEL.write(&mut bus, 0x5555);
        if epwm1::ETSEL.read(&mut bus) != (0x5555 & 0xFF0F) { f28035_test_fail(0x321F); return; }
        epwm1::ETSEL.write(&mut bus, 0xAAAA);
        if epwm1::ETSEL.read(&mut bus) != (0xAAAA & 0xFF0F) { f28035_test_fail(0x3220); return; }
        epwm1::TBPHSHR.write(&mut bus, 0x5555);
        if epwm1::TBPHSHR.read(&mut bus) != (0x5555 & 0xFF00) { f28035_test_fail(0x3240); return; }
        epwm1::TBPHSHR.write(&mut bus, 0xAAAA);
        if epwm1::TBPHSHR.read(&mut bus) != (0xAAAA & 0xFF00) { f28035_test_fail(0x3241); return; }
        epwm1::TBPRDHR.write(&mut bus, 0x5555);
        if epwm1::TBPRDHR.read(&mut bus) != (0x5555 & 0xFF00) { f28035_test_fail(0x3242); return; }
        epwm1::TBPRDHR.write(&mut bus, 0xAAAA);
        if epwm1::TBPRDHR.read(&mut bus) != (0xAAAA & 0xFF00) { f28035_test_fail(0x3243); return; }
        epwm1::CMPAHR.write(&mut bus, 0x5555);
        if epwm1::CMPAHR.read(&mut bus) != (0x5555 & 0xFF00) { f28035_test_fail(0x3244); return; }
        epwm1::CMPAHR.write(&mut bus, 0xAAAA);
        if epwm1::CMPAHR.read(&mut bus) != (0xAAAA & 0xFF00) { f28035_test_fail(0x3245); return; }
        f28035_test_pass();
    }

        // === gpio_pin_walk_smoke: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    pub unsafe fn f28035_gpio_pin_walk_smoke() {
        let mut bus = C28xMmio;
        // Walk GPIOA 0..31
        for bit in 0u32..32 {
            let mask = 1u32 << bit;
            gpio::GPA_MUX1.write_u32(&mut bus, 0);
            gpio::GPA_MUX2.write_u32(&mut bus, 0);
            gpio::GPA_DIR.write_u32(&mut bus, mask);
            gpio::GPA_SET.write_u32(&mut bus, mask);
            gpio::GPA_TOGGLE.write_u32(&mut bus, mask);
            gpio::GPA_CLEAR.write_u32(&mut bus, mask);
        }
        // Walk GPIOB 0..13
        for bit in 0u32..14 {
            let mask = 1u32 << bit;
            gpio::GPB_MUX1.write_u32(&mut bus, 0);
            gpio::GPB_DIR.write_u32(&mut bus, mask);
            gpio::GPB_SET.write_u32(&mut bus, mask);
            gpio::GPB_TOGGLE.write_u32(&mut bus, mask);
            gpio::GPB_CLEAR.write_u32(&mut bus, mask);
        }
        // Mux/QSEL pattern sweep
        gpio::GPA_MUX1.write_u32(&mut bus, 0x55555555);
        gpio::GPA_MUX2.write_u32(&mut bus, 0x55555555);
        gpio::GPB_MUX1.write_u32(&mut bus, 0x55555555);
        gpio::GPA_MUX1.write_u32(&mut bus, 0xAAAAAAAA);
        gpio::GPA_MUX2.write_u32(&mut bus, 0xAAAAAAAA);
        gpio::GPB_MUX1.write_u32(&mut bus, 0xAAAAAAAA);
        gpio::GPA_MUX1.write_u32(&mut bus, 0xFFFFFFFF);
        gpio::GPA_MUX2.write_u32(&mut bus, 0xFFFFFFFF);
        gpio::GPB_MUX1.write_u32(&mut bus, 0xFFFFFFFF);
        gpio::GPA_QSEL1.write_u32(&mut bus, 0x55555555);
        gpio::GPB_QSEL1.write_u32(&mut bus, 0x55555555);
        gpio::GPA_QSEL1.write_u32(&mut bus, 0xAAAAAAAA);
        gpio::GPB_QSEL1.write_u32(&mut bus, 0xAAAAAAAA);
        gpio::GPA_QSEL1.write_u32(&mut bus, 0xFFFFFFFF);
        gpio::GPB_QSEL1.write_u32(&mut bus, 0xFFFFFFFF);
        // Reset to GPIO mode
        gpio::GPA_MUX1.write_u32(&mut bus, 0);
        gpio::GPA_MUX2.write_u32(&mut bus, 0);
        gpio::GPB_MUX1.write_u32(&mut bus, 0);
        gpio::GPA_DIR.write_u32(&mut bus, 0);
        gpio::GPB_DIR.write_u32(&mut bus, 0);
        // Verify
        if gpio::GPA_MUX1.read_u32(&mut bus) != 0 { f28035_test_fail(0x6C01); return; }
        if gpio::GPA_MUX2.read_u32(&mut bus) != 0 { f28035_test_fail(0x6C02); return; }
        if gpio::GPB_MUX1.read_u32(&mut bus) != 0 { f28035_test_fail(0x6C03); return; }
        if gpio::GPA_DIR.read_u32(&mut bus) != 0 { f28035_test_fail(0x6C04); return; }
        if gpio::GPB_DIR.read_u32(&mut bus) != 0 { f28035_test_fail(0x6C05); return; }
        f28035_test_pass();
    }

        // === delay_us: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_delay_us(microseconds: u16) {
        // Approximate 1us delay at 60MHz SYSCLKOUT.
        // Each inner loop iteration ~10 cycles; 60 cycles/us -> ~6 iterations.
        let mut us = microseconds;
        while us != 0 {
            let mut cycles = 6u16;
            while cycles != 0 {
                core::hint::black_box(());
                cycles -= 1;
            }
            us -= 1;
        }
    }

        // === ePWM1 complex config: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_configure_deadband(period: u16, compare: u16, delay: u16) -> u16 {
        if unsafe { f28035_epwm1_configure_waveform(period, compare, 0x0012, 0) } == 0 {
            return 0;
        }
        let mut bus = C28xMmio;
        unsafe {
            // GPIO1: disable pull-up, mux=ePWM1B
            let mut pud = gpio::GPA_PUD.read_u32(&mut bus);
            pud |= 1u32 << 1;
            gpio::GPA_PUD.write_u32(&mut bus, pud);
            let mut mux = gpio::GPA_MUX1.read_u32(&mut bus);
            mux = (mux & !(3u32 << 2)) | (1u32 << 2);
            gpio::GPA_MUX1.write_u32(&mut bus, mux);
            // DBCTL=0x000B, DBRED=delay, DBFED=delay
            epwm1::DBCTL.write(&mut bus, 0x000B);
            epwm1::DBRED.write(&mut bus, delay);
            epwm1::DBFED.write(&mut bus, delay);
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_configure_events(period: u16, compare: u16) -> u16 {
        if unsafe { f28035_epwm1_configure_waveform(period, compare, 0x0012, 0) } == 0 {
            return 0;
        }
        let mut bus = C28xMmio;
        unsafe {
            // ETSEL: INTSEL=1(bits0-2), INTEN=1(bit3), SOCASEL=1(bits4-5), SOCAEN=1(bit6)
            epwm1::ETSEL.write(&mut bus, 0x0001 | 0x0008 | 0x0010 | 0x0040);
            // ETPS: INTPRD=1(bits0-1), SOCAPRD=1(bits2-3)
            epwm1::ETPS.write(&mut bus, 0x0001 | 0x0004);
            epwm1::ETCLR.write(&mut bus, 0x00FF);
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_configure_socb(period: u16, compare: u16) -> u16 {
        if unsafe { f28035_epwm1_configure_waveform(period, compare, 0x0012, 0) } == 0 {
            return 0;
        }
        let mut bus = C28xMmio;
        unsafe {
            // ETSEL: SOCBSEL=1(bits8-9), SOCBEN=1(bit10)
            epwm1::ETSEL.write(&mut bus, 0x0100 | 0x0400);
            // ETPS: SOCBPRD=1(bits4-5)
            epwm1::ETPS.write(&mut bus, 0x0010);
            epwm1::ETCLR.write(&mut bus, 0x00FF);
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_configure_software_trip(period: u16, compare: u16) -> u16 {
        if unsafe { f28035_epwm1_configure_waveform(period, compare, 0x0012, 0) } == 0 {
            return 0;
        }
        let mut bus = C28xMmio;
        unsafe {
            // GPIO1 config
            let mut pud = gpio::GPA_PUD.read_u32(&mut bus);
            pud |= 1u32 << 1;
            gpio::GPA_PUD.write_u32(&mut bus, pud);
            let mut mux = gpio::GPA_MUX1.read_u32(&mut bus);
            mux = (mux & !(3u32 << 2)) | (1u32 << 2);
            gpio::GPA_MUX1.write_u32(&mut bus, mux);
            epwm1::AQCTLB.write(&mut bus, 0x0012);
            epwm1::TZSEL.write(&mut bus, 0);
            epwm1::TZCTL.write(&mut bus, 0x000A);
            epwm1::TZEINT.write(&mut bus, 0x0004);
            epwm1::TZCLR.write(&mut bus, 0x0005);
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_configure_external_trip(period: u16, compare: u16) -> u16 {
        if unsafe { f28035_epwm1_configure_waveform(period, compare, 0x0012, 0) } == 0 {
            return 0;
        }
        let mut bus = C28xMmio;
        unsafe {
            // GPIO1 config
            let mut pud = gpio::GPA_PUD.read_u32(&mut bus);
            pud |= 1u32 << 1;
            gpio::GPA_PUD.write_u32(&mut bus, pud);
            let mut mux = gpio::GPA_MUX1.read_u32(&mut bus);
            mux = (mux & !(3u32 << 2)) | (1u32 << 2);
            gpio::GPA_MUX1.write_u32(&mut bus, mux);
            epwm1::AQCTLB.write(&mut bus, 0x0012);
            epwm1::TZSEL.write(&mut bus, 0x0100);
            epwm1::TZCTL.write(&mut bus, 0x000A);
            epwm1::TZEINT.write(&mut bus, 0x0004);
            epwm1::TZCLR.write(&mut bus, 0x0005);
        }
        1
    }

        // === ePWM1 waveform + OST: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_configure_waveform(
        period_ticks: u16,
        compare_ticks: u16,
        aqctla: u16,
        counter_mode: u16,
    ) -> u16 {
        if period_ticks == 0 || compare_ticks > period_ticks || counter_mode > 2 {
            return 0;
        }
        let mut bus = C28xMmio;
        unsafe {
            // TBCLKSYNC = 0
            sysctrl::PCLKCR0.address().modify(&mut bus, sysctrl::PCLKCR0_TBCLKSYNC, 0);
            // GPIO0: disable pull-up (bit0), mux=ePWM1A (bits0-1=1)
            let mut pud = gpio::GPA_PUD.read_u32(&mut bus);
            pud |= 1u32 << 0;
            gpio::GPA_PUD.write_u32(&mut bus, pud);
            let mut mux = gpio::GPA_MUX1.read_u32(&mut bus);
            mux = (mux & !(3u32 << 0)) | (1u32 << 0);
            gpio::GPA_MUX1.write_u32(&mut bus, mux);
            // ePWM1 config
            epwm1::TBCTL.write(&mut bus, 0);
            epwm1::TBCTL.modify(&mut bus, 0x0003, 0x0003); // CTRMODE=3 (freeze)
            epwm1::TBCTR.write(&mut bus, 0);
            epwm1::TBPRD.write(&mut bus, period_ticks);
            epwm1::CMPA.write(&mut bus, compare_ticks);
            epwm1::AQCTLA.write(&mut bus, aqctla);
            epwm1::AQCTLB.write(&mut bus, 0);
            epwm1::TBCTL.modify(&mut bus, 0x0003, counter_mode);
            // TBCLKSYNC = 1
            sysctrl::PCLKCR0.address().modify(&mut bus, sysctrl::PCLKCR0_TBCLKSYNC, sysctrl::PCLKCR0_TBCLKSYNC);
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_wait_ost(expected: u16) -> u16 {
        let mut bus = C28xMmio;
        let level = if expected != 0 { 1u16 } else { 0u16 };
        let mut remaining = 10000u16;
        while remaining != 0 {
            // TZFLG bit2: OST flag
            let set = if unsafe { epwm1::TZFLG.read(&mut bus) } & 0x0004 != 0 { 1u16 } else { 0u16 };
            if set == level {
                return 1;
            }
            remaining -= 1;
        }
        0
    }

        // === ADC complex config functions: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_configure_soc(
        soc: u16,
        channel: u16,
        acqps: u16,
        trigger: u16,
    ) -> u16 {
        if soc > 15 || channel > 15 || acqps > 63 || trigger > 31 {
            return 0;
        }
        let mut bus = C28xMmio;
        // ADCSOCxCTL: CHSEL bits0-3, ACQPS bits6-10, TRIGSEL bits11-15
        let val = channel | (acqps << 6) | (trigger << 11);
        let addr = adc::ADC_BASE.offset_words(32 + soc as u16);
        unsafe { addr.write(&mut bus, val) };
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_configure_interrupt(irq: u16, eoc: u16) -> u16 {
        if eoc > 15 {
            return 0;
        }
        let mut bus = C28xMmio;
        unsafe {
            match irq {
                1 => {
                    // INT1SEL bits0-2=eoc, INT1E bit3=1, INT1CONT bit4=0
                    let val = (eoc & 0x0007) | 0x0008;
                    adc::INTSEL1N2.modify(&mut bus, 0x001F, val);
                }
                2 => {
                    // INT2SEL bits8-10=eoc, INT2E bit11=1, INT2CONT bit12=0
                    let val = ((eoc & 0x0007) << 8) | 0x0800;
                    adc::INTSEL1N2.modify(&mut bus, 0x1F00, val);
                }
                3 => {
                    // INT3SEL bits0-2=eoc, INT3E bit3=1, INT3CONT bit4=0
                    let val = (eoc & 0x0007) | 0x0008;
                    adc::INTSEL3N4.modify(&mut bus, 0x001F, val);
                }
                _ => return 0,
            }
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_wait_interrupt(irq: u16) -> u16 {
        if irq == 0 || irq > 9 {
            return 0;
        }
        let mut bus = C28xMmio;
        let mask = 1u16 << (irq - 1);
        let mut remaining = 50000u32;
        while remaining != 0 {
            // SAFETY: fixed ADC register.
            if unsafe { adc::ADCINTFLG.read(&mut bus) } & mask != 0 {
                return 1;
            }
            remaining -= 1;
        }
        0
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_wait_soc_activity(soc: u16) -> u16 {
        if soc > 15 {
            return 0;
        }
        let mut bus = C28xMmio;
        let mask = 1u16 << soc;
        let mut remaining = 60000u32;
        while remaining != 0 {
            // SAFETY: fixed ADC registers.
            let flg = unsafe { adc::ADCSOCFLG1.read(&mut bus) };
            let ovf = unsafe { adc::ADCSOCOVF1.read(&mut bus) };
            if (flg | ovf) & mask != 0 {
                return 1;
            }
            remaining -= 1;
        }
        0
    }

        // === Simple write-register functions: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_force_mask(mask: u16) {
        let mut bus = C28xMmio;
        unsafe { adc::ADCSOCFRC1.write(&mut bus, mask) };
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_clear_interrupt(irq: u16) {
        if irq != 0 && irq <= 9 {
            let mut bus = C28xMmio;
            unsafe { adc::ADCINTFLGCLR.write(&mut bus, 1u16 << (irq - 1)) };
        }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_set_clock_dividers(hspclkdiv: u16, clkdiv: u16) -> u16 {
        if hspclkdiv > 7 || clkdiv > 7 {
            return 0;
        }
        let mut bus = C28xMmio;
        unsafe {
            // Freeze counter (CTRMODE=3), clear TBCTR, then set dividers.
            epwm1::TBCTL.modify(&mut bus, 0x0003, 0x0003);
            epwm1::TBCTR.write(&mut bus, 0);
            // HSPCLKDIV bits7-9, CLKDIV bits10-12
            let val = (hspclkdiv << 7) | (clkdiv << 10);
            epwm1::TBCTL.modify(&mut bus, 0x1C00 | 0x0380, val);
        }
        1
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_force_ost() {
        let mut bus = C28xMmio;
        // TZFRC bit2: OST force
        unsafe { epwm1::TZFRC.write(&mut bus, 0x0004) };
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_clear_ost() {
        let mut bus = C28xMmio;
        // TZCLR: bit0 OST clear + bit2 INT clear = 0x0005
        unsafe { epwm1::TZCLR.write(&mut bus, 0x0005) };
    }

        // === ePWM1 event-trigger status readers: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_event_int_enabled() -> u16 {
        let mut bus = C28xMmio;
        // ETSEL bit3: INTEN
        unsafe { (epwm1::ETSEL.read(&mut bus) & 0x0008) >> 3 }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_event_int_period() -> u16 {
        let mut bus = C28xMmio;
        // ETPS bits0-1: INTPRD
        unsafe { epwm1::ETPS.read(&mut bus) & 0x0003 }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_event_soca_enabled() -> u16 {
        let mut bus = C28xMmio;
        // ETSEL bit6: SOCAEN
        unsafe { (epwm1::ETSEL.read(&mut bus) & 0x0040) >> 6 }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_event_soca_period() -> u16 {
        let mut bus = C28xMmio;
        // ETPS bits2-3: SOCAPRD
        unsafe { (epwm1::ETPS.read(&mut bus) & 0x000C) >> 2 }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_event_socb_enabled() -> u16 {
        let mut bus = C28xMmio;
        // ETSEL bit10: SOCBEN
        unsafe { (epwm1::ETSEL.read(&mut bus) & 0x0400) >> 10 }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_event_socb_period() -> u16 {
        let mut bus = C28xMmio;
        // ETPS bits4-5: SOCBPRD
        unsafe { (epwm1::ETPS.read(&mut bus) & 0x0030) >> 4 }
    }

        // === ePWM1 DB/TZ + ADC config status readers: direct Rust PAC (2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_dbctl() -> u16 {
        let mut bus = C28xMmio;
        unsafe { epwm1::DBCTL.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_dbfed() -> u16 {
        let mut bus = C28xMmio;
        unsafe { epwm1::DBFED.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_dbred() -> u16 {
        let mut bus = C28xMmio;
        unsafe { epwm1::DBRED.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_tzctl() -> u16 {
        let mut bus = C28xMmio;
        unsafe { epwm1::TZCTL.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_tzeint() -> u16 {
        let mut bus = C28xMmio;
        unsafe { epwm1::TZEINT.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_tzsel() -> u16 {
        let mut bus = C28xMmio;
        unsafe { epwm1::TZSEL.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_ctl1_configured() -> u16 {
        let mut bus = C28xMmio;
        // ADCCTL1 bits: ADCENABLE(0), ADCREFSEL(2), INTPULSEPOS(3),
        // VREFLOCONV(4), ADCBGPWD(7), ADCREFPWD(8), ADCPWDN(9)
        let ctl1 = unsafe { adc::ADCCTL1.read(&mut bus) };
        let ok = (ctl1 & 0x0001) != 0      // ADCENABLE
            && (ctl1 & 0x0004) == 0        // ADCREFSEL == 0
            && (ctl1 & 0x0008) != 0        // INTPULSEPOS
            && (ctl1 & 0x0010) != 0        // VREFLOCONV
            && (ctl1 & 0x0080) != 0        // ADCBGPWD
            && (ctl1 & 0x0100) != 0        // ADCREFPWD
            && (ctl1 & 0x0200) != 0;       // ADCPWDN
        u16::from(ok)
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_int1_configured() -> u16 {
        let mut bus = C28xMmio;
        // INTSEL1N2 bits: INT1SEL(0-2), INT1E(3), INT1CONT(4)
        let sel = unsafe { adc::INTSEL1N2.read(&mut bus) };
        let ok = (sel & 0x0007) == 0       // INT1SEL == 0 (EOC0)
            && (sel & 0x0008) != 0         // INT1E
            && (sel & 0x0010) == 0;        // INT1CONT == 0
        u16::from(ok)
    }

        // === ePWM1 status readers: direct Rust PAC (replaced C bridge, 2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_period() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 register; TBPRD is the 16-bit period register.
        unsafe { epwm1::TBPRD.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_aqctla() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 register; AQCTLA is the action-qualifier register.
        unsafe { epwm1::AQCTLA.read(&mut bus) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_counter_mode() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 register; CTRMODE is bits 0-1 of TBCTL.
        unsafe { epwm1::TBCTL.read(&mut bus) & 0x0003 }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_hspclkdiv() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 register; HSPCLKDIV is bits 7-9 of TBCTL.
        unsafe { (epwm1::TBCTL.read(&mut bus) & 0x0380) >> 7 }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_epwm1_clkdiv() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ePWM1 register; CLKDIV is bits 10-12 of TBCTL.
        unsafe { (epwm1::TBCTL.read(&mut bus) & 0x1C00) >> 10 }
    }

        // === ADC status readers: direct Rust PAC (replaced C bridge, 2026-09-29) ===

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_soc0_channel() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ADC register; CHSEL is bits 0-4 of ADCSOC0CTL.
        unsafe { adc::ADCSOC0CTL.read(&mut bus) & adc::SOC0_CHSEL_MASK }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_soc0_acqps() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ADC register; ACQPS is bits 6-10 of ADCSOC0CTL.
        unsafe { (adc::ADCSOC0CTL.read(&mut bus) & adc::SOC0_ACQPS_MASK) >> adc::SOC0_ACQPS_SHIFT }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_soc0_trigger() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ADC register; TRIGSEL is bits 11-15 of ADCSOC0CTL.
        unsafe { (adc::ADCSOC0CTL.read(&mut bus) & adc::SOC0_TRIGSEL_MASK) >> adc::SOC0_TRIGSEL_SHIFT }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_int1_flag() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ADC register; ADCINT1 flag is bit 1 of ADCINTFLG.
        unsafe { u16::from((adc::ADCINTFLG.read(&mut bus) & adc::ADCINT1_FLAG) != 0) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_soc0_overflow() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ADC register; SOC0 overflow is bit 0 of ADCSOCOVF1.
        unsafe { u16::from((adc::ADCSOCOVF1.read(&mut bus) & adc::SOC0_FORCE) != 0) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_clock_enabled() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed sysctrl register; ADCENCLK is bit 3 of PCLKCR0.
        unsafe { u16::from((sysctrl::PCLKCR0.read_u32(&mut bus) & sysctrl::PCLKCR0_ADCENCLK as u32) != 0) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_clkdiv2_enabled() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ADC register; CLKDIV2EN is bit 0 of ADCCTL2.
        unsafe { u16::from((adc::ADCCTL2.read(&mut bus) & adc::ADCCTL2_CLKDIV2EN) != 0) }
    }

    #[cfg(not(test))]
    #[inline(never)]
    pub unsafe fn f28035_adc_busy_mask() -> u16 {
        let mut bus = C28xMmio;
        // SAFETY: fixed ADC register; ADCSOCFLG1 returns all 16 SOC busy bits.
        unsafe { adc::ADCSOCFLG1.read(&mut bus) }
    }

        /// Host path: deterministic in-memory stubs so the safe-HAL type state
    /// machine can be exercised without a C28x target.
    #[cfg(test)]
    mod stubs {
        use core::sync::atomic::{AtomicBool, AtomicU16, AtomicU32, AtomicU64, Ordering};

        static PERIPHERALS_TAKEN: AtomicBool = AtomicBool::new(false);
        static HOST_CMPA: AtomicU16 = AtomicU16::new(0);

        /// 45-pin latch mirror: each bit stores the last value written to
        /// that pin.  Updated by `f28035_gpio_write` / `f28035_gpio_toggle`
        /// so `f28035_gpio_read` can return a meaningful value.
        static HOST_GPIO_LATCH: AtomicU64 = AtomicU64::new(0);
        /// MUX field mirrors: 2 bits per pin.  GPAMUX1 = GPIO0..15,
        /// GPAMUX2 = GPIO16..31, GPBMUX1 = GPIO32..44 (mirror of the C
        /// bridge's register RMW semantics).
        static HOST_GPA_MUX1: AtomicU32 = AtomicU32::new(0);
        static HOST_GPA_MUX2: AtomicU32 = AtomicU32::new(0);
        static HOST_GPB_MUX1: AtomicU32 = AtomicU32::new(0);

        pub unsafe fn f28035_system_init() {}

        pub unsafe fn f28035_delay_us(_microseconds: u16) {}

        pub unsafe fn f28035_gpio_make_output(pin: u16) -> u16 {
            u16::from(pin <= 44)
        }

        pub unsafe fn f28035_gpio_make_input(
            pin: u16,
            _pullup_enabled: u16,
            qualification: u16,
        ) -> u16 {
            u16::from(pin <= 44 && qualification <= 3)
        }

        pub unsafe fn f28035_gpio_read(pin: u16) -> u16 {
            if pin <= 44 {
                u16::from((HOST_GPIO_LATCH.load(Ordering::Relaxed) >> pin & 1) as u8)
            } else {
                0
            }
        }

        pub unsafe fn f28035_gpio_write(pin: u16, high: u16) {
            if pin <= 44 {
                let mut latch = HOST_GPIO_LATCH.load(Ordering::Relaxed);
                let bit = 1u64 << pin;
                if high != 0 {
                    latch |= bit;
                } else {
                    latch &= !bit;
                }
                HOST_GPIO_LATCH.store(latch, Ordering::Relaxed);
            }
        }

        pub unsafe fn f28035_gpio_toggle(pin: u16) {
            if pin <= 44 {
                let mut latch = HOST_GPIO_LATCH.load(Ordering::Relaxed);
                let bit = 1u64 << pin;
                latch ^= bit;
                HOST_GPIO_LATCH.store(latch, Ordering::Relaxed);
            }
        }

        pub unsafe fn f28035_gpio_configure_xint(line: u16, pin: u16, edge: u16) -> u16 {
            u16::from(
                (line == 1 || line == 2) && pin <= 31 && (edge == 0 || edge == 1 || edge == 3),
            )
        }

        pub unsafe fn f28035_gpio_set_mux(pin: u16, function: u16) -> u16 {
            if pin > 44 || function > 3 {
                return 0;
            }
            let reg = if pin < 16 {
                &HOST_GPA_MUX1
            } else if pin < 32 {
                &HOST_GPA_MUX2
            } else {
                &HOST_GPB_MUX1
            };
            let shift = u32::from(pin % 16) * 2;
            let mask = 3u32 << shift;
            let current = reg.load(Ordering::Relaxed);
            let updated = (current & !mask) | ((function as u32) << shift);
            reg.store(updated, Ordering::Relaxed);
            1
        }

        pub unsafe fn f28035_gpio_mux(pin: u16) -> u16 {
            if pin > 44 {
                return 0xffff;
            }
            let reg = if pin < 16 {
                &HOST_GPA_MUX1
            } else if pin < 32 {
                &HOST_GPA_MUX2
            } else {
                &HOST_GPB_MUX1
            };
            let shift = u32::from(pin % 16) * 2;
            ((reg.load(Ordering::Relaxed) >> shift) & 3) as u16
        }
        pub unsafe fn f28035_adc_result(_result_index: u16) -> u16 {
            0
        }

        pub unsafe fn f28035_adc_sample(_channel: u16) -> u16 {
            0
        }

        pub unsafe fn f28035_adc_timeouts() -> u16 {
            0
        }

        pub unsafe fn f28035_take_peripherals() -> u16 {
            u16::from(!PERIPHERALS_TAKEN.swap(true, Ordering::AcqRel))
        }

        pub unsafe fn f28035_timer0_start_once_ms(period_ms: u16) -> u16 {
            u16::from((1..=1000).contains(&period_ms))
        }

        pub unsafe fn f28035_timer0_start_periodic_ms(period_ms: u16) -> u16 {
            u16::from((1..=1000).contains(&period_ms))
        }

        pub unsafe fn f28035_timer0_ack() {}
        pub unsafe fn f28035_timer0_stop() {}
        pub unsafe fn f28035_timer0_restart() {}
        pub unsafe fn f28035_timer0_set_period_ms(period_ms: u16) -> u16 {
            u16::from((1..=1000).contains(&period_ms))
        }

        pub unsafe fn f28035_timer0_interrupts() -> u16 {
            0
        }

        pub unsafe fn f28035_epwm1_configure(period_ticks: u16) -> u16 {
            u16::from(period_ticks != 0)
        }

        pub unsafe fn f28035_epwm1_set_compare(compare_ticks: u16) {
            HOST_CMPA.store(compare_ticks, Ordering::Relaxed);
        }

        pub unsafe fn f28035_epwm1_compare() -> u16 {
            HOST_CMPA.load(Ordering::Relaxed)
        }

        pub unsafe fn f28035_epwm1_enable() {}
        pub unsafe fn f28035_epwm1_disable() {}

        // === Sunk C-bridge stubs (host) ===
        pub unsafe fn f28035_ecap_apwm_matrix() {}
        pub unsafe fn f28035_ecap_capture_continuous_wrap() {}
        pub unsafe fn f28035_ecap_capture_counter_reset() {}
        pub unsafe fn f28035_ecap_capture_dual_edge() {}
        pub unsafe fn f28035_ecap_capture_prescale_div2() {}
        pub unsafe fn f28035_ecap_capture_quad_edge() {}
        pub unsafe fn f28035_ecap_capture_single_edge() {}
        pub unsafe fn f28035_ecap_capture_wrap_matrix() {}
        pub unsafe fn f28035_ecap_interrupt_integration() {}
        pub unsafe fn f28035_ecap_reg_rw_smoke() {}
        pub unsafe fn f28035_epwm1_reg_rw_smoke() {}
        pub unsafe fn f28035_eqep_compare_output_pulse() {}
        pub unsafe fn f28035_eqep_count_basic() {}
        pub unsafe fn f28035_eqep_interrupt_gate() {}
        pub unsafe fn f28035_eqep_mode_test() {}
        pub unsafe fn f28035_eqep_polarity_test() {}
        pub unsafe fn f28035_eqep_register_wr() {}
        pub unsafe fn f28035_eqep_reset_fsm_matrix() {}
        pub unsafe fn f28035_eqep_unit_timeout_test() {}
        pub unsafe fn f28035_eqep_unit_timer() {}
        pub unsafe fn f28035_eqep_watchdog_timeout_test() {}
        pub unsafe fn f28035_gpio_pin_walk_smoke() {}
        pub unsafe fn f28035_gpio_xint_falling_smoke() {}
        pub unsafe fn f28035_gpio_xint_rising_smoke() {}
        pub unsafe fn f28035_i2c_master_addr_nack_stop_basic() {}
        pub unsafe fn f28035_i2c_master_read_1byte_basic() {}
        pub unsafe fn f28035_i2c_master_read_8byte_basic() {}
        pub unsafe fn f28035_i2c_master_read_back_to_back_basic() {}
        pub unsafe fn f28035_i2c_master_repeated_start_write_then_read_4byte_basic() {}
        pub unsafe fn f28035_i2c_master_write_1byte_basic() {}
        pub unsafe fn f28035_i2c_master_write_8byte_pattern() {}
        pub unsafe fn f28035_i2c_master_write_back_to_back() {}
        pub unsafe fn f28035_i2c_master_write_then_read_4byte_basic() {}
        pub unsafe fn f28035_i2c_reg_readback_sweep_basic() {}
        pub unsafe fn f28035_lin_baud_program_basic() {}
        pub unsafe fn f28035_lin_header_break_sync_master_basic() {}
        pub unsafe fn f28035_lin_iodft_loopback_basic() {}
        pub unsafe fn f28035_lin_reg_if_rw_basic() {}
        pub unsafe fn f28035_lin_rx_checksum_length_real_basic() {}
        pub unsafe fn f28035_lin_rx_rxcnt_num_boundary_real_basic() {}
        pub unsafe fn f28035_lin_sci_multibuf_rdslot_sweep_basic() {}
        pub unsafe fn f28035_lin_top_mode_loopback_power_cross_basic() {}
        pub unsafe fn f28035_lin_tx_checksum_ext_real_basic() {}
        pub unsafe fn f28035_lin_wakeup_break_flag_route_basic() {}
        pub unsafe fn f28035_sci_baud_program_basic() {}
        pub unsafe fn f28035_sci_fifo_reset_then_loopback_basic() {}
        pub unsafe fn f28035_sci_fifo_rx_basic() {}
        pub unsafe fn f28035_sci_internal_loopback_basic() {}
        pub unsafe fn f28035_sci_loopback_data_pattern_basic() {}
        pub unsafe fn f28035_sci_reg_if_rw_basic() {}
        pub unsafe fn f28035_sci_rxrdy_clear_on_read_basic() {}
        pub unsafe fn f28035_sci_sciccr_charlen_sweep_basic() {}
        pub unsafe fn f28035_sci_stop2_parity_charlen_sweep_basic() {}
        pub unsafe fn f28035_sci_txrdy_int_nonfifo_basic() {}
        pub unsafe fn f28035_spi_charlen_sweep_basic() {}
        pub unsafe fn f28035_spi_fifo_level_boundary_basic() {}
        pub unsafe fn f28035_spi_fifo_rx_boundary_basic() {}
        pub unsafe fn f28035_spi_fifo_tx_boundary_basic() {}
        pub unsafe fn f28035_spi_internal_loopback_basic() {}
        pub unsafe fn f28035_spi_loopback_mode_matrix_basic() {}
        pub unsafe fn f28035_spi_multiple_frame_loopback_basic() {}
        pub unsafe fn f28035_spi_nonfifo_intflag_irq_basic() {}
        pub unsafe fn f28035_spi_reg_if_rw_basic() {}
        pub unsafe fn f28035_spi_triwire_loopback_basic() {}

        // === Multi-call case host stubs ===
        pub unsafe fn f28035_adc_busy_mask() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_clear_interrupt(interrupt: u16) {}
        pub unsafe fn f28035_adc_clkdiv2_enabled() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_clock_enabled() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_configure_interrupt(interrupt: u16, eoc: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_adc_configure_soc(
            soc: u16,
            channel: u16,
            acqps: u16,
            trigger: u16,
        ) -> u16 {
            0
        }
        pub unsafe fn f28035_adc_configure_soc0(channel: u16, acqps: u16) -> u16 {
            u16::from(channel <= 15 && acqps <= 63)
        }
        pub unsafe fn f28035_adc_ctl1_configured() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_force_mask(mask: u16) {}
        pub unsafe fn f28035_adc_int1_configured() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_int1_flag() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_soc0_acqps() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_soc0_channel() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_soc0_overflow() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_soc0_trigger() -> u16 {
            0
        }
        pub unsafe fn f28035_adc_wait_interrupt(interrupt: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_adc_wait_soc_activity(soc: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_clear_ost() {}
        pub unsafe fn f28035_epwm1_force_ost() {}
        pub unsafe fn f28035_timer0_stop_adc_trigger() {}
        pub unsafe fn f28035_epwm1_aqctla() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_clkdiv() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_configure_deadband(
            period: u16,
            compare: u16,
            delay: u16,
        ) -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_configure_events(period: u16, compare: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_configure_external_trip(period: u16, compare: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_configure_socb(period: u16, compare: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_configure_software_trip(period: u16, compare: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_configure_waveform(
            period: u16,
            compare: u16,
            aqctla: u16,
            mode: u16,
        ) -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_counter_mode() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_dbctl() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_dbfed() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_dbred() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_event_int_enabled() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_event_int_period() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_event_soca_enabled() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_event_soca_period() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_event_socb_enabled() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_event_socb_period() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_hspclkdiv() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_period() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_set_clock_dividers(hspclkdiv: u16, clkdiv: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_tzctl() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_tzeint() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_tzsel() -> u16 {
            0
        }
        pub unsafe fn f28035_epwm1_wait_ost(expected: u16) -> u16 {
            0
        }
        pub unsafe fn f28035_timer0_start_adc_trigger(period_ticks: u16) -> u16 {
            0
        }

        pub fn reset_peripherals() {
            PERIPHERALS_TAKEN.store(false, Ordering::Release);
            HOST_GPIO_LATCH.store(0, Ordering::Release);
            HOST_GPA_MUX1.store(0, Ordering::Release);
            HOST_GPA_MUX2.store(0, Ordering::Release);
            HOST_GPB_MUX1.store(0, Ordering::Release);
            HOST_CMPA.store(0, Ordering::Release);
        }
    }

    #[cfg(test)]
    pub use stubs::*;
}

/// Safe wrapper for the Timer0 interrupt acknowledge.
///
/// Use this from `rust_timer0_interrupt()` in app cases so the firmware
/// entry point needs no `unsafe` block.  Writing PIEACK group1 is a benign,
/// idempotent MMIO write; the unsafe boundary is contained here.
pub fn ack_timer0_interrupt() {
    // Safety: PIEACK write is idempotent; the unsafe boundary is contained
    // here so callers (no_std firmware entry) stay unsafe-free.
    unsafe { ffi::f28035_timer0_ack() }
}

/// Safe wrappers for self-contained C-bridge test cases.
/// Each call forwards to the audited C bridge function; the unsafe boundary
/// is contained here so app entry points stay `unsafe`-free.
/// Safe wrapper for $doc.
pub fn f28035_ecap_apwm_matrix() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_apwm_matrix() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_capture_continuous_wrap() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_capture_continuous_wrap() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_capture_counter_reset() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_capture_counter_reset() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_capture_dual_edge() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_capture_dual_edge() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_capture_prescale_div2() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_capture_prescale_div2() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_capture_quad_edge() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_capture_quad_edge() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_capture_single_edge() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_capture_single_edge() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_capture_wrap_matrix() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_capture_wrap_matrix() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_interrupt_integration() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_interrupt_integration() }
}
/// Safe wrapper for $doc.
pub fn f28035_ecap_reg_rw_smoke() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_ecap_reg_rw_smoke() }
}
/// Safe wrapper for $doc.
pub fn f28035_epwm1_reg_rw_smoke() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_epwm1_reg_rw_smoke() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_compare_output_pulse() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_compare_output_pulse() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_count_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_count_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_interrupt_gate() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_interrupt_gate() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_mode_test() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_mode_test() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_polarity_test() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_polarity_test() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_register_wr() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_register_wr() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_reset_fsm_matrix() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_reset_fsm_matrix() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_unit_timeout_test() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_unit_timeout_test() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_unit_timer() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_unit_timer() }
}
/// Safe wrapper for $doc.
pub fn f28035_eqep_watchdog_timeout_test() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_eqep_watchdog_timeout_test() }
}
/// Safe wrapper for $doc.
pub fn f28035_gpio_pin_walk_smoke() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_gpio_pin_walk_smoke() }
}
/// Safe wrapper for $doc.
pub fn f28035_gpio_xint_falling_smoke() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_gpio_xint_falling_smoke() }
}
/// Safe wrapper for $doc.
pub fn f28035_gpio_xint_rising_smoke() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_gpio_xint_rising_smoke() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_addr_nack_stop_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_addr_nack_stop_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_read_1byte_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_read_1byte_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_read_8byte_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_read_8byte_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_read_back_to_back_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_read_back_to_back_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_repeated_start_write_then_read_4byte_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_repeated_start_write_then_read_4byte_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_write_1byte_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_write_1byte_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_write_8byte_pattern() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_write_8byte_pattern() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_write_back_to_back() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_write_back_to_back() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_master_write_then_read_4byte_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_master_write_then_read_4byte_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_i2c_reg_readback_sweep_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_i2c_reg_readback_sweep_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_baud_program_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_baud_program_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_header_break_sync_master_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_header_break_sync_master_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_iodft_loopback_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_iodft_loopback_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_reg_if_rw_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_reg_if_rw_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_rx_checksum_length_real_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_rx_checksum_length_real_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_rx_rxcnt_num_boundary_real_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_rx_rxcnt_num_boundary_real_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_sci_multibuf_rdslot_sweep_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_sci_multibuf_rdslot_sweep_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_top_mode_loopback_power_cross_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_top_mode_loopback_power_cross_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_tx_checksum_ext_real_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_tx_checksum_ext_real_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_lin_wakeup_break_flag_route_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_lin_wakeup_break_flag_route_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_baud_program_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_baud_program_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_fifo_reset_then_loopback_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_fifo_reset_then_loopback_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_fifo_rx_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_fifo_rx_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_internal_loopback_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_internal_loopback_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_loopback_data_pattern_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_loopback_data_pattern_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_reg_if_rw_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_reg_if_rw_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_rxrdy_clear_on_read_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_rxrdy_clear_on_read_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_sciccr_charlen_sweep_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_sciccr_charlen_sweep_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_stop2_parity_charlen_sweep_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_stop2_parity_charlen_sweep_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_sci_txrdy_int_nonfifo_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_sci_txrdy_int_nonfifo_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_charlen_sweep_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_charlen_sweep_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_fifo_level_boundary_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_fifo_level_boundary_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_fifo_rx_boundary_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_fifo_rx_boundary_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_fifo_tx_boundary_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_fifo_tx_boundary_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_internal_loopback_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_internal_loopback_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_loopback_mode_matrix_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_loopback_mode_matrix_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_multiple_frame_loopback_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_multiple_frame_loopback_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_nonfifo_intflag_irq_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_nonfifo_intflag_irq_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_reg_if_rw_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_reg_if_rw_basic() }
}
/// Safe wrapper for $doc.
pub fn f28035_spi_triwire_loopback_basic() {
    // Safety: self-contained C bridge case; unsafe boundary contained here.
    unsafe { ffi::f28035_spi_triwire_loopback_basic() }
}

/// Safe wrappers for multi-call peripheral functions used by verified cases.
/// Safe wrapper for $fn.
pub fn f28035_adc_busy_mask() -> u16 {
    unsafe { ffi::f28035_adc_busy_mask() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_clkdiv2_enabled() -> u16 {
    unsafe { ffi::f28035_adc_clkdiv2_enabled() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_clock_enabled() -> u16 {
    unsafe { ffi::f28035_adc_clock_enabled() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_configure_soc0(channel: u16, acqps: u16) -> u16 {
    unsafe { ffi::f28035_adc_configure_soc0(channel, acqps) }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_ctl1_configured() -> u16 {
    unsafe { ffi::f28035_adc_ctl1_configured() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_int1_configured() -> u16 {
    unsafe { ffi::f28035_adc_int1_configured() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_int1_flag() -> u16 {
    unsafe { ffi::f28035_adc_int1_flag() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_soc0_acqps() -> u16 {
    unsafe { ffi::f28035_adc_soc0_acqps() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_soc0_channel() -> u16 {
    unsafe { ffi::f28035_adc_soc0_channel() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_soc0_overflow() -> u16 {
    unsafe { ffi::f28035_adc_soc0_overflow() }
}
/// Safe wrapper for $fn.
pub fn f28035_adc_soc0_trigger() -> u16 {
    unsafe { ffi::f28035_adc_soc0_trigger() }
}
/// Safe wrapper for $fn.
pub fn f28035_epwm1_aqctla() -> u16 {
    unsafe { ffi::f28035_epwm1_aqctla() }
}
/// Safe wrapper for $fn.
pub fn f28035_epwm1_clkdiv() -> u16 {
    unsafe { ffi::f28035_epwm1_clkdiv() }
}

#[cfg(test)]
mod tests {
    use super::gpio;
    use super::{HostMmio, MmioBus, TiWordAddress};

    #[test]
    fn gpio31_uses_gpio_a_mux2_and_data_commands() {
        let config = gpio::output_config(31).unwrap();
        let command = gpio::output_command(31).unwrap();
        assert_eq!(config.mux.address().get(), 0x6f88);
        assert_eq!(config.direction.address().get(), 0x6f8a);
        assert_eq!(config.pin_mask, 0x8000_0000);
        assert_eq!(config.mux_mask, 0xc000_0000);
        assert_eq!(command.clear.address().get(), 0x6fc4);
    }

    #[test]
    fn invalid_gpio_has_no_pac_mapping() {
        assert!(gpio::output_config(45).is_none());
        assert!(gpio::output_command(45).is_none());
    }

    #[test]
    fn adc_and_sysctrl_registers_match_ti_headers() {
        assert_eq!(super::sysctrl::PCLKCR0.address().get(), 0x701c);
        assert_eq!(super::adc::ADCCTL1.get(), 0x7100);
        assert_eq!(super::adc::ADCINTFLG.get(), 0x7104);
        assert_eq!(super::adc::ADCINTFLGCLR.get(), 0x7105);
        assert_eq!(super::adc::INTSEL1N2.get(), 0x7108);
        assert_eq!(super::adc::ADCSOCFRC1.get(), 0x711a);
        assert_eq!(super::adc::ADCSOC0CTL.get(), 0x7120);
    }

    #[test]
    fn timer0_periodic_interrupt_registers_match_ti_headers() {
        assert_eq!(super::timer0::PRD.address().get(), 0x0c02);
        assert_eq!(super::timer0::TCR.get(), 0x0c04);
        assert_eq!(super::timer0::TPR.get(), 0x0c06);
        assert_eq!(super::timer0::TPRH.get(), 0x0c07);
        assert_eq!(super::timer0::PIEACK.get(), 0x0ce1);
        assert_eq!(super::timer0::PIEIER1.get(), 0x0ce2);
        assert_eq!(super::timer0::TINT0_VECTOR.address().get(), 0x0d4c);
    }

    #[test]
    fn host_mmio_word_round_trip() {
        use super::{HostMmio, TiWordAddress};
        let mut bus = HostMmio::new();
        let addr = TiWordAddress::new(0x7100);
        unsafe { addr.write(&mut bus, 0x1234) };
        assert_eq!(unsafe { addr.read(&mut bus) }, 0x1234);
    }

    #[test]
    fn adc_power_up_sequence_writes_expected_registers() {
        use super::{HostMmio, adc};
        let mut bus = HostMmio::new();
        unsafe { adc::power_up_and_configure_soc0(&mut bus) };
        assert_eq!(bus.words[0x701c], 0x0008);
        assert_eq!(bus.words[0x7100], 0x40e4);
        assert_eq!(bus.words[0x7108], 0x0020);
        assert_eq!(bus.words[0x7120], 0x0180);
    }

    #[test]
    fn timer0_vector_table_write_is_a_little_endian_pair() {
        use super::{HostMmio, timer0};
        let mut bus = HostMmio::new();
        unsafe { timer0::set_tint0_vector(&mut bus, 0x1234_5678) };
        assert_eq!(bus.words[0x0d4c], 0x5678);
        assert_eq!(bus.words[0x0d4d], 0x1234);
    }

    #[test]
    fn epwm1_registers_match_ti_headers() {
        assert_eq!(super::epwm1::TBCTL.get(), 0x6800);
        assert_eq!(super::epwm1::TBPRD.get(), 0x6805);
        assert_eq!(super::epwm1::CMPA.get(), 0x6809);
        assert_eq!(super::epwm1::AQCTLA.get(), 0x680b);
        assert_eq!(super::epwm1::DBCTL.get(), 0x680f);
        assert_eq!(super::epwm1::TZSEL.get(), 0x6812);
        assert_eq!(super::epwm1::ETSEL.get(), 0x6818);
    }

    #[test]
    fn new_adc_registers_match_ti_headers() {
        assert_eq!(super::adc::ADCCTL2.get(), 0x7101);
        assert_eq!(super::adc::ADCSOCFLG1.get(), 0x7118);
        assert_eq!(super::adc::ADCSOCOVF1.get(), 0x711c);
        assert_eq!(super::adc::INTSEL3N4.get(), 0x7109);
    }

    #[test]
    fn sysctrl_pclkcr3_match_ti_headers() {
        assert_eq!(super::sysctrl::PCLKCR3.get(), 0x701f);
    }

    // --- A-class register readback drivers (SPI/SCI/I2C/LIN), host-verified 1:1 ---

    /// A 64k-word storage bus that forces one register to read back a chosen
    /// value, used to exercise the first fail branch of each driver.  It
    /// delegates every non-fault word to an inner [`HostMmio`] so the 64k
    /// register storage does not need to be re-implemented here.
    struct FaultBus {
        inner: super::HostMmio,
        fault_addr: u16,
        fault_read: u16,
    }
    impl FaultBus {
        fn new(fault_addr: u16, fault_read: u16) -> Self {
            Self {
                inner: super::HostMmio::new(),
                fault_addr,
                fault_read,
            }
        }
    }
    // SAFETY: full 64k-word model; the fault register returns a fixed value.
    unsafe impl MmioBus for FaultBus {
        unsafe fn read_word(&mut self, address: super::TiWordAddress) -> u16 {
            if address.get() == self.fault_addr {
                self.fault_read
            } else {
                unsafe { self.inner.read_word(address) }
            }
        }
        unsafe fn write_word(&mut self, address: super::TiWordAddress, value: u16) {
            unsafe { self.inner.write_word(address, value) }
        }
    }

    #[test]
    fn spi_reg_rw_passes_on_storage_bus() {
        use super::{spi, HostMmio};
        let mut bus = HostMmio::new();
        assert_eq!(unsafe { spi::run_spi_reg_rw(&mut bus) }, 0);
        // Each masked register must hold the written value after the sweep.
        assert_eq!(bus.peek(spi::SPICCR), 0x00D7);
        assert_eq!(bus.peek(spi::SPICTL), 0x001F);
        assert_eq!(bus.peek(spi::SPIBRR), 0x007F);
    }

    #[test]
    fn spi_reg_rw_reports_spictl_mismatch() {
        use super::spi;
        let mut bus = FaultBus::new(spi::SPICTL.get(), 0);
        // SPICCR (checked first) is normal; SPICTL reads back 0 -> 0x0002.
        assert_eq!(unsafe { spi::run_spi_reg_rw(&mut bus) }, 0x0002);
    }

    #[test]
    fn sci_reg_rw_passes_on_storage_bus() {
        use super::{sci, HostMmio};
        let mut bus = HostMmio::new();
        assert_eq!(unsafe { sci::run_sci_reg_rw(&mut bus) }, 0);
        assert_eq!(bus.peek(sci::SCICCR), 0x0037);
        assert_eq!(bus.peek(sci::SCIFFCT), 0x2055);
    }

    #[test]
    fn sci_reg_rw_reports_sciccr_mismatch() {
        use super::sci;
        let mut bus = FaultBus::new(sci::SCICCR.get(), 0);
        // First check: SCICCR masked readback fails -> 0x0001 + raw read.
        assert_eq!(unsafe { sci::run_sci_reg_rw(&mut bus) }, 0x0001);
    }

    #[test]
    fn i2c_reg_rw_passes_when_fifo_reset_state_seeded() {
        use super::{i2c, HostMmio};
        let mut bus = HostMmio::new();
        // FIFO reset-state reads need the hardware reset words pre-seeded.
        bus.words[i2c::I2CFFTX.get() as usize] = 0x0105;
        bus.words[i2c::I2CFFRX.get() as usize] = 0x0005;
        assert_eq!(unsafe { i2c::run_i2c_reg_rw(&mut bus) }, 0);
        assert_eq!(bus.peek(i2c::I2COAR), 0x0035);
        assert_eq!(bus.peek(i2c::I2CCNT), 0x0004);
    }

    #[test]
    fn i2c_reg_rw_reports_oar_mismatch() {
        use super::i2c;
        let mut bus = FaultBus::new(i2c::I2COAR.get(), 0);
        // First deterministic readback check: OAR masked readback -> 0x7F01.
        assert_eq!(unsafe { i2c::run_i2c_reg_rw(&mut bus) }, 0x7F01);
    }

    #[test]
    fn lin_reg_rw_passes_on_storage_bus() {
        use super::{lin, HostMmio};
        let mut bus = HostMmio::new();
        assert_eq!(unsafe { lin::run_lin_reg_rw(&mut bus) }, 0);
        assert_eq!(bus.peek(lin::LINID), 0x0010);
        assert_eq!(bus.peek(lin::SCIGCR2), 0x0001);
    }

    #[test]
    fn lin_reg_rw_reports_scigcr2_mismatch() {
        use super::lin;
        let mut bus = FaultBus::new(lin::SCIGCR2.get(), 0);
        // First verify: SCIGCR2 CC bit not read back -> 0x5202 + 0.
        assert_eq!(unsafe { lin::run_lin_reg_rw(&mut bus) }, 0x5202);
    }

    // --- SPI-B internal-loopback Rust port, cross-checked against the C bridge ---

    #[test]
    fn spi_unpack_rx_byte_matches_c_shift_mask() {
        use super::spi;
        assert_eq!(spi::unpack_rx_byte(0x3C00), 0x3C);
        assert_eq!(spi::unpack_rx_byte(0xFFFF), 0xFF);
        assert_eq!(spi::unpack_rx_byte(0x0000), 0x00);
    }

    #[test]
    fn spi_internal_loopback_returns_ok_when_byte_round_trips() {
        use super::{spi, HostMmio, MmioBus};
        let mut bus = HostMmio::new();
        // Pre-arm the status and receive words the way live hardware would:
        // the INT flag is already set and the transmitted byte comes back in
        // the high half of SPIRXBUF.
        bus.words[spi::SPISTS.get() as usize] = spi::SPISTS_INT_FLAG;
        // The transmitted byte 0x003C surfaces in the high half of SPIRXBUF.
        bus.words[spi::SPIRXBUF.get() as usize] = spi::SPI_LB_TX_DATA << 8;
        let result = unsafe { spi::run_internal_loopback(&mut bus, 100_000) };
        assert_eq!(result, spi::LoopbackResult::Ok);
        // The program phase must leave the exact C-bridge register side effects.
        assert_eq!(bus.peek(spi::SPICCR), spi::SPICCR_LB_8BIT_RESTART);
        assert_eq!(bus.peek(spi::SPICTL), spi::SPICTL_LB_RUN);
        assert_eq!(bus.peek(spi::SPIBRR), spi::SPIBRR_LB);
        assert_eq!(bus.peek(spi::SPIFFTX), spi::SPIFFTX_LB);
        assert_eq!(bus.peek(spi::SPIFFRX), spi::SPIFFRX_LB);
        assert_eq!(bus.peek(spi::SPITXBUF), spi::SPI_LB_TX_DATA);
    }

    #[test]
    fn spi_internal_loopback_plain_timeout_when_status_idle() {
        use super::{spi, HostMmio};
        let mut bus = HostMmio::new();
        // SPISTS stays 0: the INT flag never sets and there is no overflow.
        let result = unsafe { spi::run_internal_loopback(&mut bus, 1) };
        assert_eq!(result, spi::LoopbackResult::Fail(spi::FAIL_LB_TIMEOUT_BASE));
    }

    #[test]
    fn spi_internal_loopback_timeout_classifies_txfifo_overflow() {
        use super::{spi, HostMmio};
        let mut bus = HostMmio::new();
        // INT flag clear but the TX-overflow bit set -> the 0x0300 family.
        bus.words[spi::SPISTS.get() as usize] = spi::SPISTS_TXOVR;
        let result = unsafe { spi::run_internal_loopback(&mut bus, 3) };
        assert_eq!(
            result,
            spi::LoopbackResult::Fail(spi::FAIL_LB_TXOVR_TIMEOUT_BASE + spi::SPISTS_TXOVR)
        );
    }

    #[test]
    fn spi_internal_loopback_zero_rx_is_rx_zero_failure() {
        use super::{spi, HostMmio};
        let mut bus = HostMmio::new();
        // INT sets (0x40) but the receive word is all zero -> 0x0400 family,
        // with the status low byte folded in exactly like the C
        // `f28035_test_fail(0x0400 + (st & 0x00FF))` branch.
        bus.words[spi::SPISTS.get() as usize] = spi::SPISTS_INT_FLAG;
        let result = unsafe { spi::run_internal_loopback(&mut bus, 5) };
        assert_eq!(
            result,
            spi::LoopbackResult::Fail(spi::FAIL_LB_RX_ZERO_BASE + spi::SPISTS_INT_FLAG)
        );
    }

    #[test]
    fn spi_internal_loopback_mismatched_byte_is_data_failure() {
        use super::{spi, HostMmio};
        let mut bus = HostMmio::new();
        // INT sets but a different byte comes back -> 0x0200 + byte.
        bus.words[spi::SPISTS.get() as usize] = spi::SPISTS_INT_FLAG;
        bus.words[spi::SPIRXBUF.get() as usize] = 0x4200;
        let result = unsafe { spi::run_internal_loopback(&mut bus, 5) };
        assert_eq!(
            result,
            spi::LoopbackResult::Fail(spi::FAIL_LB_RX_MISMATCH_BASE + 0x42)
        );
    }
}
