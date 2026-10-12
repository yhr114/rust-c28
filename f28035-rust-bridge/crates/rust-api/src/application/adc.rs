//! Auto-generated peripheral module. Do not hand-edit; see split-apply.py.
use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_sample_basic() -> u16 {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    peripherals.adc.sample::<0>()
}

/// Independent Safe HAL bridge case for `epwm_cmp_basic`.
///
/// Configures ePWM1A with the production control-loop period and writes a
/// mid-scale compare value through the typed [`Pwm1Output`] handle.
#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_eoc_irq_setup() {
    system_init();
    let peripherals = Peripherals::take().expect("peripherals already taken");
    peripherals.adc.sample::<13>();
}

/// Safe HAL bridge case for `adc_clkdiv2en_basic`: sample channel 0.
#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_clkdiv2en_setup() {
    system_init();
    let peripherals = Peripherals::take().expect("peripherals already taken");
    peripherals.adc.sample::<0>();
}

/// Safe HAL bridge case for `adc_single_soc_basic`: sample channel 13.
/// The C harness reads SOC0 config (channel/acqps/trigger) after return.
#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_single_soc_setup() {
    system_init();
    let peripherals = Peripherals::take().expect("peripherals already taken");
    peripherals.adc.sample::<13>();
}

/// Safe HAL bridge case for `epwm_event_socb_smoke`: up-count + SOCB event.
/// The C harness reads TBPRD/CMPA/AQCTLA/SOCB_EN/SOCB_PRD after return.
#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_reg_rw_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_reset_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_socctl_sweep_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_multi_soc_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_int_cont_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_int_overflow_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_adc_trig_timer0_setup() {
    system_init();
}

