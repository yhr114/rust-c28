#include "DSP28x_Project.h"

extern void rust_gpio2_3_low(void);

volatile Uint16 rust_gpio2_3_called;
volatile Uint16 rust_gpio2_3_mux2;
volatile Uint16 rust_gpio2_3_mux3;
volatile Uint16 rust_gpio2_3_dir2;
volatile Uint16 rust_gpio2_3_dir3;
volatile Uint16 rust_gpio2_3_data2;
volatile Uint16 rust_gpio2_3_data3;

int main(void)
{
    rust_gpio2_3_low();
    rust_gpio2_3_mux2 = GpioCtrlRegs.GPAMUX1.bit.GPIO2;
    rust_gpio2_3_mux3 = GpioCtrlRegs.GPAMUX1.bit.GPIO3;
    rust_gpio2_3_dir2 = GpioCtrlRegs.GPADIR.bit.GPIO2;
    rust_gpio2_3_dir3 = GpioCtrlRegs.GPADIR.bit.GPIO3;
    rust_gpio2_3_data2 = GpioDataRegs.GPADAT.bit.GPIO2;
    rust_gpio2_3_data3 = GpioDataRegs.GPADAT.bit.GPIO3;
    rust_gpio2_3_called = 1U;

    for (;;) {
    }
}
