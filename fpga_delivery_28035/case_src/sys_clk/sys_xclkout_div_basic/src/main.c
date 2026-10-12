#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for sys_xclkout_div_basic
#endif

#define S03_REG16(addr)               (*((volatile Uint16 *)(addr)))
#define S03_XCLK_ADDR                 0x00007010UL
#define S03_XCLK_XCLKOUTDIV_MASK      0x0003U

volatile unsigned long g_sys_xclkout_div_basic_heartbeat = 0UL;

static void program_xclkoutdiv(Uint16 xclkoutdiv)
{
    Uint16 reg_val;

    reg_val = S03_REG16(S03_XCLK_ADDR);
    reg_val &= (Uint16)(~S03_XCLK_XCLKOUTDIV_MASK);
    reg_val |= (Uint16)(xclkoutdiv & S03_XCLK_XCLKOUTDIV_MASK);

    EALLOW;
    S03_REG16(S03_XCLK_ADDR) = reg_val;
    EDIS;
}

static unsigned int check_xclkoutdiv(Uint16 expected)
{
    Uint16 reg_val;

    if (SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) {
        return (unsigned int)(SYS_XCLKOUT_DIV_BASIC_FAIL_MCLKSTS_BASE + expected);
    }

    if (SysCtrlRegs.PLLSTS.bit.PLLLOCKS != 1U) {
        return (unsigned int)(SYS_XCLKOUT_DIV_BASIC_FAIL_PLLLOCKS_BASE + expected);
    }

    reg_val = S03_REG16(S03_XCLK_ADDR);
    if ((reg_val & S03_XCLK_XCLKOUTDIV_MASK) != expected) {
        return (unsigned int)(SYS_XCLKOUT_DIV_BASIC_FAIL_READBACK_BASE + expected);
    }

    return 0U;
}

static void run_xclkout_window(Uint16 step_id)
{
    unsigned long i;

    for (i = 0UL; i < SYS_XCLKOUT_DIV_BASIC_WINDOW_STEPS; ++i) {
        g_sys_xclkout_div_basic_heartbeat =
            ((unsigned long)step_id << 24) | i;
        board_demo_toggle();
        board_delay_us(SYS_XCLKOUT_DIV_BASIC_WINDOW_DELAY_US);
    }
}

void main(void)
{
    unsigned int fail_code;
    Uint16 divsel;

    board_demo_init();
    board_demo_toggle();

    for (divsel = 0U; divsel < 4U; ++divsel) {
        program_xclkoutdiv(divsel);
        board_delay_us(SYS_XCLKOUT_DIV_BASIC_SETTLE_US);

        fail_code = check_xclkoutdiv(divsel);
        if (fail_code != 0U) {
            test_runtime_fail(fail_code);
        }

        run_xclkout_window(divsel);
    }

    if ((g_sys_xclkout_div_basic_heartbeat & 0x00FFFFFFUL) !=
        (SYS_XCLKOUT_DIV_BASIC_WINDOW_STEPS - 1UL)) {
        test_runtime_fail(SYS_XCLKOUT_DIV_BASIC_FAIL_HEARTBEAT);
    }

    test_runtime_pass();
}
