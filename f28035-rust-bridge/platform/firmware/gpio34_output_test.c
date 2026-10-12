#include "DSP28x_Project.h"

extern void rust_gpio34_output_basic(void);

/* Set after the Rust-authored function returns; inspect through XDS. */
volatile Uint16 rust_gpio34_called;
volatile Uint16 rust_gpio34_mux;
volatile Uint16 rust_gpio34_direction;
volatile Uint16 rust_gpio34_data;

int main(void)
{
    rust_gpio34_output_basic();
    rust_gpio34_mux = GpioCtrlRegs.GPBMUX1.bit.GPIO34;
    rust_gpio34_direction = GpioCtrlRegs.GPBDIR.bit.GPIO34;
    rust_gpio34_data = GpioDataRegs.GPBDAT.bit.GPIO34;
    rust_gpio34_called = 1U;

    for (;;) {
    }
}
