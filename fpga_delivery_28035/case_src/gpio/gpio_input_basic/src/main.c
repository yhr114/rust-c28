#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    board_demo_init();
    gpio_case_gpio30_output_init(0U);
    gpio_case_gpio0_input_init(0U);
    board_delay_us(GPIO_INPUT_BASIC_INIT_DELAY_US);

    gpio_case_gpio30_write(1U);
    board_delay_us(GPIO_INPUT_BASIC_STEP_DELAY_US);
    if (gpio_case_wait_for_gpio0(1U, GPIO_INPUT_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(GPIO_INPUT_BASIC_FAIL_HIGH);
    }

    gpio_case_gpio30_write(0U);
    board_delay_us(GPIO_INPUT_BASIC_STEP_DELAY_US);
    if (gpio_case_wait_for_gpio0(0U, GPIO_INPUT_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(GPIO_INPUT_BASIC_FAIL_LOW);
    }

    test_runtime_pass();
}
