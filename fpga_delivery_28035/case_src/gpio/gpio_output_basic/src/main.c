#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    board_demo_init();
    gpio_case_gpio34_output_init(0U);
    board_delay_us(100UL);

    if (gpio_case_gpio34_read() != 0U) {
        test_runtime_fail(GPIO_OUTPUT_BASIC_FAIL_LOW);
    }

    gpio_case_gpio34_write(1U);
    board_delay_us(100UL);

    if (gpio_case_gpio34_read() != 1U) {
        test_runtime_fail(GPIO_OUTPUT_BASIC_FAIL_HIGH);
    }

    test_runtime_pass();
}
