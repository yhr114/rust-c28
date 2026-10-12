#include "DSP28x_Project.h"
extern void rust_can_rx_extid_setup(void);
volatile Uint16 called;
int main(void) {
    rust_can_rx_extid_setup();
    called = 1U;
    for (;;) {}
}