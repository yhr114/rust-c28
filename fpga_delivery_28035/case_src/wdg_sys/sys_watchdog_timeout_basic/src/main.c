#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_watchdog_timeout_basic
#endif

static void enable_watchdog(void)
{
    EALLOW;
    SysCtrlRegs.WDCR = SYS_WATCHDOG_TIMEOUT_BASIC_WDCR_ENABLE;
    EDIS;
}

static unsigned int wait_for_watchdog_counter_change(Uint16 snapshot)
{
    unsigned long loops;

    for (loops = 0UL; loops < SYS_WATCHDOG_TIMEOUT_BASIC_WAIT_LOOPS; ++loops) {
        if (SysCtrlRegs.WDCNTR != snapshot) {
            return 0U;
        }
    }

    return SYS_WATCHDOG_TIMEOUT_BASIC_FAIL_NO_PROGRESS;
}

static unsigned int check_watchdog_counter_progress(Uint16 fail_code)
{
    if (wait_for_watchdog_counter_change(SysCtrlRegs.WDCNTR) != 0U) {
        return fail_code;
    }

    return 0U;
}

static unsigned int run_watchdog_baseline(void)
{
    FeedDog();
    enable_watchdog();

    if (check_watchdog_counter_progress(SYS_WATCHDOG_TIMEOUT_BASIC_FAIL_NO_PROGRESS) != 0U) {
        return SYS_WATCHDOG_TIMEOUT_BASIC_FAIL_NO_PROGRESS;
    }

    FeedDog();
    if (check_watchdog_counter_progress(SYS_WATCHDOG_TIMEOUT_BASIC_FAIL_NO_RESTART) != 0U) {
        return SYS_WATCHDOG_TIMEOUT_BASIC_FAIL_NO_RESTART;
    }

    return 0U;
}

void main(void)
{
    unsigned int fail_code;

    board_demo_init();
    fail_code = run_watchdog_baseline();

    DisableDog();

    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    board_demo_toggle();
    test_runtime_pass();
}
