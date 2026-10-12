#![no_std]

mod user_main;
pub mod pac;
use crate::pac::ffi;

// ---- Top-level functions ----

use core::sync::atomic::{AtomicBool, Ordering};

static SYSTEM_INIT_DONE: AtomicBool = AtomicBool::new(false);

pub fn system_init() {
    if SYSTEM_INIT_DONE.load(Ordering::Relaxed) {
        return;  // already initialized, don't re-init
    }
    unsafe { ffi::f28035_system_init() };
    SYSTEM_INIT_DONE.store(true, Ordering::Relaxed);
}

pub fn delay_us(us: u16) {
    unsafe { ffi::f28035_delay_us(us) }
}

pub fn delay_ms(ms: u16) {
    for _ in 0..ms {
        delay_us(1000);
    }
}

// ---- Peripherals singleton (Level 3: ownership) ----

pub struct Peripherals {
    gpio: Gpio,
    adc: AdcResults,
    timer0: Timer0,
}

static PERIPHERALS_TAKEN: AtomicBool = AtomicBool::new(false);

impl Peripherals {
    pub fn take() -> Option<Self> {
        if PERIPHERALS_TAKEN.load(Ordering::Relaxed) {
            return None;  // already taken
        }
        PERIPHERALS_TAKEN.store(true, Ordering::Relaxed);
        Some(Self {
            gpio: Gpio,
            adc: AdcResults,
            timer0: Timer0::new(),
        })
    }

    /// Get GPIO handle. Consumes self? No, GPIO is Shareable.
    pub fn gpio(&mut self) -> &mut Gpio {
        &mut self.gpio
    }

    /// Get ADC handle.
    pub fn adc(&mut self) -> &mut AdcResults {
        &mut self.adc
    }

    /// Take Timer0. Consumes it from Peripherals.
    pub fn take_timer0(self) -> Timer0<Stopped> {
        self.timer0.into_stopped()
    }
}

// ---- GPIO ----

pub struct Gpio;

impl Gpio {
    pub fn output<const PIN: u16>(&self) -> Result<OutputPin, ()> {
        unsafe { ffi::f28035_gpio_set_output(PIN); }
        Ok(OutputPin { _pin: PIN })
    }

    pub fn input<const PIN: u16>(&self) -> Result<InputPin, ()> {
        unsafe { ffi::f28035_gpio_set_input(PIN); }
        Ok(InputPin { _pin: PIN })
    }
}

pub struct OutputPin {
    _pin: u16,
}

impl OutputPin {
    pub fn set_low(&mut self) {
        unsafe { ffi::f28035_gpio_set_low(self._pin) }
    }

    pub fn set_high(&mut self) {
        unsafe { ffi::f28035_gpio_set_high(self._pin) }
    }

    pub fn toggle(&mut self) {
        unsafe { ffi::f28035_gpio_toggle_pin(self._pin) }
    }

    /// Read back the pin's driven level. On C28x this reads the input buffer
    /// of the pin that was just configured as an output; used by the RAM
    /// smoke test to observe side effects.
    pub fn is_high(&self) -> bool {
        unsafe { ffi::f28035_gpio_read_input(self._pin) != 0 }
    }
}

pub struct InputPin {
    _pin: u16,
}

impl InputPin {
    pub fn read(&self) -> bool {
        unsafe { ffi::f28035_gpio_read_input(self._pin) != 0 }
    }
}

// ---- ADC ----

pub struct AdcResults;

impl AdcResults {
    pub fn configure_soc0<const CHANNEL: u16, const SAMPLE: u16>(&self) -> Result<(), ()> {
        unsafe { ffi::f28035_adc_configure_soc0(CHANNEL, SAMPLE) };
        Ok(())
    }

    pub fn sample<const CH: u16>(&self) -> Result<u16, AdcError> {
        let val = unsafe { ffi::f28035_adc_read_channel(CH) };
        if val == 0xFFFF {
            Err(AdcError::Timeout)
        } else {
            Ok(val)
        }
    }
}

// ---- Interrupt callback ----

#[unsafe(no_mangle)]
pub extern "C" fn rust_timer0_isr_callback() {
    // Default: do nothing
}
// ---- Timer0 state machine ----

pub struct Stopped;
pub struct Running;

pub struct Timer0<State = Stopped> {
    _state: core::marker::PhantomData<State>,
}

impl Timer0<Stopped> {
    pub fn new() -> Self {
        Self { _state: core::marker::PhantomData }
    }

    pub fn into_stopped(self) -> Self {
        self
    }

    pub fn start_periodic(self, period_us: u16) -> Timer0<Running> {
        unsafe { ffi::f28035_timer0_start_periodic(period_us) };
        Timer0 { _state: core::marker::PhantomData }
    }
}

impl Timer0<Running> {
    pub fn stop(self) -> Timer0<Stopped> {
        unsafe { ffi::f28035_timer0_stop() };
        Timer0 { _state: core::marker::PhantomData }
    }

    pub fn ack(&mut self) {
        unsafe { ffi::f28035_timer0_ack() };
    }
}
// ---- CriticalSection (Level 4: interrupt safety) ----

pub struct CriticalSection {
    _private: u16,
}

impl CriticalSection {
    pub fn new() -> Self {
        // 关中断，记录原来是不是开着
        let was_enabled = unsafe { ffi::f28035_interrupts_enabled() };
        unsafe { ffi::f28035_disable_interrupts() };
        Self { _private: was_enabled }
    }
}

impl Drop for CriticalSection {
    fn drop(&mut self) {
        // 如果进入前中断是开着的，才开
        if self._private != 0 {
            unsafe { ffi::f28035_enable_interrupts() };
        }
    }
}

/// Run a closure with interrupts disabled.
pub fn critical<F: FnOnce()>(f: F) {
    let _cs = CriticalSection::new();
    f();
    // _cs dropped here, interrupts re-enabled
}
#[derive(Debug, Copy, Clone, Eq, PartialEq)]
pub enum AdcError {
    Timeout,
}
