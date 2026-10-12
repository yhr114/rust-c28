#include "DSP28x_Project.h"
extern void rust_i2c_write1_setup(void);
volatile Uint16 i2c_w1_called;
int main(void) {
    rust_i2c_write1_setup();
    i2c_w1_called = 1U;
    for (;;) {}
}