#include "DSP28x_Project.h"
extern void rust_sci_loopback_setup(void);
volatile Uint16 sci_lb_called;
int main(void) {
    rust_sci_loopback_setup();
    sci_lb_called = 1U;
    for (;;) {}
}