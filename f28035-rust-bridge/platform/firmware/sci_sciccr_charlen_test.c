#include "DSP28x_Project.h"
extern void rust_sci_sciccr_charlen_setup(void);
volatile Uint16 called;
int main(void) {
    rust_sci_sciccr_charlen_setup();
    called = 1U;
    for (;;) {}
}