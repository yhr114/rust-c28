#include "DSP28x_Project.h"

extern void rust_gpio34_toggle_basic(void);

/* Set after the Rust-authored function returns; inspected through XDS. */
volatile Uint16 rust_gpio34_toggle_called;
volatile Uint16 rust_gpio34_toggle_mux;
volatile Uint16 rust_gpio34_toggle_direction;

/* Toggle proof: after the Rust function returns (8 even toggles from low, so
 * the pin must be low), the harness issues two TOGGLE commands of its own and
 * records 1 then 0, proving the toggle path flips the pin. */
volatile Uint16 rust_gpio34_toggle_final;
volatile Uint16 rust_gpio34_toggle_after_first;
volatile Uint16 rust_gpio34_toggle_after_second;

int main(void)
{
    rust_gpio34_toggle_basic();

    /* Rust left the pin low after 8 (even) toggles. */
    rust_gpio34_toggle_final = GpioDataRegs.GPBDAT.bit.GPIO34;

    /* TOGGLE -> should read high. */
    GpioDataRegs.GPBTOGGLE.bit.GPIO34 = 1;
    DELAY_US(50);
    rust_gpio34_toggle_after_first = GpioDataRegs.GPBDAT.bit.GPIO34;

    /* TOGGLE -> should read low again. */
    GpioDataRegs.GPBTOGGLE.bit.GPIO34 = 1;
    DELAY_US(50);
    rust_gpio34_toggle_after_second = GpioDataRegs.GPBDAT.bit.GPIO34;

    rust_gpio34_toggle_mux = GpioCtrlRegs.GPBMUX1.bit.GPIO34;
    rust_gpio34_toggle_direction = GpioCtrlRegs.GPBDIR.bit.GPIO34;
    rust_gpio34_toggle_called = 1U;

    for (;;) {
    }
}
