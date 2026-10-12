#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_capture_prescale_div2 only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint16 g_ecap_pre_div2_flags[2];
volatile Uint16 g_ecap_stim_stage;

static void init_div2_capture(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.ECAP1ENCLK = 1U;
    GpioCtrlRegs.GPAPUD.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO19 = 3U;
    EDIS;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    ECap1Regs.ECEINT.all = 0U;
    ECap1Regs.ECCLR.all = 0x001FU;
    ECap1Regs.TSCTR = 0UL;
    ECap1Regs.ECCTL1.all = 0U;
    ECap1Regs.ECCTL2.all = 0U;
    ECap1Regs.ECCTL1.bit.CAP1POL = 0U;
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;
    ECap1Regs.ECCTL1.bit.PRESCALE = 2U;
    ECap1Regs.ECCTL2.bit.CONT_ONESHT = 1U;
    ECap1Regs.ECCTL2.bit.STOP_WRAP = 0U;
    ECap1Regs.ECCTL2.bit.CAP_APWM = 0U;
    ECap1Regs.ECEINT.bit.CEVT1 = 1U;
    ECap1Regs.ECCTL2.bit.REARM = 1U;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
}

static void expect_no_cevt1(void)
{
    board_delay_us(ECAP_PRE_DIV2_SETTLE_US);
    g_ecap_pre_div2_flags[0] = ECap1Regs.ECFLG.all;
    if ((g_ecap_pre_div2_flags[0] & 0x0002U) != 0U)
        test_runtime_fail(ECAP_PRE_DIV2_FAIL_EARLY);
}

static void expect_cevt1(void)
{
    Uint32 timeout_us = ECAP_PRE_DIV2_WAIT_US;
    while (timeout_us-- != 0UL) {
        if ((ECap1Regs.ECFLG.all & 0x0003U) == 0x0003U) {
            g_ecap_pre_div2_flags[1] = ECap1Regs.ECFLG.all;
            return;
        }
        board_delay_us(1UL);
    }
    test_runtime_fail(ECAP_PRE_DIV2_FAIL_EVENT);
}

void main(void)
{
    board_demo_init();
    g_ecap_stim_stage = 0U;
    init_div2_capture();
    /* First rise is discarded; the next two rises complete PRESCALE=2. */
    g_ecap_stim_stage = ECAP_PRE_DIV2_STAGE_FIRST;
    expect_no_cevt1();
    g_ecap_stim_stage = ECAP_PRE_DIV2_STAGE_SECOND;
    expect_cevt1();
    g_ecap_stim_stage = 0U;
    test_runtime_pass();
}
