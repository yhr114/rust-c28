#include "DSP28x_Project.h"

extern void rust_gpio34_direction_switch(void);

/* Set after the Rust-authored function returns; inspect through XDS. */
volatile Uint16 rust_gpio34_direction_called;
volatile Uint16 rust_gpio34_direction_mux;
volatile Uint16 rust_gpio34_direction_direction;
volatile Uint16 rust_gpio34_direction_data;
/* Residue of the intermediate input configuration: make_input programs
 * GPBQSEL1 (qualification) and GPBPUD (pull-up); the later make_output does
 * not clear them, so they prove the input stage really ran. */
volatile Uint16 rust_gpio34_direction_qsel;
volatile Uint16 rust_gpio34_direction_pud;

int main(void)
{
    rust_gpio34_direction_switch();
    rust_gpio34_direction_mux = GpioCtrlRegs.GPBMUX1.bit.GPIO34;
    rust_gpio34_direction_direction = GpioCtrlRegs.GPBDIR.bit.GPIO34;
    rust_gpio34_direction_data = GpioDataRegs.GPBDAT.bit.GPIO34;
    rust_gpio34_direction_qsel = GpioCtrlRegs.GPBQSEL1.all;
    rust_gpio34_direction_pud = GpioCtrlRegs.GPBPUD.all;
    rust_gpio34_direction_called = 1U;

    for (;;) {
    }
}
