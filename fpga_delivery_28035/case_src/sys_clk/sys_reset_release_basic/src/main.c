#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_reset_release_basic
#endif

static unsigned int check_post_reset_state(void)
{
    Uint16 wd_snapshot;
    unsigned long loops;

    if (SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) {
        return SYS_RESET_RELEASE_BASIC_FAIL_MCLKSTS;
    }

    if (SysCtrlRegs.PLLSTS.bit.PLLLOCKS != 1U) {
        return SYS_RESET_RELEASE_BASIC_FAIL_PLLLOCKS;
    }

    if (SysCtrlRegs.PLLCR.bit.DIV != DSP28_PLLCR) {
        return SYS_RESET_RELEASE_BASIC_FAIL_PLLCR;
    }

    if (SysCtrlRegs.PLLSTS.bit.DIVSEL != DSP28_DIVSEL) {
        return SYS_RESET_RELEASE_BASIC_FAIL_DIVSEL;
    }

    wd_snapshot = SysCtrlRegs.WDCNTR;
    for (loops = 0UL; loops < 200000UL; ++loops) {
        if (SysCtrlRegs.WDCNTR != wd_snapshot) {
            return 0U;
        }
    }

    return SYS_RESET_RELEASE_BASIC_FAIL_WD_STUCK;
}

void main(void)
{
    unsigned int fail_code;

    board_demo_init();
    board_demo_toggle();

    FeedDog();

    EALLOW;
    SysCtrlRegs.WDCR = 0x0028;
    EDIS;

    fail_code = check_post_reset_state();
    DisableDog();
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    test_runtime_pass();
}
