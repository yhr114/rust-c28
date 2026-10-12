#include "DSP28x_Project.h"
extern void rust_ecap_reg_rw_setup(void);
volatile Uint16 ecap_reg_called;
int main(void) {
    rust_ecap_reg_rw_setup();
    ecap_reg_called = 1U;
    for (;;) {}
}
