#include "DSP28x_Project.h"
extern void rust_sys_reset_release_setup(void);
volatile Uint16 called;
int main(void) {
    rust_sys_reset_release_setup();
    called = 1U;
    for (;;) {}
}