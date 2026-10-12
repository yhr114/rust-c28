#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    unsigned int idx;

    board_demo_init();
    gpio_case_gpio34_output_init(0U);

    for (idx = 0U; idx < GPIO_TOGGLE_BASIC_COUNT; ++idx) {
        gpio_case_gpio34_toggle();
        board_delay_us(GPIO_TOGGLE_BASIC_DELAY_US);
    }

    if (gpio_case_gpio34_read() != (GPIO_TOGGLE_BASIC_COUNT & 0x1U)) {
        test_runtime_fail(GPIO_TOGGLE_BASIC_FAIL_FINAL);
    }

    test_runtime_pass();
}
