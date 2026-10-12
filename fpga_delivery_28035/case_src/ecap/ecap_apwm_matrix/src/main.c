#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_apwm_matrix only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint16 g_apwm_stage_log[12];
volatile Uint16 g_apwm_flag_log[12];
volatile Uint32 g_apwm_tsctr_log[12];
volatile Uint32 g_apwm_cap1_log[12];
volatile Uint32 g_apwm_cap2_log[12];

static void config_ecap1_apwm_output_on_gpio5(void)
{
    EALLOW;

    /*
     * APWM output path:
     *   ECAP1 APWM output -> GPIO5 pad when GPAMUX1.GPIO5 = 3.
     * UVM observes the internal apwm_out; no external capture stimulus is used.
     */
    GpioCtrlRegs.GPAPUD.bit.GPIO5 = 0U;
    GpioCtrlRegs.GPAMUX1.bit.GPIO5 = 3U;

    EDIS;
}

static void clear_apwm_flags(void)
{
    ECap1Regs.ECCLR.all = 0x00C1U;
}

static void init_apwm(Uint32 period, Uint32 compare, Uint16 polarity)
{
    if (period == 0UL) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_BAD_PARAM);
    }

    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.ECAP1ENCLK = 1U;
    EDIS;

    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    ECap1Regs.ECEINT.all = 0U;
    ECap1Regs.ECCLR.all = 0x00FFU;

    ECap1Regs.TSCTR = 0UL;
    ECap1Regs.CTRPHS = 0UL;
    ECap1Regs.CAP1 = period;
    ECap1Regs.CAP2 = compare;
    ECap1Regs.CAP3 = period;
    ECap1Regs.CAP4 = compare;
    ECap1Regs.ECCTL1.all = 0U;
    ECap1Regs.ECCTL2.all = 0U;

    ECap1Regs.ECCTL2.bit.CAP_APWM = 1U;
    ECap1Regs.ECCTL2.bit.APWMPOL = polarity;
    ECap1Regs.ECEINT.bit.CTR_EQ_PRD = 1U;
    ECap1Regs.ECEINT.bit.CTR_EQ_CMP = 1U;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
}

static void wait_flag(Uint16 mask, Uint16 fail_code)
{
    Uint32 timeout_us = ECAP_APWM_MTX_WAIT_US;

    while (timeout_us-- != 0UL) {
        if ((ECap1Regs.ECFLG.all & mask) == mask) {
            return;
        }
        board_delay_us(1UL);
    }

    test_runtime_fail(fail_code);
}

static void snapshot(Uint16 slot, Uint16 stage)
{
    g_apwm_stage_log[slot] = stage;
    g_apwm_flag_log[slot] = ECap1Regs.ECFLG.all;
    g_apwm_tsctr_log[slot] = ECap1Regs.TSCTR;
    g_apwm_cap1_log[slot] = ECap1Regs.CAP1;
    g_apwm_cap2_log[slot] = ECap1Regs.CAP2;
}

static void check_mode(Uint16 polarity)
{
    if (ECap1Regs.ECCTL2.bit.CAP_APWM != 1U) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_MODE);
    }
    if (ECap1Regs.ECCTL2.bit.APWMPOL != polarity) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_POL);
    }
}

static void wait_cmp_prd_int(void)
{
    wait_flag(0x0081U, ECAP_APWM_MTX_FAIL_CMP_FLAG);
    if (ECap1Regs.ECFLG.bit.INT != 1U) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_INT);
    }

    wait_flag(0x00C1U, ECAP_APWM_MTX_FAIL_PRD_FLAG);
    if (ECap1Regs.ECFLG.bit.INT != 1U) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_INT);
    }
}

static void observe_periods(Uint32 periods)
{
    while (periods-- != 0UL) {
        clear_apwm_flags();
        wait_flag(0x00C1U, ECAP_APWM_MTX_FAIL_PRD_FLAG);
    }
}

static void observe_prd_only_periods(Uint32 periods)
{
    while (periods-- != 0UL) {
        clear_apwm_flags();
        wait_flag(0x0041U, ECAP_APWM_MTX_FAIL_PRD_FLAG);
        if ((ECap1Regs.ECFLG.all & 0x0080U) != 0U) {
            test_runtime_fail(ECAP_APWM_MTX_FAIL_UNEXPECTED_CMP);
        }
    }
}

static void stop_and_check_hold(Uint16 restart_event_mask)
{
    Uint32 tsctr0;
    Uint32 tsctr1;

    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    clear_apwm_flags();
    tsctr0 = ECap1Regs.TSCTR;
    board_delay_us(ECAP_APWM_MTX_STOP_WAIT_US);
    tsctr1 = ECap1Regs.TSCTR;

    if (tsctr1 != tsctr0) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_STOP_TSCTR);
    }
    if ((ECap1Regs.ECFLG.all & 0x00C1U) != 0U) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_STOP_FLAG);
    }

    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
    wait_flag((Uint16)(restart_event_mask | 0x0001U),
              ECAP_APWM_MTX_FAIL_RESTART_FLAG);
}

static void run_basic_window(Uint16 slot,
                             Uint16 polarity,
                             Uint32 period,
                             Uint32 compare)
{
    init_apwm(period, compare, polarity);
    check_mode(polarity);
    wait_cmp_prd_int();
    snapshot(slot, polarity);
    observe_periods(ECAP_APWM_MTX_OBSERVE_PERIODS);
    stop_and_check_hold(0x00C0U);
    clear_apwm_flags();
}

static void run_shadow_window(void)
{
    Uint32 timeout_us;

    init_apwm(ECAP_APWM_MTX_PERIOD_A, ECAP_APWM_MTX_COMPARE_A, 0U);
    check_mode(0U);

    ECap1Regs.CAP3 = ECAP_APWM_MTX_PERIOD_B;
    ECap1Regs.CAP4 = ECAP_APWM_MTX_COMPARE_B;

    timeout_us = ECAP_APWM_MTX_SHADOW_WAIT_US;
    while (timeout_us-- != 0UL) {
        if ((ECap1Regs.CAP1 == ECAP_APWM_MTX_PERIOD_B) &&
            (ECap1Regs.CAP2 == ECAP_APWM_MTX_COMPARE_B)) {
            break;
        }
        board_delay_us(1UL);
    }

    snapshot(4U, 4U);
    if (ECap1Regs.CAP1 != ECAP_APWM_MTX_PERIOD_B) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_SHADOW_PERIOD);
    }
    if (ECap1Regs.CAP2 != ECAP_APWM_MTX_COMPARE_B) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_SHADOW_COMPARE);
    }

    clear_apwm_flags();
    wait_cmp_prd_int();

    ECap1Regs.CAP3 = ECAP_APWM_MTX_PERIOD_C;
    ECap1Regs.CAP4 = ECAP_APWM_MTX_COMPARE_C;
    timeout_us = ECAP_APWM_MTX_SHADOW_WAIT_US;
    while (timeout_us-- != 0UL) {
        if ((ECap1Regs.CAP1 == ECAP_APWM_MTX_PERIOD_C) &&
            (ECap1Regs.CAP2 == ECAP_APWM_MTX_COMPARE_C)) {
            break;
        }
        board_delay_us(1UL);
    }

    snapshot(5U, 5U);
    if (ECap1Regs.CAP1 != ECAP_APWM_MTX_PERIOD_C) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_SHADOW_PERIOD);
    }
    if (ECap1Regs.CAP2 != ECAP_APWM_MTX_COMPARE_C) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_SHADOW_COMPARE);
    }

    observe_periods(ECAP_APWM_MTX_OBSERVE_PERIODS);
    stop_and_check_hold(0x00C0U);
}

static void run_static_boundary_window(Uint16 slot,
                                       Uint16 polarity,
                                       Uint32 period)
{
    init_apwm(period, period + 1UL, polarity);
    check_mode(polarity);

    /* CAPLDEN is a capture control and must not auto-clear in APWM mode. */
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;
    observe_prd_only_periods(ECAP_APWM_MTX_OBSERVE_PERIODS);
    snapshot(slot, (Uint16)(10U + polarity));

    if (ECap1Regs.ECCTL1.bit.CAPLDEN != 1U) {
        test_runtime_fail(ECAP_APWM_MTX_FAIL_CAPLDEN_APWM);
    }

    stop_and_check_hold(0x0040U);
    clear_apwm_flags();
}

void main(void)
{
    board_demo_init();
    config_ecap1_apwm_output_on_gpio5();

    run_basic_window(0U, 0U, ECAP_APWM_MTX_PERIOD_A, ECAP_APWM_MTX_COMPARE_A);
    run_basic_window(1U, 1U, ECAP_APWM_MTX_PERIOD_A, ECAP_APWM_MTX_COMPARE_A);
    run_basic_window(2U, 0U, ECAP_APWM_MTX_PERIOD_B, ECAP_APWM_MTX_COMPARE_B);
    run_basic_window(3U, 1U, ECAP_APWM_MTX_PERIOD_C, ECAP_APWM_MTX_COMPARE_C);
    run_shadow_window();

    /* CMP=0 is a defined APWM boundary. Check both output polarities. */
    run_basic_window(6U, 0U, ECAP_APWM_MTX_PERIOD_B, 0UL);
    run_basic_window(7U, 1U, ECAP_APWM_MTX_PERIOD_B, 0UL);

    /* CMP=PRD gives a one-counter boundary pulse; cover both polarities. */
    run_basic_window(8U, 0U,
                     ECAP_APWM_MTX_PERIOD_BOUNDARY,
                     ECAP_APWM_MTX_PERIOD_BOUNDARY);
    run_basic_window(9U, 1U,
                     ECAP_APWM_MTX_PERIOD_BOUNDARY,
                     ECAP_APWM_MTX_PERIOD_BOUNDARY);

    /* CMP=PRD+1 is the manual-defined 100% active-output boundary. */
    run_static_boundary_window(10U, 0U, ECAP_APWM_MTX_PERIOD_BOUNDARY);
    run_static_boundary_window(11U, 1U, ECAP_APWM_MTX_PERIOD_BOUNDARY);

    test_runtime_pass();
}
