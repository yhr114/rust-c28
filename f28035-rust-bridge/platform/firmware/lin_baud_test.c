#include "DSP28x_Project.h"
extern void rust_lin_baud_setup(void);
volatile Uint16 lin_baud_called;
int main(void) {
    rust_lin_baud_setup();
    lin_baud_called = 1U;
    for (;;) {}
}
