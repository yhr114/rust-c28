#include "DSP28x_Project.h"
extern void rust_eqep_register_wr_setup(void);
volatile Uint16 called;
int main(void) {
    rust_eqep_register_wr_setup();
    called = 1U;
    for (;;) {}
}