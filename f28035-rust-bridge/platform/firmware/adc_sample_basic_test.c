#include "DSP28x_Project.h"

extern Uint16 rust_adc_sample_basic(void);

volatile Uint16 rust_adc_sample_basic_called;
volatile Uint16 rust_adc_sample_basic_value;
volatile Uint16 rust_adc_sample_basic_adcresult0;

int main(void)
{
    rust_adc_sample_basic_value = rust_adc_sample_basic();
    rust_adc_sample_basic_adcresult0 = AdcResult.ADCRESULT0;
    rust_adc_sample_basic_called = 1U;

    for (;;) {
    }
}
