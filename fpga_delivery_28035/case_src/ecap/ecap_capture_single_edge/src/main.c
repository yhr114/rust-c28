#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_capture_single_edge only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint32 g_cap1_after_first_edge;
volatile Uint16 g_ecflg_after_first_edge;
volatile Uint16 g_ecflg_after_second_edge;

static void config_ecap1_input_on_gpio19(void)
{
    EALLOW;

    /*
     * This case now relies on the UVM eCAP sub-environment to inject an
     * external edge onto the currently selected ECAP1 pad. Software only
     * selects GPIO19 as the ECAP1 input path and checks the capture result.
     */
    GpioCtrlRegs.GPAPUD.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO19 = 3U;

    EDIS;
}

static void init_ecap_capture_single_rising(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.ECAP1ENCLK = 1U;
    EDIS;

    ECap1Regs.ECEINT.all = 0U;
    ECap1Regs.ECCLR.all = 0x00FFU;

    ECap1Regs.TSCTR = 0UL;
    ECap1Regs.CTRPHS = 0UL;

    ECap1Regs.ECCTL1.all = 0U;
    ECap1Regs.ECCTL2.all = 0U;

    ECap1Regs.ECCTL1.bit.CAP1POL = 0U;
    ECap1Regs.ECCTL1.bit.CTRRST1 = 0U;
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;

    ECap1Regs.ECCTL2.bit.CONT_ONESHT = 1U;
    ECap1Regs.ECCTL2.bit.STOP_WRAP = 0U;
    ECap1Regs.ECCTL2.bit.CAP_APWM = 0U;
    ECap1Regs.ECCTL2.bit.SYNCI_EN = 0U;
    ECap1Regs.ECCTL2.bit.SYNCO_SEL = 0U;

    ECap1Regs.ECEINT.bit.CEVT1 = 1U;
    ECap1Regs.ECCTL2.bit.REARM = 1U;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
}

void main(void)
{
    board_demo_init();

    config_ecap1_input_on_gpio19();
    init_ecap_capture_single_rising();

    board_delay_us(ECAP_SINGLE_EDGE_CAPTURE_WAIT_US);

    g_ecflg_after_first_edge = ECap1Regs.ECFLG.all;
    g_cap1_after_first_edge = ECap1Regs.CAP1;
    if ((g_ecflg_after_first_edge & 0x0002U) == 0U) {
        test_runtime_fail(ECAP_SINGLE_EDGE_FAIL_NO_EVENT);
    }
    if ((g_ecflg_after_first_edge & 0x0001U) == 0U) {
        test_runtime_fail(ECAP_SINGLE_EDGE_FAIL_NO_INT);
    }
    if (g_cap1_after_first_edge == 0UL) {
        test_runtime_fail(ECAP_SINGLE_EDGE_FAIL_CAP1_ZERO);
    }

    ECap1Regs.ECCLR.all = 0x0003U;
    board_delay_us(ECAP_SINGLE_EDGE_CAPTURE_WAIT_US);

    g_ecflg_after_second_edge = ECap1Regs.ECFLG.all;
    if ((g_ecflg_after_second_edge & 0x001EU) != 0U) {
        test_runtime_fail(ECAP_SINGLE_EDGE_FAIL_EXTRA_EVENT);
    }
    if (ECap1Regs.CAP1 != g_cap1_after_first_edge) {
        test_runtime_fail(ECAP_SINGLE_EDGE_FAIL_CAP1_CHANGED);
    }

    test_runtime_pass();
}
