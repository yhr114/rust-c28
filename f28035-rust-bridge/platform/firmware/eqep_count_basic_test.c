#include "DSP28x_Project.h"
extern void rust_eqep_count_basic_setup(void);
volatile Uint16 called;
int main(void) {
    rust_eqep_count_basic_setup();
    called = 1U;
    for (;;) {}
}