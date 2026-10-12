#include "DSP28x_Project.h"
extern void rust_can_pin_mux_setup(void);
extern Uint16 f28035_gpio_mux(Uint16 pin);

volatile Uint16 can_mux_called, can_mux30, can_mux31;

int main(void) {
    rust_can_pin_mux_setup();
    can_mux30   = f28035_gpio_mux(30);
    can_mux31   = f28035_gpio_mux(31);
    can_mux_called = 1U;
    for (;;) {}
}