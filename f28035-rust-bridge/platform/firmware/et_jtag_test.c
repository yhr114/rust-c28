#include "DSP28x_Project.h"
extern void rust_et_jtag_setup(void);
volatile Uint16 called;
int main(void) {
    rust_et_jtag_setup();
    called = 1U;
    for (;;) {}
}