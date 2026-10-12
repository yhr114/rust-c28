#include "DSP28x_Project.h"

/* adc_eoc_irq_basic: Rust mirror configures ADC SOC0 channel=13, samples it,
 * then the C harness reads ADCINT1 flag, SOC0 overflow, and timeout count.
 */
extern void rust_adc_eoc_irq_setup(void);
extern Uint16 f28035_adc_int1_flag(void);
extern Uint16 f28035_adc_soc0_overflow(void);
extern Uint16 f28035_adc_timeouts(void);

volatile Uint16 rust_adc_eoc_irq_called;
volatile Uint16 rust_adc_eoc_irq_int1_flag;
volatile Uint16 rust_adc_eoc_irq_soc0_overflow;
volatile Uint16 rust_adc_eoc_irq_timeouts;

int main(void)
{
    rust_adc_eoc_irq_setup();

    rust_adc_eoc_irq_int1_flag    = f28035_adc_int1_flag();
    rust_adc_eoc_irq_soc0_overflow = f28035_adc_soc0_overflow();
    rust_adc_eoc_irq_timeouts     = f28035_adc_timeouts();

    rust_adc_eoc_irq_called = 1U;

    for (;;) {
    }
}
