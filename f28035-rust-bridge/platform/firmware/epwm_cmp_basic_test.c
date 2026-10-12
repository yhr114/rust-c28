#include "DSP28x_Project.h"

extern void rust_epwm_cmp_basic(void);

volatile Uint16 rust_epwm_cmp_basic_called;
volatile Uint16 rust_epwm_cmp_basic_gpio0_mux;
volatile Uint16 rust_epwm_cmp_basic_tbprd;
volatile Uint16 rust_epwm_cmp_basic_cmpa;

int main(void)
{
    rust_epwm_cmp_basic();
    rust_epwm_cmp_basic_gpio0_mux = GpioCtrlRegs.GPAMUX1.bit.GPIO0;
    rust_epwm_cmp_basic_tbprd = EPwm1Regs.TBPRD;
    rust_epwm_cmp_basic_cmpa = EPwm1Regs.CMPA.half.CMPA;
    rust_epwm_cmp_basic_called = 1U;

    for (;;) {
    }
}
