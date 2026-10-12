#include "DSP28x_Project.h"
extern void rust_i2c_write_then_read_setup(void);
volatile Uint16 called;
int main(void) {
    rust_i2c_write_then_read_setup();
    called = 1U;
    for (;;) {}
}