use crate::{Peripherals, system_init};

macro_rules! gpio_sweep_outputs_for_all_pins {
    ($gpio:ident) => {{
        let mut pin0 = $gpio.output::<0>();
        let mut pin1 = $gpio.output::<1>();
        let mut pin2 = $gpio.output::<2>();
        let mut pin3 = $gpio.output::<3>();
        let mut pin4 = $gpio.output::<4>();
        let mut pin5 = $gpio.output::<5>();
        let mut pin6 = $gpio.output::<6>();
        let mut pin7 = $gpio.output::<7>();
        let mut pin8 = $gpio.output::<8>();
        let mut pin9 = $gpio.output::<9>();
        let mut pin10 = $gpio.output::<10>();
        let mut pin11 = $gpio.output::<11>();
        let mut pin12 = $gpio.output::<12>();
        let mut pin13 = $gpio.output::<13>();
        let mut pin14 = $gpio.output::<14>();
        let mut pin15 = $gpio.output::<15>();
        let mut pin16 = $gpio.output::<16>();
        let mut pin17 = $gpio.output::<17>();
        let mut pin18 = $gpio.output::<18>();
        let mut pin19 = $gpio.output::<19>();
        let mut pin20 = $gpio.output::<20>();
        let mut pin21 = $gpio.output::<21>();
        let mut pin22 = $gpio.output::<22>();
        let mut pin23 = $gpio.output::<23>();
        let mut pin24 = $gpio.output::<24>();
        let mut pin25 = $gpio.output::<25>();
        let mut pin26 = $gpio.output::<26>();
        let mut pin27 = $gpio.output::<27>();
        let mut pin28 = $gpio.output::<28>();
        let mut pin29 = $gpio.output::<29>();
        let mut pin30 = $gpio.output::<30>();
        let mut pin31 = $gpio.output::<31>();
        let mut pin32 = $gpio.output::<32>();
        let mut pin33 = $gpio.output::<33>();
        let mut pin34 = $gpio.output::<34>();
        let mut pin35 = $gpio.output::<35>();
        let mut pin36 = $gpio.output::<36>();
        let mut pin37 = $gpio.output::<37>();
        let mut pin38 = $gpio.output::<38>();
        let mut pin39 = $gpio.output::<39>();
        let mut pin40 = $gpio.output::<40>();
        let mut pin41 = $gpio.output::<41>();
        let mut pin42 = $gpio.output::<42>();
        let mut pin43 = $gpio.output::<43>();
        let mut pin44 = $gpio.output::<44>();

        pin0.set_low();
        pin0.set_high();
        pin1.set_low();
        pin1.set_high();
        pin2.set_low();
        pin2.set_high();
        pin3.set_low();
        pin3.set_high();
        pin4.set_low();
        pin4.set_high();
        pin5.set_low();
        pin5.set_high();
        pin6.set_low();
        pin6.set_high();
        pin7.set_low();
        pin7.set_high();
        pin8.set_low();
        pin8.set_high();
        pin9.set_low();
        pin9.set_high();
        pin10.set_low();
        pin10.set_high();
        pin11.set_low();
        pin11.set_high();
        pin12.set_low();
        pin12.set_high();
        pin13.set_low();
        pin13.set_high();
        pin14.set_low();
        pin14.set_high();
        pin15.set_low();
        pin15.set_high();
        pin16.set_low();
        pin16.set_high();
        pin17.set_low();
        pin17.set_high();
        pin18.set_low();
        pin18.set_high();
        pin19.set_low();
        pin19.set_high();
        pin20.set_low();
        pin20.set_high();
        pin21.set_low();
        pin21.set_high();
        pin22.set_low();
        pin22.set_high();
        pin23.set_low();
        pin23.set_high();
        pin24.set_low();
        pin24.set_high();
        pin25.set_low();
        pin25.set_high();
        pin26.set_low();
        pin26.set_high();
        pin27.set_low();
        pin27.set_high();
        pin28.set_low();
        pin28.set_high();
        pin29.set_low();
        pin29.set_high();
        pin30.set_low();
        pin30.set_high();
        pin31.set_low();
        pin31.set_high();
        pin32.set_low();
        pin32.set_high();
        pin33.set_low();
        pin33.set_high();
        pin34.set_low();
        pin34.set_high();
        pin35.set_low();
        pin35.set_high();
        pin36.set_low();
        pin36.set_high();
        pin37.set_low();
        pin37.set_high();
        pin38.set_low();
        pin38.set_high();
        pin39.set_low();
        pin39.set_high();
        pin40.set_low();
        pin40.set_high();
        pin41.set_low();
        pin41.set_high();
        pin42.set_low();
        pin42.set_high();
        pin43.set_low();
        pin43.set_high();
        pin44.set_low();
        pin44.set_high();
    }};
}

/// ADC threshold used by the current protection/control policy.
pub const ADC_STATUS_THRESHOLD: u16 = 2048;

/// ePWM1 period used by the current control loop.
pub const PWM1_PERIOD_TICKS: u16 = 4095;

/// Pure Safe Rust control policy for the status output.
///
/// Keeping this as a small const function lets host tests exercise the business
/// rule while the optimized MIR still lowers to the existing C28x pattern.
#[inline(always)]
pub const fn status_high(sample: u16) -> bool {
    sample >= ADC_STATUS_THRESHOLD
}

/// Pure Safe Rust PWM compare policy. The hardware bridge also clamps CMPA,
/// but this lets the intended behavior be unit-tested without the board.
#[inline(always)]
pub const fn pwm_compare_from_sample(sample: u16) -> u16 {
    if sample > PWM1_PERIOD_TICKS {
        PWM1_PERIOD_TICKS
    } else {
        sample
    }
}

/// Independent Safe HAL bridge case for `adc_sample_basic`.
///
/// The application owns the ADC through [`Peripherals`] and performs one SOC0
/// sample of ADC channel 0.  The C harness snapshots the returned value and
/// ADC firmware counters after this function returns.

pub mod adc;
pub mod can;
pub mod ecap;
pub mod epwm;
pub mod eqep;
pub mod gpio;
pub mod hrcap;
pub mod i2c;
pub mod integration;
pub mod lin;
pub mod pie;
pub mod sci;
pub mod spi;
pub mod sys;
pub mod timer;
pub mod watchdog;
pub use adc::*;
pub use can::*;
pub use ecap::*;
pub use epwm::*;
pub use eqep::*;
pub use gpio::*;
pub use hrcap::*;
pub use i2c::*;
pub use integration::*;
pub use lin::*;
pub use pie::*;
pub use sci::*;
pub use spi::*;
pub use sys::*;
pub use timer::*;
pub use watchdog::*;
