#include "DSP28x_Project.h"
extern void rust_i2c_nack_setup(void);
volatile Uint16 called;
int main(void) {
    rust_i2c_nack_setup();
    called = 1U;
    for (;;) {}
}
