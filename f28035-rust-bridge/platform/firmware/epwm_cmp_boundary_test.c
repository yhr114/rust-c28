#include "DSP28x_Project.h"
extern void rust_epwm_cmp_boundary_setup(void);
volatile Uint16 called;
int main(void) {
    rust_epwm_cmp_boundary_setup();
    called = 1U;
    for (;;) {}
}