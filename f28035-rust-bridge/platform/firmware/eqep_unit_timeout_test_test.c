#include "DSP28x_Project.h"
extern void rust_eqep_unit_timeout_test_setup(void);
volatile Uint16 called;
int main(void) {
    rust_eqep_unit_timeout_test_setup();
    called = 1U;
    for (;;) {}
}