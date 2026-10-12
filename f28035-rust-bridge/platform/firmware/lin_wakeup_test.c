#include "DSP28x_Project.h"
extern void rust_lin_wakeup_setup(void);
volatile Uint16 called;
int main(void) {
    rust_lin_wakeup_setup();
    called = 1U;
    for (;;) {}
}