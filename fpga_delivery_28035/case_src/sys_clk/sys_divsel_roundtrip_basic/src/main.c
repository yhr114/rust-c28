#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_divsel_roundtrip_basic
#endif

static const Uint16 g_divsel_steps[] = {
    0U, 1U, 2U, 3U, 2U, 1U, 0U
};

volatile unsigned long g_sys_divsel_roundtrip_basic_heartbeat = 0UL;

static unsigned int check_state(Uint16 expected_divsel, Uint16 step_id)
{
    if (SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) {
        return (unsigned int)(SYS_DIVSEL_ROUNDTRIP_BASIC_FAIL_MCLKSTS_BASE + step_id);
    }

    if (SysCtrlRegs.PLLSTS.bit.PLLLOCKS != 1U) {
        return (unsigned int)(SYS_DIVSEL_ROUNDTRIP_BASIC_FAIL_PLLLOCKS_BASE + step_id);
    }

    if (SysCtrlRegs.PLLCR.bit.DIV != SYS_DIVSEL_ROUNDTRIP_BASIC_DIV) {
        return (unsigned int)(SYS_DIVSEL_ROUNDTRIP_BASIC_FAIL_PLLCR_BASE + step_id);
    }

    if (SysCtrlRegs.PLLSTS.bit.DIVSEL != expected_divsel) {
        return (unsigned int)(SYS_DIVSEL_ROUNDTRIP_BASIC_FAIL_DIVSEL_BASE + step_id);
    }

    return 0U;
}

static void run_window(Uint16 step_id)
{
    unsigned long i;
    unsigned long wait_count;

    for (i = 0UL; i < SYS_DIVSEL_ROUNDTRIP_BASIC_WINDOW_STEPS; ++i) {
        g_sys_divsel_roundtrip_basic_heartbeat =
            ((unsigned long)step_id << 24) | i;
        board_demo_toggle();
        for (wait_count = 0UL; wait_count < 16UL; ++wait_count) {
            __asm(" NOP");
        }
    }
}

void main(void)
{
    unsigned int fail_code;
    Uint16 idx;
    Uint16 step_id;

    board_demo_init();
    board_demo_toggle();

    DisableDog();

    for (idx = 0U; idx < (sizeof(g_divsel_steps) / sizeof(g_divsel_steps[0])); ++idx) {
        step_id = (Uint16)(idx + 1U);

        InitPll(SYS_DIVSEL_ROUNDTRIP_BASIC_DIV, g_divsel_steps[idx]);

        fail_code = check_state(g_divsel_steps[idx], step_id);
        if (fail_code != 0U) {
            test_runtime_fail(fail_code);
        }

        run_window(step_id);
    }

    if ((g_sys_divsel_roundtrip_basic_heartbeat & 0x00FFFFFFUL) !=
        (SYS_DIVSEL_ROUNDTRIP_BASIC_WINDOW_STEPS - 1UL)) {
        test_runtime_fail(SYS_DIVSEL_ROUNDTRIP_BASIC_FAIL_HEARTBEAT);
    }

    test_runtime_pass();
}
