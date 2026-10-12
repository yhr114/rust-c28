/*
 * Purpose: Verify EPWM1 HSPCLKDIV/CLKDIV programming.
 * - Mode: up-count
 * - AQ: ZRO=set, CAU=clear
 * - Checks: divider readback matrix; each divider emits a stable PWM segment
 */
#include "board_gpio.h"
#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "epwm_clkdiv_hspclkdiv_matrix currently supports VERSION=28035 only"
#endif

#include "device_28035.h"

typedef struct {
    unsigned int hspclkdiv;
    unsigned int clkdiv;
} epwm_clkdiv_cfg_t;

static const epwm_clkdiv_cfg_t g_clkdiv_matrix[] = {
    {0U, 0U}, /* /1  * /1  = /1 */
    {1U, 0U}, /* /2  * /1  = /2 */
    {2U, 0U}, /* /4  * /1  = /4 */
    {3U, 0U}, /* /6  * /1  = /6 */
    {0U, 1U}, /* /1  * /2  = /2 */
    {1U, 1U}, /* /2  * /2  = /4 */
    {2U, 1U}, /* /4  * /2  = /8 */
    {3U, 1U}, /* /6  * /2  = /12 */
    {4U, 2U}, /* /8  * /4  = /32, final UVM-checked configuration */
};

static void epwm1_stop(void)
{
    EALLOW;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTR = 0U;
    EDIS;
}

static void epwm1_program_common(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EPWM1ENCLK = 1U;

    EPwm1Regs.TBCTL.all = 0U;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTL.bit.PHSEN = 0U;
    EPwm1Regs.TBPRD = EPWM_CLKDIV_TBPRD_TICKS;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.CMPA.half.CMPA = EPWM_CLKDIV_CMPA_TICKS;
    EPwm1Regs.AQCTLA.all = 0x0012U;
    EPwm1Regs.AQCTLB.all = 0x0000U;
    EDIS;

    epwm1_stop();
}

static void epwm1_apply_divider(unsigned int hspclkdiv, unsigned int clkdiv)
{
    EALLOW;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.TBCTL.bit.HSPCLKDIV = hspclkdiv;
    EPwm1Regs.TBCTL.bit.CLKDIV = clkdiv;
    EPwm1Regs.TBCTL.bit.CTRMODE = 0U;
    EDIS;
}

static void epwm1_check_divider(unsigned int hspclkdiv, unsigned int clkdiv)
{
    if ((EPwm1Regs.TBCTL.bit.HSPCLKDIV != hspclkdiv) ||
        (EPwm1Regs.TBCTL.bit.CLKDIV != clkdiv) ||
        (EPwm1Regs.TBPRD != EPWM_CLKDIV_TBPRD_TICKS) ||
        (EPwm1Regs.CMPA.half.CMPA != EPWM_CLKDIV_CMPA_TICKS) ||
        (EPwm1Regs.AQCTLA.all != 0x0012U)) {
        test_runtime_fail(EPWM_CLKDIV_FAIL_REG_READBACK);
    }
}

void main(void)
{
    unsigned int i;

    board_demo_init();
    gpio_case_epwm1a_mux_init();
    epwm1_program_common();

    if (GpioCtrlRegs.GPAMUX1.bit.GPIO0 != 1U) {
        test_runtime_fail(EPWM_CLKDIV_FAIL_GPIO_MUX);
    }

    for (i = 0U; i < (sizeof(g_clkdiv_matrix) / sizeof(g_clkdiv_matrix[0])); ++i) {
        epwm1_apply_divider(g_clkdiv_matrix[i].hspclkdiv,
                            g_clkdiv_matrix[i].clkdiv);
        board_delay_us(EPWM_CLKDIV_CONFIG_RUN_US);
        epwm1_check_divider(g_clkdiv_matrix[i].hspclkdiv,
                            g_clkdiv_matrix[i].clkdiv);
    }

    if ((EPwm1Regs.TBCTL.bit.HSPCLKDIV != EPWM_CLKDIV_FINAL_HSPCLKDIV) ||
        (EPwm1Regs.TBCTL.bit.CLKDIV != EPWM_CLKDIV_FINAL_CLKDIV) ||
        (EPwm1Regs.TBCTL.bit.CTRMODE != 0U)) {
        test_runtime_fail(EPWM_CLKDIV_FAIL_FINAL_CFG);
    }

    board_delay_us(EPWM_CLKDIV_FINAL_RUN_DELAY_US);
    test_runtime_pass();
}
