#include "DSP28x_Project.h"
extern void rust_spi_multiple_frame_loopback_setup(void);
volatile Uint16 called;
int main(void) {
    rust_spi_multiple_frame_loopback_setup();
    called = 1U;
    for (;;) {}
}