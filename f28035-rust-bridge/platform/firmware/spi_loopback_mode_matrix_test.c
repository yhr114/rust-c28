#include "DSP28x_Project.h"
extern void rust_spi_loopback_mode_matrix_setup(void);
volatile Uint16 called;
int main(void) {
    rust_spi_loopback_mode_matrix_setup();
    called = 1U;
    for (;;) {}
}