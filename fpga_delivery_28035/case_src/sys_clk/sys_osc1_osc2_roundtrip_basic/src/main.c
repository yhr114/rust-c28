#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_osc1_osc2_roundtrip_basic
#endif

typedef struct {
    Uint16 source_id;
    Uint16 expect_oscclksrcsel;
    Uint16 expect_oscclksrc2sel;
    Uint16 expect_intosc1off;
    Uint16 expect_intosc2off;
} osc_profile_t;

static const osc_profile_t g_profiles[] = {
    {1U, 0U, 0U, 0U, 1U},
    {2U, 1U, 1U, 0U, 0U},
    {1U, 0U, 0U, 0U, 1U}
};

volatile unsigned long g_sys_osc1_osc2_roundtrip_basic_heartbeat = 0UL;

static void select_intosc1(void)
{
    device_pll_enter_safe_config();

    EALLOW;
    SysCtrlRegs.CLKCTL.bit.INTOSC1OFF = 0U;
    SysCtrlRegs.CLKCTL.bit.OSCCLKSRC2SEL = 0U;
    SysCtrlRegs.CLKCTL.bit.OSCCLKSRCSEL = 0U;
    SysCtrlRegs.CLKCTL.bit.XCLKINOFF = 1U;
    SysCtrlRegs.CLKCTL.bit.XTALOSCOFF = 1U;
    EDIS;

    board_delay_us(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_SETTLE_US);

    EALLOW;
    SysCtrlRegs.CLKCTL.bit.INTOSC2OFF = 1U;
    EDIS;
}

static void select_intosc2(void)
{
    device_pll_enter_safe_config();

    EALLOW;
    SysCtrlRegs.CLKCTL.bit.INTOSC1OFF = 0U;
    SysCtrlRegs.CLKCTL.bit.INTOSC2OFF = 0U;
    SysCtrlRegs.CLKCTL.bit.XCLKINOFF = 1U;
    SysCtrlRegs.CLKCTL.bit.XTALOSCOFF = 1U;
    SysCtrlRegs.CLKCTL.bit.WDCLKSRCSEL = 0U;
    EDIS;

    board_delay_us(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_SETTLE_US);

    EALLOW;
    SysCtrlRegs.CLKCTL.bit.OSCCLKSRC2SEL = 1U;
    SysCtrlRegs.CLKCTL.bit.OSCCLKSRCSEL = 1U;
    EDIS;
}

static unsigned int check_profile(const osc_profile_t *profile, Uint16 phase_id)
{
    if (SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) {
        return (unsigned int)(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_FAIL_MCLKSTS_BASE + phase_id);
    }

    if (SysCtrlRegs.PLLCR.bit.DIV != 0U) {
        return (unsigned int)(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_FAIL_PLLCR_BASE + phase_id);
    }

    if (SysCtrlRegs.PLLSTS.bit.DIVSEL != 0U) {
        return (unsigned int)(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_FAIL_DIVSEL_BASE + phase_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.OSCCLKSRCSEL != profile->expect_oscclksrcsel) {
        return (unsigned int)(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_FAIL_OSCCLKSRC_BASE + phase_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.OSCCLKSRC2SEL != profile->expect_oscclksrc2sel) {
        return (unsigned int)(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_FAIL_OSCCLKSRC2_BASE + phase_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.INTOSC1OFF != profile->expect_intosc1off) {
        return (unsigned int)(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_FAIL_INTOSC1OFF_BASE + phase_id);
    }

    if (SysCtrlRegs.CLKCTL.bit.INTOSC2OFF != profile->expect_intosc2off) {
        return (unsigned int)(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_FAIL_INTOSC2OFF_BASE + phase_id);
    }

    return 0U;
}

static void run_window(Uint16 phase_id, Uint16 source_id)
{
    unsigned long i;

    for (i = 0UL; i < SYS_OSC1_OSC2_ROUNDTRIP_BASIC_WINDOW_STEPS; ++i) {
        g_sys_osc1_osc2_roundtrip_basic_heartbeat =
            ((unsigned long)phase_id << 28) |
            ((unsigned long)source_id << 24) |
            i;
        board_demo_toggle();
        board_delay_us(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_WINDOW_DELAY_US);
    }
}

void main(void)
{
    unsigned int fail_code;

    board_demo_init();
    board_demo_toggle();
    DisableDog();

    select_intosc1();
    board_delay_us(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_SETTLE_US);
    device_pll_apply(0U, 0U);
    board_delay_us(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_SETTLE_US);

    select_intosc1();
    board_delay_us(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_SETTLE_US);

    fail_code = check_profile(&g_profiles[0], 1U);
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }
    run_window(1U, g_profiles[0].source_id);

    select_intosc2();
    board_delay_us(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_SETTLE_US);

    fail_code = check_profile(&g_profiles[1], 2U);
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }
    run_window(2U, g_profiles[1].source_id);

    select_intosc1();
    board_delay_us(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_SETTLE_US);

    fail_code = check_profile(&g_profiles[2], 3U);
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }
    run_window(3U, g_profiles[2].source_id);

    if ((g_sys_osc1_osc2_roundtrip_basic_heartbeat & 0x00FFFFFFUL) !=
        (SYS_OSC1_OSC2_ROUNDTRIP_BASIC_WINDOW_STEPS - 1UL)) {
        test_runtime_fail(SYS_OSC1_OSC2_ROUNDTRIP_BASIC_FAIL_HEARTBEAT);
    }

    test_runtime_pass();
}
