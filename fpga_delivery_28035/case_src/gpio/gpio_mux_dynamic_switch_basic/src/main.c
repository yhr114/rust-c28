#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    board_demo_init();

    gpio_case_gpio0_set_mux(0U);
    if (GpioCtrlRegs.GPAMUX1.bit.GPIO0 != 0U) {
        test_runtime_fail(GPIO_MUX_DYNAMIC_SWITCH_BASIC_FAIL_INIT_GPIO);
    }

    gpio_case_gpio0_set_mux(1U);
    if (GpioCtrlRegs.GPAMUX1.bit.GPIO0 != 1U) {
        test_runtime_fail(GPIO_MUX_DYNAMIC_SWITCH_BASIC_FAIL_EPWM1A);
    }

    gpio_case_gpio0_set_mux(0U);
    if (GpioCtrlRegs.GPAMUX1.bit.GPIO0 != 0U) {
        test_runtime_fail(GPIO_MUX_DYNAMIC_SWITCH_BASIC_FAIL_RESTORE);
    }

    test_runtime_pass();
}
