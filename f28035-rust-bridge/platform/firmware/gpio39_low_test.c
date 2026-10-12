#include "DSP28x_Project.h"

extern void rust_gpio39_low(void);

/* Set after the Rust-authored function returns; inspect through XDS. */
volatile Uint16 rust_gpio39_called;
volatile Uint16 rust_gpio39_mux;
volatile Uint16 rust_gpio39_direction;
volatile Uint16 rust_gpio39_data;

int main(void)
{
    rust_gpio39_low();
    rust_gpio39_mux = GpioCtrlRegs.GPBMUX1.bit.GPIO39;
    rust_gpio39_direction = GpioCtrlRegs.GPBDIR.bit.GPIO39;
    rust_gpio39_data = GpioDataRegs.GPBDAT.bit.GPIO39;
    rust_gpio39_called = 1U;

    for (;;) {
    }
}
