#include "DSP28x_Project.h"
extern void rust_gpio_xint_rising_setup(void);
volatile Uint16 called;
int main(void) {
    rust_gpio_xint_rising_setup();
    called = 1U;
    for (;;) {}
}