#include "DSP28x_Project.h"
extern void rust_adc_trig_timer0_setup(void);
volatile Uint16 called;
int main(void) {
    rust_adc_trig_timer0_setup();
    called = 1U;
    for (;;) {}
}