#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    board_demo_init();
    gpio_case_gpio34_output_init(1U);
    board_delay_us(GPIO_OUTPUT_READBACK_BASIC_SETTLE_DELAY_US);

    if (gpio_case_gpio34_read() != 1U) {
        test_runtime_fail(GPIO_OUTPUT_READBACK_BASIC_FAIL_STEP0);
    }

    gpio_case_gpio34_write(0U);
    board_delay_us(GPIO_OUTPUT_READBACK_BASIC_SETTLE_DELAY_US);
    if (gpio_case_gpio34_read() != 0U) {
        test_runtime_fail(GPIO_OUTPUT_READBACK_BASIC_FAIL_STEP1);
    }

    gpio_case_gpio34_write(1U);
    board_delay_us(GPIO_OUTPUT_READBACK_BASIC_SETTLE_DELAY_US);
    if (gpio_case_gpio34_read() != 1U) {
        test_runtime_fail(GPIO_OUTPUT_READBACK_BASIC_FAIL_STEP2);
    }

    test_runtime_pass();
}
