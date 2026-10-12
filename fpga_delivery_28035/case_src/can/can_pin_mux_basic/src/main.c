#include "board_can_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    board_demo_init();
    can_case_gpio30_31_can_mux_init();
    board_delay_us(CAN_PIN_MUX_BASIC_DELAY_US);

    if ((unsigned int)GpioCtrlRegs.GPAMUX2.bit.GPIO30 != 1U) {
        test_runtime_fail(CAN_PIN_MUX_BASIC_FAIL_GPIO30_MUX);
    }
    if ((unsigned int)GpioCtrlRegs.GPAMUX2.bit.GPIO31 != 1U) {
        test_runtime_fail(CAN_PIN_MUX_BASIC_FAIL_GPIO31_MUX);
    }

    test_runtime_pass();
}
