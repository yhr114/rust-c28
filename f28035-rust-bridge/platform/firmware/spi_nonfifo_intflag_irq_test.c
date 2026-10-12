#include "DSP28x_Project.h"
extern void rust_spi_nonfifo_intflag_irq_setup(void);
volatile Uint16 called;
int main(void) {
    rust_spi_nonfifo_intflag_irq_setup();
    called = 1U;
    for (;;) {}
}