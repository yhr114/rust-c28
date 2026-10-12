#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_capture_dual_edge only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint32 g_cap1_after_pulse;
volatile Uint32 g_cap2_after_pulse;
volatile Uint16 g_ecflg_after_pulse;
volatile Uint16 g_ecflg_after_clear;

static void config_ecap1_input_on_gpio19(void)
{
    EALLOW;

    /*
     * ECAP1 input path:
     *   GPIO19 pad -> GPAMUX2.GPIO19 = 3 -> ECAP1
     *
     * The actual pulse is injected by the UVM eCAP environment onto the
     * selected external pad. This case verifies that one pulse produces two
     * ordered capture events: rising edge into CAP1, then falling edge into CAP2.
     */
    GpioCtrlRegs.GPAPUD.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO19 = 3U;

    EDIS;
}

static void init_ecap_capture_dual_edge(void)
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

    /* Event 1: rising edge -> CAP1, Event 2: falling edge -> CAP2. */
    ECap1Regs.ECCTL1.bit.CAP1POL = 0U;
    ECap1Regs.ECCTL1.bit.CAP2POL = 1U;
    ECap1Regs.ECCTL1.bit.CTRRST1 = 0U;
    ECap1Regs.ECCTL1.bit.CTRRST2 = 0U;
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;

    ECap1Regs.ECCTL2.bit.CONT_ONESHT = 1U;
    ECap1Regs.ECCTL2.bit.STOP_WRAP = 1U;
    ECap1Regs.ECCTL2.bit.CAP_APWM = 0U;
    ECap1Regs.ECCTL2.bit.SYNCI_EN = 0U;
    ECap1Regs.ECCTL2.bit.SYNCO_SEL = 0U;

    ECap1Regs.ECEINT.bit.CEVT1 = 1U;
    ECap1Regs.ECEINT.bit.CEVT2 = 1U;
    ECap1Regs.ECCTL2.bit.REARM = 1U;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
}

void main(void)
{
    board_demo_init();

    config_ecap1_input_on_gpio19();
    init_ecap_capture_dual_edge();

    board_delay_us(ECAP_DUAL_EDGE_CAPTURE_WAIT_US);

    g_ecflg_after_pulse = ECap1Regs.ECFLG.all;
    g_cap1_after_pulse = ECap1Regs.CAP1;
    g_cap2_after_pulse = ECap1Regs.CAP2;

    if ((g_ecflg_after_pulse & 0x0002U) == 0U) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_NO_CEVT1);
    }
    if ((g_ecflg_after_pulse & 0x0004U) == 0U) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_NO_CEVT2);
    }
    if ((g_ecflg_after_pulse & 0x0001U) == 0U) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_NO_INT);
    }
    if (g_cap1_after_pulse == 0UL) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_CAP1_ZERO);
    }
    if (g_cap2_after_pulse == 0UL) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_CAP2_ZERO);
    }
    if (g_cap2_after_pulse <= g_cap1_after_pulse) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_EDGE_ORDER);
    }

    ECap1Regs.ECCLR.all = 0x0007U;
    board_delay_us(ECAP_DUAL_EDGE_CAPTURE_WAIT_US);

    g_ecflg_after_clear = ECap1Regs.ECFLG.all;
    if ((g_ecflg_after_clear & 0x001EU) != 0U) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_EXTRA_EVENT);
    }
    if (ECap1Regs.CAP1 != g_cap1_after_pulse) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_CAP1_CHANGED);
    }
    if (ECap1Regs.CAP2 != g_cap2_after_pulse) {
        test_runtime_fail(ECAP_DUAL_EDGE_FAIL_CAP2_CHANGED);
    }

    test_runtime_pass();
}
