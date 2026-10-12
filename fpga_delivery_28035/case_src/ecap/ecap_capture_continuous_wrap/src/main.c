#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_capture_continuous_wrap only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint32 g_cap1_first_window;
volatile Uint32 g_cap2_first_window;
volatile Uint32 g_cap3_first_window;
volatile Uint32 g_cap4_first_window;
volatile Uint32 g_cap1_second_window;
volatile Uint32 g_cap2_second_window;
volatile Uint32 g_cap3_second_window;
volatile Uint32 g_cap4_second_window;
volatile Uint16 g_ecflg_first_window;
volatile Uint16 g_ecflg_second_window;

static void config_ecap1_input_on_gpio19(void)
{
    EALLOW;

    /*
     * ECAP1 input path:
     *   GPIO19 pad -> GPAMUX2.GPIO19 = 3 -> ECAP1
     *
     * UVM drives repeated low->high->low pulses onto the selected ECAP1 pad.
     * This case verifies continuous capture mode:
     *   1. CAP1~CAP4 are filled by the first event sequence
     *   2. after clearing flags and waiting again, CAP1~CAP4 are overwritten
     *      by later events in the circular continuous path
     */
    GpioCtrlRegs.GPAPUD.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO19 = 3U;

    EDIS;
}

static void init_ecap_capture_continuous_wrap(void)
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
    ECap1Regs.ECCTL1.bit.CAP2POL = 1U;
    ECap1Regs.ECCTL1.bit.CAP3POL = 0U;
    ECap1Regs.ECCTL1.bit.CAP4POL = 1U;
    ECap1Regs.ECCTL1.bit.CTRRST1 = 0U;
    ECap1Regs.ECCTL1.bit.CTRRST2 = 0U;
    ECap1Regs.ECCTL1.bit.CTRRST3 = 0U;
    ECap1Regs.ECCTL1.bit.CTRRST4 = 0U;
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;

    /* Continuous mode: wrap after CEVT4 and keep capturing. */
    ECap1Regs.ECCTL2.bit.CONT_ONESHT = 0U;
    ECap1Regs.ECCTL2.bit.STOP_WRAP = 3U;
    ECap1Regs.ECCTL2.bit.CAP_APWM = 0U;
    ECap1Regs.ECCTL2.bit.SYNCI_EN = 0U;
    ECap1Regs.ECCTL2.bit.SYNCO_SEL = 0U;

    ECap1Regs.ECEINT.bit.CEVT1 = 1U;
    ECap1Regs.ECEINT.bit.CEVT2 = 1U;
    ECap1Regs.ECEINT.bit.CEVT3 = 1U;
    ECap1Regs.ECEINT.bit.CEVT4 = 1U;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
}

static void freeze_capture_snapshot(void)
{
    /*
     * Continuous mode keeps updating CAP1~CAP4 in the background. Freeze the
     * capture pipeline before reading software snapshots to avoid torn values.
     */
    ECap1Regs.ECCTL1.bit.CAPLDEN = 0U;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
}

static void resume_capture_snapshot(void)
{
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;
}

static void wait_first_sequence_ready(void)
{
    Uint32 timeout_us = ECAP_CONT_WRAP_FIRST_WAIT_US;

    while (timeout_us-- != 0UL) {
        Uint16 ecflg_now = ECap1Regs.ECFLG.all;

        if (((ecflg_now & 0x001EU) == 0x001EU) &&
            (ECap1Regs.CAP1 != 0UL) &&
            (ECap1Regs.CAP2 != 0UL) &&
            (ECap1Regs.CAP3 != 0UL) &&
            (ECap1Regs.CAP4 != 0UL)) {
            return;
        }
        board_delay_us(1UL);
    }

    test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_NO_CEVT4);
}

static void wait_second_sequence_ready(Uint32 cap1_prev,
                                       Uint32 cap2_prev,
                                       Uint32 cap3_prev,
                                       Uint32 cap4_prev)
{
    Uint32 timeout_us = ECAP_CONT_WRAP_SECOND_WAIT_US;

    while (timeout_us-- != 0UL) {
        Uint16 ecflg_now = ECap1Regs.ECFLG.all;

        if (((ecflg_now & 0x001EU) == 0x001EU) &&
            ((ECap1Regs.CAP1 != cap1_prev) ||
             (ECap1Regs.CAP2 != cap2_prev) ||
             (ECap1Regs.CAP3 != cap3_prev) ||
             (ECap1Regs.CAP4 != cap4_prev))) {
            return;
        }
        board_delay_us(1UL);
    }

    test_runtime_fail(ECAP_CONT_WRAP_FAIL_CAP4_NOT_UPDATED);
}

static void check_ordered_caps(Uint32 cap1,
                               Uint32 cap2,
                               Uint32 cap3,
                               Uint32 cap4,
                               Uint16 fail12,
                               Uint16 fail23,
                               Uint16 fail34)
{
    if (cap2 <= cap1) {
        test_runtime_fail(fail12);
    }
    if (cap3 <= cap2) {
        test_runtime_fail(fail23);
    }
    if (cap4 <= cap3) {
        test_runtime_fail(fail34);
    }
}

void main(void)
{
    board_demo_init();

    config_ecap1_input_on_gpio19();
    init_ecap_capture_continuous_wrap();

    wait_first_sequence_ready();
    freeze_capture_snapshot();

    g_ecflg_first_window = ECap1Regs.ECFLG.all;
    g_cap1_first_window = ECap1Regs.CAP1;
    g_cap2_first_window = ECap1Regs.CAP2;
    g_cap3_first_window = ECap1Regs.CAP3;
    g_cap4_first_window = ECap1Regs.CAP4;

    if ((g_ecflg_first_window & 0x0002U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_NO_CEVT1);
    }
    if ((g_ecflg_first_window & 0x0004U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_NO_CEVT2);
    }
    if ((g_ecflg_first_window & 0x0008U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_NO_CEVT3);
    }
    if ((g_ecflg_first_window & 0x0010U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_NO_CEVT4);
    }
    if ((g_ecflg_first_window & 0x0001U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_NO_INT);
    }
    if (g_cap1_first_window == 0UL) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_CAP1_ZERO);
    }
    if (g_cap2_first_window == 0UL) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_CAP2_ZERO);
    }
    if (g_cap3_first_window == 0UL) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_CAP3_ZERO);
    }
    if (g_cap4_first_window == 0UL) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_FIRST_CAP4_ZERO);
    }
    check_ordered_caps(g_cap1_first_window,
                       g_cap2_first_window,
                       g_cap3_first_window,
                       g_cap4_first_window,
                       ECAP_CONT_WRAP_FAIL_FIRST_ORDER_12,
                       ECAP_CONT_WRAP_FAIL_FIRST_ORDER_23,
                       ECAP_CONT_WRAP_FAIL_FIRST_ORDER_34);

    ECap1Regs.ECCLR.all = 0x001FU;
    resume_capture_snapshot();
    wait_second_sequence_ready(g_cap1_first_window,
                               g_cap2_first_window,
                               g_cap3_first_window,
                               g_cap4_first_window);
    freeze_capture_snapshot();

    g_ecflg_second_window = ECap1Regs.ECFLG.all;
    g_cap1_second_window = ECap1Regs.CAP1;
    g_cap2_second_window = ECap1Regs.CAP2;
    g_cap3_second_window = ECap1Regs.CAP3;
    g_cap4_second_window = ECap1Regs.CAP4;

    if ((g_ecflg_second_window & 0x0002U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_SECOND_NO_CEVT1);
    }
    if ((g_ecflg_second_window & 0x0004U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_SECOND_NO_CEVT2);
    }
    if ((g_ecflg_second_window & 0x0008U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_SECOND_NO_CEVT3);
    }
    if ((g_ecflg_second_window & 0x0010U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_SECOND_NO_CEVT4);
    }
    if ((g_ecflg_second_window & 0x0001U) == 0U) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_SECOND_NO_INT);
    }

    check_ordered_caps(g_cap1_second_window,
                       g_cap2_second_window,
                       g_cap3_second_window,
                       g_cap4_second_window,
                       ECAP_CONT_WRAP_FAIL_SECOND_ORDER_12,
                       ECAP_CONT_WRAP_FAIL_SECOND_ORDER_23,
                       ECAP_CONT_WRAP_FAIL_SECOND_ORDER_34);

    if (g_cap1_second_window == g_cap1_first_window) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_CAP1_NOT_UPDATED);
    }
    if (g_cap2_second_window == g_cap2_first_window) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_CAP2_NOT_UPDATED);
    }
    if (g_cap3_second_window == g_cap3_first_window) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_CAP3_NOT_UPDATED);
    }
    if (g_cap4_second_window == g_cap4_first_window) {
        test_runtime_fail(ECAP_CONT_WRAP_FAIL_CAP4_NOT_UPDATED);
    }

    test_runtime_pass();
}
