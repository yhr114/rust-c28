#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_pll_lock_basic
#endif

static unsigned int check_pll_state(void)
{
    if (SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) {
        return SYS_PLL_LOCK_BASIC_FAIL_MCLKSTS;
    }

    if (SysCtrlRegs.PLLSTS.bit.PLLLOCKS != 1U) {
        return SYS_PLL_LOCK_BASIC_FAIL_LOCK;
    }

    if (SysCtrlRegs.PLLCR.bit.DIV != DSP28_PLLCR) {
        return SYS_PLL_LOCK_BASIC_FAIL_PLLCR;
    }

    if (SysCtrlRegs.PLLSTS.bit.DIVSEL != DSP28_DIVSEL) {
        return SYS_PLL_LOCK_BASIC_FAIL_DIVSEL;
    }

    return 0U;
}

void main(void)
{
    unsigned int fail_code;

    board_demo_init();
    board_demo_toggle();

    fail_code = check_pll_state();
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    test_runtime_pass();
}
