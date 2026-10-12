#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    board_demo_init();
    gpio_case_gpio34_output_init(1U);
    board_delay_us(50UL);

    if ((GpioCtrlRegs.GPBDIR.bit.GPIO34 != 1U) || (gpio_case_gpio34_read() != 1U)) {
        test_runtime_fail(GPIO_DIRECTION_SWITCH_BASIC_FAIL_OUT_HIGH);
    }

    gpio_case_gpio34_input_init();
    board_delay_us(50UL);
    if (GpioCtrlRegs.GPBDIR.bit.GPIO34 != 0U) {
        test_runtime_fail(GPIO_DIRECTION_SWITCH_BASIC_FAIL_TO_INPUT);
    }

    gpio_case_gpio34_output_init(0U);
    board_delay_us(50UL);
    if ((GpioCtrlRegs.GPBDIR.bit.GPIO34 != 1U) || (gpio_case_gpio34_read() != 0U)) {
        test_runtime_fail(GPIO_DIRECTION_SWITCH_BASIC_FAIL_OUT_LOW);
    }

    test_runtime_pass();
}
