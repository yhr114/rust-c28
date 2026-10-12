#include "DSP28x_Project.h"
extern void rust_hrcap_dual_instance_setup(void);
volatile Uint16 called;
int main(void) {
    rust_hrcap_dual_instance_setup();
    called = 1U;
    for (;;) {}
}