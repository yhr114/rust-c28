#include "DSP28x_Project.h"
extern void rust_demo_led_blink_setup(void);
volatile Uint16 called;
int main(void) {
    rust_demo_led_blink_setup();
    called = 1U;
    for (;;) {}
}