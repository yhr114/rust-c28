//! Auto-generated peripheral module. Do not hand-edit; see split-apply.py.
use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio39_low() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut gpio39 = peripherals.gpio.output::<39>();
    gpio39.set_low();
}

/// Configure GPIO2 as an output and drive it low through the safe HAL.
///
/// This keeps the same true-Rust path as the GPIO34/GPIO39 pilots, but targets
/// a GPIOA pin so the MIR backend exercises the low-port register mapping.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio2_low() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut gpio2 = peripherals.gpio.output::<2>();
    gpio2.set_low();
}

/// Configure GPIO3 as an output and drive it low through the safe HAL.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio3_low() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut gpio3 = peripherals.gpio.output::<3>();
    gpio3.set_low();
}

/// Configure GPIO2 and GPIO3 as outputs and drive both low through the safe HAL.
///
/// This is the two-pin hardware case: the application code owns both typed
/// `OutputPin` handles and never reaches for raw registers or direct FFI.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio2_3_low() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut gpio2 = peripherals.gpio.output::<2>();
    let mut gpio3 = peripherals.gpio.output::<3>();
    gpio2.set_low();
    gpio3.set_low();
}

/// Configure GPIO30 as an output and drive it low through the safe HAL.
///
/// GPIO30 exercises the GPA MUX2/DIR/DAT path, complementing the GPIO2/GPIO3
/// low-pin checks and the GPIO34/GPIO39 GPIOB checks.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio30_low() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut gpio30 = peripherals.gpio.output::<30>();
    gpio30.set_low();
}

/// Full GPIO output sweep for RAM/JTAG verification.
///
/// This configures every F28035 GPIO number supported by the current PAC
/// (GPIO0..GPIO44) through typed Safe HAL handles, then drives each pin low
/// and high.  The C harness snapshots the final GPIO mux/direction/data
/// registers and prints a per-pin PASS table; the function itself contains no
/// direct FFI or unsafe block.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio_sweep_outputs() {
    system_init();

    let peripherals = Peripherals::take().expect("peripherals already taken");
    let mut gpio = peripherals.gpio;
    gpio_sweep_outputs_for_all_pins!(gpio);
}

/// Main application entry point.
///
/// Put the F28035 control loop, state machines, protection logic, and calls to
/// safe peripheral wrappers in this function.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio34_output_basic() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin34 = peripherals.gpio.output::<34>();
    pin34.set_low();
    pin34.set_high();
    pin34.set_low();
}

/// Second Safe HAL vertical template: `gpio_output_readback_basic`.
///
/// Mirrors the original C case's write/read sequence: high -> read high,
/// low -> read low, high -> read high.  The Safe HAL body contains no
/// `unsafe` block and no direct FFI declaration; both writes and read-backs
/// go through the typed [`OutputPin`] handle.  The C harness still snapshots
/// the final GPIO registers after this function returns, but the write/read
/// assertion now lives in Rust and is lowered by the MIR backend.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio34_output_readback() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin34 = peripherals.gpio.output::<34>();
    pin34.set_high();
    if !pin34.is_high() {
        loop {}
    }
    pin34.set_low();
    if !pin34.is_low() {
        loop {}
    }
    pin34.set_high();
    if !pin34.is_high() {
        loop {}
    }
}

/// Third Safe HAL vertical template: `gpio_toggle_basic`.
///
/// Mirrors the original C case: GPIO34 starts low, then toggles
/// `GPIO_TOGGLE_BASIC_COUNT` (8, an even count) times, so the final level is
/// low again.  The body uses typed `OutputPin` handles (`set_low` + eight
/// `toggle` calls); no `unsafe` block, no direct FFI declaration.  The C
/// harness (`gpio34_toggle_test.c`) reads `GPBDAT` back after this function
/// returns (must be 0 after 8 even toggles), then issues two TOGGLE commands
/// of its own and records 1 then 0, proving the toggle path flips the pin.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio34_toggle_basic() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin34 = peripherals.gpio.output::<34>();
    pin34.set_low();
    pin34.toggle(); // 1
    pin34.toggle(); // 2
    pin34.toggle(); // 3
    pin34.toggle(); // 4
    pin34.toggle(); // 5
    pin34.toggle(); // 6
    pin34.toggle(); // 7
    pin34.toggle(); // 8 (even -> back to low)
}

/// Direction-switch Safe HAL mirror of `gpio_direction_switch_basic`.
///
/// GPIO34 starts as an output driven high, is reconfigured as an input, then
/// reconfigured back as an output driven low.  This exercises the backend's
/// input-configuration path (`f28035_gpio_make_input`) and the same pin being
/// reconfigured across a direction switch, which the earlier pure-output
/// templates never touch.  The body contains no `unsafe` block and no direct
/// FFI declaration.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio34_direction_switch() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    let mut pin34 = peripherals.gpio.output::<34>();
    pin34.set_high();
    let _input34 = peripherals.gpio.input::<34>();
    let mut pin34 = peripherals.gpio.output::<34>();
    pin34.set_low();
}

/// MUX-switch Safe HAL mirror of gpio_mux_basic, phase 1.
///
/// GPIO0's MUX field starts at 0 (GPIO); this phase programs it to 1
/// (EPWM1A).  The C harness (gpio0_mux_switch_test.c) snapshots GPAMUX1
/// after this function returns (must be 1), proving the set_mux write really
/// took effect on silicon.  The body contains no unsafe block and no direct
/// FFI declaration.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio0_mux_to_epwm1a() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    peripherals
        .gpio
        .set_mux::<0, 1>()
        .expect("mux GPIO0 to EPWM1A");
}

/// MUX-switch Safe HAL mirror of gpio_mux_basic, phase 2.
///
/// Restores GPIO0's MUX field back to 0 (GPIO).  The C harness snapshots
/// GPAMUX1 after this function returns (must be 0), closing the 0 -> 1 -> 0
/// round trip that the original C case verifies.  The harness resets the
/// one-shot peripheral lock between phases so the second 	ake succeeds.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio0_mux_restore_gpio() {
    system_init();

    let mut peripherals = Peripherals::take().expect("peripherals already taken");
    peripherals
        .gpio
        .set_mux::<0, 0>()
        .expect("restore GPIO0 to GPIO");
}
/// Safe HAL bridge case for `epwm_up_aq_smoke`.
///
/// Configures ePWM1 up-count mode: period=99, compare=40.  The C harness
/// reads TBPRD / CMPA / AQCTLA / CTLMODE and GPIO0 MUX (must be 1) after return.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio_pin_walk_setup() {
    system_init();
}

/// can_pin_mux_basic.
#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio_xint_falling_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio_xint_rising_setup() {
    system_init();
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_gpio_input_setup() {
    system_init();
}


#[unsafe(no_mangle)]
pub extern "C" fn rust_demo_led_blink_setup() {
    system_init();
}