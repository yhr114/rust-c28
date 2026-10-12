#include "DSP28x_Project.h"
extern void rust_pie_fill_u32_setup(void);
volatile Uint16 called;
int main(void) {
    rust_pie_fill_u32_setup();
    called = 1U;
    for (;;) {}
}