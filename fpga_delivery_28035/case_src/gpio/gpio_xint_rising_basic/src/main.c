#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

static volatile unsigned int g_gpio_xint_rising_basic_seen = 0U;

__interrupt void gpio_xint_rising_basic_isr(void)
{
    g_gpio_xint_rising_basic_seen++;
    PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
}

void main(void)
{
    board_demo_init();
    gpio_case_gpio30_output_init(0U);
    gpio_case_gpio0_input_init(0U);

    EALLOW;
    PieVectTable.XINT1 = &gpio_xint_rising_basic_isr;
    EDIS;

    gpio_case_xint1_gpio0_setup(1U);
    gpio_case_xint1_enable();

    board_delay_us(GPIO_XINT_RISING_BASIC_PRE_TRIGGER_DELAY_US);
    gpio_case_gpio30_write(1U);

    if (gpio_case_wait_for_count(&g_gpio_xint_rising_basic_seen,
                                 1U,
                                 GPIO_XINT_RISING_BASIC_WAIT_LOOPS) != 0U) {
        gpio_case_xint1_disable();
        test_runtime_fail(GPIO_XINT_RISING_BASIC_FAIL_IRQ);
    }

    gpio_case_xint1_disable();
    test_runtime_pass();
}
