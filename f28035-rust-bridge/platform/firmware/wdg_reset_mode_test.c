#include "DSP28x_Project.h"
extern void rust_wdg_reset_mode_setup(void);
volatile Uint16 called;
int main(void) {
    rust_wdg_reset_mode_setup();
    called = 1U;
    for (;;) {}
}