/*
 * HRCAP1 high-resolution FALL-service capture.
 * HRCAP2/ePWM7A is used only for calibration.  HRCAP1 then measures the
 * external pad waveform and publishes all five Type-0 Q16 API results.
 */
#include "board_gpio.h"
#include "board_hrcap_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "hrcap_hr_capture_fall currently supports VERSION=28035 only"
#endif

#include "device_28035.h"
#include "DSP2803x_EPwm_defines.h"
#include "HCCal_Type0_V1.h"

#define HCCAPCLK_PLLCLK 1U
#define NUM_HRCAP 3U
#define HRCAP_TIMING_SAMPLE_COUNT 4U
#define HRCAP_TIMING_STAGE_SAMPLE_BASE 0x0010U
#define HRCAP_Q16_IDENTITY_TOLERANCE 2UL

#define HRCAP_MB_MAGIC_ADDR       0x9020U
#define HRCAP_MB_COUNT_ADDR       0x9022U
#define HRCAP_MB_MODE_ADDR        0x9024U
#define HRCAP_MB_HCCAL_ADDR       0x9026U
#define HRCAP_MB_HCCAL_CALLS_ADDR 0x9028U
#define HRCAP_MB_HIGH0_BASE       0x9040U
#define HRCAP_MB_HIGH1_BASE       0x9060U
#define HRCAP_MB_LOW0_BASE        0x9080U
#define HRCAP_MB_PERIOD_RISE_BASE 0x90A0U
#define HRCAP_MB_PERIOD_FALL_BASE 0x90C0U
#define HRCAP_MB_MAGIC_COMPLETE   0x4852U
#define HRCAP_MB_MODE_FALL        2U

#define HRCAP_MB16(addr) (*(volatile Uint16 *)(addr))

volatile struct HRCAP_REGS *HRCAP[NUM_HRCAP] = {0, &HRCap1Regs, &HRCap2Regs};

volatile Uint16 g_hrcap_stim_stage = HRCAP_STAGE_INIT;
volatile Uint16 g_hccal_status = HCCAL_IN_PROGRESS;
volatile Uint16 g_hccal_calls = 0U;
volatile Uint16 g_timing_sample_count = 0U;
volatile Uint32 g_timing_high0[HRCAP_TIMING_SAMPLE_COUNT];
volatile Uint32 g_timing_high1[HRCAP_TIMING_SAMPLE_COUNT];
volatile Uint32 g_timing_low0[HRCAP_TIMING_SAMPLE_COUNT];
volatile Uint32 g_timing_period_rise[HRCAP_TIMING_SAMPLE_COUNT];
volatile Uint32 g_timing_period_fall[HRCAP_TIMING_SAMPLE_COUNT];
volatile Uint32 g_timing_rise_identity_diff[HRCAP_TIMING_SAMPLE_COUNT];
volatile Uint32 g_timing_fall_identity_diff[HRCAP_TIMING_SAMPLE_COUNT];

static void mailbox_write32(Uint16 base, Uint16 index, Uint32 value)
{
    Uint16 addr = (Uint16)(base + (index * 4U));
    HRCAP_MB16(addr) = (Uint16)(value & 0xFFFFUL);
    HRCAP_MB16((Uint16)(addr + 2U)) = (Uint16)(value >> 16);
}

static void mailbox_init(void)
{
    HRCAP_MB16(HRCAP_MB_MAGIC_ADDR) = 0U;
    HRCAP_MB16(HRCAP_MB_COUNT_ADDR) = 0U;
    HRCAP_MB16(HRCAP_MB_MODE_ADDR) = HRCAP_MB_MODE_FALL;
    HRCAP_MB16(HRCAP_MB_HCCAL_ADDR) = HCCAL_IN_PROGRESS;
    HRCAP_MB16(HRCAP_MB_HCCAL_CALLS_ADDR) = 0U;
}

static void set_hrcap_clocks(Uint16 hrcap1_enable, Uint16 hrcap2_enable)
{
    EALLOW;
    SysCtrlRegs.PCLKCR2.bit.HRCAP1ENCLK = hrcap1_enable;
    SysCtrlRegs.PCLKCR2.bit.HRCAP2ENCLK = hrcap2_enable;
    EDIS;
}

static Uint16 check_pll_state(void)
{
    if ((SysCtrlRegs.PLLSTS.bit.MCLKSTS != 0U) ||
        (SysCtrlRegs.PLLSTS.bit.PLLLOCKS != 1U) ||
        (SysCtrlRegs.PLLCR.bit.DIV != DSP28_PLLCR) ||
        (SysCtrlRegs.PLLSTS.bit.DIVSEL != DSP28_DIVSEL)) {
        return HRCAP_HR_FALL_FAIL_PLL;
    }
    return 0U;
}

static void run_calibration(void)
{
    g_hccal_status = HCCAL_IN_PROGRESS;
    g_hccal_calls = 0U;
    while (g_hccal_status == HCCAL_IN_PROGRESS) {
        g_hccal_status = HRCAP_Cal(2U, HCCAPCLK_PLLCLK, &EPwm7Regs);
        g_hccal_calls++;
        ServiceDog();
    }
    HRCAP_MB16(HRCAP_MB_HCCAL_ADDR) = g_hccal_status;
    HRCAP_MB16(HRCAP_MB_HCCAL_CALLS_ADDR) = g_hccal_calls;
}

static Uint32 abs_diff32(Uint32 lhs, Uint32 rhs)
{
    return (lhs >= rhs) ? (lhs - rhs) : (rhs - lhs);
}

static void wait_capture_snapshot(void)
{
    Uint16 wait_count;

    /* HCIFR crosses into the software clock domain independently of the
     * hidden high-resolution edge slots.  Leave a bounded settling window
     * before a group of library calls so every result uses one snapshot. */
    for (wait_count = 0U; wait_count < 16U; wait_count++)
        __asm("          NOP");
}

void main(void)
{
    Uint16 idx;
    Uint16 rise_identity_failed = 0U;
    Uint16 fall_identity_failed = 0U;
    Uint32 rise_sum;
    Uint32 fall_sum;

    board_demo_init();
    /* Keep the proven cal-only initialization order and route pads afterward. */
    InitHRCap();
    mailbox_init();

    if (check_pll_state() != 0U)
        test_runtime_fail(HRCAP_HR_FALL_FAIL_PLL);

    run_calibration();
    if (g_hccal_status != HCCAL_COMPLETE)
        test_runtime_fail(HRCAP_HR_FALL_FAIL_HCCAL);

    set_hrcap_clocks(1U, 1U);
    hrcap_case_select_default_pads();
    hrcap_case_config(&HRCap1Regs, 0x0104U);
    g_hrcap_stim_stage = HRCAP_STAGE_ARMED;
    if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_FALL, 2000000UL))
        test_runtime_fail(HRCAP_HR_FALL_FAIL_WARMUP);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL);
    if (!hrcap_case_wait_clear(&HRCap1Regs, HRCAP_CASE_FLAG_FALL, 2000000UL))
        test_runtime_fail(HRCAP_HR_FALL_FAIL_WARMUP);

    /* The Type-0 FALL result path needs one additional completed interval
     * before all five API result slots refer to a fully initialized history.
     * Handshake this pulse explicitly; a fixed delay here would race the
     * instruction-accurate CPU model and could reintroduce stale sample 0. */
    g_hrcap_stim_stage = HRCAP_STAGE_MEASURE;
    if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_FALL, 2000000UL))
        test_runtime_fail(HRCAP_HR_FALL_FAIL_WARMUP);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL);
    if (!hrcap_case_wait_clear(&HRCap1Regs, HRCAP_CASE_FLAG_FALL, 2000000UL))
        test_runtime_fail(HRCAP_HR_FALL_FAIL_WARMUP);

    for (idx = 0U; idx < HRCAP_TIMING_SAMPLE_COUNT; idx++) {
        if (!hrcap_case_wait_clear(&HRCap1Regs, HRCAP_CASE_FLAG_FALL, 2000000UL))
            test_runtime_fail(HRCAP_HR_FALL_FAIL_CAPTURE);
        g_hrcap_stim_stage = (Uint16)(HRCAP_TIMING_STAGE_SAMPLE_BASE + idx);
        if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_FALL, 2000000UL))
            test_runtime_fail(HRCAP_HR_FALL_FAIL_CAPTURE);
        if ((HRCap1Regs.HCIFR.all & HRCAP_CASE_FLAG_RISEOVF) != 0U)
            test_runtime_fail(HRCAP_HR_FALL_FAIL_RISEOVF);

        wait_capture_snapshot();
        g_timing_high0[idx] = HighPulseWidth0((Uint16 *)&HRCap1Regs);
        g_timing_high1[idx] = HighPulseWidth1((Uint16 *)&HRCap1Regs);
        g_timing_low0[idx] = LowPulseWidth0((Uint16 *)&HRCap1Regs);
        g_timing_period_rise[idx] = PeriodWidthRise0((Uint16 *)&HRCap1Regs);
        g_timing_period_fall[idx] = PeriodWidthFall0((Uint16 *)&HRCap1Regs);
        rise_sum = g_timing_high1[idx] + g_timing_low0[idx];
        fall_sum = g_timing_high0[idx] + g_timing_low0[idx];
        g_timing_rise_identity_diff[idx] = abs_diff32(g_timing_period_rise[idx], rise_sum);
        g_timing_fall_identity_diff[idx] = abs_diff32(g_timing_period_fall[idx], fall_sum);
        if (g_timing_rise_identity_diff[idx] > HRCAP_Q16_IDENTITY_TOLERANCE)
            rise_identity_failed = 1U;
        if (g_timing_fall_identity_diff[idx] > HRCAP_Q16_IDENTITY_TOLERANCE)
            fall_identity_failed = 1U;

        if ((g_timing_high0[idx] == 0UL) ||
            (g_timing_high1[idx] == 0UL) ||
            (g_timing_low0[idx] == 0UL) ||
            (g_timing_period_rise[idx] == 0UL) ||
            (g_timing_period_fall[idx] == 0UL))
            test_runtime_fail(HRCAP_HR_FALL_FAIL_ZERO);
        /* Publish every sample before numerical acceptance is decided.  The
         * timing checker reports both identities and measured-ps errors;
         * terminating here would hide the diagnostic mailbox. */

        mailbox_write32(HRCAP_MB_HIGH0_BASE, idx, g_timing_high0[idx]);
        mailbox_write32(HRCAP_MB_HIGH1_BASE, idx, g_timing_high1[idx]);
        mailbox_write32(HRCAP_MB_LOW0_BASE, idx, g_timing_low0[idx]);
        mailbox_write32(HRCAP_MB_PERIOD_RISE_BASE, idx, g_timing_period_rise[idx]);
        mailbox_write32(HRCAP_MB_PERIOD_FALL_BASE, idx, g_timing_period_fall[idx]);
        g_timing_sample_count = (Uint16)(idx + 1U);
        HRCAP_MB16(HRCAP_MB_COUNT_ADDR) = g_timing_sample_count;
        hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL);
    }

    HRCAP_MB16(HRCAP_MB_MAGIC_ADDR) = HRCAP_MB_MAGIC_COMPLETE;
    g_hrcap_stim_stage = HRCAP_STAGE_FINISH;
    set_hrcap_clocks(0U, 0U);
    if (rise_identity_failed != 0U)
        test_runtime_fail(HRCAP_HR_FALL_FAIL_RISE_SUM);
    if (fall_identity_failed != 0U)
        test_runtime_fail(HRCAP_HR_FALL_FAIL_FALL_SUM);
    test_runtime_pass();
}
