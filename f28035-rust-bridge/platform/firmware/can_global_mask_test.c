#include "DSP28x_Project.h"
extern void rust_can_global_mask_setup(void);
volatile Uint16 called;
int main(void) {
    rust_can_global_mask_setup();
    called = 1U;
    for (;;) {}
}