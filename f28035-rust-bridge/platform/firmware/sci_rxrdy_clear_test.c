#include "DSP28x_Project.h"
extern void rust_sci_rxrdy_clear_setup(void);
volatile Uint16 called;
int main(void) {
    rust_sci_rxrdy_clear_setup();
    called = 1U;
    for (;;) {}
}