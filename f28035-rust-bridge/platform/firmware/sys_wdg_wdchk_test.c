#include "DSP28x_Project.h"
extern void rust_sys_wdg_wdchk_setup(void);
volatile Uint16 called;
int main(void) {
    rust_sys_wdg_wdchk_setup();
    called = 1U;
    for (;;) {}
}