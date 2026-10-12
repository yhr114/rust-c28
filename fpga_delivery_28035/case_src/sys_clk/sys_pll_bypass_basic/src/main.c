#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_pll_bypass_basic
#endif

volatile unsigned long g_sys_pll_bypass_basic_heartbeat = 0UL;

static unsigned int check_bypass_state(void)
{
    if (SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) {
        return SYS_PLL_BYPASS_BASIC_FAIL_MCLKSTS;
    }

    if (SysCtrlRegs.PLLCR.bit.DIV != 0U) {
        return SYS_PLL_BYPASS_BASIC_FAIL_PLLCR;
    }

    if (SysCtrlRegs.PLLSTS.bit.DIVSEL != 0U) {
        return SYS_PLL_BYPASS_BASIC_FAIL_DIVSEL;
    }

    return 0U;
}

void main(void)
{
    unsigned int fail_code;
    unsigned long i;

    board_demo_init();
    board_demo_toggle();

    DisableDog();
    InitPll(0U, 0U);
    board_delay_us(SYS_PLL_BYPASS_BASIC_SETTLE_US);

    fail_code = check_bypass_state();
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    for (i = 0UL; i < SYS_PLL_BYPASS_BASIC_WINDOW_STEPS; ++i) {
        g_sys_pll_bypass_basic_heartbeat = i;
        board_demo_toggle();
        board_delay_us(SYS_PLL_BYPASS_BASIC_WINDOW_DELAY_US);
    }

    if (g_sys_pll_bypass_basic_heartbeat != (SYS_PLL_BYPASS_BASIC_WINDOW_STEPS - 1UL)) {
        test_runtime_fail(SYS_PLL_BYPASS_BASIC_FAIL_HEARTBEAT);
    }

    test_runtime_pass();
}
