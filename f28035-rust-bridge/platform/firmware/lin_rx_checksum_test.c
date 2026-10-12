#include "DSP28x_Project.h"
extern void rust_lin_rx_checksum_setup(void);
volatile Uint16 called;
int main(void) {
    rust_lin_rx_checksum_setup();
    called = 1U;
    for (;;) {}
}