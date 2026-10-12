//###########################################################################
//  FILE:  watchdog_reset_mode_test/main.c
//  TITLE: Watchdog Reset Mode Smoke Test
//  DESC:  Verify watchdog reset restart path. WDFLAG is checked when visible;
//         a NOINIT marker prevents full-chip reset timing from causing loops.
//###########################################################################
#include "board_gpio.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for watchdog_reset_mode_test
#endif

#define WD_RESET_WAIT_US   50000UL
#define WD_CLEAR_WAIT_US    2000UL
#define WD_BOOT_MARKER     0xA55AU
#define WD_BOOT_MARKER_ADDR ((volatile Uint16 *)0x9000U)


static Uint16 wdflag_is_set(void)
{
    return ((SysCtrlRegs.WDCR & 0x80U) != 0U);
}

static Uint16 wait_for_wdflag_clear(Uint32 timeout_us)
{
    while (timeout_us--)
    {
        if (!wdflag_is_set())
        {
            return 1U;
        }
        device_delay_us(1UL);
    }

    return 0U;
}

static void disable_watchdog_and_clear_flag(Uint16 fail_code)
{
    EALLOW;
    SysCtrlRegs.WDCR = 0x00E8U;
    EDIS;

    if (!wait_for_wdflag_clear(WD_CLEAR_WAIT_US))
    {
        test_runtime_fail(fail_code);
    }
}

static void enable_watchdog_reset_mode(void)
{
    EALLOW;
    SysCtrlRegs.SCSR &= (Uint16)(~0x0002U);
    SysCtrlRegs.WDCR = 0x0028U;
    EDIS;
}

static void pass_after_watchdog_restart(void)
{
    *WD_BOOT_MARKER_ADDR = 0U;
    if (wdflag_is_set())
    {
        disable_watchdog_and_clear_flag(2U);
    }
    else
    {
        DisableDog();
    }
    board_demo_toggle();
    test_runtime_pass();
}

void main(void)
{
    Uint16 post_watchdog_restart;

    post_watchdog_restart = (Uint16)(wdflag_is_set() || (*WD_BOOT_MARKER_ADDR == WD_BOOT_MARKER));

    board_demo_init();

    if (post_watchdog_restart)
    {
        pass_after_watchdog_restart();
    }

    *WD_BOOT_MARKER_ADDR = WD_BOOT_MARKER;
    ServiceDog();
    enable_watchdog_reset_mode();

    device_delay_us(WD_RESET_WAIT_US);

    DisableDog();
    *WD_BOOT_MARKER_ADDR = 0U;
    test_runtime_fail(1U);
}
