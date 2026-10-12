#include "DSP28x_Project.h"
extern void rust_sys_xrs_runtime_setup(void);
volatile Uint16 called;
int main(void) {
    rust_sys_xrs_runtime_setup();
    called = 1U;
    for (;;) {}
}