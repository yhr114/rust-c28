#include "board_can_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    board_demo_init();

    if ((unsigned int)GpioCtrlRegs.GPAMUX2.bit.GPIO30 != 0U) {
        test_runtime_fail(CAN_RESET_DEFAULT_STATE_BASIC_FAIL_GPIO30_MUX);
    }
    if ((unsigned int)GpioCtrlRegs.GPAMUX2.bit.GPIO31 != 0U) {
        test_runtime_fail(CAN_RESET_DEFAULT_STATE_BASIC_FAIL_GPIO31_MUX);
    }

    test_runtime_pass();
}
