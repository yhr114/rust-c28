#include "DSP28x_Project.h"
extern void rust_sys_divsel_setup(void);
volatile Uint16 called;
int main(void) {
    rust_sys_divsel_setup();
    called = 1U;
    for (;;) {}
}