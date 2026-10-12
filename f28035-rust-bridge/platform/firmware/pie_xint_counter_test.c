#include "DSP28x_Project.h"
extern void rust_pie_xint_counter_setup(void);
volatile Uint16 called;
int main(void) {
    rust_pie_xint_counter_setup();
    called = 1U;
    for (;;) {}
}