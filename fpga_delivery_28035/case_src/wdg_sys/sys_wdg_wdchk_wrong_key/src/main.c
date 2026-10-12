#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_wdg_wdchk_wrong_key
#endif

#pragma DATA_SECTION(g_reset_marker, ".noinit")
volatile Uint16 g_reset_marker;

static Uint16 read_wdcr(void)
{
    return SysCtrlRegs.WDCR;
}

static unsigned int watchdog_reset_flag_is_set(void)
{
    return ((read_wdcr() & SYS_WDG_WDCHK_WRONG_KEY_WDFLAG_MASK) != 0U);
}

static void disable_watchdog_and_clear_flag(void)
{
    EALLOW;
    SysCtrlRegs.WDCR = SYS_WDG_WDCHK_WRONG_KEY_WDCR_DISABLE_CLEAR;
    EDIS;
}

static unsigned int wait_for_watchdog_reset_flag(void)
{
    unsigned long guard;

    for (guard = 0UL; guard < SYS_WDG_WDCHK_WRONG_KEY_WDFLAG_WAIT_LOOPS; guard++) {
        if (watchdog_reset_flag_is_set() != 0U) {
            return 1U;
        }
    }

    return 0U;
}

static void trigger_bad_wdchk_reset(void)
{
    ServiceDog();

    EALLOW;
    SysCtrlRegs.SCSR &= (Uint16)(~BIT1);
    EDIS;

    if ((SysCtrlRegs.SCSR & BIT1) != 0U) {
        test_runtime_fail(SYS_WDG_WDCHK_WRONG_KEY_FAIL_BAD_SCSR);
    }

    g_reset_marker = SYS_WDG_WDCHK_WRONG_KEY_STAGE_ARMED;

    EALLOW;
    SysCtrlRegs.WDCR = SYS_WDG_WDCHK_WRONG_KEY_ENABLE_WDCR;
    SysCtrlRegs.WDCR = SYS_WDG_WDCHK_WRONG_KEY_BAD_WDCR;
    EDIS;

    device_delay_us(SYS_WDG_WDCHK_WRONG_KEY_RESET_WAIT_US);

    DisableDog();
    test_runtime_fail(SYS_WDG_WDCHK_WRONG_KEY_FAIL_NO_RESET);
}

void main(void)
{
    board_demo_init();

    if (wait_for_watchdog_reset_flag() != 0U) {
        disable_watchdog_and_clear_flag();
        if (watchdog_reset_flag_is_set()) {
            test_runtime_fail(SYS_WDG_WDCHK_WRONG_KEY_FAIL_WDFLAG_NOT_CLR);
        }

        g_reset_marker = 0U;
        board_demo_toggle();
        test_runtime_pass();
    }

    g_reset_marker = 0U;
    trigger_bad_wdchk_reset();
}
