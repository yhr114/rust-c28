#include "DSP28x_Project.h"
extern void rust_gpio_pin_walk_setup(void);

volatile Uint16 pinwalk_called;

int main(void) {
    rust_gpio_pin_walk_setup();
    pinwalk_called = 1U;
    for (;;) {}
}