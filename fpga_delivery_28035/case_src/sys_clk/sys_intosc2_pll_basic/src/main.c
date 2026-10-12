#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_intosc2_pll_basic
#endif

typedef struct {
    Uint16 div;
    Uint16 divsel;
    Uint16 profile_id;
} pll_profile_t;

static const pll_profile_t g_profiles[] = {
    {2U, 0U, 1U},
    {3U, 2U, 2U},
    {5U, 3U, 3U},
    {6U, 2U, 4U}
};

volatile unsigned long g_sys_intosc2_pll_basic_heartbeat = 0UL;

static void select_intosc2_source(void)
{
    EALLOW;
    SysCtrlRegs.CLKCTL.bit.INTOSC1OFF = 0U;
    SysCtrlRegs.CLKCTL.bit.INTOSC2OFF = 0U;
    SysCtrlRegs.CLKCTL.bit.XCLKINOFF = 1U;
    SysCtrlRegs.CLKCTL.bit.XTALOSCOFF = 1U;
    EDIS;

    board_delay_us(SYS_INTOSC2_PLL_BASIC_SOURCE_SETTLE_US);

    EALLOW;
    SysCtrlRegs.CLKCTL.bit.OSCCLKSRC2SEL = 1U;
    SysCtrlRegs.CLKCTL.bit.OSCCLKSRCSEL = 1U;
    EDIS;
}

static unsigned int check_intosc2_source(Uint16 step_id)
{
    if (SysCtrlRegs.CLKCTL.bit.OSCCLKSRCSEL != 1U) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_OSCCLKSRCSEL_BASE + step_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.OSCCLKSRC2SEL != 1U) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_OSCCLKSRC2SEL_BASE + step_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.INTOSC1OFF != 0U) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_INTOSC1OFF_BASE + step_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.INTOSC2OFF != 0U) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_INTOSC2OFF_BASE + step_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.XCLKINOFF != 1U) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_XCLKINOFF_BASE + step_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.XTALOSCOFF != 1U) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_XTALOSCOFF_BASE + step_id);
    }

    return 0U;
}

static unsigned int check_profile(const pll_profile_t *profile)
{
    unsigned int fail_code;

    fail_code = check_intosc2_source(profile->profile_id);
    if (fail_code != 0U) {
        return fail_code;
    }

    if (SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_MCLKSTS_BASE + profile->profile_id);
    }

    if (SysCtrlRegs.PLLSTS.bit.PLLLOCKS != 1U) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_PLLLOCKS_BASE + profile->profile_id);
    }

    if (SysCtrlRegs.PLLCR.bit.DIV != profile->div) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_PLLCR_BASE + profile->profile_id);
    }

    if (SysCtrlRegs.PLLSTS.bit.DIVSEL != profile->divsel) {
        return (unsigned int)(SYS_INTOSC2_PLL_BASIC_FAIL_DIVSEL_BASE + profile->profile_id);
    }

    return 0U;
}

static void run_profile_window(Uint16 profile_id)
{
    unsigned long i;

    for (i = 0UL; i < SYS_INTOSC2_PLL_BASIC_WINDOW_STEPS; ++i) {
        g_sys_intosc2_pll_basic_heartbeat =
            ((unsigned long)profile_id << 24) | i;
        board_demo_toggle();
        board_delay_us(SYS_INTOSC2_PLL_BASIC_WINDOW_DELAY_US);
    }
}

void main(void)
{
    unsigned int fail_code;
    unsigned int idx;

    board_demo_init();
    board_demo_toggle();

    DisableDog();

    InitPll(0U, 0U);
    board_delay_us(SYS_INTOSC2_PLL_BASIC_SOURCE_SETTLE_US);

    select_intosc2_source();
    board_delay_us(SYS_INTOSC2_PLL_BASIC_SOURCE_SETTLE_US);

    fail_code = check_intosc2_source(0U);
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    for (idx = 0U; idx < (sizeof(g_profiles) / sizeof(g_profiles[0])); ++idx) {
        InitPll(g_profiles[idx].div, g_profiles[idx].divsel);
        board_delay_us(SYS_INTOSC2_PLL_BASIC_PLL_SETTLE_US);

        fail_code = check_profile(&g_profiles[idx]);
        if (fail_code != 0U) {
            test_runtime_fail(fail_code);
        }

        run_profile_window(g_profiles[idx].profile_id);
    }

    if ((g_sys_intosc2_pll_basic_heartbeat & 0x00FFFFFFUL) !=
        (SYS_INTOSC2_PLL_BASIC_WINDOW_STEPS - 1UL)) {
        test_runtime_fail(SYS_INTOSC2_PLL_BASIC_FAIL_HEARTBEAT);
    }

    test_runtime_pass();
}
