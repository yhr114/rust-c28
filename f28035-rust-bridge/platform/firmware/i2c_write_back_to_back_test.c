#include "DSP28x_Project.h"
extern void rust_i2c_write_back_to_back_setup(void);
volatile Uint16 called;
int main(void) {
    rust_i2c_write_back_to_back_setup();
    called = 1U;
    for (;;) {}
}