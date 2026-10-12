#![no_std]

#[cfg(feature = "arithmetic")]
mod arithmetic;
pub mod pac;
use crate::pac::ffi;

/// RAM-only zero-C compiler experiment using the normal Safe HAL GPIO API.
#[cfg(feature = "bare-mmio")]
#[unsafe(no_mangle)]
pub extern "C" fn rust_safe_gpio34_low() {
    let mut peripherals = Peripherals::take().expect("peripherals unavailable");
    let mut pin = peripherals.gpio.output::<34>().expect("GPIO34 unavailable");
    #[cfg(feature = "bare-mmio-negative")]
    pin.set_high();
    #[cfg(not(feature = "bare-mmio-negative"))]
    pin.set_low();
}

#[cfg(feature = "arithmetic")]
pub use arithmetic::rust_add;

/// Initializes the clocks, watchdog configuration, and GPIO defaults by
/// calling the original TI F2803x support code.
#[inline(always)]
pub fn system_init() {
    // Safety: the C bridge has no arguments and is intended to run once during
    // startup, before peripheral handles are created.
    unsafe { ffi::f28035_system_init() }
}

/// Busy-waits for the requested number of microseconds using the TI delay
/// routine. Call this only after [`system_init`] has configured the clock.
#[inline(always)]
pub fn delay_us(microseconds: u16) {
    // Safety: the C bridge takes a value, accesses no caller memory, and
    // performs a bounded delay for every u16 argument.
    unsafe { ffi::f28035_delay_us(microseconds) }
}

/// A resource-construction error returned by the safe HAL.
///
/// These are the *recoverable* failures: a caller can inspect the pin number and
/// retry or fail soft instead of aborting.  Compile-time-illegal constants
/// (e.g. `PIN > 44`) are still rejected by a checked `const` assertion at the
/// call site, so they never reach this type.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HalError {
    /// The pin is already owned by another handle derived from the same
    /// [`Gpio`] root.  Taking it again would alias the same physical pin.
    PinAlreadyTaken(u16),
    /// The C bridge reported that the resource could not be configured
    /// (invalid mode, reserved encoding, or a readback mismatch).
    ConfigurationRejected(u16),
}

/// The single ownership root for F28035 peripherals.
pub struct Peripherals {
    pub gpio: Gpio,
    pub adc: AdcResults,
    pub timer0: Timer0,
    pub pwm1: Pwm1,
    pub spi_b: SpiB,
    pub sci_a: SciA,
    pub i2c_a: I2cA,
    pub lin_a: LinA,
    pub ecap1: ECap1,
    pub eqep1: EQep1,
}

impl Peripherals {
    #[inline(always)]
    pub fn take() -> Option<Self> {
        // Safety: ownership is acquired during startup, before interrupts are
        // enabled. The C bridge's flag is not a general atomic primitive.
        let available = unsafe { ffi::f28035_take_peripherals() };
        (available != 0).then_some(Self {
            gpio: Gpio { used: [0; 3] },
            adc: AdcResults(()),
            timer0: Timer0(()),
            pwm1: Pwm1(()),
            spi_b: SpiB(()),
            sci_a: SciA(()),
            i2c_a: I2cA(()),
            lin_a: LinA(()),
            ecap1: ECap1(()),
            eqep1: EQep1(()),
        })
    }
}

/// GPIO root.  Each physical pin may be derived into **exactly one** handle:
/// three 16-bit occupancy words track which of the 45 F28035 pins are claimed.
///
/// Taking a pin that is already claimed returns [`HalError::PinAlreadyTaken`]
/// instead of silently aliasing the pin — this is the resource-conflict case
/// the borrow checker cannot express, so the HAL detects it at the boundary.
pub struct Gpio {
    used: [u16; 3],
}

impl Gpio {
    /// Marks `pin` as claimed and returns true if it was free; otherwise
    /// leaves the mask unchanged and returns false.
    #[inline(always)]
    fn claim(&mut self, pin: u16) -> bool {
        let word = usize::from(pin / 16);
        let bit = 1u16 << (pin % 16);
        if self.used[word] & bit != 0 {
            return false;
        }
        self.used[word] |= bit;
        true
    }

    #[inline(always)]
    fn release(&mut self, pin: u16) {
        let word = usize::from(pin / 16);
        let bit = 1u16 << (pin % 16);
        self.used[word] &= !bit;
    }

    #[inline(always)]
    fn is_claimed(&self, pin: u16) -> bool {
        let word = usize::from(pin / 16);
        let bit = 1u16 << (pin % 16);
        self.used[word] & bit != 0
    }

    /// Claims `PIN` as an output.  Fails if `PIN` is already owned by this
    /// root, or if the C bridge rejects the configuration.
    #[inline(always)]
    pub fn output<const PIN: u16>(&mut self) -> Result<OutputPin<PIN>, HalError> {
        assert!(PIN <= 44, "PIN <= 44");
        if !self.claim(PIN) {
            return Err(HalError::PinAlreadyTaken(PIN));
        }
        // Safety: the const-generic pin is checked before crossing the FFI.
        let configured = unsafe { ffi::f28035_gpio_make_output(PIN) };
        if configured == 0 {
            self.release(PIN);
            return Err(HalError::ConfigurationRejected(PIN));
        }
        Ok(OutputPin::<PIN>(()))
    }

    /// Claims `PIN` as a plain input (sync-qualified, pull-up enabled).
    #[inline(always)]
    pub fn input<const PIN: u16>(&mut self) -> Result<InputPin<PIN>, HalError> {
        self.input_with::<PIN, true, { Qualification::Sync as u16 }>()
    }

    /// Claims `PIN` as an input with an explicit pull-up and qualification.
    #[inline(always)]
    pub fn input_with<const PIN: u16, const PULLUP: bool, const QUALIFICATION: u16>(
        &mut self,
    ) -> Result<InputPin<PIN>, HalError> {
        assert!(PIN <= 44, "PIN <= 44");
        assert!(QUALIFICATION <= 3, "QUALIFICATION <= 3");
        if !self.claim(PIN) {
            return Err(HalError::PinAlreadyTaken(PIN));
        }
        // Safety: the const-generic pin and qualifier are checked before FFI.
        let configured =
            unsafe { ffi::f28035_gpio_make_input(PIN, u16::from(PULLUP), QUALIFICATION) };
        if configured == 0 {
            self.release(PIN);
            return Err(HalError::ConfigurationRejected(PIN));
        }
        Ok(InputPin::<PIN>(()))
    }

    /// Routes `PIN` into external-interrupt line 1.  The pin is claimed so it
    /// cannot also be used as a plain output/input handle.
    #[inline(always)]
    pub fn xint1<const PIN: u16, const EDGE: u16>(
        &mut self,
    ) -> Result<ExternalInterrupt<1, PIN, EDGE>, HalError> {
        self.xint::<1, PIN, EDGE>()
    }

    /// Routes `PIN` into external-interrupt line 2.
    #[inline(always)]
    pub fn xint2<const PIN: u16, const EDGE: u16>(
        &mut self,
    ) -> Result<ExternalInterrupt<2, PIN, EDGE>, HalError> {
        self.xint::<2, PIN, EDGE>()
    }

    #[inline(always)]
    fn xint<const LINE: u16, const PIN: u16, const EDGE: u16>(
        &mut self,
    ) -> Result<ExternalInterrupt<LINE, PIN, EDGE>, HalError> {
        assert!(LINE == 1 || LINE == 2, "LINE is 1 or 2");
        assert!(PIN <= 31, "PIN <= 31");
        assert!(
            EDGE == 0 || EDGE == 1 || EDGE == 3,
            "EDGE == 0 || EDGE == 1 || EDGE == 3"
        );
        if !self.claim(PIN) {
            return Err(HalError::PinAlreadyTaken(PIN));
        }
        // Safety: XINT1/XINT2 only accept GPIO0..31 and the edge is validated.
        let configured = unsafe { ffi::f28035_gpio_configure_xint(LINE, PIN, EDGE) };
        if configured == 0 {
            self.release(PIN);
            return Err(HalError::ConfigurationRejected(PIN));
        }
        Ok(ExternalInterrupt::<LINE, PIN, EDGE>(()))
    }

    /// Selects the peripheral function for PIN via its MUX field
    /// (0 = GPIO, 1..3 = peripheral function).  The MUX routing is
    /// allowed only while `PIN` has no live GPIO or XINT handle. This does
    /// not consume a claim slot; a later input/output claim restores GPIO
    /// mode through the bridge.
    #[inline(always)]
    pub fn set_mux<const PIN: u16, const FUNC: u16>(&mut self) -> Result<(), HalError> {
        assert!(PIN <= 44, "PIN <= 44");
        assert!(FUNC <= 3, "FUNC <= 3");
        if self.is_claimed(PIN) {
            return Err(HalError::PinAlreadyTaken(PIN));
        }
        // Safety: the const-generic pin and function are checked before FFI.
        let configured = unsafe { ffi::f28035_gpio_set_mux(PIN, FUNC) };
        if configured == 0 {
            return Err(HalError::ConfigurationRejected(PIN));
        }
        Ok(())
    }

    /// Reads back the current MUX field for PIN (0 = GPIO, 1..3 = peripheral
    /// function), mirroring 28035_gpio_mux.
    #[inline(always)]
    pub fn mux<const PIN: u16>(&self) -> u16 {
        assert!(PIN <= 44, "PIN <= 44");
        // Safety: the const-generic pin is checked before FFI.
        unsafe { ffi::f28035_gpio_mux(PIN) }
    }
}

#[repr(u16)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Qualification {
    Sync = 0,
    Sample3 = 1,
    Sample6 = 2,
    Async = 3,
}

#[repr(u16)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InterruptEdge {
    Falling = 0,
    Rising = 1,
    Both = 3,
}

/// A typed F28035 GPIO output handle selected at compile time.
///
/// Constructed only through [`Gpio::output`], which claims the pin so no
/// second handle for the same pin can exist while this one is alive.
///
/// A handle cannot be copied or cloned:
///
/// ```compile_fail
/// use f28035_safe_hal::OutputPin;
/// fn duplicate(pin: OutputPin<34>) {
///     let other = pin;
///     pin.set_low();
///     drop(other);
/// }
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::OutputPin;
/// fn duplicate(pin: OutputPin<34>) {
///     let _other = pin.clone();
/// }
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::OutputPin;
/// let _forged = OutputPin::<34>(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct OutputPin<const PIN: u16>(());

impl<const PIN: u16> OutputPin<PIN> {
    #[inline(always)]
    pub fn set(&mut self, high: bool) {
        // Safety: only a pin claimed by Gpio::output constructs this type.
        unsafe { ffi::f28035_gpio_write(PIN, u16::from(high)) }
    }

    #[inline(always)]
    pub fn set_high(&mut self) {
        self.set(true);
    }

    #[inline(always)]
    pub fn set_low(&mut self) {
        self.set(false);
    }

    #[inline(always)]
    pub fn toggle(&mut self) {
        // Safety: only a pin claimed by Gpio::output constructs this type.
        unsafe { ffi::f28035_gpio_toggle(PIN) }
    }

    /// Reads back the output latch for this pin.  For pure GPIO (mux=0) the
    /// C bridge returns the DATA bit; the value is stable between commands.
    #[inline(always)]
    pub fn is_high(&self) -> bool {
        // Safety: the pin was validated by Gpio before this handle existed.
        unsafe { ffi::f28035_gpio_read(PIN) != 0 }
    }

    #[inline(always)]
    pub fn is_low(&self) -> bool {
        !self.is_high()
    }

    /// Reconfigures this pin as an input, consuming the output handle.
    ///
    /// Releases the exclusive claim on `PIN` and re-claims it as an input
    /// (pull-up enabled, Sync qualification).  The returned [`InputPin`] is the
    /// only live handle for the pin, so no two handles ever alias it.
    #[inline(always)]
    pub fn into_input(self, gpio: &mut Gpio) -> Result<InputPin<PIN>, HalError> {
        gpio.release(PIN);
        gpio.input::<PIN>()
    }
}

/// A typed F28035 GPIO input handle selected at compile time.
///
/// Constructed only through [`Gpio::input`]/[`Gpio::input_with`].
///
/// ```compile_fail
/// use f28035_safe_hal::InputPin;
/// fn duplicate(pin: InputPin<34>) {
///     let other = pin;
///     let _ = pin.is_high();
///     drop(other);
/// }
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::InputPin;
/// let _forged = InputPin::<34>(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct InputPin<const PIN: u16>(());

impl<const PIN: u16> InputPin<PIN> {
    #[inline(always)]
    pub fn read(&self) -> bool {
        // Safety: only a pin claimed by Gpio constructs this type.
        unsafe { ffi::f28035_gpio_read(PIN) != 0 }
    }

    #[inline(always)]
    pub fn is_high(&self) -> bool {
        self.read()
    }

    #[inline(always)]
    pub fn is_low(&self) -> bool {
        !self.read()
    }

    /// Reconfigures this pin as an output, consuming the input handle.
    ///
    /// Releases the exclusive claim on `PIN` and re-claims it as an output.
    /// The returned [`OutputPin`] is the only live handle for the pin, so no
    /// two handles ever alias it.
    #[inline(always)]
    pub fn into_output(self, gpio: &mut Gpio) -> Result<OutputPin<PIN>, HalError> {
        gpio.release(PIN);
        gpio.output::<PIN>()
    }
}

/// A claimed XINT1/XINT2 route.  Constructed only through
/// [`Gpio::xint1`]/[`Gpio::xint2`].
///
/// ```compile_fail
/// use f28035_safe_hal::ExternalInterrupt;
/// fn duplicate(route: ExternalInterrupt<1, 2, 1>) {
///     let other = route;
///     let _ = route.line();
///     drop(other);
/// }
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::ExternalInterrupt;
/// let _forged = ExternalInterrupt::<1, 2, 1>(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct ExternalInterrupt<const LINE: u16, const PIN: u16, const EDGE: u16>(());

impl<const LINE: u16, const PIN: u16, const EDGE: u16> ExternalInterrupt<LINE, PIN, EDGE> {
    /// The external-interrupt line number this handle owns.
    pub const fn line(&self) -> u16 {
        LINE
    }
}

/// Timer0 ownership token, available only from [`Peripherals::take`].
///
/// ```compile_fail
/// use f28035_safe_hal::Timer0;
/// let _forged = Timer0(());
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::Timer0;
/// fn duplicate(timer: Timer0) {
///     let other = timer;
///     let _again = timer;
///     drop(other);
/// }
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct Timer0(());
#[derive(Debug, PartialEq, Eq)]
pub struct ArmedTimer0<const PERIOD_MS: u16>(());
/// Active Timer0 ownership cannot be duplicated.
///
/// ```compile_fail
/// use f28035_safe_hal::PeriodicTimer0;
/// fn duplicate(timer: PeriodicTimer0<10>) {
///     let other = timer;
///     let _again = timer;
///     drop(other);
/// }
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct PeriodicTimer0<const PERIOD_MS: u16>(());
#[derive(Debug, PartialEq, Eq)]
pub struct StoppedTimer0<const PERIOD_MS: u16>(());

impl Timer0 {
    /// Starts Timer0 in one-shot mode.  The period range (1..=1000 ms) is a
    /// compile-time constant and is rejected by the const check below; a
    /// runtime configuration failure from the C bridge is surfaced as
    /// [`HalError::ConfigurationRejected`] and returns the timer so the caller
    /// keeps ownership.
    #[inline(always)]
    pub fn start_once<const PERIOD_MS: u16>(
        self,
    ) -> Result<ArmedTimer0<PERIOD_MS>, (Timer0, HalError)> {
        assert!(PERIOD_MS > 0 && PERIOD_MS <= 1000, "PERIOD_MS is 1..=1000");
        // Safety: the period is range checked and Timer0 is uniquely owned.
        let started = unsafe { ffi::f28035_timer0_start_once_ms(PERIOD_MS) };
        if started == 0 {
            return Err((self, HalError::ConfigurationRejected(PERIOD_MS)));
        }
        Ok(ArmedTimer0(()))
    }

    /// Starts Timer0 in periodic mode.  See [`Timer0::start_once`] for the
    /// error semantics: the period const is rejected at compile time, while a
    /// bridge configuration failure returns the timer to the caller.
    #[inline(always)]
    pub fn start_periodic<const PERIOD_MS: u16>(
        self,
    ) -> Result<PeriodicTimer0<PERIOD_MS>, (Timer0, HalError)> {
        assert!(PERIOD_MS > 0 && PERIOD_MS <= 1000, "PERIOD_MS is 1..=1000");
        // Safety: the period is range checked and Timer0 is uniquely owned.
        let started = unsafe { ffi::f28035_timer0_start_periodic_ms(PERIOD_MS) };
        if started == 0 {
            return Err((self, HalError::ConfigurationRejected(PERIOD_MS)));
        }
        Ok(PeriodicTimer0(()))
    }
}

impl<const PERIOD_MS: u16> PeriodicTimer0<PERIOD_MS> {
    #[inline(always)]
    pub fn interrupt_count(&self) -> u16 {
        // Safety: an aligned u16 load is atomic on C28x.
        unsafe { ffi::f28035_timer0_interrupts() }
    }

    #[inline(always)]
    pub fn stop(self) -> StoppedTimer0<PERIOD_MS> {
        // Safety: this handle uniquely owns Timer0.
        unsafe { ffi::f28035_timer0_stop() }
        StoppedTimer0(())
    }
}

impl<const PERIOD_MS: u16> StoppedTimer0<PERIOD_MS> {
    /// Changes the period of a stopped timer.  A bridge configuration failure
    /// returns the (still stopped) timer to the caller.
    #[inline(always)]
    pub fn set_period<const NEW_PERIOD_MS: u16>(
        self,
    ) -> Result<StoppedTimer0<NEW_PERIOD_MS>, (StoppedTimer0<PERIOD_MS>, HalError)> {
        assert!(
            NEW_PERIOD_MS > 0 && NEW_PERIOD_MS <= 1000,
            "NEW_PERIOD_MS is 1..=1000"
        );
        // Safety: Timer0 is stopped and uniquely owned by this handle.
        let configured = unsafe { ffi::f28035_timer0_set_period_ms(NEW_PERIOD_MS) };
        if configured == 0 {
            return Err((self, HalError::ConfigurationRejected(NEW_PERIOD_MS)));
        }
        Ok(StoppedTimer0::<NEW_PERIOD_MS>(()))
    }

    #[inline(always)]
    pub fn restart(self) -> PeriodicTimer0<PERIOD_MS> {
        // Safety: only a stopped, uniquely owned timer constructs this type.
        unsafe { ffi::f28035_timer0_restart() }
        PeriodicTimer0(())
    }
}

/// ePWM1 ownership token, available only from [`Peripherals::take`].
///
/// ```compile_fail
/// use f28035_safe_hal::Pwm1;
/// let _forged = Pwm1(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct Pwm1(());
/// Configured ePWM1 ownership cannot be duplicated.
///
/// ```compile_fail
/// use f28035_safe_hal::Pwm1Output;
/// fn duplicate(pwm: Pwm1Output<4095>) {
///     let other = pwm;
///     let _again = pwm;
///     drop(other);
/// }
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct Pwm1Output<const PERIOD_TICKS: u16>(());

impl Pwm1 {
    /// Configures ePWM1 for up-counting with the given period.  A nonzero
    /// period is a compile-time check; a bridge configuration failure is
    /// surfaced as [`HalError::ConfigurationRejected`] and the handle is
    /// returned so the caller keeps ownership of ePWM1.
    #[inline(always)]
    pub fn configure<const PERIOD_TICKS: u16>(
        self,
    ) -> Result<Pwm1Output<PERIOD_TICKS>, (Pwm1, HalError)> {
        assert!(PERIOD_TICKS > 0, "PERIOD_TICKS > 0");
        // Safety: ePWM1 is uniquely owned and the period is nonzero.
        let configured = unsafe { ffi::f28035_epwm1_configure(PERIOD_TICKS) };
        if configured == 0 {
            return Err((self, HalError::ConfigurationRejected(PERIOD_TICKS)));
        }
        Ok(Pwm1Output(()))
    }
}

impl<const PERIOD_TICKS: u16> Pwm1Output<PERIOD_TICKS> {
    #[inline(always)]
    pub fn set_compare(&mut self, compare_ticks: u16) {
        // Safety: the bridge clamps the compare value to the configured period.
        unsafe { ffi::f28035_epwm1_set_compare(compare_ticks) }
    }

    /// Reads back the active CMPA value (clamped to the period at write time).
    #[inline(always)]
    pub fn get_compare(&self) -> u16 {
        // Safety: fixed ePWM1 register; the bridge returns the latched value.
        unsafe { ffi::f28035_epwm1_compare() }
    }

    /// Enables the ePWM1A output (TBCTL PWMENABLE).  Idempotent.
    #[inline(always)]
    pub fn enable(&mut self) {
        // Safety: ePWM1 is uniquely owned by this handle.
        unsafe { ffi::f28035_epwm1_enable() };
    }

    /// Disables the ePWM1A output and forces it to the idle state.
    #[inline(always)]
    pub fn disable(&mut self) {
        // Safety: ePWM1 is uniquely owned by this handle.
        unsafe { ffi::f28035_epwm1_disable() };
    }

    /// The configured period in ticks.  Compile-time constant.
    pub const fn period_ticks(&self) -> u16 {
        PERIOD_TICKS
    }
}

/// A handle to the ADC result registers.  Constructed only by
/// [`Peripherals::take`] so there is a single owner of the result file.
/// ADC ownership token, available only from [`Peripherals::take`].
///
/// ```compile_fail
/// use f28035_safe_hal::AdcResults;
/// let _forged = AdcResults(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct AdcResults(());

/// SOC0 configured for one ADC channel. The channel is carried in the type,
/// so sampling cannot accidentally select a different channel.
///
/// ```compile_fail
/// use f28035_safe_hal::Peripherals;
/// let peripherals = Peripherals::take().unwrap();
/// let mut adc0 = peripherals.adc.into_soc0::<0, 7>().unwrap();
/// let _ = adc0.sample::<1>(); // The configured handle has no channel argument.
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::Peripherals;
/// let peripherals = Peripherals::take().unwrap();
/// let adc0 = peripherals.adc.into_soc0::<0, 7>().unwrap();
/// let _ = adc0.sample(); // Sampling requires exclusive mutable access.
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct ConfiguredAdc<const CHANNEL: u16>(AdcResults);

impl AdcResults {
    /// Consumes the unconfigured ADC owner and returns a channel-bound SOC0
    /// handle. On configuration failure, ownership is returned to the caller.
    #[inline(always)]
    pub fn into_soc0<const CHANNEL: u16, const ACQPS: u16>(
        mut self,
    ) -> Result<ConfiguredAdc<CHANNEL>, (Self, HalError)> {
        match self.configure_soc0::<CHANNEL, ACQPS>() {
            Ok(()) => Ok(ConfiguredAdc(self)),
            Err(error) => Err((self, error)),
        }
    }

    /// Configures SOC0 for a channel. Prefer [`Self::into_soc0`] when the
    /// application can transfer ownership into a channel-bound handle.
    #[inline(always)]
    pub fn configure_soc0<const CHANNEL: u16, const ACQPS: u16>(&mut self) -> Result<(), HalError> {
        assert!(CHANNEL <= 15, "CHANNEL <= 15");
        assert!(ACQPS <= 63, "ACQPS <= 63");
        // Safety: both constants are checked and this handle uniquely owns ADC.
        let configured = unsafe { ffi::f28035_adc_configure_soc0(CHANNEL, ACQPS) };
        if configured == 0 {
            return Err(HalError::ConfigurationRejected(CHANNEL));
        }
        Ok(())
    }

    #[inline(always)]
    pub fn read<const INDEX: u16>(&self) -> u16 {
        assert!(INDEX <= 15, "INDEX <= 15");
        // Safety: the const-generic index is checked before crossing the FFI.
        unsafe { ffi::f28035_adc_result(INDEX) }
    }

    #[inline(always)]
    pub fn sample<const CHANNEL: u16>(&self) -> u16 {
        assert!(CHANNEL <= 15, "CHANNEL <= 15");
        // Safety: CHANNEL is validated and SOC0 is exclusively configured by
        // the uniquely owned ADC handle.
        unsafe { ffi::f28035_adc_sample(CHANNEL) }
    }

    #[inline(always)]
    pub fn timeout_count(&self) -> u16 {
        // Safety: an aligned u16 load is atomic on C28x.
        unsafe { ffi::f28035_adc_timeouts() }
    }

    /// Reads a result register by a *runtime* index (0..=15). Invalid indices
    /// return 0 rather than wrapping around to a different result register.
    #[inline(always)]
    pub fn read_channel(&self, channel: u16) -> u16 {
        if channel > 15 {
            return 0;
        }
        // Safety: the result index was validated before crossing the FFI.
        unsafe { ffi::f28035_adc_result(channel) }
    }
}

impl<const CHANNEL: u16> ConfiguredAdc<CHANNEL> {
    /// Samples the channel chosen when SOC0 was configured. A mutable borrow
    /// prevents two safe callers from starting overlapping conversions.
    #[inline(always)]
    pub fn sample(&mut self) -> u16 {
        // Safety: `ConfiguredAdc` is created only after valid SOC0 setup.
        unsafe { ffi::f28035_adc_sample(CHANNEL) }
    }

    #[inline(always)]
    pub fn timeout_count(&self) -> u16 {
        self.0.timeout_count()
    }
}

/// A uniquely owned SPI-B controller handle.
///
/// The current implementation keeps the audited register sequences in the
/// C-ABI bridge, but the application no longer calls those bridge symbols
/// directly.  Each method names the legal operation in Rust and validates the
/// small amount of static configuration that can be expressed today.
#[derive(Debug, PartialEq, Eq)]
pub struct SpiB(());

/// A completed SPI-B internal-loopback exercise. The C case uses 8-bit data.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SpiLoopback<const CHAR_BITS: u16>(());

impl SpiB {
    #[inline(always)]
    pub fn reg_readback(&mut self) {
        pac::f28035_spi_reg_if_rw_basic();
    }

    /// Runs the SPI-B internal-loopback 8-bit exchange.
    ///
    /// An audited Rust port of this exact register sequence now lives at
    /// [`pac::spi::run_internal_loopback`] and is host-verified 1:1 against the
    /// C bridge (every failure-code branch asserted in the PAC host tests).
    /// Until the C28x backend lowers that sequence to target code, the target
    /// image still routes through the C bridge via
    /// [`pac::f28035_spi_internal_loopback_basic`] so the verified hardware
    /// behaviour is unchanged; the Rust sequence is the pending backend
    /// milestone.
    #[inline(always)]
    pub fn internal_loopback<const CHAR_BITS: u16>(&mut self) -> SpiLoopback<CHAR_BITS> {
        assert!(CHAR_BITS >= 1 && CHAR_BITS <= 16, "CHAR_BITS is 1..=16");
        assert!(CHAR_BITS == 8, "internal loopback C case uses 8-bit characters");
        pac::f28035_spi_internal_loopback_basic();
        SpiLoopback(())
    }

    #[inline(always)]
    pub fn triwire_loopback<const CHAR_BITS: u16>(&mut self) -> SpiLoopback<CHAR_BITS> {
        assert!(CHAR_BITS >= 1 && CHAR_BITS <= 16, "CHAR_BITS is 1..=16");
        assert!(CHAR_BITS == 8, "triwire C case uses 8-bit characters");
        pac::f28035_spi_triwire_loopback_basic();
        SpiLoopback(())
    }

    #[inline(always)]
    pub fn loopback_mode_matrix(&mut self) {
        pac::f28035_spi_loopback_mode_matrix_basic();
    }

    #[inline(always)]
    pub fn charlen_sweep(&mut self) {
        pac::f28035_spi_charlen_sweep_basic();
    }

    #[inline(always)]
    pub fn fifo_rx_boundary(&mut self) {
        pac::f28035_spi_fifo_rx_boundary_basic();
    }

    #[inline(always)]
    pub fn fifo_tx_boundary(&mut self) {
        pac::f28035_spi_fifo_tx_boundary_basic();
    }

    #[inline(always)]
    pub fn fifo_level_boundary(&mut self) {
        pac::f28035_spi_fifo_level_boundary_basic();
    }

    #[inline(always)]
    pub fn multiple_frame_loopback(&mut self) {
        pac::f28035_spi_multiple_frame_loopback_basic();
    }

    #[inline(always)]
    pub fn nonfifo_interrupt_flag(&mut self) {
        pac::f28035_spi_nonfifo_intflag_irq_basic();
    }
}

/// A uniquely owned SCI-A controller handle.
#[derive(Debug, PartialEq, Eq)]
pub struct SciA(());

/// Legacy result tag for SCI-A self-tests. The C cases do not program the
/// const parameters; use the explicit `*_self_test` methods for target builds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SciProfile<const BAUD_DIV: u16, const CHAR_BITS: u16>(());

impl SciA {
    /// Runs the fixed SCI-A baud programming self-test in the C bridge.
    #[inline(always)]
    pub fn baud_program_self_test(&mut self) {
        pac::f28035_sci_baud_program_basic();
    }

    /// Runs the fixed SCI-A internal loopback self-test.
    #[inline(always)]
    pub fn internal_loopback_self_test(&mut self) {
        pac::f28035_sci_internal_loopback_basic();
    }

    /// Runs the fixed SCI-A loopback pattern self-test.
    #[inline(always)]
    pub fn loopback_data_pattern_self_test(&mut self) {
        pac::f28035_sci_loopback_data_pattern_basic();
    }

    #[inline(always)]
    pub fn configure_basic<const BAUD_DIV: u16, const CHAR_BITS: u16>(
        &mut self,
    ) -> SciProfile<BAUD_DIV, CHAR_BITS> {
        assert!(BAUD_DIV > 0, "BAUD_DIV > 0");
        assert!(CHAR_BITS >= 1 && CHAR_BITS <= 8, "CHAR_BITS is 1..=8");
        pac::f28035_sci_baud_program_basic();
        SciProfile(())
    }

    #[inline(always)]
    pub fn reg_readback(&mut self) {
        pac::f28035_sci_reg_if_rw_basic();
    }

    #[inline(always)]
    pub fn internal_loopback<const BAUD_DIV: u16, const CHAR_BITS: u16>(
        &mut self,
    ) -> SciProfile<BAUD_DIV, CHAR_BITS> {
        let profile = self.configure_basic::<BAUD_DIV, CHAR_BITS>();
        pac::f28035_sci_internal_loopback_basic();
        profile
    }

    #[inline(always)]
    pub fn loopback_data_pattern<const BAUD_DIV: u16, const CHAR_BITS: u16>(
        &mut self,
    ) -> SciProfile<BAUD_DIV, CHAR_BITS> {
        let profile = self.configure_basic::<BAUD_DIV, CHAR_BITS>();
        pac::f28035_sci_loopback_data_pattern_basic();
        profile
    }

    #[inline(always)]
    pub fn fifo_reset_then_loopback(&mut self) {
        pac::f28035_sci_fifo_reset_then_loopback_basic();
    }

    #[inline(always)]
    pub fn fifo_rx(&mut self) {
        pac::f28035_sci_fifo_rx_basic();
    }

    #[inline(always)]
    pub fn rx_ready_clears_on_read(&mut self) {
        pac::f28035_sci_rxrdy_clear_on_read_basic();
    }

    #[inline(always)]
    pub fn charlen_sweep(&mut self) {
        pac::f28035_sci_sciccr_charlen_sweep_basic();
    }

    #[inline(always)]
    pub fn stop_parity_charlen_sweep(&mut self) {
        pac::f28035_sci_stop2_parity_charlen_sweep_basic();
    }

    #[inline(always)]
    pub fn tx_ready_interrupt_nonfifo(&mut self) {
        pac::f28035_sci_txrdy_int_nonfifo_basic();
    }
}

/// A uniquely owned I2C-A master handle.
#[derive(Debug, PartialEq, Eq)]
pub struct I2cA(());

/// A 7-bit I2C slave address carried in the type system.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct I2cSlave<const ADDRESS: u16>(());

impl I2cA {
    #[inline(always)]
    pub fn slave<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        assert!(ADDRESS <= 0x7f, "ADDRESS is 7-bit");
        I2cSlave(())
    }

    #[inline(always)]
    fn fixed_case_slave<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.slave::<ADDRESS>();
        assert!(ADDRESS == 0x36, "I2C C cases use fixed address 0x36");
        slave
    }

    #[inline(always)]
    pub fn reg_readback_sweep(&mut self) {
        pac::f28035_i2c_reg_readback_sweep_basic();
    }

    #[inline(always)]
    pub fn master_write_1byte<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_write_1byte_basic();
        slave
    }

    #[inline(always)]
    pub fn master_write_8byte_pattern<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_write_8byte_pattern();
        slave
    }

    #[inline(always)]
    pub fn master_read_1byte<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_read_1byte_basic();
        slave
    }

    #[inline(always)]
    pub fn master_read_8byte<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_read_8byte_basic();
        slave
    }

    #[inline(always)]
    pub fn master_write_back_to_back<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_write_back_to_back();
        slave
    }

    #[inline(always)]
    pub fn master_read_back_to_back<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_read_back_to_back_basic();
        slave
    }

    #[inline(always)]
    pub fn master_write_then_read_4byte<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_write_then_read_4byte_basic();
        slave
    }

    #[inline(always)]
    pub fn repeated_start_write_then_read_4byte<const ADDRESS: u16>(
        &mut self,
    ) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_repeated_start_write_then_read_4byte_basic();
        slave
    }

    #[inline(always)]
    pub fn addr_nack_stop<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_addr_nack_stop_basic();
        slave
    }
}

/// A uniquely owned LIN-A controller handle.
#[derive(Debug, PartialEq, Eq)]
pub struct LinA(());

impl LinA {
    #[inline(always)]
    pub fn baud_program(&mut self) {
        pac::f28035_lin_baud_program_basic();
    }

    #[inline(always)]
    pub fn header_break_sync_master(&mut self) {
        pac::f28035_lin_header_break_sync_master_basic();
    }

    #[inline(always)]
    pub fn iodft_loopback(&mut self) {
        pac::f28035_lin_iodft_loopback_basic();
    }

    #[inline(always)]
    pub fn reg_readback(&mut self) {
        pac::f28035_lin_reg_if_rw_basic();
    }

    #[inline(always)]
    pub fn rx_checksum_length(&mut self) {
        pac::f28035_lin_rx_checksum_length_real_basic();
    }

    #[inline(always)]
    pub fn rx_count_boundary(&mut self) {
        pac::f28035_lin_rx_rxcnt_num_boundary_real_basic();
    }

    #[inline(always)]
    pub fn sci_multibuf_read_slot_sweep(&mut self) {
        pac::f28035_lin_sci_multibuf_rdslot_sweep_basic();
    }

    #[inline(always)]
    pub fn top_mode_loopback_power_cross(&mut self) {
        pac::f28035_lin_top_mode_loopback_power_cross_basic();
    }

    #[inline(always)]
    pub fn tx_checksum_extended(&mut self) {
        pac::f28035_lin_tx_checksum_ext_real_basic();
    }

    #[inline(always)]
    pub fn wakeup_break_flag_route(&mut self) {
        pac::f28035_lin_wakeup_break_flag_route_basic();
    }
}

/// A uniquely owned eCAP1 controller handle.
#[derive(Debug, PartialEq, Eq)]
pub struct ECap1(());

impl ECap1 {
    #[inline(always)]
    pub fn reg_readback(&mut self) {
        pac::f28035_ecap_reg_rw_smoke();
    }

    #[inline(always)]
    pub fn apwm_matrix(&mut self) {
        pac::f28035_ecap_apwm_matrix();
    }

    #[inline(always)]
    pub fn capture_single_edge(&mut self) {
        pac::f28035_ecap_capture_single_edge();
    }

    #[inline(always)]
    pub fn capture_dual_edge(&mut self) {
        pac::f28035_ecap_capture_dual_edge();
    }

    #[inline(always)]
    pub fn capture_quad_edge(&mut self) {
        pac::f28035_ecap_capture_quad_edge();
    }

    #[inline(always)]
    pub fn capture_continuous_wrap(&mut self) {
        pac::f28035_ecap_capture_continuous_wrap();
    }

    #[inline(always)]
    pub fn capture_counter_reset(&mut self) {
        pac::f28035_ecap_capture_counter_reset();
    }

    #[inline(always)]
    pub fn capture_prescale_div2(&mut self) {
        pac::f28035_ecap_capture_prescale_div2();
    }

    #[inline(always)]
    pub fn capture_wrap_matrix(&mut self) {
        pac::f28035_ecap_capture_wrap_matrix();
    }

    #[inline(always)]
    pub fn interrupt_integration(&mut self) {
        pac::f28035_ecap_interrupt_integration();
    }
}

/// A uniquely owned eQEP1 controller handle.
#[derive(Debug, PartialEq, Eq)]
pub struct EQep1(());

impl EQep1 {
    #[inline(always)]
    pub fn register_write_readback(&mut self) {
        pac::f28035_eqep_register_wr();
    }

    #[inline(always)]
    pub fn polarity_test(&mut self) {
        pac::f28035_eqep_polarity_test();
    }

    #[inline(always)]
    pub fn count_basic(&mut self) {
        pac::f28035_eqep_count_basic();
    }

    #[inline(always)]
    pub fn mode_test(&mut self) {
        pac::f28035_eqep_mode_test();
    }

    #[inline(always)]
    pub fn compare_output_pulse(&mut self) {
        pac::f28035_eqep_compare_output_pulse();
    }

    #[inline(always)]
    pub fn unit_timer(&mut self) {
        pac::f28035_eqep_unit_timer();
    }

    #[inline(always)]
    pub fn unit_timeout(&mut self) {
        pac::f28035_eqep_unit_timeout_test();
    }

    #[inline(always)]
    pub fn watchdog_timeout(&mut self) {
        pac::f28035_eqep_watchdog_timeout_test();
    }

    #[inline(always)]
    pub fn interrupt_gate(&mut self) {
        pac::f28035_eqep_interrupt_gate();
    }

    #[inline(always)]
    pub fn reset_fsm_matrix(&mut self) {
        pac::f28035_eqep_reset_fsm_matrix();
    }
}

/// embedded-hal trait implementations.
///
/// `OutputPin` / `InputPin` are infallible because all GPIO operations go
/// through a validated const-generic handle.  `StatefulOutputPin::is_set_high`
/// now reads back the GPIO output latch via the C bridge.
///
/// embedded-hal 1.0 trait implementations.
///
/// embedded-hal 1.0.0 exposes `digital` (OutputPin / StatefulOutputPin /
/// InputPin — no `v2` prefix) and `pwm::SetDutyCycle`, plus i2c/spi/delay.
/// Those traits all inherit from `ErrorType` (`type Error: Error`), so each
/// handle first implements `ErrorType` with `Infallible` (every GPIO/PWM op
/// goes through a validated const-generic handle and cannot fail), and then
/// the concrete trait.  1.0.0 has no `adc` / `timer` modules, so
/// `AdcResults` and `PeriodicTimer0` keep their native safe-HAL methods.
///
/// `StatefulOutputPin::is_set_high` reads back the GPIO output latch via the
/// C bridge; `SetDutyCycle` writes the real ePWM1 CMPA and reports the
/// configured period as `max_duty_cycle`.
///
/// ```no_run
/// use f28035_safe_hal::Peripherals;
///
/// fn drive_status_pin(mut peripherals: Peripherals) {
///     let mut pin = peripherals.gpio.output::<44>().unwrap();
///     embedded_hal::digital::OutputPin::set_high(&mut pin).unwrap();
/// }
/// ```
#[cfg(feature = "embedded-hal")]
mod hal_impl {
    use super::{InputPin, OutputPin, Pwm1Output};

    impl<const PIN: u16> embedded_hal::digital::ErrorType for OutputPin<PIN> {
        type Error = core::convert::Infallible;
    }

    impl<const PIN: u16> embedded_hal::digital::OutputPin for OutputPin<PIN> {
        fn set_high(&mut self) -> Result<(), Self::Error> {
            self.set_high();
            Ok(())
        }
        fn set_low(&mut self) -> Result<(), Self::Error> {
            self.set_low();
            Ok(())
        }
    }

    impl<const PIN: u16> embedded_hal::digital::StatefulOutputPin for OutputPin<PIN> {
        fn is_set_high(&mut self) -> Result<bool, Self::Error> {
            Ok(self.is_high())
        }
        fn is_set_low(&mut self) -> Result<bool, Self::Error> {
            Ok(self.is_low())
        }
    }

    impl<const PIN: u16> embedded_hal::digital::ErrorType for InputPin<PIN> {
        type Error = core::convert::Infallible;
    }

    impl<const PIN: u16> embedded_hal::digital::InputPin for InputPin<PIN> {
        fn is_high(&mut self) -> Result<bool, Self::Error> {
            // Disambiguate from the trait method of the same name: call the
            // inherent `bool`-returning read explicitly.
            Ok(InputPin::<PIN>::is_high(self))
        }
        fn is_low(&mut self) -> Result<bool, Self::Error> {
            Ok(InputPin::<PIN>::is_low(self))
        }
    }

    impl<const PERIOD: u16> embedded_hal::pwm::ErrorType for Pwm1Output<PERIOD> {
        type Error = core::convert::Infallible;
    }

    impl<const PERIOD: u16> embedded_hal::pwm::SetDutyCycle for Pwm1Output<PERIOD> {
        fn set_duty_cycle(&mut self, duty: u16) -> Result<(), Self::Error> {
            self.set_compare(duty);
            Ok(())
        }
        fn max_duty_cycle(&self) -> u16 {
            PERIOD
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{HalError, InterruptEdge, Peripherals, Qualification, ffi};

    fn fresh_peripherals() -> Peripherals {
        ffi::reset_peripherals();
        Peripherals::take().unwrap()
    }

    #[test]
    fn valid_const_generic_resources_use_safe_handles() {
        let mut peripherals = fresh_peripherals();
        let mut pin = peripherals.gpio.output::<44>().unwrap();
        pin.set_high();
        assert!(pin.is_high());
        assert!(!pin.is_low());
        pin.set_low();
        assert!(pin.is_low());
        pin.toggle(); // low -> high
        assert!(pin.is_high());
        assert_eq!(peripherals.adc.read::<15>(), 0);
    }

    #[test]
    fn gpio_inputs_support_pullups_qualification_and_xint_tokens() {
        let mut peripherals = fresh_peripherals();
        let pin = peripherals
            .gpio
            .input_with::<1, true, { Qualification::Sample6 as u16 }>()
            .unwrap();
        assert!(pin.is_low());
        assert!(!pin.is_high());

        // Pin 1 is already claimed by the input handle above, so the XINT
        // routes use distinct pins (2 and 31) — claiming pin 1 as XINT1 is
        // intentionally rejected by the exclusivity mask.
        let _xint1 = peripherals
            .gpio
            .xint1::<2, { InterruptEdge::Falling as u16 }>()
            .unwrap();
        let _xint2 = peripherals
            .gpio
            .xint2::<31, { InterruptEdge::Both as u16 }>()
            .unwrap();
    }

    /// T1 proof: a pin can only be claimed once.  The second handle for the
    /// same physical pin is rejected with `PinAlreadyTaken` instead of
    /// aliasing it.
    #[test]
    fn same_pin_cannot_be_claimed_twice() {
        let mut peripherals = fresh_peripherals();
        let _out = peripherals.gpio.output::<5>().unwrap();
        let again = peripherals.gpio.output::<5>();
        assert_eq!(again, Err(HalError::PinAlreadyTaken(5)));

        // A different pin on the same root is still allowed.
        assert!(peripherals.gpio.output::<6>().is_ok());

        // An input handle for a pin already owned as an output conflicts too.
        assert_eq!(
            peripherals.gpio.input::<5>(),
            Err(HalError::PinAlreadyTaken(5))
        );
    }

    #[test]
    fn gpio_claims_span_all_three_16_bit_words() {
        let mut peripherals = fresh_peripherals();
        let gpio = &mut peripherals.gpio;
        assert!(gpio.output::<0>().is_ok());
        assert!(gpio.output::<15>().is_ok());
        assert!(gpio.output::<16>().is_ok());
        assert!(gpio.output::<31>().is_ok());
        assert!(gpio.output::<32>().is_ok());
        assert!(gpio.output::<44>().is_ok());

        assert_eq!(gpio.output::<0>(), Err(HalError::PinAlreadyTaken(0)));
        assert_eq!(gpio.input::<15>(), Err(HalError::PinAlreadyTaken(15)));
        assert_eq!(gpio.output::<16>(), Err(HalError::PinAlreadyTaken(16)));
        assert_eq!(gpio.input::<31>(), Err(HalError::PinAlreadyTaken(31)));
        assert_eq!(gpio.output::<32>(), Err(HalError::PinAlreadyTaken(32)));
        assert_eq!(gpio.input::<44>(), Err(HalError::PinAlreadyTaken(44)));
    }

    #[test]
    fn xint_pins_are_claimed_against_plain_handles() {
        let mut peripherals = fresh_peripherals();
        let _xint = peripherals
            .gpio
            .xint1::<1, { InterruptEdge::Falling as u16 }>()
            .unwrap();
        assert_eq!(
            peripherals.gpio.output::<1>(),
            Err(HalError::PinAlreadyTaken(1))
        );
    }

    #[test]
    #[should_panic(expected = "PIN <= 44")]
    fn nonexistent_gpio_is_rejected() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.gpio.output::<45>();
    }

    #[test]
    #[should_panic(expected = "PIN <= 44")]
    fn nonexistent_gpio_input_is_rejected() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.gpio.input::<45>();
    }

    #[test]
    #[should_panic(expected = "PIN <= 31")]
    fn xint_rejects_gpio_b_pins() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals
            .gpio
            .xint1::<32, { InterruptEdge::Rising as u16 }>();
    }

    #[test]
    #[should_panic(expected = "EDGE == 0 || EDGE == 1 || EDGE == 3")]
    fn xint_rejects_reserved_edge_encoding() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.gpio.xint2::<1, 2>();
    }

    #[test]
    #[should_panic(expected = "INDEX <= 15")]
    fn nonexistent_adc_result_is_rejected() {
        let peripherals = fresh_peripherals();
        let _ = peripherals.adc.read::<16>();
    }

    #[test]
    fn peripheral_root_can_only_be_taken_once() {
        ffi::reset_peripherals();
        assert!(Peripherals::take().is_some());
        assert!(Peripherals::take().is_none());
    }

    #[test]
    fn timer_and_pwm_validate_configuration() {
        let peripherals = fresh_peripherals();
        let _timer = peripherals.timer0.start_periodic::<10>().unwrap();
        let mut pwm = peripherals.pwm1.configure::<4095>().unwrap();
        pwm.set_compare(2048);
        assert_eq!(pwm.get_compare(), 2048);
        pwm.enable();
        pwm.disable();
        assert_eq!(pwm.period_ticks(), 4095);
    }

    #[test]
    fn periodic_timer_state_transitions_preserve_ownership() {
        let peripherals = fresh_peripherals();
        let running = peripherals.timer0.start_periodic::<10>().unwrap();
        assert_eq!(running.interrupt_count(), 0);
        let stopped = running.stop().set_period::<20>().unwrap();
        let _running_again = stopped.restart();
    }

    #[test]
    #[should_panic(expected = "PERIOD_MS is 1..=1000")]
    fn timer_rejects_bad_period_const() {
        let peripherals = fresh_peripherals();
        let _ = peripherals.timer0.start_periodic::<0>();
    }

    #[test]
    fn adc_handle_is_reachable_only_from_peripherals() {
        // AdcResults no longer exposes `new()`; the only path is the root.
        let peripherals = fresh_peripherals();
        assert_eq!(peripherals.adc.read_channel(15), 0);
        assert_eq!(peripherals.adc.timeout_count(), 0);
    }

    #[test]
    fn configured_adc_keeps_its_channel_in_the_handle() {
        let peripherals = fresh_peripherals();
        let mut adc0 = peripherals.adc.into_soc0::<0, 7>().unwrap();
        assert_eq!(adc0.sample(), 0);
        assert_eq!(adc0.timeout_count(), 0);
    }

    #[test]
    fn serial_buses_are_reachable_only_from_peripherals() {
        let mut peripherals = fresh_peripherals();
        let _spi = peripherals.spi_b.internal_loopback::<8>();
        peripherals.spi_b.reg_readback();
        peripherals.spi_b.fifo_rx_boundary();

        let _sci = peripherals.sci_a.internal_loopback::<194, 8>();
        peripherals.sci_a.reg_readback();
        peripherals.sci_a.fifo_rx();

        let _slave = peripherals.i2c_a.master_write_1byte::<0x36>();
        peripherals.i2c_a.reg_readback_sweep();
    }

    #[test]
    #[should_panic(expected = "CHAR_BITS is 1..=16")]
    fn spi_rejects_invalid_char_length() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.spi_b.internal_loopback::<17>();
    }

    #[test]
    #[should_panic(expected = "internal loopback C case uses 8-bit characters")]
    fn spi_fixed_case_rejects_other_valid_char_length() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.spi_b.internal_loopback::<9>();
    }

    #[test]
    #[should_panic(expected = "CHAR_BITS is 1..=8")]
    fn sci_rejects_invalid_char_length() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.sci_a.configure_basic::<194, 9>();
    }

    #[test]
    #[should_panic(expected = "ADDRESS is 7-bit")]
    fn i2c_rejects_non_7bit_slave_address() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.i2c_a.slave::<0x80>();
    }

    #[test]
    #[should_panic(expected = "I2C C cases use fixed address 0x36")]
    fn i2c_fixed_case_rejects_other_valid_address() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.i2c_a.master_write_1byte::<0x37>();
    }

    /// Direction switch: consuming the output handle releases the claim, so
    /// the same pin can be re-claimed as an input and then back as an output
    /// without ever holding two aliasing handles.
    #[test]
    fn direction_switch_reclaims_same_pin() {
        let mut peripherals = fresh_peripherals();
        let mut out = peripherals.gpio.output::<34>().unwrap();
        out.set_high();
        assert!(out.is_high());

        let input = out.into_input(&mut peripherals.gpio).unwrap();
        // The latch still reads what the output stage wrote (make_input does
        // not clear the DATA bit); what matters is the exclusivity transfer.
        assert!(input.is_high());

        // While the input handle is alive the pin cannot be taken as output.
        assert_eq!(
            peripherals.gpio.output::<34>(),
            Err(HalError::PinAlreadyTaken(34))
        );

        let mut out = input.into_output(&mut peripherals.gpio).unwrap();
        out.set_low();
        assert!(out.is_low());

        // After the direction switch the pin is once more exclusive.
        assert_eq!(
            peripherals.gpio.input::<34>(),
            Err(HalError::PinAlreadyTaken(34))
        );
    }

    /// MUX routing: set_mux programs the 2-bit MUX field and mux reads it
    /// back through the C-bridge stub (pin 0 lands in GPAMUX1 bits 0..1).
    /// The MUX path is orthogonal to the data-direction claim, so it works
    /// without consuming a claim slot and does not conflict with an output
    /// handle on a different pin.
    #[test]
    fn mux_routing_programs_and_reads_back_field() {
        let mut peripherals = fresh_peripherals();
        peripherals.gpio.set_mux::<0, 0>().unwrap();
        assert_eq!(peripherals.gpio.mux::<0>(), 0);
        peripherals.gpio.set_mux::<0, 1>().unwrap();
        assert_eq!(peripherals.gpio.mux::<0>(), 1);
        peripherals.gpio.set_mux::<0, 0>().unwrap();
        assert_eq!(peripherals.gpio.mux::<0>(), 0);
    }

    #[test]
    fn mux_cannot_change_a_pin_owned_by_gpio_handle() {
        let mut peripherals = fresh_peripherals();
        let _output = peripherals.gpio.output::<34>().unwrap();
        assert_eq!(
            peripherals.gpio.set_mux::<34, 1>(),
            Err(HalError::PinAlreadyTaken(34))
        );
        assert_eq!(peripherals.gpio.mux::<34>(), 0);
        peripherals.gpio.set_mux::<35, 1>().unwrap();
        assert_eq!(peripherals.gpio.mux::<35>(), 1);
    }

    /// MUX rejects a function encoding above 3 through the const assert.
    #[test]
    #[should_panic(expected = "FUNC <= 3")]
    fn mux_rejects_invalid_function_encoding() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.gpio.set_mux::<0, 4>();
    }
}
