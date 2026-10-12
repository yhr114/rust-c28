#include "DSP28x_Project.h"
extern void rust_i2c_read1_setup(void);
volatile Uint16 i2c_r1_called;
int main(void) {
    rust_i2c_read1_setup();
    i2c_r1_called = 1U;
    for (;;) {}
}
