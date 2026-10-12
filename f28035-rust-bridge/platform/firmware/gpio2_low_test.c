#include "DSP28x_Project.h"

extern void rust_gpio2_low(void);

/* Set after the Rust-authored function returns; inspect through XDS. */
volatile Uint16 rust_gpio2_called;
volatile Uint16 rust_gpio2_mux;
volatile Uint16 rust_gpio2_direction;
volatile Uint16 rust_gpio2_data;

int main(void)
{
    rust_gpio2_low();
    rust_gpio2_mux = GpioCtrlRegs.GPAMUX1.bit.GPIO2;
    rust_gpio2_direction = GpioCtrlRegs.GPADIR.bit.GPIO2;
    rust_gpio2_data = GpioDataRegs.GPADAT.bit.GPIO2;
    rust_gpio2_called = 1U;

    for (;;) {
    }
}
