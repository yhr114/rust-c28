#include "DSP28x_Project.h"
extern void rust_spi_fifo_rx_setup(void);
volatile Uint16 called;
int main(void) {
    rust_spi_fifo_rx_setup();
    called = 1U;
    for (;;) {}
}
