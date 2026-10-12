#include "DSP28x_Project.h"
extern void rust_hrcap_reg_rw_setup(void);
volatile Uint16 called;
int main(void) {
    rust_hrcap_reg_rw_setup();
    called = 1U;
    for (;;) {}
}