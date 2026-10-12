#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_capture_counter_reset only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint32 g_abs_cap1;
volatile Uint32 g_abs_cap2;
volatile Uint32 g_abs_cap3;
volatile Uint32 g_abs_cap4;
volatile Uint32 g_delta_cap1;
volatile Uint32 g_delta_cap2;
volatile Uint32 g_delta_cap3;
volatile Uint32 g_delta_cap4;
volatile Uint16 g_abs_ecflg;
volatile Uint16 g_delta_ecflg;
volatile Uint16 g_ecflg_after_clear;

static void config_ecap1_input_on_gpio19(void)
{
    EALLOW;

    /*
     * ECAP1 input path:
     *   GPIO19 pad -> GPAMUX2.GPIO19 = 3 -> ECAP1
     *
     * UVM drives low->high->low->high->low bursts with stable segment
     * lengths. This case compares:
     *   1. CTRRST1~4=0: CAP1~CAP4 are absolute TSCTR timestamps.
     *   2. CTRRST1~4=1: CAP2~CAP4 become inter-edge delta timestamps.
     */
    GpioCtrlRegs.GPAPUD.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO19 = 3U;

    EDIS;
}

static Uint32 abs_diff_u32(Uint32 lhs, Uint32 rhs)
{
    return (lhs > rhs) ? (lhs - rhs) : (rhs - lhs);
}

static void init_ecap_capture_counter_reset(Uint16 ctrrst_enable)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.ECAP1ENCLK = 1U;
    EDIS;

    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    ECap1Regs.ECEINT.all = 0U;
    ECap1Regs.ECCLR.all = 0x00FFU;

    ECap1Regs.TSCTR = 0UL;
    ECap1Regs.CTRPHS = 0UL;
    ECap1Regs.CAP1 = 0UL;
    ECap1Regs.CAP2 = 0UL;
    ECap1Regs.CAP3 = 0UL;
    ECap1Regs.CAP4 = 0UL;

    ECap1Regs.ECCTL1.all = 0U;
    ECap1Regs.ECCTL2.all = 0U;

    ECap1Regs.ECCTL1.bit.CAP1POL = 0U;
    ECap1Regs.ECCTL1.bit.CAP2POL = 1U;
    ECap1Regs.ECCTL1.bit.CAP3POL = 0U;
    ECap1Regs.ECCTL1.bit.CAP4POL = 1U;
    ECap1Regs.ECCTL1.bit.CTRRST1 = ctrrst_enable;
    ECap1Regs.ECCTL1.bit.CTRRST2 = ctrrst_enable;
    ECap1Regs.ECCTL1.bit.CTRRST3 = ctrrst_enable;
    ECap1Regs.ECCTL1.bit.CTRRST4 = ctrrst_enable;
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;

    ECap1Regs.ECCTL2.bit.CONT_ONESHT = 1U;
    ECap1Regs.ECCTL2.bit.STOP_WRAP = 3U;
    ECap1Regs.ECCTL2.bit.CAP_APWM = 0U;
    ECap1Regs.ECCTL2.bit.SYNCI_EN = 0U;
    ECap1Regs.ECCTL2.bit.SYNCO_SEL = 0U;

    ECap1Regs.ECEINT.bit.CEVT1 = 1U;
    ECap1Regs.ECEINT.bit.CEVT2 = 1U;
    ECap1Regs.ECEINT.bit.CEVT3 = 1U;
    ECap1Regs.ECEINT.bit.CEVT4 = 1U;
    ECap1Regs.ECCTL2.bit.REARM = 1U;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
}

static void wait_quad_capture(Uint16 no_cevt1_fail,
                              Uint16 no_cevt2_fail,
                              Uint16 no_cevt3_fail,
                              Uint16 no_cevt4_fail,
                              Uint16 require_cap1_nonzero)
{
    Uint32 timeout_us = ECAP_COUNTER_RESET_CAPTURE_WAIT_US;

    while (timeout_us-- != 0UL) {
        Uint16 ecflg_now = ECap1Regs.ECFLG.all;

        if (((ecflg_now & 0x001EU) == 0x001EU) &&
            ((require_cap1_nonzero == 0U) || (ECap1Regs.CAP1 != 0UL)) &&
            (ECap1Regs.CAP2 != 0UL) &&
            (ECap1Regs.CAP3 != 0UL) &&
            (ECap1Regs.CAP4 != 0UL)) {
            return;
        }
        board_delay_us(1UL);
    }

    if ((ECap1Regs.ECFLG.all & 0x0002U) == 0U) {
        test_runtime_fail(no_cevt1_fail);
    }
    if ((ECap1Regs.ECFLG.all & 0x0004U) == 0U) {
        test_runtime_fail(no_cevt2_fail);
    }
    if ((ECap1Regs.ECFLG.all & 0x0008U) == 0U) {
        test_runtime_fail(no_cevt3_fail);
    }
    if ((ECap1Regs.ECFLG.all & 0x0010U) == 0U) {
        test_runtime_fail(no_cevt4_fail);
    }
}

static void check_caps_nonzero(Uint32 cap1,
                               Uint32 cap2,
                               Uint32 cap3,
                               Uint32 cap4,
                               Uint16 fail_code)
{
    if ((cap1 == 0UL) || (cap2 == 0UL) ||
        (cap3 == 0UL) || (cap4 == 0UL)) {
        test_runtime_fail(fail_code);
    }
}

static void run_absolute_timestamp_window(void)
{
    init_ecap_capture_counter_reset(0U);
    wait_quad_capture(ECAP_COUNTER_RESET_FAIL_ABS_NO_CEVT1,
                      ECAP_COUNTER_RESET_FAIL_ABS_NO_CEVT2,
                      ECAP_COUNTER_RESET_FAIL_ABS_NO_CEVT3,
                      ECAP_COUNTER_RESET_FAIL_ABS_NO_CEVT4,
                      1U);

    g_abs_ecflg = ECap1Regs.ECFLG.all;
    g_abs_cap1 = ECap1Regs.CAP1;
    g_abs_cap2 = ECap1Regs.CAP2;
    g_abs_cap3 = ECap1Regs.CAP3;
    g_abs_cap4 = ECap1Regs.CAP4;

    check_caps_nonzero(g_abs_cap1,
                       g_abs_cap2,
                       g_abs_cap3,
                       g_abs_cap4,
                       ECAP_COUNTER_RESET_FAIL_ABS_CAP_ZERO);

    if ((g_abs_cap2 <= g_abs_cap1) ||
        (g_abs_cap3 <= g_abs_cap2) ||
        (g_abs_cap4 <= g_abs_cap3)) {
        test_runtime_fail(ECAP_COUNTER_RESET_FAIL_ABS_ORDER);
    }
}

static void run_delta_timestamp_window(void)
{
    init_ecap_capture_counter_reset(1U);
    wait_quad_capture(ECAP_COUNTER_RESET_FAIL_DELTA_NO_CEVT1,
                      ECAP_COUNTER_RESET_FAIL_DELTA_NO_CEVT2,
                      ECAP_COUNTER_RESET_FAIL_DELTA_NO_CEVT3,
                      ECAP_COUNTER_RESET_FAIL_DELTA_NO_CEVT4,
                      0U);

    g_delta_ecflg = ECap1Regs.ECFLG.all;
    g_delta_cap1 = ECap1Regs.CAP1;
    g_delta_cap2 = ECap1Regs.CAP2;
    g_delta_cap3 = ECap1Regs.CAP3;
    g_delta_cap4 = ECap1Regs.CAP4;

    check_caps_nonzero(1UL,
                       g_delta_cap2,
                       g_delta_cap3,
                       g_delta_cap4,
                       ECAP_COUNTER_RESET_FAIL_DELTA_CAP_ZERO);

    if ((g_delta_cap2 >= g_abs_cap2) ||
        (g_delta_cap3 >= g_abs_cap3) ||
        (g_delta_cap4 >= g_abs_cap4)) {
        test_runtime_fail(ECAP_COUNTER_RESET_FAIL_DELTA_NOT_SMALL);
    }

    if (abs_diff_u32(g_delta_cap2, g_delta_cap4) >
        ECAP_COUNTER_RESET_WIDTH_TOLERANCE) {
        test_runtime_fail(ECAP_COUNTER_RESET_FAIL_HIGH_MISMATCH);
    }
    if ((g_delta_cap2 + g_delta_cap3 + g_delta_cap4) >= g_abs_cap4) {
        test_runtime_fail(ECAP_COUNTER_RESET_FAIL_DELTA_SPAN_BAD);
    }
}

void main(void)
{
    board_demo_init();
    config_ecap1_input_on_gpio19();

    run_absolute_timestamp_window();
    run_delta_timestamp_window();

    ECap1Regs.ECCLR.all = 0x001FU;
    board_delay_us(ECAP_COUNTER_RESET_CAPTURE_WAIT_US);
    g_ecflg_after_clear = ECap1Regs.ECFLG.all;
    if ((g_ecflg_after_clear & 0x001EU) != 0U) {
        test_runtime_fail(ECAP_COUNTER_RESET_FAIL_EXTRA_EVENT);
    }

    test_runtime_pass();
}
