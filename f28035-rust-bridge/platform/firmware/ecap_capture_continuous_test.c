#include "DSP28x_Project.h"
extern void rust_ecap_capture_continuous_setup(void);
volatile Uint16 called;
int main(void) {
    rust_ecap_capture_continuous_setup();
    called = 1U;
    for (;;) {}
}