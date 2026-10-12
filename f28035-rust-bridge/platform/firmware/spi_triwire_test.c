#include "DSP28x_Project.h"
extern void rust_spi_triwire_setup(void);
volatile Uint16 called;
int main(void) {
    rust_spi_triwire_setup();
    called = 1U;
    for (;;) {}
}
