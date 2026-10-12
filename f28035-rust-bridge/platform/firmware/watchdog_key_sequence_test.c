#include "DSP28x_Project.h"
extern void rust_watchdog_key_sequence_setup(void);
volatile Uint16 called;
int main(void) {
    rust_watchdog_key_sequence_setup();
    called = 1U;
    for (;;) {}
}