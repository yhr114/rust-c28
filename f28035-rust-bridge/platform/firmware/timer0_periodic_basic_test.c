#include "DSP28x_Project.h"

extern void rust_timer0_periodic_basic(void);

volatile Uint16 rust_timer0_periodic_basic_called;
volatile Uint16 rust_timer0_periodic_basic_gpio30_mux;
volatile Uint16 rust_timer0_periodic_basic_gpio30_dir;

int main(void)
{
    rust_timer0_periodic_basic();
    rust_timer0_periodic_basic_gpio30_mux = GpioCtrlRegs.GPAMUX2.bit.GPIO30;
    rust_timer0_periodic_basic_gpio30_dir = GpioCtrlRegs.GPADIR.bit.GPIO30;
    rust_timer0_periodic_basic_called = 1U;

    for (;;) {
    }
}
