#include "DSP28x_Project.h"
extern void rust_sys_watchdog_timeout_setup(void);
volatile Uint16 called;
int main(void) {
    rust_sys_watchdog_timeout_setup();
    called = 1U;
    for (;;) {}
}