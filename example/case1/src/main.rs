#![no_std]

use f28035_safe_hal::{Peripherals, delay_us, system_init};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();

    let mut peripherals = Peripherals::take().unwrap();
    let button = peripherals.gpio.input::<34>().expect("GPIO34 input rejected");
    let mut gpio39 = peripherals.gpio.output::<39>().expect("GPIO39 output rejected");
    let mut adc0 = peripherals.adc.into_soc0::<0, 7>().expect("ADC0 setup rejected");

    loop {
        let adc = adc0.sample();
        let button_high = button.read();
        if button_high || adc > 2048 {
            gpio39.set_low();
        }
        delay_us(50_000);
    }
}
