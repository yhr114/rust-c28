#include "DSP28x_Project.h"
extern void rust_can_mbox32_sweep_setup(void);
volatile Uint16 called;
int main(void) {
    rust_can_mbox32_sweep_setup();
    called = 1U;
    for (;;) {}
}