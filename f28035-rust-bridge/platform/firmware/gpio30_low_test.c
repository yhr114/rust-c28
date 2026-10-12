#include "DSP28x_Project.h"

extern void rust_gpio30_low(void);

/* Set after the Rust-authored function returns; inspect through XDS. */
volatile Uint16 rust_gpio30_called;
volatile Uint16 rust_gpio30_mux;
volatile Uint16 rust_gpio30_direction;
volatile Uint16 rust_gpio30_data;

int main(void)
{
    rust_gpio30_low();
    rust_gpio30_mux = GpioCtrlRegs.GPAMUX2.bit.GPIO30;
    rust_gpio30_direction = GpioCtrlRegs.GPADIR.bit.GPIO30;
    rust_gpio30_data = GpioDataRegs.GPADAT.bit.GPIO30;
    rust_gpio30_called = 1U;

    for (;;) {
    }
}
