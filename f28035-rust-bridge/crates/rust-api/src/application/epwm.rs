//! Auto-generated peripheral module. Do not hand-edit; see split-apply.py.
use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_cmp_basic() {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pwm = peripherals.pwm1.configure::<PWM1_PERIOD_TICKS>();
    pwm.set_compare(2048);
}

/// Independent Safe HAL bridge case for `timer0_periodic_basic`.
///
/// Starts Timer0 in 10 ms periodic mode.  The hardware harness keeps the CPU
/// alive after return so DSS can observe multiple interrupts.
#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_up_aq_setup() {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pwm = peripherals.pwm1.configure::<99>();
    pwm.set_compare(40);
}

/// Safe HAL bridge case for `adc_eoc_irq_basic`: sample channel 13.
/// The C harness reads ADCINT1 flag and SOC0 overflow after return.
#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_event_socb_setup() {
    system_init();
    let peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pwm = peripherals.pwm1.configure::<99>();
    pwm.set_compare(40);
}

/// Safe HAL bridge case for `epwm_event_int_soca_smoke`: up-count + INT+SOCA.
#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_event_int_soca_setup() {
    system_init();
    let peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pwm = peripherals.pwm1.configure::<99>();
    pwm.set_compare(40);
}

/// epwm_deadband_basic.
#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_deadband_setup() {
    system_init();
    let p = Peripherals::take().expect("taken");
    let mut pwm = p.pwm1.configure::<99>();
    pwm.set_compare(40);
}

/// epwm_tripzone_swforce_basic.
#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_tz_swforce_setup() {
    system_init();
    let p = Peripherals::take().expect("taken");
    let mut pwm = p.pwm1.configure::<99>();
    pwm.set_compare(40);
}

/// epwm_tz_external_basic.
#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_tz_external_setup() {
    system_init();
    let p = Peripherals::take().expect("taken");
    let mut pwm = p.pwm1.configure::<99>();
    pwm.set_compare(40);
}

/// epwm_updown_aq_smoke.
#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_updown_aq_setup() {
    system_init();
    let p = Peripherals::take().expect("taken");
    let mut pwm = p.pwm1.configure::<99>();
    pwm.set_compare(20);
}

/// i2c_write1_basic.
#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_reg_rw_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_clkdiv_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_cmp_boundary_setup() {
    system_init();
}


#[unsafe(no_mangle)]
pub extern "C" fn rust_epwm_tz_ext_simple_setup() {
    system_init();
}
