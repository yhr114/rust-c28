#include "DSP28x_Project.h"

extern void rust_gpio34_output_readback(void);

/* Set after the Rust-authored function returns; inspected through XDS. */
volatile Uint16 rust_gpio34_readback_called;
volatile Uint16 rust_gpio34_readback_mux;
volatile Uint16 rust_gpio34_readback_direction;

/* Read-back proof: after the Rust function returns, the harness writes the
 * pin high/low/high, reads GPBDAT after each write, and records the three
 * levels.  The JTAG judge requires 1, 0, 1. */
volatile Uint16 rust_gpio34_readback_after_high;
volatile Uint16 rust_gpio34_readback_after_low;
volatile Uint16 rust_gpio34_readback_final;

int main(void)
{
    rust_gpio34_output_readback();

    /* Write high -> read back. */
    GpioDataRegs.GPBSET.bit.GPIO34 = 1;
    DELAY_US(50);
    rust_gpio34_readback_after_high = GpioDataRegs.GPBDAT.bit.GPIO34;

    /* Write low -> read back. */
    GpioDataRegs.GPBCLEAR.bit.GPIO34 = 1;
    DELAY_US(50);
    rust_gpio34_readback_after_low = GpioDataRegs.GPBDAT.bit.GPIO34;

    /* Write high -> read back (final state matches the Rust sequence end). */
    GpioDataRegs.GPBSET.bit.GPIO34 = 1;
    DELAY_US(50);
    rust_gpio34_readback_final = GpioDataRegs.GPBDAT.bit.GPIO34;

    rust_gpio34_readback_mux = GpioCtrlRegs.GPBMUX1.bit.GPIO34;
    rust_gpio34_readback_direction = GpioCtrlRegs.GPBDIR.bit.GPIO34;
    rust_gpio34_readback_called = 1U;

    for (;;) {
    }
}
