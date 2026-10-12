#include "DSP28x_Project.h"
extern void rust_adc_clkdiv2en_setup(void);
extern Uint16 f28035_adc_timeouts(void);
volatile Uint16 rust_adc_clkdiv2en_called;
volatile Uint16 rust_adc_clkdiv2en_timeouts;
int main(void) {
    rust_adc_clkdiv2en_setup();
    rust_adc_clkdiv2en_timeouts = f28035_adc_timeouts();
    rust_adc_clkdiv2en_called = 1U;
    for (;;) {}
}
