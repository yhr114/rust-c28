#include "DSP28x_Project.h"
extern void rust_lin_reg_rw_setup(void);
volatile Uint16 lin_reg_called;
int main(void) {
    rust_lin_reg_rw_setup();
    lin_reg_called = 1U;
    for (;;) {}
}
