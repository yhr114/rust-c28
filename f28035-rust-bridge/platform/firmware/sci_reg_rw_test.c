#include "DSP28x_Project.h"
extern void rust_sci_reg_rw_setup(void);
volatile Uint16 sci_reg_called;
int main(void) {
    rust_sci_reg_rw_setup();
    sci_reg_called = 1U;
    for (;;) {}
}
