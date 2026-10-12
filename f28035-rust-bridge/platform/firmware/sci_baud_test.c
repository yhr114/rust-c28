#include "DSP28x_Project.h"
extern void rust_sci_baud_setup(void);
volatile Uint16 sci_baud_called;
int main(void) {
    rust_sci_baud_setup();
    sci_baud_called = 1U;
    for (;;) {}
}
