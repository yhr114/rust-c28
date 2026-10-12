#include "DSP28x_Project.h"
extern void rust_watchdog_prescaler_setup(void);
volatile Uint16 called;
int main(void) {
    rust_watchdog_prescaler_setup();
    called = 1U;
    for (;;) {}
}