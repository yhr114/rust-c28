#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_xrs_runtime_window_basic
#endif

volatile unsigned long g_reset_runtime_window_heartbeat = 0UL;

static unsigned int check_reset_window_prereq(void)
{
    if (SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) {
        return SYS_XRS_RUNTIME_WINDOW_BASIC_FAIL_MCLKSTS;
    }

    if (SysCtrlRegs.PLLSTS.bit.PLLLOCKS != 1U) {
        return SYS_XRS_RUNTIME_WINDOW_BASIC_FAIL_PLLLOCKS;
    }

    return 0U;
}

void main(void)
{
    unsigned int fail_code;
    unsigned long i;

    board_demo_init();

    fail_code = check_reset_window_prereq();
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    for (i = 0UL; i < SYS_XRS_RUNTIME_WINDOW_BASIC_ITERATIONS; ++i) {
        g_reset_runtime_window_heartbeat = i;

        if ((i % SYS_XRS_RUNTIME_WINDOW_BASIC_TOGGLE_STRIDE) == 0UL) {
            board_demo_toggle();
        }
    }

    if (g_reset_runtime_window_heartbeat != (SYS_XRS_RUNTIME_WINDOW_BASIC_ITERATIONS - 1UL)) {
        test_runtime_fail(SYS_XRS_RUNTIME_WINDOW_BASIC_FAIL_HEARTBEAT);
    }

    test_runtime_pass();
}
