#include "DSP28x_Project.h"
extern void rust_hrcap_clock_reset_setup(void);
volatile Uint16 called;
int main(void) {
    rust_hrcap_clock_reset_setup();
    called = 1U;
    for (;;) {}
}