#include "DSP28x_Project.h"
extern void rust_watchdog_disable_setup(void);
volatile Uint16 called;
int main(void) {
    rust_watchdog_disable_setup();
    called = 1U;
    for (;;) {}
}