#include "DSP28x_Project.h"
extern void rust_epwm_tz_external_setup(void);
volatile Uint16 called;
int main(void) {
    rust_epwm_tz_external_setup();
    called = 1U;
    for (;;) {}
}