#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_watchdog_timeout_reset
#endif

/* .noinit: not zero-initialised by _c_int00, survives watchdog reset */
#pragma DATA_SECTION(g_wdg_rst_count, ".noinit")
volatile Uint16 g_wdg_rst_count;

static Uint16 read_wdcr(void)
{
    return SysCtrlRegs.WDCR;
}

static unsigned int watchdog_reset_flag_is_set(void)
{
    return ((read_wdcr() & SYS_WATCHDOG_TIMEOUT_RESET_WDFLAG_MASK) != 0U);
}

static void enable_watchdog_reset_mode(void)
{
    EALLOW;
    SysCtrlRegs.SCSR &= (Uint16)(~BIT1);
    SysCtrlRegs.WDCR = SYS_WATCHDOG_TIMEOUT_RESET_WDCR_ENABLE;
    EDIS;
}

static void disable_watchdog_and_clear_flag(void)
{
    EALLOW;
    SysCtrlRegs.WDCR = SYS_WATCHDOG_TIMEOUT_RESET_WDCR_DISABLE_CLEAR;
    EDIS;
}

static unsigned int handle_post_watchdog_reset_boot(void)
{
    disable_watchdog_and_clear_flag();

    if (watchdog_reset_flag_is_set()) {
        return SYS_WATCHDOG_TIMEOUT_RESET_FAIL_WDFLAG_NOT_CLR;
    }

    board_demo_toggle();
    return 0U;
}

static void trigger_watchdog_reset(void)
{
    ServiceDog();
    enable_watchdog_reset_mode();

    if ((SysCtrlRegs.SCSR & BIT1) != 0U) {
        test_runtime_fail(SYS_WATCHDOG_TIMEOUT_RESET_FAIL_BAD_SCSR);
    }

    /* Intentionally stop feeding the watchdog and wait for the reset path. */
    device_delay_us(SYS_WATCHDOG_TIMEOUT_RESET_RESET_WAIT_US);

    DisableDog();
    test_runtime_fail(SYS_WATCHDOG_TIMEOUT_RESET_FAIL_NO_RESET);
}

void main(void)
{
    board_demo_init();

    if (watchdog_reset_flag_is_set()) {
        unsigned int fail_code;

        g_wdg_rst_count += 1U;
        fail_code = handle_post_watchdog_reset_boot();
        if (fail_code != 0U) {
            test_runtime_fail(fail_code);
        }
    } else {
        g_wdg_rst_count = 0U;
    }

    if (g_wdg_rst_count >= 1U) {
        test_runtime_pass();
    }

    if (watchdog_reset_flag_is_set()) {
        test_runtime_fail(SYS_WATCHDOG_TIMEOUT_RESET_FAIL_BAD_WDFLAG);
    }

    trigger_watchdog_reset();
}
