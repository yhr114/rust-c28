#include "DSP28x_Project.h"

extern void rust_gpio3_low(void);

/* Set after the Rust-authored function returns; inspect through XDS. */
volatile Uint16 rust_gpio3_called;
volatile Uint16 rust_gpio3_mux;
volatile Uint16 rust_gpio3_direction;
volatile Uint16 rust_gpio3_data;

int main(void)
{
    rust_gpio3_low();
    rust_gpio3_mux = GpioCtrlRegs.GPAMUX1.bit.GPIO3;
    rust_gpio3_direction = GpioCtrlRegs.GPADIR.bit.GPIO3;
    rust_gpio3_data = GpioDataRegs.GPADAT.bit.GPIO3;
    rust_gpio3_called = 1U;

    for (;;) {
    }
}
