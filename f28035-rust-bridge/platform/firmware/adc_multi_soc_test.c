#include "DSP28x_Project.h"
extern void rust_adc_multi_soc_setup(void);
volatile Uint16 called;
int main(void) {
    rust_adc_multi_soc_setup();
    called = 1U;
    for (;;) {}
}