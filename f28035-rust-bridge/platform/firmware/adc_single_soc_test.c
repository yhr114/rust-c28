#include "DSP28x_Project.h"
extern void rust_adc_single_soc_setup(void);
extern Uint16 f28035_adc_clock_enabled(void);
extern Uint16 f28035_adc_clkdiv2_enabled(void);
extern Uint16 f28035_adc_ctl1_configured(void);
extern Uint16 f28035_adc_int1_configured(void);
extern Uint16 f28035_adc_soc0_channel(void);
extern Uint16 f28035_adc_soc0_acqps(void);
extern Uint16 f28035_adc_soc0_trigger(void);

volatile Uint16 rust_adc_single_soc_called;
volatile Uint16 rust_adc_single_soc_clock;
volatile Uint16 rust_adc_single_soc_clkdiv2;
volatile Uint16 rust_adc_single_soc_ctl1;
volatile Uint16 rust_adc_single_soc_int1;
volatile Uint16 rust_adc_single_soc_channel;
volatile Uint16 rust_adc_single_soc_acqps;
volatile Uint16 rust_adc_single_soc_trigger;

int main(void) {
    rust_adc_single_soc_setup();
    rust_adc_single_soc_clock   = f28035_adc_clock_enabled();
    rust_adc_single_soc_clkdiv2  = f28035_adc_clkdiv2_enabled();
    rust_adc_single_soc_ctl1     = f28035_adc_ctl1_configured();
    rust_adc_single_soc_int1     = f28035_adc_int1_configured();
    rust_adc_single_soc_channel  = f28035_adc_soc0_channel();
    rust_adc_single_soc_acqps     = f28035_adc_soc0_acqps();
    rust_adc_single_soc_trigger  = f28035_adc_soc0_trigger();
    rust_adc_single_soc_called = 1U;
    for (;;) {}
}
