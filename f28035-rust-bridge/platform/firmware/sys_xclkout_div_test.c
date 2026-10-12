#include "DSP28x_Project.h"
extern void rust_sys_xclkout_div_setup(void);
volatile Uint16 called;
int main(void) {
    rust_sys_xclkout_div_setup();
    called = 1U;
    for (;;) {}
}