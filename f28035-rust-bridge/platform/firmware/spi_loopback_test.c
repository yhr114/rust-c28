#include "DSP28x_Project.h"
extern void rust_spi_loopback_setup(void);
volatile Uint16 spi_lb_called;
int main(void) {
    rust_spi_loopback_setup();
    spi_lb_called = 1U;
    for (;;) {}
}
