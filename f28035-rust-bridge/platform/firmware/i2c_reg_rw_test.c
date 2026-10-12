#include "DSP28x_Project.h"
extern void rust_i2c_reg_rw_setup(void);
volatile Uint16 i2c_reg_called;
int main(void) {
    rust_i2c_reg_rw_setup();
    i2c_reg_called = 1U;
    for (;;) {}
}
