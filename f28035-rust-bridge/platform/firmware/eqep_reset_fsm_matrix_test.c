#include "DSP28x_Project.h"
extern void rust_eqep_reset_fsm_matrix_setup(void);
volatile Uint16 called;
int main(void) {
    rust_eqep_reset_fsm_matrix_setup();
    called = 1U;
    for (;;) {}
}