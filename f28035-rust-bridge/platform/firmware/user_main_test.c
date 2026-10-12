#include "DSP28x_Project.h"

extern Uint16 rust_user_main(void);
#ifdef F28035_FLASH_BOOT
extern void f28035_flash_prepare(void);
#endif

volatile Uint16 user_main_called;
volatile Uint16 user_main_result;
volatile Uint16 user_gpio30_mux;
volatile Uint16 user_gpio30_direction;
volatile Uint16 user_gpio30_data;
volatile Uint16 user_gpio34_mux;
volatile Uint16 user_gpio34_direction;
volatile Uint16 user_gpio34_data;

int main(void)
{
#ifdef F28035_FLASH_BOOT
    f28035_flash_prepare();
#endif
    user_main_result = rust_user_main();
    user_gpio30_mux = GpioCtrlRegs.GPAMUX2.bit.GPIO30;
    user_gpio30_direction = GpioCtrlRegs.GPADIR.bit.GPIO30;
    user_gpio30_data = GpioDataRegs.GPADAT.bit.GPIO30;
    user_gpio34_mux = GpioCtrlRegs.GPBMUX1.bit.GPIO34;
    user_gpio34_direction = GpioCtrlRegs.GPBDIR.bit.GPIO34;
    user_gpio34_data = GpioDataRegs.GPBDAT.bit.GPIO34;
    user_main_called = 1U;

    for (;;) {
    }
}
